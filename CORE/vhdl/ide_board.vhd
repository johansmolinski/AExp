---------------------------------------------------------------------------------------------------------
-- Amiga 500 for MEGA65 (AExp)
--
-- ide_board: a Zorro II IDE controller, register-compatible with RIPPLE
-- (github.com/LIV2/RIPPLE-IDE), so that the open-source lide.device boot ROM
-- (github.com/LIV2/lide.device) autoboots Kickstart 1.3 from it. The drive behind it
-- is an HDF image on the SD card, served by the QNICE firmware.
--
-- The autoconfig part lives in cpu_wrapper.v (it owns the chain); this module serves the
-- bus cycles of the configured 128 KB board (sel_i = ext_sel of cpu_wrapper):
--
--   ROM    Before the first write to the board the ROM fills the whole board; afterwards
--          it is at +64 KB, and also wherever address bits 13 and 12 are equal (RIPPLE's
--          IDE_ROMEN). ROM byte k is at board offset 2k on the upper data byte (an 8-bit
--          flash on D15..D8), so the nibble-wide DiagArea at offset 0x0008 is ROM byte 4.
--          The 32 KB lide.rom lives in HyperRAM (loaded by a byte-window bridge, even ROM
--          bytes in bits 7:0 of a word); reads go through rom_avm_* with a 1-word cache.
--   IDE    Channel 0 at offset 0x1000, register n at 0x1000 + n * 0x200 (A11..A9), so that
--          a MOVEM burst stays on the data register. A14 selects the control block
--          (device control, alternate status). The 8-bit registers are on D15..D8 (RIPPLE's
--          IDE bus is byte-swapped, so sector data needs no swapping). Channel 1 and an
--          absent drive read 0xFF: lide treats a register value with bits 7:6 = 11 as a
--          floating bus. Master and slave share the task file, the status and the data
--          buffer, as on a real ATA channel; DEV (device/head bit 4) picks the drive, and
--          the firmware serves the one the command was written to.
--
-- Work split: the hardware does what must happen within a bus cycle - BSY on a command
-- write, DRQ off with the 256th data word - and the firmware does everything else, like
-- MiSTer's HPS side (ide.cpp) does for Minimig's ide.v. Firmware interface: QNICE device,
-- word addresses within the 4k window:
--
--   0x000-0x0FF  W: data for the CPU (read buffer)      R: data from the CPU (write buffer)
--   0x100        R: events: bit 0 command, bit 1 buffer done, bit 2 reset, bit 3 commit
--                   acknowledge - each a toggle; the firmware compares with the last value
--   0x101-0x107  R: task file snapshot: command, features, sector count, LBA 7:0, LBA 15:8,
--                   LBA 23:16, device/head (frozen while BSY)
--   0x110        R/W: status to apply on commit (BSY, DRDY, DF, DSC, DRQ, ..., ERR)
--   0x111        R/W: error register to apply on commit
--   0x112        R/W: bit 0: the data phase started by a commit with DRQ is CPU -> buffer
--                     bit 1: also apply the task file values 0x113-0x117
--   0x113-0x117  R/W: sector count, LBA 7:0, 15:8, 23:16, device/head to apply on commit
--   0x118        R/W: bit 0: master (unit 0) present, bit 1: board enabled (in the autoconfig
--                     chain), bit 2: slave (unit 1) present (Megamiga 0.3.1)
--   0x11F        W: commit (any value)
--   0x120-0x125  R/W: sector engine, unit 0: mode (bits 1..0: 0 off, 1 file, 2 partition; bit 2:
--                     the SD slot, 0 = bottom tray, 1 = back), sectors lo/hi,
--                     base block lo/hi, log2(sectors per cluster) - see ide_engine.vhd
--   0x128-0x12D  R/W: the same for unit 1
--   0x130        R: bit 0 SD card ready (sdhost), bit 1 engine busy
--   0x131-0x133  R: engine statistics: commands taken, forwarded to the firmware, failed
--   window 1     W: the extent maps of the engine, unit u at u * 2048 (FAT32$FILE_MAP format)
--
-- Sector engine (Megamiga 0.6.1): READ SECTORS and WRITE SECTORS of a unit whose engine mode is
-- not 0 are served by ide_engine.vhd (QNICE clock) through the engine port of the SD host
-- controller, with rings of 8 sector buffers in block RAM in both directions: the Amiga reads
-- sector n while sector n + 1.. arrive, and writes sector n + 1 while sector n goes to the
-- card. The core side keeps DRQ up across sector boundaries while the ring has data (read) or
-- room (write). The firmware never sees these commands (the engine forwards all others).
--   window 0xFFFF   the M2M CSR (qnice_csr.vhd): the OSM HDF mount line is a manual
--                CRT/ROM load into this device, so the Shell writes the file size and
--                STATUS=OK and then waits for PARSEST. PREP_LOAD_IMAGE moves the read
--                pointer to the end of the file (nothing is streamed: the firmware
--                serves the sectors from the file itself), and the responder answers
--                READY right away.
--
-- All registers above are in window 0; the firmware selects it before accessing them.
--
-- A commit is applied a few core clocks after its toggle crossed over (the payload was
-- written before it, so it has settled) and only while BSY is set: a late commit after an
-- Amiga reset can never raise DRQ. Each commit is acknowledged (event bit 3) either way.
-- Events are raised a few core clocks after the fact, so the snapshot has settled when
-- the firmware sees them. Resets (Amiga reset, 68000 RESET instruction, SRST) raise the
-- reset event, so the firmware can abandon a transfer in progress.
--
-- Done in 2026 (AExp fork, WIP-V2-A11-JS-01) and licensed under GPL v3.
---------------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.qnice_csr_pkg.all;

