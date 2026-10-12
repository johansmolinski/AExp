---------------------------------------------------------------------------------------------------------
-- Megamiga
--
-- share_buf: the shared memory of the shared folder (the /amiga folder of the SD card as an
-- AmigaOS volume). It is the memory MiSTer's Minimig maps at $DD4000-$DD5FFF for
-- MiSTerFileSystem: the Amiga-side handler writes a request (an AmigaOS DOS packet in the
-- layout of MiSTer's miminig_fs_messages.h) and waits; the QNICE firmware (SHARE_STEP in
-- m2m-rom.asm) answers it from the FAT32 file system of the SD card, like the HPS side
-- (Main_MiSTer support/minimig/minimig_share.cpp) does on the MiSTer.
--
--   $DD4000  request flag: word 0 = request number (written last by the CPU), word 1 =
--            0xA55A while a request is pending, the request number once it is answered
--   $DD4004  request / response (up to 512 bytes)
--   $DD4FF8  Megamiga: firmware status for MegamigaFS (see m2m-rom.asm, SHARE_*)
--   $DD5000  data buffer (4 KB) for READ and WRITE
--
-- CPU side: cpu_wrapper's ext_* port (sel_i = ext_sel for $DD4000-$DD5FFF), a word or byte
-- access per bus cycle, DTACK two clocks after the strobe (one for the block RAM read).
--
-- QNICE side: device C_DEV_AMIGA_SHARE, falling edge, zero wait states.
--   window 0  the 8 KB as 4096 words (word n = CPU bytes 2n (bits 15:8) and 2n+1)
--   window 1  word 0: the number of Amiga resets so far (read only): the firmware drops
--             every lock and open file of the handler when it changes
--
-- Done in 2026 (Megamiga) and licensed under GPL v3.
---------------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity share_buf is
   port (
      -- core clock domain: the CPU (cpu_wrapper ext_* port)
      clk_i          : in  std_logic;
      rst_i          : in  std_logic;        -- Amiga reset or RESET instruction
      sel_i          : in  std_logic;        -- bus cycle to $DD4000-$DD5FFF
      rw_i           : in  std_logic;        -- '1' = read
      uds_n_i        : in  std_logic;
      lds_n_i        : in  std_logic;
      addr_i         : in  std_logic_vector(12 downto 1);  -- offset from $DD4000
      data_i         : in  std_logic_vector(15 downto 0);
      data_o         : out std_logic_vector(15 downto 0);
      ready_o        : out std_logic;        -- -> DTACK

      -- QNICE clock domain: the firmware
      qnice_clk_i    : in  std_logic;
      qnice_addr_i   : in  std_logic_vector(27 downto 0);
      qnice_data_i   : in  std_logic_vector(15 downto 0);
      qnice_ce_i     : in  std_logic;
      qnice_we_i     : in  std_logic;
      qnice_data_o   : out std_logic_vector(15 downto 0)
   );
end entity share_buf;

architecture synthesis of share_buf is

   type t_bus is (B_IDLE, B_READ, B_ACK);
   signal bus_state : t_bus := B_IDLE;
   signal ready     : std_logic := '0';
   signal ack_rw    : std_logic := '1';
   signal rdata     : std_logic_vector(15 downto 0) := (others => '0');

   signal a_addr    : std_logic_vector(11 downto 0) := (others => '0');
   signal a_wdata   : std_logic_vector(15 downto 0) := (others => '0');
   signal a_be      : std_logic_vector(1 downto 0) := "00";
   signal a_we      : std_logic := '0';
   signal a_q       : std_logic_vector(15 downto 0);

   -- Amiga resets: counted in the core clock domain, the count is gray coded and
   -- synchronized into the QNICE domain (it changes slowly: one step per reset)
   signal rst_d     : std_logic := '0';
   signal rst_cnt   : unsigned(15 downto 0) := (others => '0');
   signal rst_gray  : std_logic_vector(15 downto 0) := (others => '0');
   signal q_gray1   : std_logic_vector(15 downto 0) := (others => '0');
   signal q_gray2   : std_logic_vector(15 downto 0) := (others => '0');
   attribute ASYNC_REG : string;
   attribute ASYNC_REG of q_gray1 : signal is "TRUE";
   attribute ASYNC_REG of q_gray2 : signal is "TRUE";

   signal q_win1    : std_logic := '0';
   signal q_we      : std_logic;
   signal q_q       : std_logic_vector(15 downto 0);
   signal q_rcnt    : std_logic_vector(15 downto 0);

   function gray2bin(g : std_logic_vector(15 downto 0)) return std_logic_vector is
      variable b : std_logic_vector(15 downto 0);
   begin
      b(15) := g(15);
      for i in 14 downto 0 loop
         b(i) := b(i + 1) xor g(i);
      end loop;
      return b;
   end function gray2bin;

