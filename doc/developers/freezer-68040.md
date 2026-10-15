# Freezer cartridge on the 68040 - parked (October 2026)

Status: **not supported**. The freezer cartridges (HRTmon, Action Replay III) are
plugged in only with a 68000 or 68020 profile; with the 68040 the "Cart" radio of
Profile Settings plugs in nothing (`main_cart_req` in `CORE/vhdl/mega65.vhd`). This
note records how far the 68040 work got, so it can be picked up again.

## What was seen on the hardware

Build f of the `cart-ar3-hrtmon` worktree, A1200 profile (KS 3.1, AGA, OS 3.1, no RTG,
Z3 RAM), HRTmon, freeze with CTRL+MEGA+HELP:

| CPU   | at the Kickstart screen | after Workbench has loaded |
|-------|-------------------------|----------------------------|
| 68000 | works (A500 profile, KS 1.3) | works |
| 68020 | works                   | works                      |
| 68040 | **works**               | **hangs** (no guru, frozen) |

One more 68040 observation that was never explained: after Workbench, reset, then
freeze at the Kickstart screen - "it does not load nor hangs". Check this first on any
new attempt (it may be the same cause: the VBR/caches survive a warm reset).

## Cause (found in simulation)

A freeze is a level 7 interrupt. `cart.v` makes the CPU enter the cartridge by
overriding the level 7 autovector read (VBR + `$7C`) on the chip bus; the 68000/68020
end the request with their IACK cycle, the 68040 core has none, so `cart.v`
acknowledges the freeze when it sees the vector read.

On the 68040 that read never reaches `cart.v` once the OS has turned the caches on:

1. **The data cache serves it.** Chip RAM is D-cacheable (snooped) on this core, and the
   cache line of `$7C` also holds `$78`, the level 6 (CIA-B) vector, which is read all the
   time - so the line is practically always resident.
2. **The Fast RAM port serves it** when the OS (or SetPatch/68040.library tools) moved
   the VBR into Fast RAM: `ap040_island.v` sends Zorro II/III reads straight to the
   `fp_*` port of `sdram_ctrl`, past the chip bus.

The CPU then runs the OS's level 7 handler, the freeze request is never acknowledged,
IPL stays at 7 and masks every lower interrupt: the machine freezes.

## The fix that worked in simulation

`freezer-68040.patch` (next to this file; `git apply doc/developers/freezer-68040.patch`
from the repository root, applies to the Minimig submodule as of the cart worktree).
Active only while IPL is 7 and only for the exact long word VBR + `$7C`, so no other
access can bypass a dirty copyback line:

- `rtl/ap040/ap040_pipe_tg68k_compat.v`, at module level: `nmi_vec_q <= vbr_out[31:2] +
  30'h1F`, `nmi_l7_q <= (ipl == 3'b000)` (IPL is active low), `dfp_nmi_q` = the data fast
  path's address is that vector. In `g_cache`: `nmi_vec_rd` ORed into `.c_nocache`
  (read uncached), `!dfp_nmi` ANDed into `dfp_hit` and `dfp_ram` (no fast-path hit).
- `rtl/ap040_island.v`: `e_nmi` keeps that read off the Fast RAM port (`e_fp`).
- `cpu_wrapper.v`'s existing `sel_nmi_vector` then puts the read on the chip bus, where
  `cart.v` overrides it.

(A first attempt put the registers into the `g_nommu` branch - wrong, the A1200 build
has the MMU; they must be at module level.)

## Simulation proof

Out-of-repo freeze testbench `~/aexp-work/cart/frz/` (Verilator; cpu_wrapper, bridge,
cart.v, ar3.v, fx68k/TG68K/AP68040 + island, a Fast RAM port model with 16-byte lines):

