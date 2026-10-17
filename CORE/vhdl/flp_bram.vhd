---------------------------------------------------------------------------------------------------------
-- Megamiga for MEGA65
--
-- flp_bram: what is left of the "floppy memory" once the ADF images are read straight from the SD
-- card (adf_sd.vhd): the IDE board's boot ROM (lide.rom), in block RAM.
--
-- Until now the IDE boot ROM and the three ADF pools shared the floppy port of amiga_sdram.vhd, a
-- half of SDRAM bank 0 (column bit 9 = 1). The pools are gone, so the ROM moves here and that half
-- bank is free. This is an Avalon slave on the core clock in place of the SDRAM floppy port behind
-- the same arbiter tree (mega65.vhd): the ROM loader (a mount wrapper used as a byte bridge) writes
-- bytes into the window G_BASE .. G_BASE + 2^G_ADDR_WIDTH - 1 (word addresses), the IDE board reads
-- words from it. Every other address is accepted and answers 0 (the ADF wrappers' byte bridges are
-- no longer used by the firmware; nothing may hang on them if they are).
--
-- Reads: one word per clock after the address, bursts supported (waitrequest while one runs);
-- writes: one word per clock with byte enables.
--
-- Done in 2026 (Megamiga fork) and licensed under GPL v3.
---------------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity flp_bram is
   generic (
      G_BASE          : std_logic_vector(21 downto 0);   -- word address of the window
      G_ADDR_WIDTH    : natural := 14                    -- 16K words = 32 KB
   );
   port (
      clk_i               : in  std_logic;
      rst_i               : in  std_logic;
      avm_write_i         : in  std_logic;
      avm_read_i          : in  std_logic;
      avm_address_i       : in  std_logic_vector(31 downto 0);
      avm_writedata_i     : in  std_logic_vector(15 downto 0);
      avm_byteenable_i    : in  std_logic_vector( 1 downto 0);
      avm_burstcount_i    : in  std_logic_vector( 7 downto 0);
      avm_readdata_o      : out std_logic_vector(15 downto 0);
      avm_readdatavalid_o : out std_logic;
      avm_waitrequest_o   : out std_logic
   );
end entity flp_bram;

architecture synthesis of flp_bram is

   signal cnt    : unsigned(7 downto 0) := (others => '0');   -- words of the burst still to go
   signal cur    : unsigned(31 downto 0) := (others => '0');
   signal r_addr : std_logic_vector(31 downto 0);
   signal r_win  : std_logic;
   signal rdv    : std_logic := '0';
   signal rwin   : std_logic := '0';
   signal we_lo  : std_logic;
   signal we_hi  : std_logic;
   signal q_lo   : std_logic_vector(7 downto 0);
   signal q_hi   : std_logic_vector(7 downto 0);

   function f_win(a : std_logic_vector(31 downto 0)) return std_logic is
   begin
      if a(31 downto 22) = "0000000000" and
         a(21 downto G_ADDR_WIDTH) = G_BASE(21 downto G_ADDR_WIDTH) then
         return '1';
      end if;
      return '0';
   end function;

begin

   assert unsigned(G_BASE(G_ADDR_WIDTH - 1 downto 0)) = 0
      report "flp_bram: the window must be aligned to its size" severity failure;

   avm_waitrequest_o   <= '1' when cnt /= 0 else '0';
   avm_readdatavalid_o <= rdv;
   avm_readdata_o      <= q_hi & q_lo when rwin = '1' else (others => '0');

   -- the address of this clock: a new access, or the next word of a running burst
   r_addr <= std_logic_vector(cur) when cnt /= 0 else avm_address_i;
   r_win  <= f_win(r_addr);

   we_lo <= '1' when cnt = 0 and avm_write_i = '1' and avm_byteenable_i(0) = '1' and r_win = '1' else '0';
   we_hi <= '1' when cnt = 0 and avm_write_i = '1' and avm_byteenable_i(1) = '1' and r_win = '1' else '0';

   i_lo : entity work.tdp_ram
      generic map (ADDR_WIDTH => G_ADDR_WIDTH, DATA_WIDTH => 8)
      port map (
         clock_a   => clk_i,
         address_a => r_addr(G_ADDR_WIDTH - 1 downto 0),
         data_a    => avm_writedata_i(7 downto 0),
         wren_a    => we_lo,
         q_a       => q_lo,
         clock_b   => clk_i,
         address_b => (others => '0'),
         data_b    => (others => '0'),
         wren_b    => '0',
         q_b       => open
      ); -- i_lo

   i_hi : entity work.tdp_ram
      generic map (ADDR_WIDTH => G_ADDR_WIDTH, DATA_WIDTH => 8)
      port map (
         clock_a   => clk_i,
         address_a => r_addr(G_ADDR_WIDTH - 1 downto 0),
         data_a    => avm_writedata_i(15 downto 8),
         wren_a    => we_hi,
         q_a       => q_hi,
         clock_b   => clk_i,
         address_b => (others => '0'),
         data_b    => (others => '0'),
         wren_b    => '0',
         q_b       => open
      ); -- i_hi

   p_ctrl : process (clk_i)
   begin
      if rising_edge(clk_i) then
         rdv  <= '0';
         rwin <= r_win;
         if cnt /= 0 then
            -- the next word of the burst (its address went to the RAM in this clock)
            rdv <= '1';
            cur <= cur + 1;
            cnt <= cnt - 1;
         elsif avm_read_i = '1' then
            rdv <= '1';
            cur <= unsigned(avm_address_i) + 1;
            if unsigned(avm_burstcount_i) > 1 then
               cnt <= unsigned(avm_burstcount_i) - 1;
            end if;
         end if;
         if rst_i = '1' then
            cnt <= (others => '0');
            rdv <= '0';
         end if;
      end if;
   end process p_ctrl;

end architecture synthesis;
