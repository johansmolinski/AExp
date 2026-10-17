---------------------------------------------------------------------------------------------------------
-- Megamiga for MEGA65
--
-- ide_engine: READ SECTORS / WRITE SECTORS of the IDE board in hardware (QNICE clock domain).
--
-- The firmware ATA server (m2m-rom.asm, IDE_STEP) gets one time slice per pass of the QNICE
-- main loop and copies every sector through the CPU, which limits a hard disk to a few hundred
-- KB/s. This engine takes the two data commands away from it: it decodes the command from the
-- task file snapshot, translates the sectors to SD card blocks through the extent map the
-- firmware put into the board (cluster runs, FAT32$FILE_MAP format) or through the partition
-- start, and streams the blocks with multi-block commands through the engine port of the SD
-- host controller (M2M/vhdl/QNICE/sdhost.vhd) into or out of a ring of sector buffers that the
-- Amiga reads or writes at the same time. Everything else - IDENTIFY, errors, commands for a
-- unit the engine does not serve, sectors outside the image, CHS addresses that are invalid
-- for the unit's geometry (or a unit without one) - goes to the firmware as before: the
-- engine forwards the command event. CHS addressing (the scsi.device of Kickstart 3.1 and
-- older; Megamiga 0.7) is converted to LBA with the geometry the firmware writes (cfg_geom).
--
-- Handshake with the core side of ide_board (single-bit toggles, synchronised by the board):
--   acc   the engine took the command (acc_wr_o = direction, stable 4 clocks before)
--   rdy   read: one more sector is in the ring; write: one more ring slot is free again
--   fin   write: all sectors are on the card; read or write: error (fin_err_o, stable before)
--   free  (from the core) read: the CPU read a sector; write: the CPU filled a sector
-- An Amiga/ATA reset (rst toggle) aborts a command at the next block boundary.
--
-- Map / configuration (written by the firmware, registers in ide_board): per unit u
--   mode   0 = off (firmware), 1 = file (extent map), 2 = partition
--   slot   the SD card: 0 = bottom tray, 1 = back slot (sd_slot_o selects the controller)
--   sects  sectors of the image
--   base   file: DEV_CLUSTER - (2 << shift) (block of cluster 0); partition: first block
--   shift  log2(sectors per cluster)
--   map    words u * 2048 + ...: word 0 extents n, then n x (first cluster lo/hi, clusters lo/hi)
--
-- Done in 2026 (Megamiga fork) and licensed under GPL v3.
---------------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ide_engine is
   generic (
      G_RING_LOG2 : natural := 3                  -- sectors in each ring = 2 ** G_RING_LOG2
   );
   port (
      clk_i          : in  std_logic;             -- QNICE clock
      rst_i          : in  std_logic;

      -- from the board (QNICE domain)
      tf_i           : in  std_logic_vector(55 downto 0);  -- cmd, feat, scnt, lba0, lba1, lba2, devh
      cmd_tgl_i      : in  std_logic;
      rst_tgl_i      : in  std_logic;
      fw_cmd_tgl_o   : out std_logic;             -- the command event as the firmware sees it

      -- configuration
      cfg_mode0_i    : in  std_logic_vector(1 downto 0);
      cfg_mode1_i    : in  std_logic_vector(1 downto 0);
      cfg_slot0_i    : in  std_logic := '0';
      cfg_slot1_i    : in  std_logic := '0';
      -- Megamiga 0.7: the unit has a multiple count (SET MULTIPLE MODE): READ/WRITE
      -- MULTIPLE (0xC4/0xC5) are served too; the board groups the sectors into blocks
      cfg_mult0_i    : in  std_logic := '0';
      cfg_mult1_i    : in  std_logic := '0';
      -- Megamiga 0.7: the unit's CHS geometry (INITIALIZE DEVICE PARAMETERS, the firmware's
      -- HDF_HEADS/HDF_SPT): bits 15..12 heads - 1, bits 8..0 sectors per track (1..256);
      -- 0 = none: CHS commands go to the firmware
      cfg_geom0_i    : in  std_logic_vector(15 downto 0) := (others => '0');
      cfg_geom1_i    : in  std_logic_vector(15 downto 0) := (others => '0');
      cfg_sects0_i   : in  std_logic_vector(31 downto 0);
      cfg_sects1_i   : in  std_logic_vector(31 downto 0);
      cfg_base0_i    : in  std_logic_vector(31 downto 0);
      cfg_base1_i    : in  std_logic_vector(31 downto 0);
      cfg_shift0_i   : in  std_logic_vector(2 downto 0);
      cfg_shift1_i   : in  std_logic_vector(2 downto 0);
      cfg_wr_i       : in  std_logic;             -- any configuration write: drop caches
      map_addr_o     : out std_logic_vector(11 downto 0);
      map_data_i     : in  std_logic_vector(15 downto 0);  -- one clock after the address

      -- handshake with the core side
      acc_tgl_o      : out std_logic;
      acc_wr_o       : out std_logic;
      rdy_tgl_o      : out std_logic;
      fin_tgl_o      : out std_logic;
      fin_err_o      : out std_logic;
      free_tgl_i     : in  std_logic;             -- synchronised

      -- the rings (QNICE side)
      rring_we_o     : out std_logic;
      rring_addr_o   : out std_logic_vector(G_RING_LOG2 + 7 downto 0);
      rring_data_o   : out std_logic_vector(15 downto 0);
      wring_addr_o   : out std_logic_vector(G_RING_LOG2 + 7 downto 0);
      wring_data_i   : in  std_logic_vector(15 downto 0);  -- one clock after the address

      -- statistics
      st_acc_o       : out std_logic_vector(15 downto 0); -- commands taken
      st_fwd_o       : out std_logic_vector(15 downto 0); -- commands forwarded
      st_err_o       : out std_logic_vector(15 downto 0); -- commands failed
      busy_o         : out std_logic;

      -- SD host engine port
      sd_slot_o      : out std_logic;             -- the controller (stable while busy)
      sd_ready_i     : in  std_logic;             -- of the controller sd_slot_o names
      sd_gnt_i       : in  std_logic := '1';      -- Megamiga: owns the shared port (sd_eng_arb)
      sd_start_o     : out std_logic;
      sd_write_o     : out std_logic;
      sd_addr_o      : out std_logic_vector(31 downto 0);
      sd_count_o     : out std_logic_vector(15 downto 0);
      sd_limit_o     : out std_logic_vector(15 downto 0);
      sd_abort_o     : out std_logic;
      sd_busy_i      : in  std_logic;
      sd_done_i      : in  std_logic;
      sd_error_i     : in  std_logic;
      sd_blk_i       : in  std_logic;
      sd_rd_we_i     : in  std_logic;
      sd_rd_blk_i    : in  std_logic_vector(15 downto 0);
      sd_rd_idx_i    : in  std_logic_vector(8 downto 0);
      sd_rd_data_i   : in  std_logic_vector(7 downto 0);
      sd_wr_blk_i    : in  std_logic_vector(15 downto 0);
      sd_wr_idx_i    : in  std_logic_vector(8 downto 0);
      sd_wr_data_o   : out std_logic_vector(7 downto 0)
   );