entity ide_board is
   generic (
      G_ROM_BASE   : std_logic_vector(21 downto 0)   -- HyperRAM word address of lide.rom
   );
   port (
      -- core clock domain: the board's bus cycles (cpu_wrapper ext_* port)
      clk_i                  : in  std_logic;
      rst_i                  : in  std_logic;        -- Amiga reset or RESET instruction
      sel_i                  : in  std_logic;        -- bus cycle to the board
      rw_i                   : in  std_logic;        -- '1' = read
      uds_n_i                : in  std_logic;
      lds_n_i                : in  std_logic;
      addr_i                 : in  std_logic_vector(16 downto 1);  -- offset within the board
      data_i                 : in  std_logic_vector(15 downto 0);
      data_o                 : out std_logic_vector(15 downto 0);
      ready_o                : out std_logic;        -- -> DTACK
      board_ena_o            : out std_logic;        -- -> cpu_wrapper ide_ena
      activity_o             : out std_logic;        -- a command runs (BSY or DRQ): drive LED

      -- core clock domain: reading lide.rom from HyperRAM (via avm_fifo)
      rom_avm_read_o         : out std_logic;
      rom_avm_address_o      : out std_logic_vector(31 downto 0);
      rom_avm_waitrequest_i  : in  std_logic;
      rom_avm_readdata_i     : in  std_logic_vector(15 downto 0);
      rom_avm_readdatavalid_i: in  std_logic;

      -- QNICE clock domain: the firmware interface (see header)
      qnice_clk_i            : in  std_logic;
      qnice_rst_i            : in  std_logic;
      qnice_addr_i           : in  std_logic_vector(27 downto 0);
      qnice_data_i           : in  std_logic_vector(15 downto 0);
      qnice_ce_i             : in  std_logic;
      qnice_we_i             : in  std_logic;
      qnice_data_o           : out std_logic_vector(15 downto 0);
      qnice_wait_o           : out std_logic;

      -- QNICE clock domain: the engine port of the SD host controller (sdhost.vhd)
      sd_slot_o              : out std_logic;     -- the controller: 0 = bottom tray, 1 = back
      sd_ready_i             : in  std_logic := '0';
      sd_start_o             : out std_logic;
      sd_write_o             : out std_logic;
      sd_addr_o              : out std_logic_vector(31 downto 0);
      sd_count_o             : out std_logic_vector(15 downto 0);
      sd_limit_o             : out std_logic_vector(15 downto 0);
      sd_abort_o             : out std_logic;
      sd_busy_i              : in  std_logic := '0';
      sd_done_i              : in  std_logic := '0';
      sd_error_i             : in  std_logic := '0';
      sd_blk_i               : in  std_logic := '0';
      sd_rd_we_i             : in  std_logic := '0';
      sd_rd_blk_i            : in  std_logic_vector(15 downto 0) := (others => '0');
      sd_rd_idx_i            : in  std_logic_vector(8 downto 0) := (others => '0');
      sd_rd_data_i           : in  std_logic_vector(7 downto 0) := (others => '0');
      sd_wr_blk_i            : in  std_logic_vector(15 downto 0) := (others => '0');
      sd_wr_idx_i            : in  std_logic_vector(8 downto 0) := (others => '0');
      sd_wr_data_o           : out std_logic_vector(7 downto 0)
   );
end entity ide_board;

