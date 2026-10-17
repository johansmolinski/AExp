---------------------------------------------------------------------------------------------------------
-- Megamiga for MEGA65
--
-- sd_eng_arb: the SD host controller's engine port (sdhost_pkg) shared by two clients: the IDE
-- sector engine (client A, the default owner) and the ADF track buffer (client B, adf_sd.vhd).
--
--   * One client owns the port at a time. Only the owner sees the controller: the other one sees
--     busy = '1' (both clients start a transfer only while busy is '0') and no done/block/data
--     strobes. The owner's outputs (slot, start, addresses, write data) go to the controller.
--   * Client B asks with req_b_i and holds it for a whole operation (one or more transfers);
--     while it holds it, gnt_b_o says that it owns the port. Client A gets gnt_a_o: the IDE
--     engine waits with a new command until it owns the port, because it decides on the
--     controller's ready bit, which is only meaningful for the owner's slot.
--   * The owner changes only between transfers: a start pulse locks the port until the
--     controller's done pulse (sdhost raises busy only some clocks after the start, and
--     sdslots latches the slot from the start pulse on, so the lock must begin with the pulse).
--     A client decides to start on the busy it sees in one clock and raises its start pulse in
--     the next one, so the port is handed to B in two steps: first A is frozen (it sees busy
--     from now on) while A still owns the port - a start that A decided in the clock before
--     still reaches the controller and locks it for A - and one clock later, if A did not
--     start, B owns it. B gives it back as soon as it drops the request (it never starts
--     after that). A preempted transfer of A (QNICE has priority in the controller) ends with
--     a done pulse like any other, so B can get in between.
--
-- QNICE clock domain. Done in 2026 (Megamiga fork) and licensed under GPL v3.
---------------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

use work.sdhost_pkg.all;

entity sd_eng_arb is
   port (
      clk_i     : in  std_logic;
      rst_i     : in  std_logic;
      -- client A (IDE engine)
      a_c2q_i   : in  t_sd_c2q;
      a_q2c_o   : out t_sd_q2c;
      gnt_a_o   : out std_logic;
      -- client B (ADF track buffer)
      b_c2q_i   : in  t_sd_c2q;
      b_q2c_o   : out t_sd_q2c;
      req_b_i   : in  std_logic;
      gnt_b_o   : out std_logic;
      -- the controller (sdslots)
      c2q_o     : out t_sd_c2q;
      q2c_i     : in  t_sd_q2c
   );
end entity sd_eng_arb;

architecture synthesis of sd_eng_arb is

   signal own_b  : std_logic := '0';
   signal frz_a  : std_logic := '0';     -- A sees busy, but still owns the port
   signal locked : std_logic := '0';

   -- what a client that does not own the port sees: ready as it is (the owner's slot), busy,
   -- nothing else
   function f_shut(q : t_sd_q2c) return t_sd_q2c is
      variable r : t_sd_q2c := (others => '0');
   begin
      r(Q2C_READY) := q(Q2C_READY);
      r(Q2C_BUSY)  := '1';
      return r;
   end function;

begin

   c2q_o <= b_c2q_i when own_b = '1' else a_c2q_i;

   a_q2c_o <= q2c_i when own_b = '0' and frz_a = '0' else
              q2c_i when own_b = '0' and locked = '1' else
              f_shut(q2c_i);
   b_q2c_o <= q2c_i when own_b = '1' else f_shut(q2c_i);

   gnt_a_o <= not own_b and not frz_a;
   gnt_b_o <= own_b and req_b_i;

   p_owner : process (clk_i)
   begin
      if rising_edge(clk_i) then
         if locked = '0' then
            if (own_b = '0' and a_c2q_i(C2Q_START) = '1') or
               (own_b = '1' and b_c2q_i(C2Q_START) = '1') then
               locked <= '1';                  -- (a frozen A that started keeps the port)
               frz_a  <= '0';
            elsif own_b = '0' and frz_a = '0' and req_b_i = '1' then
               frz_a  <= '1';
            elsif own_b = '0' and frz_a = '1' then
               frz_a  <= '0';
               own_b  <= req_b_i;
            elsif own_b = '1' and req_b_i = '0' then
               own_b  <= '0';
            end if;
         elsif q2c_i(Q2C_DONE) = '1' then
            locked <= '0';
         end if;
         if rst_i = '1' then
            own_b  <= '0';
            frz_a  <= '0';
            locked <= '0';
         end if;
      end if;
   end process p_owner;

end architecture synthesis;