end entity ide_engine;

architecture synthesis of ide_engine is

   constant C_RING : natural := 2 ** G_RING_LOG2;

   type t_state is (
      E_IDLE, E_DECIDE, E_CHS1, E_CHS2, E_CHS3, E_ACC_WAIT, E_LOOK, E_LOOK_N, E_LOOK_EXT, E_LOOK_CMP, E_LOOK_C2,
      E_LOOK_C3, E_START, E_RUN,
      E_WAIT_DATA, E_FAIL, E_FAIL2, E_ABORT
   );
   signal st        : t_state := E_IDLE;

   signal cmd_seen  : std_logic := '0';
   signal rst_seen  : std_logic := '0';
   signal fw_tgl    : std_logic := '0';
   signal acc_tgl   : std_logic := '0';
   signal acc_wr    : std_logic := '0';
   signal rdy_tgl   : std_logic := '0';
   signal fin_tgl   : std_logic := '0';
   signal fin_err   : std_logic := '0';
   signal free_seen : std_logic := '0';

   -- the command
   signal unit      : std_logic := '0';
   signal wr        : std_logic := '0';
   signal lba       : unsigned(31 downto 0) := (others => '0');   -- next sector to start
   -- Megamiga 0.7: CHS -> LBA (E_CHS1..3): LBA = (cylinder x heads + head) x spt + sector - 1
   signal ch_cyl    : unsigned(15 downto 0) := (others => '0');
   signal ch_head   : unsigned(3 downto 0) := (others => '0');
   signal ch_sec    : unsigned(7 downto 0) := (others => '0');
   signal ch_heads  : unsigned(4 downto 0) := (others => '0');
   signal ch_spt    : unsigned(8 downto 0) := (others => '0');
   signal ch_p1     : unsigned(20 downto 0) := (others => '0');
   signal ch_wr     : std_logic := '0';
   signal left      : unsigned(8 downto 0) := (others => '0');    -- sectors not yet started
   signal moved     : unsigned(15 downto 0) := (others => '0');   -- sectors done (produced/written)
   signal freed     : unsigned(15 downto 0) := (others => '0');   -- free toggles seen
   signal tbase     : unsigned(15 downto 0) := (others => '0');   -- moved at the transfer start
   signal tblocks   : unsigned(15 downto 0) := (others => '0');   -- blocks of this transfer
   signal waitc     : natural range 0 to 7 := 0;

   -- lookup
   signal mode      : std_logic_vector(1 downto 0);
   signal base      : unsigned(31 downto 0);
   signal shift     : natural range 0 to 7;
   signal ci        : unsigned(31 downto 0) := (others => '0');   -- cluster index of lba
   signal ext_i     : unsigned(9 downto 0) := (others => '0');    -- extent being looked at
   signal ext_n     : unsigned(15 downto 0) := (others => '0');
   signal cum       : unsigned(31 downto 0) := (others => '0');   -- cluster index ext_i starts at
   signal e_first   : unsigned(31 downto 0) := (others => '0');
   signal e_len     : unsigned(31 downto 0) := (others => '0');
   signal rd_ph     : natural range 0 to 7 := 0;
   signal maddr     : unsigned(11 downto 0) := (others => '0');
   signal c_i       : unsigned(9 downto 0) := (others => '0');     -- cached extent (per unit)
   signal c_cum     : unsigned(31 downto 0) := (others => '0');
   signal c_unit    : std_logic := '0';
   signal c_valid   : std_logic := '0';
   signal run_blk   : unsigned(31 downto 0) := (others => '0');
   signal p_rel     : unsigned(31 downto 0) := (others => '0');    -- pipeline of the lookup
   signal p_off     : unsigned(31 downto 0) := (others => '0');
   signal p_end     : unsigned(31 downto 0) := (others => '0');
   signal p_clus    : unsigned(31 downto 0) := (others => '0');
   signal run_len   : unsigned(15 downto 0) := (others => '0');

   signal sd_start  : std_logic := '0';
   signal sd_abort  : std_logic := '0';
   signal hi_byte   : std_logic_vector(7 downto 0) := (others => '0');
   signal r_we      : std_logic := '0';
   signal r_addr    : std_logic_vector(G_RING_LOG2 + 7 downto 0) := (others => '0');
   signal r_data    : std_logic_vector(15 downto 0) := (others => '0');
   signal wsel      : std_logic := '0';

   signal n_acc, n_fwd, n_err : unsigned(15 downto 0) := (others => '0');

   function shl(v : unsigned(31 downto 0); n : natural) return unsigned is
   begin
      return shift_left(v, n);
   end function;