architecture synthesis of ide_board is

   -- status bits
   constant C_BSY  : natural := 7;
   constant C_DRQ  : natural := 3;
   constant C_ST_READY : std_logic_vector(7 downto 0) := x"50";   -- DRDY | DSC
   constant C_ST_BUSY  : std_logic_vector(7 downto 0) := x"80";

   constant C_EVT_DELAY : natural := 8;   -- core clocks between an event and its toggle

   constant C_ERROR_STRINGS : string_vector(0 to 15) := (others => "OK                 \n");

   -- the two sector buffers: distributed RAM, one write port each, asynchronous read
   type t_buf is array (0 to 255) of std_logic_vector(15 downto 0);
   signal rd_buf : t_buf := (others => (others => '0'));   -- QNICE writes, CPU reads
   signal wr_buf : t_buf := (others => (others => '0'));   -- CPU writes, QNICE reads
   attribute ram_style : string;
   attribute ram_style of rd_buf : signal is "distributed";
   attribute ram_style of wr_buf : signal is "distributed";

   ---------------------------------------------------------------------------------------
   -- core clock domain
   ---------------------------------------------------------------------------------------

   type t_bus is (B_IDLE, B_ROM_REQ, B_ROM_WAIT, B_ACK);
   signal bus_state   : t_bus := B_IDLE;
   signal ready       : std_logic := '0';
   signal ack_rw      : std_logic := '1';
   signal rdata       : std_logic_vector(15 downto 0) := (others => '1');
   signal lat_addr    : std_logic_vector(16 downto 1) := (others => '0');

   signal ide_enabled : std_logic := '0';

   signal rom_read    : std_logic := '0';
   signal rom_c_valid : std_logic := '0';
   signal rom_c_addr  : std_logic_vector(13 downto 0) := (others => '0');
   signal rom_c_data  : std_logic_vector(15 downto 0) := (others => '0');

   -- ATA task file and state
   signal tf_feat, tf_scnt, tf_lba0, tf_lba1, tf_lba2, tf_cmd : std_logic_vector(7 downto 0) := (others => '0');
   signal tf_devh     : std_logic_vector(7 downto 0) := x"A0";
   signal status      : std_logic_vector(7 downto 0) := C_ST_READY;
   signal error       : std_logic_vector(7 downto 0) := x"01";
   signal srst        : std_logic := '0';
   signal phase_wr    : std_logic := '0';
   signal ptr         : unsigned(7 downto 0) := (others => '0');

   -- events to the firmware (toggles, raised C_EVT_DELAY clocks late)
   signal evt_cmd, evt_buf, evt_rst, evt_ack : std_logic := '0';
   signal dly_cmd, dly_buf, dly_rst, dly_ack : natural range 0 to C_EVT_DELAY := 0;

   -- commit from the firmware
   signal m_present, m_present1, m_board_ena : std_logic;
   signal m_commit_tgl, commit_seen : std_logic := '0';
   signal m_nstat, m_nerr, m_nflags, m_nscnt, m_nlba0, m_nlba1, m_nlba2, m_ndevh : std_logic_vector(7 downto 0);
   signal dly_commit  : natural range 0 to C_EVT_DELAY := 0;

   ---------------------------------------------------------------------------------------
   -- QNICE clock domain
   ---------------------------------------------------------------------------------------

   signal q_nstat   : std_logic_vector(7 downto 0) := C_ST_READY;
   signal q_nerr    : std_logic_vector(7 downto 0) := (others => '0');
   signal q_nflags  : std_logic_vector(7 downto 0) := (others => '0');
   signal q_nscnt, q_nlba0, q_nlba1, q_nlba2 : std_logic_vector(7 downto 0) := (others => '0');
   signal q_ndevh   : std_logic_vector(7 downto 0) := x"A0";
   signal q_ctrl    : std_logic_vector(2 downto 0) := "000";
   signal q_commit  : std_logic := '0';
   signal q_win0, q_reg_ce, q_csr, q_csr_wait : std_logic;
   signal q_csr_data, q_rd : std_logic_vector(15 downto 0);
   signal q_req_status, q_resp_status : std_logic_vector(3 downto 0);

   signal q_events  : std_logic_vector(3 downto 0);
   signal q_tf      : std_logic_vector(55 downto 0);

   signal q_bufaddr : unsigned(7 downto 0);

   -- CPU -> write buffer, one clock after the bus cycle (own process: LUTRAM inference)
   signal wb_we     : std_logic := '0';
   signal wb_addr   : unsigned(7 downto 0) := (others => '0');
   signal wb_data   : std_logic_vector(15 downto 0) := (others => '0');

   ---------------------------------------------------------------------------------------
   -- sector engine
   ---------------------------------------------------------------------------------------

   constant C_RING_LOG2 : natural := 3;
   constant C_RING      : natural := 2 ** C_RING_LOG2;
   constant C_ST_DRQ    : std_logic_vector(7 downto 0) := x"58";   -- DRDY | DSC | DRQ
   constant C_ST_ERR    : std_logic_vector(7 downto 0) := x"51";   -- DRDY | DSC | ERR

   -- core side
   type t_emode is (EM_NONE, EM_READ, EM_WRITE);
   signal e_mode      : t_emode := EM_NONE;
   signal e_left      : unsigned(8 downto 0) := (others => '0');   -- sectors left for the CPU
   signal e_avail     : unsigned(C_RING_LOG2 downto 0) := (others => '0');  -- read: full slots; write: free
   signal e_slot      : unsigned(C_RING_LOG2 - 1 downto 0) := (others => '0');
   signal e_err_pend  : std_logic := '0';
   signal m_acc_d, m_acc_s, m_acc_seen : std_logic := '0';
   signal m_accwr_d, m_accwr_s         : std_logic := '0';
   signal m_rdy_d, m_rdy_s, m_rdy_seen : std_logic := '0';
   signal m_fin_d, m_fin_s, m_fin_seen : std_logic := '0';
   signal m_finerr_d, m_finerr_s       : std_logic := '0';
   signal m_free_tgl  : std_logic := '0';
   signal rr_q        : std_logic_vector(15 downto 0);
   signal rr_addr     : std_logic_vector(C_RING_LOG2 + 7 downto 0);
   signal wr_we       : std_logic := '0';
   signal wr_addr     : std_logic_vector(C_RING_LOG2 + 7 downto 0) := (others => '0');

   attribute async_reg : string;
   attribute async_reg of m_acc_d, m_acc_s, m_accwr_d, m_accwr_s, m_rdy_d, m_rdy_s,
                          m_fin_d, m_fin_s, m_finerr_d, m_finerr_s : signal is "true";

   -- QNICE side
   signal q_free_d, q_free_s : std_logic := '0';
   attribute async_reg of q_free_d, q_free_s : signal is "true";
   signal q_win1      : std_logic;
   signal q_map_we_f  : std_logic := '0';                          -- falling-edge capture
   signal q_map_wa    : std_logic_vector(11 downto 0) := (others => '0');
   signal q_map_wd    : std_logic_vector(15 downto 0) := (others => '0');
   signal q_map_we    : std_logic := '0';
   signal q_cfg_wr_f, q_cfg_wr : std_logic := '0';
   signal q_mode0, q_mode1   : std_logic_vector(2 downto 0) := "000";
   signal q_sects0, q_sects1 : std_logic_vector(31 downto 0) := (others => '0');
   signal q_base0, q_base1   : std_logic_vector(31 downto 0) := (others => '0');
   signal q_shift0, q_shift1 : std_logic_vector(2 downto 0) := (others => '0');
   signal q_map_addr  : std_logic_vector(11 downto 0);
   signal q_map_q     : std_logic_vector(15 downto 0);
   signal q_fw_cmd    : std_logic;
   signal q_acc, q_acc_wr, q_rdy, q_fin, q_fin_err : std_logic;
   signal q_rr_we     : std_logic;
   signal q_rr_addr   : std_logic_vector(C_RING_LOG2 + 7 downto 0);
   signal q_rr_data   : std_logic_vector(15 downto 0);
   signal q_wr_addr   : std_logic_vector(C_RING_LOG2 + 7 downto 0);
   signal q_wr_q      : std_logic_vector(15 downto 0);
   signal q_st_acc, q_st_fwd, q_st_err : std_logic_vector(15 downto 0);
   signal q_eng_busy  : std_logic;

   -- helpers
   function rd8(v : std_logic_vector(7 downto 0)) return std_logic_vector is
   begin
      return v & x"FF";                      -- 8-bit registers are on D15..D8
   end function rd8;