begin

   ready_o <= ready and sel_i and not (rw_i xor ack_rw);
   data_o  <= rdata;

   i_ram : entity work.dualport_2clk_ram_byteenable
      generic map (
         G_ADDR_WIDTH => 12,
         G_DATA_WIDTH => 16,
         G_FALLING_A  => false,
         G_FALLING_B  => true
      )
      port map (
         a_clk_i        => clk_i,
         a_address_i    => a_addr,
         a_data_i       => a_wdata,
         a_byteenable_i => a_be,
         a_wren_i       => a_we,
         a_q_o          => a_q,
         b_clk_i        => qnice_clk_i,
         b_address_i    => qnice_addr_i(11 downto 0),
         b_data_i       => qnice_data_i,
         b_byteenable_i => "11",
         b_wren_i       => q_we,
         b_q_o          => q_q
      ); -- i_ram

   -- the CPU: one access per bus cycle, then hold DTACK until the cycle ends
   cpu_proc : process (clk_i)
   begin
      if rising_edge(clk_i) then
         a_we <= '0';
         case bus_state is
            when B_IDLE =>
               ready <= '0';
               -- a write starts once a data strobe is valid (the data is valid then)
               if sel_i = '1' and (rw_i = '1' or uds_n_i = '0' or lds_n_i = '0') then
                  a_addr  <= addr_i;
                  a_wdata <= data_i;
                  a_be    <= (not uds_n_i) & (not lds_n_i);
                  ack_rw  <= rw_i;
                  if rw_i = '1' then
                     bus_state <= B_READ;
                  else
                     a_we      <= '1';
                     ready     <= '1';
                     bus_state <= B_ACK;
                  end if;
               end if;

            when B_READ =>
               -- the address was applied in the previous clock: the data is there now
               bus_state <= B_ACK;

            when B_ACK =>
               if ack_rw = '1' and ready = '0' then
                  rdata <= a_q;
                  ready <= '1';
               end if;
               -- hold DTACK until the cycle ends (AS negated or the direction changed)
               if ready = '1' and (sel_i = '0' or rw_i /= ack_rw) then
                  ready     <= '0';
                  bus_state <= B_IDLE;
               end if;
         end case;

         if rst_i = '1' then
            bus_state <= B_IDLE;
            ready     <= '0';
         end if;

         -- count the Amiga resets (rising edge of rst_i)
         rst_d <= rst_i;
         if rst_i = '1' and rst_d = '0' then
            rst_cnt <= rst_cnt + 1;
         end if;
         rst_gray <= std_logic_vector(rst_cnt xor shift_right(rst_cnt, 1));
      end if;
   end process cpu_proc;

   -- the firmware: window 0 is the RAM, window 1 the reset counter
   q_we <= qnice_ce_i and qnice_we_i and not qnice_addr_i(12);

   qnice_proc : process (qnice_clk_i)
   begin
      if falling_edge(qnice_clk_i) then
         q_gray1 <= rst_gray;
         q_gray2 <= q_gray1;
         q_rcnt  <= gray2bin(q_gray2);
         q_win1  <= qnice_addr_i(12);
      end if;
   end process qnice_proc;

   -- (the RAM output is registered on the falling edge, like the address of q_win1)
   qnice_data_o <= q_rcnt when q_win1 = '1' else q_q;

end architecture synthesis;