begin

   fw_cmd_tgl_o <= fw_tgl;
   acc_tgl_o    <= acc_tgl;
   acc_wr_o     <= acc_wr;
   rdy_tgl_o    <= rdy_tgl;
   fin_tgl_o    <= fin_tgl;
   fin_err_o    <= fin_err;
   st_acc_o     <= std_logic_vector(n_acc);
   st_fwd_o     <= std_logic_vector(n_fwd);
   st_err_o     <= std_logic_vector(n_err);
   busy_o       <= '0' when st = E_IDLE else '1';

   rring_we_o   <= r_we;
   rring_addr_o <= r_addr;
   rring_data_o <= r_data;

   map_addr_o   <= std_logic_vector(maddr);

   sd_start_o   <= sd_start;
   -- E_DECIDE checks sd_ready_i of the unit of the new command (unit is set there)
   sd_slot_o    <= cfg_slot1_i when (st = E_DECIDE and tf_i(52) = '1') or (st /= E_DECIDE and unit = '1') else
                   cfg_slot0_i;
   sd_write_o   <= wr;
   sd_addr_o    <= std_logic_vector(run_blk);
   sd_count_o   <= std_logic_vector(run_len);
   sd_abort_o   <= sd_abort;

   mode  <= cfg_mode1_i when unit = '1' else cfg_mode0_i;
   base  <= unsigned(cfg_base1_i) when unit = '1' else unsigned(cfg_base0_i);
   shift <= to_integer(unsigned(cfg_shift1_i)) when unit = '1' else to_integer(unsigned(cfg_shift0_i));

   -- flow control: read - blocks of this transfer that have a free slot; write - blocks of
   -- this transfer that the CPU has filled
   sd_limit_o <= std_logic_vector(freed + C_RING - tbase) when wr = '0' else
                 std_logic_vector(freed - tbase);

   -- write data: ring slot of the block, word idx/2, byte idx(0) (one clock of BRAM latency
   -- plus the registered byte select: valid two clocks after the address changed)
   wring_addr_o <= std_logic_vector(resize(tbase + unsigned(sd_wr_blk_i), G_RING_LOG2)) &
                   sd_wr_idx_i(8 downto 1);
   sd_wr_data_o <= wring_data_i(15 downto 8) when wsel = '0' else wring_data_i(7 downto 0);

   main : process (clk_i)
      variable cnt   : unsigned(8 downto 0);
      variable last  : unsigned(31 downto 0);
      variable runv  : unsigned(31 downto 0);
      variable off   : unsigned(31 downto 0);
      variable endc  : unsigned(31 downto 0);
      variable ok    : boolean;
      variable c     : std_logic_vector(7 downto 0);
      variable elig  : boolean;
      variable g     : std_logic_vector(15 downto 0);
      variable gh    : unsigned(4 downto 0);
      variable gs    : unsigned(8 downto 0);

      -- take the command (direction w) / leave it to the firmware
      procedure take(w : std_logic) is
      begin
         wr      <= w;
         acc_wr  <= w;
         fin_err <= '0';
         moved   <= (others => '0');
         freed   <= (others => '0');
         tbase   <= (others => '0');
         n_acc   <= n_acc + 1;
         waitc   <= 4;
         st      <= E_ACC_WAIT;
      end procedure;
      procedure forward is
      begin
         fw_tgl <= not fw_tgl;            -- the firmware's
         n_fwd  <= n_fwd + 1;
         st     <= E_IDLE;
      end procedure;
   begin
      if rising_edge(clk_i) then
         sd_start <= '0';
         r_we     <= '0';
         wsel     <= sd_wr_idx_i(0);

         -- CPU side frees ring slots (read) or fills them (write)
         if free_tgl_i /= free_seen then
            free_seen <= free_tgl_i;
            freed     <= freed + 1;
         end if;

         -- read data into the ring: even byte = high byte of the word
         if sd_rd_we_i = '1' then
            if sd_rd_idx_i(0) = '0' then
               hi_byte <= sd_rd_data_i;
            else
               r_we   <= '1';
               r_addr <= std_logic_vector(resize(tbase + unsigned(sd_rd_blk_i), G_RING_LOG2)) &
                         sd_rd_idx_i(8 downto 1);
               r_data <= hi_byte & sd_rd_data_i;
            end if;
         end if;

         -- a completed block
         if sd_blk_i = '1' then
            moved   <= moved + 1;
            rdy_tgl <= not rdy_tgl;
         end if;

         -- configuration writes invalidate the extent cache
         if cfg_wr_i = '1' then
            c_valid <= '0';
         end if;

         case st is

            when E_IDLE =>
               sd_abort <= '0';
               if rst_tgl_i /= rst_seen then
                  rst_seen <= rst_tgl_i;
               elsif cmd_tgl_i /= cmd_seen then
                  cmd_seen <= cmd_tgl_i;
                  st       <= E_DECIDE;
               end if;

            -- Megamiga: the port is shared with the ADF track buffer (sd_eng_arb.vhd); sd_ready_i
            -- belongs to the owner's slot, so a new command waits until this engine owns it
            when E_DECIDE =>
               if sd_gnt_i = '1' then
               -- tf: 7..0 cmd, 23..16 count, 31..24 lba0, 39..32 lba1, 47..40 lba2, 55..48 devh
               c    := tf_i(7 downto 0);
               unit <= tf_i(52);
               if tf_i(23 downto 16) = x"00" then
                  cnt := to_unsigned(256, 9);
               else
                  cnt := resize(unsigned(tf_i(23 downto 16)), 9);
               end if;
               lba  <= x"0" & unsigned(tf_i(51 downto 48)) & unsigned(tf_i(47 downto 24));
               left <= cnt;
               -- Megamiga 0.7: + READ/WRITE MULTIPLE while the unit has a multiple count
               --ok := tf_i(54) = '1' and sd_ready_i = '1' and
               --      (c = x"20" or c = x"21" or c = x"30" or c = x"31");
               elig := sd_ready_i = '1' and
                       (c = x"20" or c = x"21" or c = x"30" or c = x"31" or
                        ((c = x"C4" or c = x"C5") and
                         ((tf_i(52) = '0' and cfg_mult0_i = '1') or (tf_i(52) = '1' and cfg_mult1_i = '1'))));
               ok := tf_i(54) = '1' and elig;
               if tf_i(52) = '1' then
                  ok := ok and cfg_mode1_i /= "00" and
                        resize(unsigned(tf_i(51 downto 48)) & unsigned(tf_i(47 downto 24)), 33) +
                        resize(cnt, 33) <= resize(unsigned(cfg_sects1_i), 33);
               else
                  ok := ok and cfg_mode0_i /= "00" and
                        resize(unsigned(tf_i(51 downto 48)) & unsigned(tf_i(47 downto 24)), 33) +
                        resize(cnt, 33) <= resize(unsigned(cfg_sects0_i), 33);
               end if;
               -- Megamiga 0.7: CHS (DEVH bit 6 clear) with a valid address for the unit's
               -- geometry: converted in E_CHS1..3 (an invalid one stays with the firmware: IDNF)
               if tf_i(52) = '1' then g := cfg_geom1_i; else g := cfg_geom0_i; end if;
               gh := resize(unsigned(g(15 downto 12)), 5) + 1;
               gs := unsigned(g(8 downto 0));
               ch_cyl   <= unsigned(tf_i(47 downto 32));
               ch_head  <= unsigned(tf_i(51 downto 48));
               ch_sec   <= unsigned(tf_i(31 downto 24));
               ch_heads <= gh;
               ch_spt   <= gs;
               ch_wr    <= c(4) or (c(7) and c(0));
               if ok then
                  --wr      <= c(4);                 -- 0x30/0x31
                  --acc_wr  <= c(4);
                  take(c(4) or (c(7) and c(0)));  -- 0x30/0x31/0xC5
               elsif tf_i(54) = '0' and elig and gs /= 0 and
                     resize(unsigned(tf_i(51 downto 48)), 5) < gh and
                     unsigned(tf_i(31 downto 24)) /= 0 and
                     resize(unsigned(tf_i(31 downto 24)), 9) <= gs then
                  st <= E_CHS1;
               else
                  forward;
               end if;
               end if;

            when E_CHS1 =>                         -- cylinder x heads + head
               ch_p1 <= ch_cyl * ch_heads + ch_head;
               st    <= E_CHS2;

            when E_CHS2 =>                         -- x sectors per track + sector - 1
               lba <= resize(ch_p1 * ch_spt, 32) + ch_sec - 1;
               st  <= E_CHS3;

            when E_CHS3 =>                         -- the range check of E_DECIDE
               if unit = '1' then
                  ok := cfg_mode1_i /= "00" and
                        resize(lba, 33) + resize(left, 33) <= resize(unsigned(cfg_sects1_i), 33);
               else
                  ok := cfg_mode0_i /= "00" and
                        resize(lba, 33) + resize(left, 33) <= resize(unsigned(cfg_sects0_i), 33);
               end if;
               if ok then
                  take(ch_wr);
               else
                  forward;
               end if;

            when E_ACC_WAIT =>                     -- acc_wr settles, then the toggle
               if waitc = 0 then
                  acc_tgl <= not acc_tgl;
                  st      <= E_LOOK;
               else
                  waitc <= waitc - 1;
               end if;

            ------------------------------------------------------------------------------
            -- lookup: lba -> run_blk, run_len (<= left)
            ------------------------------------------------------------------------------
            when E_LOOK =>
               if rst_tgl_i /= rst_seen then
                  rst_seen <= rst_tgl_i;
                  st       <= E_IDLE;
               elsif mode = "10" then
                  run_blk <= base + lba;
                  run_len <= resize(left, 16);
                  st      <= E_START;
               elsif mode = "01" then
                  ci <= shift_right(lba, shift);
                  -- start at the cached extent when lba is not in front of it
                  if c_valid = '1' and c_unit = unit and shift_right(lba, shift) >= c_cum then
                     ext_i <= c_i;
                     cum   <= c_cum;
                  else
                     ext_i <= (others => '0');
                     cum   <= (others => '0');
                  end if;
                  maddr <= unit & "00000000000";   -- word 0: number of extents
                  rd_ph <= 0;
                  st    <= E_LOOK_N;
               else
                  st <= E_FAIL;                     -- unmounted under our feet
               end if;

            when E_LOOK_N =>
               if rd_ph = 1 then
                  ext_n <= unsigned(map_data_i);
                  rd_ph <= 0;
                  st    <= E_LOOK_EXT;
               else
                  rd_ph <= rd_ph + 1;
               end if;

            when E_LOOK_EXT =>
               -- read the 4 words of extent ext_i (addresses 1 + 4i .. 4 + 4i)
               if ext_i >= ext_n then
                  st <= E_FAIL;                     -- not in the map
               else
                  case rd_ph is
                     when 0 =>
                        maddr <= unit & (ext_i(8 downto 0) & "00") + 1;
                     when 2 =>
                        e_first(15 downto 0) <= unsigned(map_data_i);
                        maddr <= unit & (ext_i(8 downto 0) & "00") + 2;
                     when 3 =>
                        maddr <= unit & (ext_i(8 downto 0) & "00") + 3;
                     when 4 =>
                        e_first(31 downto 16) <= unsigned(map_data_i);
                        maddr <= unit & (ext_i(8 downto 0) & "00") + 4;
                     when 5 =>
                        e_len(15 downto 0) <= unsigned(map_data_i);
                     when 6 =>
                        e_len(31 downto 16) <= unsigned(map_data_i);
                     when others => null;
                  end case;
                  if rd_ph = 6 then
                     rd_ph <= 0;
                     st    <= E_LOOK_CMP;
                  else
                     rd_ph <= rd_ph + 1;
                  end if;
               end if;

            -- block = base + ((first + ci - cum) << shift) + (lba - (ci << shift)), in three
            -- steps (50 MHz)
            when E_LOOK_CMP =>
               endc := cum + e_len;
               if ci < endc then
                  p_rel   <= ci - cum;
                  p_off   <= lba - shl(ci, shift);
                  p_end   <= endc;
                  c_i     <= ext_i;
                  c_cum   <= cum;
                  c_unit  <= unit;
                  c_valid <= '1';
                  st      <= E_LOOK_C2;
               else
                  cum   <= endc;
                  ext_i <= ext_i + 1;
                  st    <= E_LOOK_EXT;
               end if;

            when E_LOOK_C2 =>
               p_clus <= e_first + p_rel;
               runv := shl(p_end, shift) - lba;   -- sectors left in this extent
               if runv < resize(left, 32) then
                  run_len <= runv(15 downto 0);
               else
                  run_len <= resize(left, 16);
               end if;
               st <= E_LOOK_C3;

            when E_LOOK_C3 =>
               run_blk <= base + shl(p_clus, shift) + p_off;
               st      <= E_START;

            ------------------------------------------------------------------------------
            -- a transfer: run_len blocks from run_blk
            ------------------------------------------------------------------------------
            when E_START =>
               if wr = '1' and freed = moved then
                  st <= E_WAIT_DATA;                -- nothing to write yet
               elsif sd_busy_i = '0' then
                  tbase    <= moved;
                  tblocks  <= run_len;
                  sd_start <= '1';
                  st       <= E_RUN;
               end if;

            when E_WAIT_DATA =>
               if rst_tgl_i /= rst_seen then
                  rst_seen <= rst_tgl_i;
                  st       <= E_IDLE;
               elsif freed /= moved then
                  st <= E_START;
               end if;

            when E_RUN =>
               if rst_tgl_i /= rst_seen then
                  sd_abort <= '1';                  -- ends at the next block edge
               end if;
               if sd_done_i = '1' then
                  if sd_error_i = '1' then
                     st <= E_FAIL;
                  elsif sd_abort = '1' or rst_tgl_i /= rst_seen then
                     rst_seen <= rst_tgl_i;
                     sd_abort <= '0';
                     st       <= E_IDLE;
                  else
                     -- (moved already counts this transfer's blocks; sd_blk_i and
                     -- sd_done_i are never in the same clock)
                     lba  <= lba + resize(moved - tbase, 32);
                     left <= left - resize(moved - tbase, 9);
                     if left = resize(moved - tbase, 9) then
                        -- all sectors are moved
                        if wr = '1' then
                           fin_tgl <= not fin_tgl;
                        end if;
                        st <= E_IDLE;
                     else
                        st <= E_LOOK;               -- preempted or end of the extent
                     end if;
                  end if;
               end if;

            when E_FAIL =>
               fin_err <= '1';
               n_err   <= n_err + 1;
               waitc   <= 4;
               st      <= E_FAIL2;

            when E_FAIL2 =>
               if waitc = 0 then
                  fin_tgl <= not fin_tgl;
                  st      <= E_IDLE;
               else
                  waitc <= waitc - 1;
               end if;

            when others =>
               st <= E_IDLE;
         end case;

         if rst_i = '1' then
            st       <= E_IDLE;
            sd_abort <= '0';
            c_valid  <= '0';
            cmd_seen <= cmd_tgl_i;
            rst_seen <= rst_tgl_i;
         end if;
      end if;
   end process main;

end architecture synthesis;