begin

   ready_o     <= ready and sel_i and not (rw_i xor ack_rw);
   data_o      <= rdata;
   board_ena_o <= m_board_ena;
   activity_o  <= status(C_BSY) or status(C_DRQ);

   rom_avm_read_o    <= rom_read;
   rom_avm_address_o <= std_logic_vector(resize(unsigned(G_ROM_BASE) + unsigned(lat_addr(15 downto 2)), 32));

   ---------------------------------------------------------------------------------------
   -- Bus cycles, ATA register file, events and commits (core clock)
   ---------------------------------------------------------------------------------------

   bus_proc : process (clk_i)
      variable a         : std_logic_vector(16 downto 1);
      variable is_rom    : boolean;
      variable is_tf     : boolean;   -- channel 0 command block
      variable is_ctl    : boolean;   -- channel 0 control block
      variable reg       : natural range 0 to 7;
      variable present   : boolean;
      variable byte      : std_logic_vector(7 downto 0);
      variable va        : unsigned(C_RING_LOG2 downto 0);   -- e_avail of this clock
      variable e_sect    : boolean;                           -- the CPU finished a sector

      procedure buffer_done is
      begin
         status  <= C_ST_BUSY;
         dly_buf <= C_EVT_DELAY;
      end procedure;

      procedure device_reset is
      begin
         status   <= C_ST_READY;
         error    <= x"01";                   -- diagnostic code: no error
         tf_devh  <= x"A0";
         ptr      <= (others => '0');
         phase_wr <= '0';
         dly_rst  <= C_EVT_DELAY;
         e_mode   <= EM_NONE;
      end procedure;
   begin
      if rising_edge(clk_i) then
         wb_we  <= '0';
         wr_we  <= '0';
         e_sect := false;

         -- sector engine handshake (single-bit toggles from the QNICE domain)
         m_acc_d    <= q_acc;     m_acc_s    <= m_acc_d;
         m_accwr_d  <= q_acc_wr;  m_accwr_s  <= m_accwr_d;
         m_rdy_d    <= q_rdy;     m_rdy_s    <= m_rdy_d;
         m_fin_d    <= q_fin;     m_fin_s    <= m_fin_d;
         m_finerr_d <= q_fin_err; m_finerr_s <= m_finerr_d;
         va := e_avail;
         if m_rdy_s /= m_rdy_seen then           -- read: a sector more; write: a slot free
            m_rdy_seen <= m_rdy_s;
            if e_mode /= EM_NONE then
               va := va + 1;
            end if;
         end if;

         -- delayed event toggles
         if dly_cmd = 1 then evt_cmd <= not evt_cmd; end if;
         if dly_buf = 1 then evt_buf <= not evt_buf; end if;
         if dly_rst = 1 then evt_rst <= not evt_rst; end if;
         if dly_ack = 1 then evt_ack <= not evt_ack; end if;
         if dly_cmd /= 0 then dly_cmd <= dly_cmd - 1; end if;
         if dly_buf /= 0 then dly_buf <= dly_buf - 1; end if;
         if dly_rst /= 0 then dly_rst <= dly_rst - 1; end if;
         if dly_ack /= 0 then dly_ack <= dly_ack - 1; end if;

         -- commits from the firmware: applied C_EVT_DELAY clocks after the toggle, only
         -- while BSY, always acknowledged
         if m_commit_tgl /= commit_seen then
            commit_seen <= m_commit_tgl;
            dly_commit  <= C_EVT_DELAY;
         end if;
         if dly_commit /= 0 then
            dly_commit <= dly_commit - 1;
            if dly_commit = 1 then
               if status(C_BSY) = '1' then
                  status <= m_nstat;
                  error  <= m_nerr;
                  if m_nflags(1) = '1' then
                     tf_scnt <= m_nscnt;
                     tf_lba0 <= m_nlba0;
                     tf_lba1 <= m_nlba1;
                     tf_lba2 <= m_nlba2;
                     tf_devh <= m_ndevh;
                  end if;
                  if m_nstat(C_DRQ) = '1' then
                     ptr      <= (others => '0');
                     phase_wr <= m_nflags(0);
                  end if;
               end if;
               dly_ack <= C_EVT_DELAY;
            end if;
         end if;

         present := (m_present = '1' and tf_devh(4) = '0') or (m_present1 = '1' and tf_devh(4) = '1');

         case bus_state is

            when B_IDLE =>
               ready <= '0';
               -- a write starts once a data strobe is valid (the data is valid then)
               if sel_i = '1' and (rw_i = '1' or uds_n_i = '0' or lds_n_i = '0') then
                  a        := addr_i;
                  lat_addr <= addr_i;
                  ack_rw   <= rw_i;
                  is_rom   := ide_enabled = '0' or a(16) = '1' or a(13) = a(12);
                  is_tf    := ide_enabled = '1' and a(16 downto 12) = "00001";
                  is_ctl   := ide_enabled = '1' and a(16 downto 12) = "00101";
                  reg      := to_integer(unsigned(a(11 downto 9)));
                  byte     := data_i(15 downto 8);
                  rdata    <= (others => '1');

                  if rw_i = '1' then
                     -------------------------------------------------------------- reads
                     if is_rom then
                        if rom_c_valid = '1' and rom_c_addr = a(15 downto 2) then
                           rdata     <= (rom_c_data(7 downto 0) & x"FF") when a(1) = '0' else
                                        (rom_c_data(15 downto 8) & x"FF");
                           ready     <= '1';
                           bus_state <= B_ACK;
                        else
                           rom_read  <= '1';
                           bus_state <= B_ROM_REQ;
                        end if;
                     else
                        if (is_tf or is_ctl) and present then
                           if is_ctl then
                              if reg = 6 then rdata <= rd8(status); end if;   -- alternate status
                           else
                              case reg is
                                 when 0 =>
                                    if status(C_DRQ) = '1' and phase_wr = '0' and e_mode = EM_READ then
                                       rdata <= rr_q;           -- the sector engine's ring
                                       ptr   <= ptr + 1;
                                       if ptr = 255 then
                                          e_sect := true;
                                       end if;
                                    elsif status(C_DRQ) = '1' and phase_wr = '0' then
                                       rdata <= rd_buf(to_integer(ptr));
                                       ptr   <= ptr + 1;
                                       if ptr = 255 then
                                          buffer_done;
                                       end if;
                                    else
                                       rdata <= (others => '0');
                                    end if;
                                 when 1 => rdata <= rd8(error);
                                 when 2 => rdata <= rd8(tf_scnt);
                                 when 3 => rdata <= rd8(tf_lba0);
                                 when 4 => rdata <= rd8(tf_lba1);
                                 when 5 => rdata <= rd8(tf_lba2);
                                 when 6 => rdata <= rd8(tf_devh);
                                 when others => rdata <= rd8(status);
                              end case;
                           end if;
                        end if;
                        ready     <= '1';
                        bus_state <= B_ACK;
                     end if;
                  else
                     -------------------------------------------------------------- writes
                     if uds_n_i = '0' then
                        ide_enabled <= '1';          -- RIPPLE: the first write maps the IDE in
                     end if;
                     if is_tf then
                        case reg is
                           when 0 =>
                              if present and status(C_DRQ) = '1' and phase_wr = '1' then
                                 wb_we   <= '1';
                                 wb_addr <= ptr;
                                 wb_data <= data_i;
                                 ptr     <= ptr + 1;
                                 if e_mode = EM_WRITE then
                                    wr_we   <= '1';        -- the sector engine's ring
                                    wr_addr <= std_logic_vector(e_slot) & std_logic_vector(ptr);
                                    if ptr = 255 then
                                       e_sect := true;
                                    end if;
                                 elsif ptr = 255 then
                                    buffer_done;
                                 end if;
                              end if;
                           when 6 =>
                              tf_devh <= byte;       -- always: it selects master/slave
                           when 7 =>
                              if present and status(C_BSY) = '0' then
                                 tf_cmd  <= byte;
                                 status  <= C_ST_BUSY;
                                 error   <= x"00";
                                 dly_cmd <= C_EVT_DELAY;
                              end if;
                           when others =>
                              if status(C_BSY) = '0' then
                                 case reg is
                                    when 1 => tf_feat <= byte;
                                    when 2 => tf_scnt <= byte;
                                    when 3 => tf_lba0 <= byte;
                                    when 4 => tf_lba1 <= byte;
                                    when 5 => tf_lba2 <= byte;
                                    when others => null;
                                 end case;
                              end if;
                        end case;
                     elsif is_ctl and reg = 6 then   -- device control: SRST is bit 2
                        srst <= byte(2);
                        if byte(2) = '1' then
                           status <= C_ST_BUSY;
                        elsif srst = '1' then
                           device_reset;
                        end if;
                     end if;
                     ready     <= '1';
                     bus_state <= B_ACK;
                  end if;
               end if;

            when B_ROM_REQ =>
               if rom_avm_waitrequest_i = '0' then
                  rom_read  <= '0';
                  bus_state <= B_ROM_WAIT;
               end if;

            when B_ROM_WAIT =>
               if rom_avm_readdatavalid_i = '1' then
                  rom_c_valid <= '1';
                  rom_c_addr  <= lat_addr(15 downto 2);
                  rom_c_data  <= rom_avm_readdata_i;
                  rdata       <= (rom_avm_readdata_i(7 downto 0) & x"FF") when lat_addr(1) = '0' else
                                 (rom_avm_readdata_i(15 downto 8) & x"FF");
                  ready       <= '1';
                  bus_state   <= B_ACK;
               end if;

            when B_ACK =>
               -- hold DTACK until the cycle ends (AS negated or the direction changed)
               if sel_i = '0' or rw_i /= ack_rw then
                  ready     <= '0';
                  bus_state <= B_IDLE;
               end if;
         end case;

         ---------------------------------------------------------------------------------
         -- sector engine: command taken, sectors, completion
         ---------------------------------------------------------------------------------
         if m_acc_s /= m_acc_seen then
            m_acc_seen <= m_acc_s;
            if status(C_BSY) = '1' and e_mode = EM_NONE then
               if tf_scnt = x"00" then
                  e_left <= to_unsigned(256, 9);
               else
                  e_left <= resize(unsigned(tf_scnt), 9);
               end if;
               e_slot     <= (others => '0');
               ptr        <= (others => '0');
               e_err_pend <= '0';
               if m_accwr_s = '1' then
                  e_mode   <= EM_WRITE;
                  va       := to_unsigned(C_RING, C_RING_LOG2 + 1);
                  status   <= C_ST_DRQ;
                  phase_wr <= '1';
               else
                  e_mode   <= EM_READ;
                  va       := (others => '0');
                  phase_wr <= '0';
               end if;
            end if;
         end if;

         if m_fin_s /= m_fin_seen then
            m_fin_seen <= m_fin_s;
            if e_mode = EM_WRITE then
               if m_finerr_s = '1' then
                  status <= C_ST_ERR;
                  error  <= x"40";                -- UNC
               else
                  status <= C_ST_READY;
               end if;
               e_mode <= EM_NONE;
            elsif e_mode = EM_READ and m_finerr_s = '1' then
               e_err_pend <= '1';
            end if;
         end if;

         if e_sect then
            -- the CPU read (read) or filled (write) the sector of slot e_slot
            e_slot     <= e_slot + 1;
            m_free_tgl <= not m_free_tgl;
            va         := va - 1;
            e_left     <= e_left - 1;
            if e_left = 1 then
               if e_mode = EM_READ then
                  status <= C_ST_READY;           -- all data delivered
                  e_mode <= EM_NONE;
               else
                  status <= C_ST_BUSY;            -- until the last sector is on the card
               end if;
            elsif va /= 0 and not (e_mode = EM_READ and e_err_pend = '1') then
               null;                              -- DRQ stays, ptr wrapped to 0
            else
               status <= C_ST_BUSY;
            end if;
         elsif e_mode = EM_READ and status(C_BSY) = '1' then
            if e_err_pend = '1' then
               status <= C_ST_ERR;
               error  <= x"40";                   -- UNC
               e_mode <= EM_NONE;
            elsif va /= 0 then
               status   <= C_ST_DRQ;
               ptr      <= (others => '0');
               phase_wr <= '0';
            end if;
         elsif e_mode = EM_WRITE and status(C_BSY) = '1' and e_left /= 0 and va /= 0 then
            status   <= C_ST_DRQ;
            ptr      <= (others => '0');
            phase_wr <= '1';
         end if;
         e_avail <= va;

         if rst_i = '1' then
            bus_state   <= B_IDLE;
            ready       <= '0';
            rom_read    <= '0';
            rom_c_valid <= '0';
            ide_enabled <= '0';
            srst        <= '0';
            tf_feat <= (others => '0'); tf_scnt <= (others => '0'); tf_lba0 <= (others => '0');
            tf_lba1 <= (others => '0'); tf_lba2 <= (others => '0'); tf_cmd  <= (others => '0');
            device_reset;
         end if;
      end if;
   end process bus_proc;

   wr_buf_proc : process (clk_i)
   begin
      if rising_edge(clk_i) then
         if wb_we = '1' then
            wr_buf(to_integer(wb_addr)) <= wb_data;
         end if;
      end if;
   end process wr_buf_proc;

   ---------------------------------------------------------------------------------------
   -- Clock domain crossings (both directions: slowly changing values plus toggles; the
   -- toggles follow their payload, see the header)
   ---------------------------------------------------------------------------------------

   i_cdc_to_core : entity work.cdc_stable
      generic map (
         G_DATA_SIZE    => 68,
         G_REGISTER_SRC => true
      )
      port map (
         src_clk_i                => qnice_clk_i,
         src_data_i( 7 downto  0) => q_nstat,
         src_data_i(15 downto  8) => q_nerr,
         src_data_i(23 downto 16) => q_nflags,
         src_data_i(31 downto 24) => q_nscnt,
         src_data_i(39 downto 32) => q_nlba0,
         src_data_i(47 downto 40) => q_nlba1,
         src_data_i(55 downto 48) => q_nlba2,
         src_data_i(63 downto 56) => q_ndevh,
         src_data_i(64)           => q_ctrl(0),
         src_data_i(65)           => q_ctrl(1),
         src_data_i(66)           => q_commit,
         src_data_i(67)           => q_ctrl(2),
         dst_clk_i                => clk_i,
         dst_data_o( 7 downto  0) => m_nstat,
         dst_data_o(15 downto  8) => m_nerr,
         dst_data_o(23 downto 16) => m_nflags,
         dst_data_o(31 downto 24) => m_nscnt,
         dst_data_o(39 downto 32) => m_nlba0,
         dst_data_o(47 downto 40) => m_nlba1,
         dst_data_o(55 downto 48) => m_nlba2,
         dst_data_o(63 downto 56) => m_ndevh,
         dst_data_o(64)           => m_present,
         dst_data_o(65)           => m_board_ena,
         dst_data_o(66)           => m_commit_tgl,
         dst_data_o(67)           => m_present1
      ); -- i_cdc_to_core

   i_cdc_to_qnice : entity work.cdc_stable
      generic map (
         G_DATA_SIZE    => 60,
         G_REGISTER_SRC => true
      )
      port map (
         src_clk_i                => clk_i,
         src_data_i( 7 downto  0) => tf_cmd,
         src_data_i(15 downto  8) => tf_feat,
         src_data_i(23 downto 16) => tf_scnt,
         src_data_i(31 downto 24) => tf_lba0,
         src_data_i(39 downto 32) => tf_lba1,
         src_data_i(47 downto 40) => tf_lba2,
         src_data_i(55 downto 48) => tf_devh,
         src_data_i(56)           => evt_cmd,
         src_data_i(57)           => evt_buf,
         src_data_i(58)           => evt_rst,
         src_data_i(59)           => evt_ack,
         dst_clk_i                => qnice_clk_i,
         dst_data_o(55 downto  0) => q_tf,
         dst_data_o(59 downto 56) => q_events
      ); -- i_cdc_to_qnice

   ---------------------------------------------------------------------------------------
   -- Sector engine (QNICE clock) and its rings
   ---------------------------------------------------------------------------------------

   -- read ring: the engine writes (QNICE clock), the CPU reads (core clock)
   rr_addr <= std_logic_vector(e_slot) & std_logic_vector(ptr);

   i_rring : entity work.tdp_ram
      generic map (
         ADDR_WIDTH => C_RING_LOG2 + 8,
         DATA_WIDTH => 16
      )
      port map (
         clock_a   => qnice_clk_i,
         address_a => q_rr_addr,
         data_a    => q_rr_data,
         wren_a    => q_rr_we,
         q_a       => open,
         clock_b   => clk_i,
         address_b => rr_addr,
         data_b    => (others => '0'),
         wren_b    => '0',
         q_b       => rr_q
      ); -- i_rring

   -- write ring: the CPU writes (core clock), the engine reads (QNICE clock)
   i_wring : entity work.tdp_ram
      generic map (
         ADDR_WIDTH => C_RING_LOG2 + 8,
         DATA_WIDTH => 16
      )
      port map (
         clock_a   => clk_i,
         address_a => wr_addr,
         data_a    => wb_data,
         wren_a    => wr_we,
         q_a       => open,
         clock_b   => qnice_clk_i,
         address_b => q_wr_addr,
         data_b    => (others => '0'),
         wren_b    => '0',
         q_b       => q_wr_q
      ); -- i_wring

   -- the extent maps: the firmware writes (window 1), the engine reads
   i_map : entity work.tdp_ram
      generic map (
         ADDR_WIDTH => 12,
         DATA_WIDTH => 16
      )
      port map (
         clock_a   => qnice_clk_i,
         address_a => q_map_wa,
         data_a    => q_map_wd,
         wren_a    => q_map_we,
         q_a       => open,
         clock_b   => qnice_clk_i,
         address_b => q_map_addr,
         data_b    => (others => '0'),
         wren_b    => '0',
         q_b       => q_map_q
      ); -- i_map

   -- the core side's free toggle into the QNICE domain
   q_sync_proc : process (qnice_clk_i)
   begin
      if rising_edge(qnice_clk_i) then
         q_free_d <= m_free_tgl;
         q_free_s <= q_free_d;
         -- writes captured on the falling edge, applied on the rising one
         q_map_we <= q_map_we_f;
         q_cfg_wr <= q_cfg_wr_f;
      end if;
   end process q_sync_proc;

   i_engine : entity work.ide_engine
      generic map (
         G_RING_LOG2 => C_RING_LOG2
      )
      port map (
         clk_i        => qnice_clk_i,
         rst_i        => qnice_rst_i,
         tf_i         => q_tf,
         cmd_tgl_i    => q_events(0),
         rst_tgl_i    => q_events(2),
         fw_cmd_tgl_o => q_fw_cmd,
         cfg_mode0_i  => q_mode0(1 downto 0),
         cfg_mode1_i  => q_mode1(1 downto 0),
         cfg_slot0_i  => q_mode0(2),
         cfg_slot1_i  => q_mode1(2),
         cfg_sects0_i => q_sects0,
         cfg_sects1_i => q_sects1,
         cfg_base0_i  => q_base0,
         cfg_base1_i  => q_base1,
         cfg_shift0_i => q_shift0,
         cfg_shift1_i => q_shift1,
         cfg_wr_i     => q_cfg_wr,
         map_addr_o   => q_map_addr,
         map_data_i   => q_map_q,
         acc_tgl_o    => q_acc,
         acc_wr_o     => q_acc_wr,
         rdy_tgl_o    => q_rdy,
         fin_tgl_o    => q_fin,
         fin_err_o    => q_fin_err,
         free_tgl_i   => q_free_s,
         rring_we_o   => q_rr_we,
         rring_addr_o => q_rr_addr,
         rring_data_o => q_rr_data,
         wring_addr_o => q_wr_addr,
         wring_data_i => q_wr_q,
         st_acc_o     => q_st_acc,
         st_fwd_o     => q_st_fwd,
         st_err_o     => q_st_err,
         busy_o       => q_eng_busy,
         sd_slot_o    => sd_slot_o,
         sd_ready_i   => sd_ready_i,
         sd_start_o   => sd_start_o,
         sd_write_o   => sd_write_o,
         sd_addr_o    => sd_addr_o,
         sd_count_o   => sd_count_o,
         sd_limit_o   => sd_limit_o,
         sd_abort_o   => sd_abort_o,
         sd_busy_i    => sd_busy_i,
         sd_done_i    => sd_done_i,
         sd_error_i   => sd_error_i,
         sd_blk_i     => sd_blk_i,
         sd_rd_we_i   => sd_rd_we_i,
         sd_rd_blk_i  => sd_rd_blk_i,
         sd_rd_idx_i  => sd_rd_idx_i,
         sd_rd_data_i => sd_rd_data_i,
         sd_wr_blk_i  => sd_wr_blk_i,
         sd_wr_idx_i  => sd_wr_idx_i,
         sd_wr_data_o => sd_wr_data_o
      ); -- i_engine

   ---------------------------------------------------------------------------------------
   -- Firmware interface (QNICE clock)
   ---------------------------------------------------------------------------------------

   q_bufaddr    <= unsigned(qnice_addr_i(7 downto 0));
   q_win0       <= '1' when qnice_addr_i(27 downto 12) = x"0000" else '0';
   q_win1       <= '1' when qnice_addr_i(27 downto 12) = x"0001" else '0';
   q_reg_ce     <= qnice_ce_i and q_win0;

   -- the M2M CSR in window 0xFFFF: answers READY as soon as the Shell reports the file
   i_qnice_csr : entity work.qnice_csr
      generic map (
         G_ERROR_STRINGS => C_ERROR_STRINGS
      )
      port map (
         qnice_clk_i          => qnice_clk_i,
         qnice_rst_i          => qnice_rst_i,
         qnice_addr_i         => qnice_addr_i,
         qnice_data_i         => qnice_data_i,
         qnice_ce_i           => qnice_ce_i,
         qnice_we_i           => qnice_we_i,
         qnice_data_o         => q_csr_data,
         qnice_wait_o         => q_csr_wait,
         qnice_csr_o          => q_csr,
         qnice_req_status_o   => q_req_status,
         qnice_req_length_o   => open,
         qnice_resp_status_i  => q_resp_status,
         qnice_resp_error_i   => x"0",
         qnice_resp_address_i => (others => '0')
      ); -- i_qnice_csr

   q_resp_status <= C_CSR_RESP_READY when q_req_status = C_CSR_REQ_OK else C_CSR_RESP_IDLE;

   qnice_data_o <= q_csr_data when q_csr = '1' else q_rd;
   qnice_wait_o <= q_csr_wait when q_csr = '1' else '0';

   qnice_write_proc : process (qnice_clk_i)
   begin
      if falling_edge(qnice_clk_i) then
         q_map_we_f <= '0';
         q_cfg_wr_f <= '0';
         if qnice_ce_i = '1' and qnice_we_i = '1' and q_win1 = '1' then
            q_map_we_f <= '1';
            q_map_wa   <= qnice_addr_i(11 downto 0);
            q_map_wd   <= qnice_data_i;
         end if;
         if q_reg_ce = '1' and qnice_we_i = '1' then
            if qnice_addr_i(8) = '0' then
               rd_buf(to_integer(q_bufaddr)) <= qnice_data_i;
            else
               case qnice_addr_i(7 downto 0) is
                  when x"10" => q_nstat  <= qnice_data_i(7 downto 0);
                  when x"11" => q_nerr   <= qnice_data_i(7 downto 0);
                  when x"12" => q_nflags <= qnice_data_i(7 downto 0);
                  when x"13" => q_nscnt  <= qnice_data_i(7 downto 0);
                  when x"14" => q_nlba0  <= qnice_data_i(7 downto 0);
                  when x"15" => q_nlba1  <= qnice_data_i(7 downto 0);
                  when x"16" => q_nlba2  <= qnice_data_i(7 downto 0);
                  when x"17" => q_ndevh  <= qnice_data_i(7 downto 0);
                  when x"18" => q_ctrl   <= qnice_data_i(2 downto 0);
                  when x"1F" => q_commit <= not q_commit;
                  when x"20" => q_mode0  <= qnice_data_i(2 downto 0);
                  when x"21" => q_sects0(15 downto 0)  <= qnice_data_i;
                  when x"22" => q_sects0(31 downto 16) <= qnice_data_i;
                  when x"23" => q_base0(15 downto 0)   <= qnice_data_i;
                  when x"24" => q_base0(31 downto 16)  <= qnice_data_i;
                  when x"25" => q_shift0 <= qnice_data_i(2 downto 0);
                  when x"28" => q_mode1  <= qnice_data_i(2 downto 0);
                  when x"29" => q_sects1(15 downto 0)  <= qnice_data_i;
                  when x"2A" => q_sects1(31 downto 16) <= qnice_data_i;
                  when x"2B" => q_base1(15 downto 0)   <= qnice_data_i;
                  when x"2C" => q_base1(31 downto 16)  <= qnice_data_i;
                  when x"2D" => q_shift1 <= qnice_data_i(2 downto 0);
                  when others => null;
               end case;
               if qnice_addr_i(7 downto 4) = x"2" then
                  q_cfg_wr_f <= '1';
               end if;
            end if;
         end if;
         if qnice_rst_i = '1' then
            q_ctrl  <= "000";
            q_mode0 <= "000";
            q_mode1 <= "000";
         end if;
      end if;
   end process qnice_write_proc;

   -- Read data is registered on the falling edge (address stable then, data consumed at
   -- the following rising edge, no wait states): the QNICE device data path into the
   -- CPU only sees one flip-flop - the pattern of physical_fdd_diag (WIP-V2-A5), which
   -- keeps the half-period qnice_dev_data_o cone short.
   qnice_read_proc : process (qnice_clk_i)
      variable d : std_logic_vector(15 downto 0);
   begin
      if falling_edge(qnice_clk_i) then
         d := (others => '0');
         if qnice_addr_i(8) = '0' then
            d := wr_buf(to_integer(q_bufaddr));
         else
            case qnice_addr_i(7 downto 0) is
               when x"00" => d(3 downto 0) := q_events(3 downto 1) & q_fw_cmd;
               when x"01" => d(7 downto 0) := q_tf( 7 downto  0);
               when x"02" => d(7 downto 0) := q_tf(15 downto  8);
               when x"03" => d(7 downto 0) := q_tf(23 downto 16);
               when x"04" => d(7 downto 0) := q_tf(31 downto 24);
               when x"05" => d(7 downto 0) := q_tf(39 downto 32);
               when x"06" => d(7 downto 0) := q_tf(47 downto 40);
               when x"07" => d(7 downto 0) := q_tf(55 downto 48);
               when x"10" => d(7 downto 0) := q_nstat;
               when x"11" => d(7 downto 0) := q_nerr;
               when x"12" => d(7 downto 0) := q_nflags;
               when x"13" => d(7 downto 0) := q_nscnt;
               when x"14" => d(7 downto 0) := q_nlba0;
               when x"15" => d(7 downto 0) := q_nlba1;
               when x"16" => d(7 downto 0) := q_nlba2;
               when x"17" => d(7 downto 0) := q_ndevh;
               when x"18" => d(2 downto 0) := q_ctrl;
               when x"20" => d(2 downto 0) := q_mode0;
               when x"21" => d := q_sects0(15 downto 0);
               when x"22" => d := q_sects0(31 downto 16);
               when x"23" => d := q_base0(15 downto 0);
               when x"24" => d := q_base0(31 downto 16);
               when x"25" => d(2 downto 0) := q_shift0;
               when x"28" => d(2 downto 0) := q_mode1;
               when x"29" => d := q_sects1(15 downto 0);
               when x"2A" => d := q_sects1(31 downto 16);
               when x"2B" => d := q_base1(15 downto 0);
               when x"2C" => d := q_base1(31 downto 16);
               when x"2D" => d(2 downto 0) := q_shift1;
               when x"30" => d(1 downto 0) := q_eng_busy & sd_ready_i;
               when x"31" => d := q_st_acc;
               when x"32" => d := q_st_fwd;
               when x"33" => d := q_st_err;
               when others => null;
            end case;
         end if;
         q_rd <= d;
      end if;
   end process qnice_read_proc;

end architecture synthesis;
