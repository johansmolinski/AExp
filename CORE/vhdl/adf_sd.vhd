---------------------------------------------------------------------------------------------------------
-- Megamiga for MEGA65
--
-- adf_sd: the ADF disk images straight from the SD card, without a copy in memory.
--
-- Before, a mounted ADF was copied into an SDRAM pool (one per drive) and adf_track_engine read
-- and wrote that pool; the firmware wrote dirty tracks back to the file in the background. Here
-- the engine's memory port stays exactly as it was (single-word Avalon reads and writes at
-- "pool base + track x 2816 + sector x 256 + word"), but the words come from a ONE-TRACK BUFFER
-- in block RAM that this module fills from the file on the SD card and writes back to it:
--
--   * the engine announces every sector before it touches it: the first word of a sector (or
--     any word of a sector other than the one it was granted) sends a request into the QNICE
--     domain - PREP_RD (the engine is about to read the sector), PREP_WR (it is about to write
--     it) - and the write of the sector's last word sends COMMIT. Requests are toggles with a
--     payload that is stable while the toggle crosses (CORE.xdc bounds qnice <-> main).
--   * the buffer holds the eleven sectors of one track of one drive (tag = drive, track) with a
--     valid and a dirty bit per sector. PREP_RD of a sector that is not valid loads every sector
--     of the track that is not valid (dirty sectors are valid and never reloaded), usually with
--     one multi-block read. PREP_WR invalidates the sector (an engine abort halfway through the
--     sector must not leave a torn sector that looks valid); COMMIT makes it valid and dirty.
--   * dirty sectors go to the card when the buffer has to change tags (always before), when no
--     sector was committed for G_FLUSH_DELAY clocks (a track write of trackdisk commits its
--     eleven sectors within a few milliseconds, so they normally leave as one multi-block
--     write), or when the firmware asks (register FLUSH, before it ejects or changes a drive).
--   * a sector is translated into an SD block through the extent map of the drive's file (the
--     FAT32$FILE_MAP format, written by the firmware at mount, as for the IDE engine) and moved
--     through the SD host controller's engine port, which this module shares with the IDE
--     sector engine (sd_eng_arb.vhd): it raises sd_req_o and waits for sd_gnt_i.
--   * a failed transfer is tried again G_RETRIES times, 1 ms apart. A controller that is not
--     ready (sdhost re-initialises the card after a failed transfer, in another bus mode, or
--     the slot has no card) is waited for up to G_READY_WAIT ms from its first "not ready"
--     (wall time: the IDE engine may hold the port in between), the port released meanwhile,
--     without using up a retry.
--   * a sector that cannot be read (SD error, drive off, sector outside the file) is still
--     served, but with avm_rderr_o set: the engine then sends it with a wrong data checksum, so
--     the Amiga sees a read error, as with a bad sector on a real disk - never silently wrong
--     data. A write that cannot be done (after G_RETRIES retries) is dropped and counted; the
--     drive's FAULT bit stays set until the firmware configures it again.
--
-- Clock domains: the engine side runs on the core clock (clk_main_i), everything else on the QNICE
-- clock (the engine port of the SD host controller lives there). The buffer is a true dual-port
-- block RAM with one port per domain.
--
-- QNICE registers (one set per drive u, written on the falling edge, read registered):
--   0x00 MODE    bit 0 = on (file), bit 1 = the card is in slot 1. Any write of 0x00..0x05
--                invalidates the buffer if it holds this drive (the firmware flushes first).
--   0x01/0x02    SECTS  number of 512-byte sectors of the file (lo, hi)
--   0x03/0x04    BASE   SD block of cluster 0 = DEV_CLUSTER - (2 << SHIFT) (lo, hi)
--   0x05 SHIFT   log2(sectors per cluster)
--   0x08 STATUS  (read) bit 0 = the buffer holds dirty sectors of this drive, bit 1 = busy (a
--                load or a write-back is running), bit 2 = FAULT (a write was lost), bit 3 = a
--                load or write-back for this drive is pending (requested, not done yet)
--   0x09 FLUSH   (write) write this drive's dirty sectors now (STATUS bit 0 drops when done)
--   0x10..0x15   (read) statistics: blocks read, blocks written, read errors, write errors,
--                track loads, requests (all drives, 16 bit, wrapping)
-- The extent map of drive u: map words 0..2047 (word 0 = number of extents, then 4 words per
-- extent: first cluster lo/hi, clusters lo/hi; up to 511 extents).
--
-- Done in 2026 (Megamiga fork) and licensed under GPL v3.
---------------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity adf_sd is
   generic (
      -- word base of each drive's address window as the engine computes it (C_HMAP_ADF_DF<n>);
      -- each must be a multiple of 0x80000 (the drive is told apart by address bits 21:19)
      G_BASE_DF0     : std_logic_vector(21 downto 0);
      G_BASE_DF1     : std_logic_vector(21 downto 0);
      G_BASE_DF2     : std_logic_vector(21 downto 0);
      G_FLUSH_DELAY  : natural := 1_000_000;   -- QNICE clocks without a commit (20 ms)
      G_RETRIES      : natural := 2;           -- a failed transfer is tried again
      G_MS           : natural := 50_000;      -- QNICE clocks per millisecond
      G_READY_WAIT   : natural := 500          -- ms to wait for a controller that is not
   );                                          -- ready (it re-initialises the card)
   port (
      -- engine side (core clock)
      clk_main_i          : in  std_logic;
      rst_main_i          : in  std_logic;
      avm_write_i         : in  std_logic;
      avm_read_i          : in  std_logic;
      avm_address_i       : in  std_logic_vector(31 downto 0);
      avm_writedata_i     : in  std_logic_vector(15 downto 0);
      avm_readdata_o      : out std_logic_vector(15 downto 0);
      avm_readdatavalid_o : out std_logic;
      avm_rderr_o         : out std_logic;     -- with avm_readdatavalid_o: the sector is bad
      avm_waitrequest_o   : out std_logic;
      dirty_main_o        : out std_logic;     -- the buffer holds dirty sectors (drive LED)

      -- QNICE side
      clk_i               : in  std_logic;     -- QNICE clock
      rst_i               : in  std_logic;     -- QNICE reset
      qnice_ce_i          : in  std_logic;
      qnice_we_i          : in  std_logic;
      qnice_unit_i        : in  std_logic_vector(1 downto 0);   -- drive 0..2
      qnice_map_i         : in  std_logic;     -- '1' = the extent map window, '0' = registers
      qnice_addr_i        : in  std_logic_vector(11 downto 0);
      qnice_data_i        : in  std_logic_vector(15 downto 0);
      qnice_data_o        : out std_logic_vector(15 downto 0);

      -- SD host engine port (through sd_eng_arb)
      sd_req_o            : out std_logic;     -- wants the port
      sd_gnt_i            : in  std_logic;     -- has it
      sd_slot_o           : out std_logic;
      sd_ready_i          : in  std_logic;
      sd_start_o          : out std_logic;
      sd_write_o          : out std_logic;
      sd_addr_o           : out std_logic_vector(31 downto 0);
      sd_count_o          : out std_logic_vector(15 downto 0);
      sd_limit_o          : out std_logic_vector(15 downto 0);
      sd_abort_o          : out std_logic;
      sd_busy_i           : in  std_logic;
      sd_done_i           : in  std_logic;
      sd_error_i          : in  std_logic;
      sd_blk_i            : in  std_logic;
      sd_rd_we_i          : in  std_logic;
      sd_rd_blk_i         : in  std_logic_vector(15 downto 0);
      sd_rd_idx_i         : in  std_logic_vector(8 downto 0);
      sd_rd_data_i        : in  std_logic_vector(7 downto 0);
      sd_wr_blk_i         : in  std_logic_vector(15 downto 0);
      sd_wr_idx_i         : in  std_logic_vector(8 downto 0);
      sd_wr_data_o        : out std_logic_vector(7 downto 0)
   );