```sh
cd ~/aexp-work/cart/frz
# real HRTmon image (patched: AGA, 2 MB), 68040, HRTmon
REALHRT=1 HRTDIR=<dir with hrtmon_?.hex> SUF=_wbC \
  PROGAS="--defsym POSTWB=1 --defsym MOVEVBR=1 --defsym HOTVEC=1" \
  ./build.sh 040 1 -DREALHRT
# result line: "REALHRT: main loop reads N, OS NMI handler TAKEN / not taken"
# R=<rtl dir> runs against another copy of the RTL (e.g. HEAD without the fix)
```

`prog.S` symbols: `POSTWB` = caches on like after Workbench (DE+IE, copyback),
`MOVEVBR` = VBR to `$200000` (Fast RAM), `HOTVEC` = the main loop keeps reading VBR+`$7C`'s
line (keeps it in the cache), `AUTOCONFIG`.

| variant | PROGAS                     | with fix | without fix |
|---------|----------------------------|----------|-------------|
| ks      | -                          | PASS     | PASS (matches the HW: KS screen works) |
| wbA     | POSTWB                     | PASS     | PASS        |
| wbB     | POSTWB MOVEVBR             | PASS     | OS handler taken (red) |
| wbC     | POSTWB MOVEVBR HOTVEC      | PASS     | red; also red with only the c_nocache part, and without the island part |
| wbD     | POSTWB HOTVEC (VBR 0)      | PASS     | red         |

With the fix, 68000/020/040 with the real image all reach HRTmon's main loop
(`$A18Dxx`); the regression runs 000/1, 020/1, 040/1, 000/2 (AR3) pass.

## Why it was parked: timing

The fix is a 30-bit compare on the cache address and one on the fast-path address in the
68040's `cpu_clk` domain (42.04 MHz), which has almost no slack (build f, without the fix:
WNS +0.017 ns).

Build g (fix included), R6: four placement passes ended at WNS -0.743 / -0.509 / -0.878 /
-0.270 ns, the final result was **WNS -0.547 ns** (WHS +0.050), larger than the 0.5 ns
re-roll limit. The identical sources on the Fedora build host gave the identical result
(Vivado is deterministic), so a re-run with the same sources is pointless.

The failing paths do **not** contain the fix's cells. All of them lie inside the AP68040
core, 43 logic levels, 74 % routing:
`u_eaf/eaf_o_reg[cls]` -> `u_ex` ALU (shift count, adder) -> flags -> `fw_ccr` ->
`u_eaf` condition (`cond_true`, `eaf_stall`) -> `u_eac` redirect -> `u_id` consume ->
`u_if` `f_req`/`f_gnt` -> the fetch PC adder `u_if/fpc_reg[31:0]` (and
`g_bus.u_bcu/mem_addr_reg`). The extra logic changes the placement, and this long path
of the core loses.

## How to resume

1. Apply the patch; rerun the testbench table above (all with fix must PASS).
2. Get the timing back, e.g.:
   - make the compare cheaper: compare `mm_addr` against a registered VBR + `$7C` only in
     the low bits that can differ within a cache line, gating with a registered
     "VBR line matched" flag computed one cycle earlier;
   - or avoid the core entirely: when a freeze starts, have `cart.v`/cpu_wrapper request
     a D-cache line invalidate (or a full CPUSHA-like flush) of the vector line before
     raising IPL 7, and keep only the island part (cheap, outside the core);
   - or shorten the core's own critical path (ALU flags -> branch -> fetch PC), which would
     help the 68040 in general.
3. Build on the Fedora host (`~/aexp-work/remote/README.md`), test on the board: freeze at
   the KS screen, after Workbench, after Workbench + reset, and leaving HRTmon (`x`) back
   into Workbench.
4. Still untested on the 68040 even if the freeze works: HRTmon's own cache handling while
   frozen, exiting back to the program, the MMU set up by `68040.library`.
5. Remove the 68040 exclusion in `main_cart_req` (`CORE/vhdl/mega65.vhd`) and the
   sentence in `README.md` (Freezer cartridges).