end entity adf_sd;

architecture synthesis of adf_sd is

   constant OP_RD     : std_logic_vector(1 downto 0) := "01";
   constant OP_WR     : std_logic_vector(1 downto 0) := "10";
   constant OP_COMMIT : std_logic_vector(1 downto 0) := "11";

   attribute async_reg : string;

   ------------------------------------------------------------------------------------------
   -- core clock side
   ------------------------------------------------------------------------------------------
   type t_mstate is (MS_IDLE, MS_REQ, MS_COMMIT);
   signal m_state     : t_mstate := MS_IDLE;
   signal m_unit      : std_logic_vector(1 downto 0);
   signal m_lba       : unsigned(10 downto 0);
   signal m_idx       : unsigned(7 downto 0);
   signal m_inrange   : std_logic;
   signal m_req       : std_logic := '0';               -- toggle
   signal m_req_op    : std_logic_vector(1 downto 0) := "00";
   signal m_req_unit  : std_logic_vector(1 downto 0) := "00";
   signal m_req_lba   : unsigned(10 downto 0) := (others => '0');
   signal m_ack_d, m_ack_s : std_logic := '0';
   attribute async_reg of m_ack_d, m_ack_s : signal is "true";
   signal m_ack_seen  : std_logic := '0';
   signal m_gen_d, m_gen_s, m_gen_seen : std_logic := '0';
   attribute async_reg of m_gen_d, m_gen_s : signal is "true";
   signal m_dirty_d, m_dirty_s : std_logic := '0';
   attribute async_reg of m_dirty_d, m_dirty_s : signal is "true";
   -- the grant: the sector the engine may read or write now
   signal g_valid     : std_logic := '0';
   signal g_fresh     : std_logic := '0';               -- not one word moved yet
   signal g_op        : std_logic_vector(1 downto 0) := "00";
   signal g_unit      : std_logic_vector(1 downto 0) := "00";
   signal g_lba       : unsigned(10 downto 0) := (others => '0');
   signal g_sec       : unsigned(3 downto 0) := (others => '0');
   signal g_err       : std_logic := '0';
   signal m_hit       : std_logic;
   signal m_op        : std_logic_vector(1 downto 0);
   signal a_addr      : std_logic_vector(11 downto 0) := (others => '0');
   signal a_we        : std_logic := '0';
   signal a_data      : std_logic_vector(15 downto 0) := (others => '0');
   signal a_q         : std_logic_vector(15 downto 0);
   signal rd_p1       : std_logic := '0';
   signal rd_err1     : std_logic := '0';

   ------------------------------------------------------------------------------------------
   -- QNICE side
   ------------------------------------------------------------------------------------------
   type t_u2   is array (0 to 3) of std_logic_vector(1 downto 0);
   type t_u32  is array (0 to 3) of unsigned(31 downto 0);
   type t_u3   is array (0 to 3) of unsigned(2 downto 0);
   signal c_mode  : t_u2  := (others => "00");
   signal c_sects : t_u32 := (others => (others => '0'));
   signal c_base  : t_u32 := (others => (others => '0'));
   signal c_shift : t_u3  := (others => (others => '0'));
   signal c_wr_f  : std_logic_vector(3 downto 0) := (others => '0');   -- falling edge
   signal c_wr    : std_logic_vector(3 downto 0) := (others => '0');   -- rising edge
   signal c_pend  : std_logic_vector(3 downto 0) := (others => '0');   -- to invalidate
   signal fl_f    : std_logic_vector(3 downto 0) := (others => '0');
   signal fl_req  : std_logic_vector(3 downto 0) := (others => '0');   -- FLUSH pending
   signal fault   : std_logic_vector(3 downto 0) := (others => '0');
   signal q_gen   : std_logic := '0';
   signal q_rd    : std_logic_vector(15 downto 0) := (others => '0');

   signal map_we_f, map_we : std_logic := '0';
   signal map_wa_f, map_wa : std_logic_vector(12 downto 0) := (others => '0');
   signal map_wd_f, map_wd : std_logic_vector(15 downto 0) := (others => '0');
   signal maddr   : unsigned(12 downto 0) := (others => '0');
   signal map_q   : std_logic_vector(15 downto 0);

   signal q_req_d, q_req_s, q_req_seen : std_logic := '0';
   attribute async_reg of q_req_d, q_req_s : signal is "true";
   signal q_ack   : std_logic := '0';
   signal q_ack_sec : unsigned(3 downto 0) := (others => '0');
   signal q_ack_err : std_logic := '0';

   -- the buffer
   signal t_valid : std_logic := '0';                   -- tag valid
   signal t_unit  : std_logic_vector(1 downto 0) := "00";
   signal t_track : unsigned(7 downto 0) := (others => '0');
   signal t_nsec  : natural range 0 to 11 := 11;        -- sectors of the track inside the file
   signal s_valid : std_logic_vector(10 downto 0) := (others => '0');
   signal s_dirty : std_logic_vector(10 downto 0) := (others => '0');
   signal age     : natural range 0 to G_FLUSH_DELAY := 0;

   -- the request being worked on
   signal r_op    : std_logic_vector(1 downto 0) := "00";
   signal r_unit  : std_logic_vector(1 downto 0) := "00";
   signal r_lba   : unsigned(10 downto 0) := (others => '0');
   signal r_track : unsigned(7 downto 0) := (others => '0');
   signal r_sec   : unsigned(3 downto 0) := (others => '0');
   signal r_prod  : unsigned(23 downto 0) := (others => '0');

   type t_qstate is (
      Q_IDLE, Q_DIV, Q_SEC, Q_DECIDE, Q_ANSWER,
      Q_FLUSH, Q_LOAD, Q_RUN_LOOK, Q_LOOK_N, Q_LOOK_EXT, Q_LOOK_CMP, Q_LOOK_C2, Q_LOOK_C3,
      Q_GNT, Q_START, Q_RUN, Q_RUN_END, Q_BACKOFF
   );
   signal st      : t_qstate := Q_IDLE;
   signal st_next   : t_qstate := Q_IDLE;                -- where a finished flush/load goes

   -- a transfer: run_n sectors from sector run_s of the tagged track
   signal x_wr    : std_logic := '0';                   -- write-back (else load)
   signal x_unit  : std_logic_vector(1 downto 0) := "00";
   signal run_s   : unsigned(3 downto 0) := (others => '0');
   signal run_n   : unsigned(3 downto 0) := (others => '0');
   signal run_lba : unsigned(31 downto 0) := (others => '0');
   signal run_blk : unsigned(31 downto 0) := (others => '0');
   signal run_len : unsigned(15 downto 0) := (others => '0');   -- blocks of this SD transfer
   signal moved   : unsigned(15 downto 0) := (others => '0');
   signal tries   : natural range 0 to 15 := 0;
   constant C_NR_MAX : natural := G_READY_WAIT * G_MS;
   signal nr_on   : std_logic := '0';                   -- waiting for ready in this run
   signal nr_cnt  : natural range 0 to C_NR_MAX := 0;   -- clocks since the first "not ready"
   signal x_nrdy  : std_logic := '0';                   -- the failure was "not ready"
   signal bo_cnt  : natural range 0 to G_MS := 0;
   signal x_fail  : std_logic := '0';
   signal hold    : std_logic := '0';                   -- keeps sd_req_o up during an op

   -- extent lookup (ide_engine's)
   signal mode    : std_logic_vector(1 downto 0);
   signal base    : unsigned(31 downto 0);
   signal shift   : natural range 0 to 7;
   signal ci      : unsigned(31 downto 0) := (others => '0');
   signal ext_i   : unsigned(9 downto 0) := (others => '0');
   signal ext_n   : unsigned(15 downto 0) := (others => '0');
   signal cum     : unsigned(31 downto 0) := (others => '0');
   signal e_first : unsigned(31 downto 0) := (others => '0');
   signal e_len   : unsigned(31 downto 0) := (others => '0');
   signal rd_ph   : natural range 0 to 7 := 0;
   signal c_i     : unsigned(9 downto 0) := (others => '0');
   signal c_cum   : unsigned(31 downto 0) := (others => '0');
   signal c_unit  : std_logic_vector(1 downto 0) := "00";
   signal c_valid : std_logic := '0';
   signal p_rel, p_off, p_end, p_clus : unsigned(31 downto 0) := (others => '0');

   -- SD engine port
   signal sd_start  : std_logic := '0';
   signal lo_byte   : std_logic_vector(7 downto 0) := (others => '0');
   signal b_we      : std_logic := '0';
   signal b_waddr   : std_logic_vector(11 downto 0) := (others => '0');
   signal b_wdata   : std_logic_vector(15 downto 0) := (others => '0');
   signal b_addr    : std_logic_vector(11 downto 0);
   signal b_q       : std_logic_vector(15 downto 0);
   signal wsel      : std_logic := '0';

   -- statistics
   signal n_rblk, n_wblk, n_rerr, n_werr, n_load, n_req : unsigned(15 downto 0) := (others => '0');

   function f_sec_mask(s : unsigned(3 downto 0)) return std_logic_vector is
      variable m : std_logic_vector(10 downto 0) := (others => '0');
   begin
      for i in 0 to 10 loop
         if to_integer(s) = i then
            m(i) := '1';
         end if;
      end loop;
      return m;
   end function;

begin

   assert G_BASE_DF0(18 downto 0) = "0000000000000000000" and
          G_BASE_DF1(18 downto 0) = "0000000000000000000" and
          G_BASE_DF2(18 downto 0) = "0000000000000000000" and
          G_BASE_DF0(21 downto 19) /= G_BASE_DF1(21 downto 19) and
          G_BASE_DF0(21 downto 19) /= G_BASE_DF2(21 downto 19) and
          G_BASE_DF1(21 downto 19) /= G_BASE_DF2(21 downto 19)
      report "adf_sd: drive windows must be distinct multiples of 0x80000" severity failure;

   ------------------------------------------------------------------------------------------
   -- the buffer: port A = engine (core clock), port B = SD (QNICE clock)
   ------------------------------------------------------------------------------------------
   i_buf : entity work.tdp_ram
      generic map (
         ADDR_WIDTH => 12,
         DATA_WIDTH => 16
      )
      port map (
         clock_a   => clk_main_i,
         address_a => a_addr,
         data_a    => a_data,
         wren_a    => a_we,
         q_a       => a_q,
         clock_b   => clk_i,
         address_b => b_addr,
         data_b    => b_wdata,
         wren_b    => b_we,
         q_b       => b_q
      ); -- i_buf

   ------------------------------------------------------------------------------------------
   -- engine side
   ------------------------------------------------------------------------------------------

   -- which drive, which sector (track x 11 + sector), which word
   m_lba <= unsigned(avm_address_i(18 downto 8));
   m_idx <= unsigned(avm_address_i(7 downto 0));
   m_unit <= "00" when avm_address_i(21 downto 19) = G_BASE_DF0(21 downto 19) else
             "01" when avm_address_i(21 downto 19) = G_BASE_DF1(21 downto 19) else
             "10" when avm_address_i(21 downto 19) = G_BASE_DF2(21 downto 19) else
             "11";
   m_inrange <= '1' when avm_address_i(31 downto 22) = "0000000000" else '0';
   m_op   <= OP_WR when avm_write_i = '1' else OP_RD;

   -- an access may go on at once when it is in the granted sector (a new sector starts with
   -- word 0: that always asks again, unless the grant was made for exactly this access)
   m_hit <= '1' when m_state = MS_IDLE and g_valid = '1' and g_op = m_op and g_unit = m_unit and
                     g_lba = m_lba and (m_idx /= 0 or g_fresh = '1') and m_inrange = '1'
            else '0';

   avm_waitrequest_o   <= not m_hit;
   avm_readdata_o      <= a_q;
   avm_readdatavalid_o <= rd_p1;
   avm_rderr_o         <= rd_err1;
   dirty_main_o        <= m_dirty_s;

   a_addr <= std_logic_vector(g_sec) & std_logic_vector(m_idx);
   a_data <= avm_writedata_i;
   a_we   <= '1' when m_hit = '1' and avm_write_i = '1' and g_err = '0' else '0';

   main_side : process (clk_main_i)
   begin
      if rising_edge(clk_main_i) then
         m_ack_d   <= q_ack;
         m_ack_s   <= m_ack_d;
         m_gen_d   <= q_gen;
         m_gen_s   <= m_gen_d;
         m_dirty_d <= '1' when t_valid = '1' and s_dirty /= "00000000000" else '0';
         m_dirty_s <= m_dirty_d;

         rd_p1   <= '0';
         rd_err1 <= '0';

         -- a configuration change: whatever was granted may belong to another image now
         if m_gen_s /= m_gen_seen then
            m_gen_seen <= m_gen_s;
            if m_state = MS_IDLE then
               g_valid <= '0';
            end if;
         end if;

         case m_state is
            when MS_IDLE =>
               if m_hit = '1' then
                  g_fresh <= '0';
                  if avm_read_i = '1' then
                     rd_p1   <= '1';
                     rd_err1 <= g_err;
                     if m_idx = 255 then
                        g_valid <= '0';            -- the sector is done
                     end if;
                  elsif avm_write_i = '1' and m_idx = 255 then
                     g_valid <= '0';
                     if g_err = '0' then           -- the whole sector is in the buffer
                        m_req_op <= OP_COMMIT;
                        m_state  <= MS_COMMIT;
                     end if;
                  end if;
               elsif (avm_read_i = '1' or avm_write_i = '1') then
                  if m_inrange = '1' and m_unit /= "11" then
                     m_req_op   <= m_op;
                     m_req_unit <= m_unit;
                     m_req_lba  <= m_lba;
                     m_state    <= MS_REQ;
                  else
                     -- not a drive window: grant an error "sector" (reads give bad data,
                     -- writes are dropped) so that the engine does not wait forever
                     g_valid <= '1';
                     g_fresh <= '1';
                     g_op    <= m_op;
                     g_unit  <= m_unit;
                     g_lba   <= m_lba;
                     g_err   <= '1';
                  end if;
               end if;

            -- payload stable since the last clock: toggle, then wait for the answer
            when MS_REQ | MS_COMMIT =>
               if m_req = m_ack_seen then
                  m_req <= not m_req;
               elsif m_ack_s /= m_ack_seen then
                  m_ack_seen <= m_ack_s;
                  if m_state = MS_REQ then
                     g_valid <= '1';
                     g_fresh <= '1';
                     g_op    <= m_req_op;
                     g_unit  <= m_req_unit;
                     g_lba   <= m_req_lba;
                     g_sec   <= q_ack_sec;          -- stable since before the toggle
                     g_err   <= q_ack_err;
                  end if;
                  m_state <= MS_IDLE;
               end if;
         end case;

         if rst_main_i = '1' and m_state = MS_IDLE then
            g_valid <= '0';
         end if;
      end if;
   end process main_side;

   ------------------------------------------------------------------------------------------
   -- QNICE registers
   ------------------------------------------------------------------------------------------
   qnice_data_o <= q_rd;

   q_write : process (clk_i)
      variable u : natural range 0 to 3;
   begin
      if falling_edge(clk_i) then
         map_we_f <= '0';
         c_wr_f   <= (others => '0');
         fl_f     <= (others => '0');
         u := to_integer(unsigned(qnice_unit_i));
         if qnice_ce_i = '1' and qnice_we_i = '1' then
            if qnice_map_i = '1' then
               if qnice_addr_i(11) = '0' then
                  map_we_f <= '1';
                  map_wa_f <= qnice_unit_i & qnice_addr_i(10 downto 0);
                  map_wd_f <= qnice_data_i;
               end if;
            else
               case qnice_addr_i(7 downto 0) is
                  when x"00" => c_mode(u)  <= qnice_data_i(1 downto 0);
                  when x"01" => c_sects(u)(15 downto 0)  <= unsigned(qnice_data_i);
                  when x"02" => c_sects(u)(31 downto 16) <= unsigned(qnice_data_i);
                  when x"03" => c_base(u)(15 downto 0)   <= unsigned(qnice_data_i);
                  when x"04" => c_base(u)(31 downto 16)  <= unsigned(qnice_data_i);
                  when x"05" => c_shift(u) <= unsigned(qnice_data_i(2 downto 0));
                  when x"09" => fl_f(u) <= '1';
                  when others => null;
               end case;
               if qnice_addr_i(7 downto 3) = "00000" and unsigned(qnice_addr_i(2 downto 0)) <= 5 then
                  c_wr_f(u) <= '1';
               end if;
            end if;
         end if;

         -- registered readout
         q_rd <= (others => '0');
         if qnice_ce_i = '1' and qnice_map_i = '0' then
            case qnice_addr_i(7 downto 0) is
               when x"00" => q_rd <= "00000000000000" & c_mode(u);
               when x"01" => q_rd <= std_logic_vector(c_sects(u)(15 downto 0));
               when x"02" => q_rd <= std_logic_vector(c_sects(u)(31 downto 16));
               when x"03" => q_rd <= std_logic_vector(c_base(u)(15 downto 0));
               when x"04" => q_rd <= std_logic_vector(c_base(u)(31 downto 16));
               when x"05" => q_rd <= "0000000000000" & std_logic_vector(c_shift(u));
               when x"08" =>
                  if t_valid = '1' and t_unit = qnice_unit_i and s_dirty /= "00000000000" then
                     q_rd(0) <= '1';
                  end if;
                  if st /= Q_IDLE then
                     q_rd(1) <= '1';
                  end if;
                  q_rd(2) <= fault(u);
                  if fl_req(u) = '1' or fl_f(u) = '1' or
                     (q_req_s /= q_req_seen and m_req_unit = qnice_unit_i) then
                     q_rd(3) <= '1';
                  end if;
               when x"10" => q_rd <= std_logic_vector(n_rblk);
               when x"11" => q_rd <= std_logic_vector(n_wblk);
               when x"12" => q_rd <= std_logic_vector(n_rerr);
               when x"13" => q_rd <= std_logic_vector(n_werr);
               when x"14" => q_rd <= std_logic_vector(n_load);
               when x"15" => q_rd <= std_logic_vector(n_req);
               when others => null;
            end case;
         end if;

         if rst_i = '1' then
            c_mode <= (others => "00");
         end if;
      end if;
   end process q_write;

   -- the extent maps: the firmware writes, the state machine reads
   i_map : entity work.tdp_ram
      generic map (
         ADDR_WIDTH => 13,
         DATA_WIDTH => 16
      )
      port map (
         clock_a   => clk_i,
         address_a => map_wa,
         data_a    => map_wd,
         wren_a    => map_we,
         q_a       => open,
         clock_b   => clk_i,
         address_b => std_logic_vector(maddr),
         data_b    => (others => '0'),
         wren_b    => '0',
         q_b       => map_q
      ); -- i_map

   ------------------------------------------------------------------------------------------
   -- QNICE side state machine
   ------------------------------------------------------------------------------------------
   mode  <= c_mode(to_integer(unsigned(x_unit)));
   base  <= c_base(to_integer(unsigned(x_unit)));
   shift <= to_integer(c_shift(to_integer(unsigned(x_unit))));

   sd_req_o   <= hold;
   sd_slot_o  <= mode(1);
   sd_start_o <= sd_start;
   sd_write_o <= x_wr;
   sd_addr_o  <= std_logic_vector(run_blk);
   sd_count_o <= std_logic_vector(run_len);
   sd_limit_o <= x"FFFF";
   sd_abort_o <= '0';

   -- port B: SD read data in (buffer word = run sector + block, byte idx / 2; the even byte of
   -- the file is bits 7:0, the engine's packing), SD write data out (two clocks after the
   -- address: one clock of block RAM plus the registered byte select, as in ide_engine)
   b_addr <= b_waddr when x_wr = '0' else
             std_logic_vector(resize(run_s + unsigned(sd_wr_blk_i(3 downto 0)), 4)) &
             sd_wr_idx_i(8 downto 1);
   sd_wr_data_o <= b_q(7 downto 0) when wsel = '0' else b_q(15 downto 8);

   q_main : process (clk_i)
      variable endc : unsigned(31 downto 0);
      variable runv : unsigned(31 downto 0);
      variable m    : std_logic_vector(10 downto 0);
      variable s, e : natural range 0 to 11;
      variable u    : natural range 0 to 3;
   begin
      if rising_edge(clk_i) then
         sd_start <= '0';
         b_we     <= '0';
         wsel     <= sd_wr_idx_i(0);
         q_req_d  <= m_req;
         q_req_s  <= q_req_d;
         map_we   <= map_we_f;
         map_wa   <= map_wa_f;
         map_wd   <= map_wd_f;
         c_wr     <= c_wr_f;

         if age /= G_FLUSH_DELAY then
            age <= age + 1;
         end if;
         if nr_on = '1' and nr_cnt /= C_NR_MAX then
            nr_cnt <= nr_cnt + 1;
         end if;
         for i in 0 to 3 loop
            if fl_f(i) = '1' then
               fl_req(i) <= '1';
            end if;
         end loop;

         -- a configuration write: this drive's buffer contents (if any) are no longer its own,
         -- its extent cache is stale, its FAULT is cleared, and the engine side must ask again
         for i in 0 to 3 loop
            if c_wr(i) = '1' then
               fault(i) <= '0';
               q_gen    <= not q_gen;
               if c_unit = std_logic_vector(to_unsigned(i, 2)) then
                  c_valid <= '0';
               end if;
               c_pend(i) <= '1';
            end if;
         end loop;

         -- SD read data into the buffer
         if sd_rd_we_i = '1' and x_wr = '0' then
            if sd_rd_idx_i(0) = '0' then
               lo_byte <= sd_rd_data_i;
            else
               b_we    <= '1';
               b_waddr <= std_logic_vector(resize(run_s + unsigned(sd_rd_blk_i(3 downto 0)), 4)) &
                          sd_rd_idx_i(8 downto 1);
               b_wdata <= sd_rd_data_i & lo_byte;
            end if;
         end if;
         if sd_blk_i = '1' then
            moved <= moved + 1;
            if x_wr = '1' then
               n_wblk <= n_wblk + 1;
            else
               n_rblk <= n_rblk + 1;
            end if;
         end if;

         case st is

            when Q_IDLE =>
               hold <= '0';
               if c_pend /= "0000" then
                  -- configuration writes, applied between operations: a drive's buffer
                  -- contents are dropped (the firmware has flushed them before)
                  c_pend <= (others => '0');
                  if c_pend(to_integer(unsigned(t_unit))) = '1' then
                     t_valid <= '0';
                     s_valid <= (others => '0');
                     s_dirty <= (others => '0');
                  end if;
               elsif q_req_s /= q_req_seen then
                  q_req_seen <= q_req_s;
                  r_op   <= m_req_op;              -- stable while the toggle crossed
                  r_unit <= m_req_unit;
                  r_lba  <= m_req_lba;
                  r_prod <= resize(m_req_lba * to_unsigned(5958, 13), 24);   -- / 11 (exact
                  n_req  <= n_req + 1;                                       --  below 2048)
                  st     <= Q_DIV;
               elsif t_valid = '1' and s_dirty /= "00000000000" and
                     (age = G_FLUSH_DELAY or fl_req(to_integer(unsigned(t_unit))) = '1') then
                  fl_req(to_integer(unsigned(t_unit))) <= '0';
                  st_next <= Q_IDLE;
                  st    <= Q_FLUSH;
               else
                  -- a FLUSH for a drive that has nothing dirty is done at once
                  for i in 0 to 3 loop
                     if fl_req(i) = '1' and fl_f(i) = '0' and
                        (t_valid = '0' or t_unit /= std_logic_vector(to_unsigned(i, 2)) or
                         s_dirty = "00000000000") then
                        fl_req(i) <= '0';
                     end if;
                  end loop;
               end if;

            when Q_DIV =>
               r_track <= r_prod(23 downto 16);
               st      <= Q_SEC;

            when Q_SEC =>
               r_sec <= resize(r_lba - resize(r_track * to_unsigned(11, 4), 11), 4);
               st    <= Q_DECIDE;

            when Q_DECIDE =>
               u := to_integer(unsigned(r_unit));
               q_ack_sec <= r_sec;
               q_ack_err <= '0';
               if c_mode(u)(0) = '0' or resize(r_lba, 32) >= c_sects(u) then
                  -- not a sector of a mounted file: reads get an error, writes are dropped
                  q_ack_err <= '1';
                  st        <= Q_ANSWER;
               elsif r_op = OP_COMMIT then
                  if t_valid = '1' and t_unit = r_unit and t_track = r_track then
                     s_valid <= s_valid or f_sec_mask(r_sec);
                     s_dirty <= s_dirty or f_sec_mask(r_sec);
                     age     <= 0;
                  end if;
                  st <= Q_ANSWER;
               elsif t_valid = '0' or t_unit /= r_unit or t_track /= r_track then
                  -- another track: write the dirty sectors back, then take the new tag
                  if t_valid = '1' and s_dirty /= "00000000000" then
                     st_next <= Q_DECIDE;
                     st    <= Q_FLUSH;
                  else
                     t_valid <= '1';
                     t_unit  <= r_unit;
                     t_track <= r_track;
                     s_valid <= (others => '0');
                     s_dirty <= (others => '0');
                     if c_sects(u) >= resize(r_lba - r_sec + 11, 32) then
                        t_nsec <= 11;
                     else
                        t_nsec <= to_integer(c_sects(u)(3 downto 0) - resize(r_lba - r_sec, 4));
                     end if;
                  end if;
               elsif r_op = OP_WR and (s_dirty and f_sec_mask(r_sec)) /= "00000000000" then
                  -- a committed sector that is not on the card yet: write it back first (an
                  -- engine that aborts halfway through overwriting it must not lose it)
                  st_next <= Q_DECIDE;
                  st      <= Q_FLUSH;
               elsif r_op = OP_WR then
                  -- the engine overwrites the sector; until COMMIT it is not valid
                  s_valid <= s_valid and not f_sec_mask(r_sec);
                  st      <= Q_ANSWER;
               elsif (s_valid and f_sec_mask(r_sec)) /= "00000000000" then
                  st <= Q_ANSWER;                       -- a hit
               else
                  n_load <= n_load + 1;
                  tries  <= 0;
                  st_next  <= Q_ANSWER;
                  st     <= Q_LOAD;
               end if;

            when Q_ANSWER =>
               -- PREP_RD after a failed load: the sector is still not valid
               if r_op = OP_RD and q_ack_err = '0' and
                  (s_valid and f_sec_mask(r_sec)) = "00000000000" then
                  q_ack_err <= '1';
               end if;
               hold <= '0';
               st   <= Q_ANSWER;
               if q_ack_err = '1' or r_op /= OP_RD or
                  (s_valid and f_sec_mask(r_sec)) /= "00000000000" then
                  q_ack <= not q_ack;                -- q_ack_sec/err settled a clock ago
                  st    <= Q_IDLE;
               end if;

            ------------------------------------------------------------------------------
            -- write-back: the first run of dirty sectors, until none is left
            ------------------------------------------------------------------------------
            when Q_FLUSH =>
               s := 11;
               for i in 10 downto 0 loop
                  if s_dirty(i) = '1' then
                     s := i;
                  end if;
               end loop;
               if s = 11 then
                  st <= st_next;
               else
                  e := s;
                  for i in 0 to 10 loop
                     if i > s and i = e + 1 and s_dirty(i) = '1' then
                        e := i;
                     end if;
                  end loop;
                  x_wr   <= '1';
                  x_unit <= t_unit;
                  run_s  <= to_unsigned(s, 4);
                  run_n  <= to_unsigned(e - s + 1, 4);
                  tries  <= 0;
                  nr_on  <= '0';
                  st     <= Q_RUN_LOOK;
               end if;

            ------------------------------------------------------------------------------
            -- load: the first run of sectors that are not valid
            ------------------------------------------------------------------------------
            when Q_LOAD =>
               s := 11;
               for i in 10 downto 0 loop
                  if s_valid(i) = '0' and i < t_nsec then
                     s := i;
                  end if;
               end loop;
               if s = 11 then
                  st <= st_next;
               else
                  e := s;
                  for i in 0 to 10 loop
                     if i > s and i = e + 1 and s_valid(i) = '0' and i < t_nsec then
                        e := i;
                     end if;
                  end loop;
                  x_wr   <= '0';
                  x_unit <= t_unit;
                  run_s  <= to_unsigned(s, 4);
                  run_n  <= to_unsigned(e - s + 1, 4);
                  tries  <= 0;
                  nr_on  <= '0';
                  st     <= Q_RUN_LOOK;
               end if;

            ------------------------------------------------------------------------------
            -- lookup of the run's first sector (ide_engine's E_LOOK..E_LOOK_C3)
            ------------------------------------------------------------------------------
            when Q_RUN_LOOK =>
               run_lba <= resize(t_track * to_unsigned(11, 4), 32) + run_s;
               if mode(0) = '0' then
                  x_fail <= '1';                     -- the drive went off under our feet
                  st     <= Q_RUN_END;
               else
                  st <= Q_LOOK_N;
                  rd_ph <= 7;                        -- compute ci first (below)
               end if;

            when Q_LOOK_N =>
               if rd_ph = 7 then
                  if resize(run_lba, 33) + run_n > resize(c_sects(to_integer(unsigned(x_unit))), 33) then
                     -- a run past the end of the file: only what is inside (a sector outside
                     -- the file is never asked for: Q_DECIDE refuses it)
                     run_n <= resize(c_sects(to_integer(unsigned(x_unit))) - run_lba, 4);
                  end if;
                  ci <= shift_right(run_lba, shift);
                  if c_valid = '1' and c_unit = x_unit and shift_right(run_lba, shift) >= c_cum then
                     ext_i <= c_i;
                     cum   <= c_cum;
                  else
                     ext_i <= (others => '0');
                     cum   <= (others => '0');
                  end if;
                  maddr <= unsigned(x_unit) & "00000000000";
                  rd_ph <= 0;
               elsif rd_ph = 1 then
                  ext_n <= unsigned(map_q);
                  rd_ph <= 0;
                  st    <= Q_LOOK_EXT;
               else
                  rd_ph <= rd_ph + 1;
               end if;

            when Q_LOOK_EXT =>
               if ext_i >= ext_n then
                  x_fail <= '1';                     -- not in the map
                  st     <= Q_RUN_END;
               else
                  case rd_ph is
                     when 0 =>
                        maddr <= unsigned(x_unit) & ((ext_i(8 downto 0) & "00") + 1);
                     when 2 =>
                        e_first(15 downto 0) <= unsigned(map_q);
                        maddr <= unsigned(x_unit) & ((ext_i(8 downto 0) & "00") + 2);
                     when 3 =>
                        maddr <= unsigned(x_unit) & ((ext_i(8 downto 0) & "00") + 3);
                     when 4 =>
                        e_first(31 downto 16) <= unsigned(map_q);
                        maddr <= unsigned(x_unit) & ((ext_i(8 downto 0) & "00") + 4);
                     when 5 =>
                        e_len(15 downto 0) <= unsigned(map_q);
                     when 6 =>
                        e_len(31 downto 16) <= unsigned(map_q);
                     when others => null;
                  end case;
                  if rd_ph = 6 then
                     rd_ph <= 0;
                     st    <= Q_LOOK_CMP;
                  else
                     rd_ph <= rd_ph + 1;
                  end if;
               end if;

            when Q_LOOK_CMP =>
               endc := cum + e_len;
               if ci < endc then
                  p_rel   <= ci - cum;
                  p_off   <= run_lba - shift_left(ci, shift);
                  p_end   <= endc;
                  c_i     <= ext_i;
                  c_cum   <= cum;
                  c_unit  <= x_unit;
                  c_valid <= '1';
                  st      <= Q_LOOK_C2;
               else
                  cum   <= endc;
                  ext_i <= ext_i + 1;
                  st    <= Q_LOOK_EXT;
               end if;

            when Q_LOOK_C2 =>
               p_clus <= e_first + p_rel;
               runv := shift_left(p_end, shift) - run_lba;   -- sectors left in this extent
               if runv < resize(run_n, 32) then
                  run_len <= runv(15 downto 0);
               else
                  run_len <= resize(run_n, 16);
               end if;
               st <= Q_LOOK_C3;

            when Q_LOOK_C3 =>
               run_blk <= base + shift_left(p_clus, shift) + p_off;
               hold    <= '1';
               st      <= Q_GNT;

            ------------------------------------------------------------------------------
            -- the transfer: run_len blocks from run_blk <-> sectors run_s..
            ------------------------------------------------------------------------------
            when Q_GNT =>
               if sd_gnt_i = '1' then
                  if sd_ready_i = '0' then
                     x_fail <= '1';                  -- no card / not initialised
                     x_nrdy <= '1';
                     st     <= Q_RUN_END;
                  else
                     st <= Q_START;
                  end if;
               end if;

            when Q_START =>
               if sd_busy_i = '0' then
                  moved    <= (others => '0');
                  sd_start <= '1';
                  st       <= Q_RUN;
               end if;

            when Q_RUN =>
               if sd_done_i = '1' then
                  if sd_error_i = '1' then
                     x_fail <= '1';
                     st     <= Q_RUN_END;
                  else
                     -- the blocks that are through (a preempted transfer ends early: the
                     -- rest is looked up and started again)
                     m := (others => '0');
                     for i in 0 to 10 loop
                        if i >= to_integer(run_s) and i < to_integer(run_s) + to_integer(moved) then
                           m(i) := '1';
                        end if;
                     end loop;
                     if x_wr = '1' then
                        s_dirty <= s_dirty and not m;
                     else
                        s_valid <= s_valid or m;
                     end if;
                     run_s <= run_s + moved(3 downto 0);
                     run_n <= run_n - moved(3 downto 0);
                     tries <= 0;
                     if moved(3 downto 0) = run_n then
                        st <= Q_RUN_END;
                     else
                        st <= Q_RUN_LOOK;
                     end if;
                  end if;
               end if;

            -- one run is over: the next one, or a retry, or give up
            when Q_RUN_END =>
               if x_fail = '1' then
                  x_fail <= '0';
                  x_nrdy <= '0';
                  if x_nrdy = '1' and (nr_on = '0' or nr_cnt < C_NR_MAX) and mode(0) = '1' then
                     if nr_on = '0' then             -- wait for the controller
                        nr_on  <= '1';
                        nr_cnt <= 0;
                     end if;
                     hold   <= '0';
                     bo_cnt <= G_MS;
                     st     <= Q_BACKOFF;
                  elsif tries < G_RETRIES and mode(0) = '1' then
                     tries  <= tries + 1;            -- try again a little later
                     hold   <= '0';
                     bo_cnt <= G_MS;
                     st     <= Q_BACKOFF;
                  elsif x_wr = '1' then
                     -- the write-back of these sectors failed for good: drop them
                     n_werr <= n_werr + 1;
                     fault(to_integer(unsigned(x_unit))) <= '1';
                     m := (others => '0');
                     for i in 0 to 10 loop
                        if i >= to_integer(run_s) and i < to_integer(run_s) + to_integer(run_n) then
                           m(i) := '1';
                        end if;
                     end loop;
                     s_dirty <= s_dirty and not m;
                     tries   <= 0;
                     st      <= Q_FLUSH;
                  else
                     -- a load failed for good: the sectors stay not valid (asked again later)
                     n_rerr <= n_rerr + 1;
                     tries  <= 0;
                     hold   <= '0';
                     st     <= st_next;
                  end if;
               elsif x_wr = '1' then
                  st <= Q_FLUSH;
               else
                  st <= Q_LOAD;
               end if;

            when Q_BACKOFF =>
               if bo_cnt = 0 then
                  st <= Q_RUN_LOOK;
               else
                  bo_cnt <= bo_cnt - 1;
               end if;

            when others =>
               st <= Q_IDLE;
         end case;

         if rst_i = '1' then
            st      <= Q_IDLE;
            hold    <= '0';
            t_valid <= '0';
            s_valid <= (others => '0');
            s_dirty <= (others => '0');
            c_valid <= '0';
            fl_req  <= (others => '0');
            fault   <= (others => '0');
            c_pend  <= (others => '0');
            q_req_seen <= q_req_s;
            q_ack      <= q_req_s;               -- a request that crossed is answered
            q_ack_err  <= '1';
         end if;
      end if;
   end process q_main;

end architecture synthesis;
