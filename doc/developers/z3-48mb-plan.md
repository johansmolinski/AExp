# Zorro III RAM 16 MB -> 48 MB: design survey (2026-10-17, not implemented)

With `floppy-direct` nothing uses the upper column halves of the SDRAM (column bit 9 = 1) any
more: bank 0's was the floppy area, banks 1..3 were always free. Four halves = 32 MB. Plan:
keep the 16 MB board (Z3A, lower halves of banks 2/3) and add a 32 MB Zorro III board (Z3B)
built from the four upper halves. AutoConfig sizes are powers of two, so two boards.
Line numbers are those of the `floppy-direct` worktree (2026-10-17); "rtl/" =
`CORE/Minimig_MiSTerMEGA65/rtl/`.

No change needed: `cpu_cache_new` (tag = cpu_adr[28:11], 28-bit ports already; chipset snoops
carry bit 25 = 0 and never match Z3B), the 68020 cache decisions (no address windows; caches
every `ramsel` access), refresh (AUTO REFRESH covers all columns), SDRAM timing (every slot is
ACTIVATE + READ/WRITE with auto-precharge), HyperRAM (RTG VRAM: `sel_rtg` -> `ramaddr[26]`).

## 1. SDRAM word address + 1 bit (bit 25 = column bit 9)

- `rtl/sdram_ctrl.v`: `cpuAddr [24:1]` -> `[25:1]` (l.67), `fpAddr [24:2]` -> `[25:2]`
  (l.105), `writeAddr` (l.227); `casaddr[9] <= writeAddr[25]` (CPU write, l.433),
  `<= cpuAddr[25]` (cache read, l.477), `<= fpAddr[25]` (FP branch l.442-473). l.400 defaults
  bit 9 to 0; the FP second-write (l.513) already reuses `casaddr[9]`. `chipAddr` stays 24 bit.
  Remove the floppy branch (l.418-430, `casaddr[9] <= 1`): it would alias Z3B's first 8 MB.
- `vhdl/amiga_sdram.vhd`: l.77/93/184/203 widen (straight pass-through), header comment l.13-23.
- `vhdl/main.vhd`: ports l.156/173/584 widen; mapping l.885-890 with `ramaddr[25]` as the Z3B
  flag: Z2 `"001" & r(22:1)`, Z3A `"01" & r(23:1)`, Z3B `'1' & r(24:1)`, else `"000" & r(22:1)`.
- `vhdl/mega65.vhd`: `main_fram_addr` (l.393), `main_fp_addr` (l.349); other users take low
  slices only.

## 2. Second Zorro III board in `rtl/cpu_wrapper.v`

- Today: `sel_z3ram16` (l.271) into `sel_zram` (l.273); `z3_configured`/`z3_base[7:0]`
  (l.382-383), `ac_z3` (l.1026); autoconfig data l.1057-1071 (Z3, memlist, ext. size code 000 =
  16 MB, product 0x10, manufacturer 0x139C, serial 2); base write reg 0x44 (l.1224-1233);
  reset/latch l.1190 `ac_z3 <= z3ena & cpucfg[1]`; `ramaddr` l.349-358.
- Add: `ac_z3b`, `z3b_configured`, `z3b_base[6:0]` (A31..A25), declared ABOVE the CPU generate
  block (forward references inside it become undriven nets); size code `4'b0001` (32 MB),
  another serial; base write `z3b_base <= cpu_dout[15:9]`; `sel_z3ram32 =
  cpu_addr[31:25] == z3b_base && z3b_configured`; `ramaddr[28] |= sel_z3ram32`, `[25] =
  sel_z3ram32`, `[24:23] = sel_z3ram32 ? cpu_addr[24:23] : {0, sel_z3ram16 & cpu_addr[23]}`.
- Chain order = if/else priority in `autocfg_data` (l.1037-1153) and the write block
  (l.1215-1291): Z2 RAM -> Z3A -> RTG -> IDE -> eth. Put Z3B FIRST among the Z3 boards
  (largest first: $40000000 Z3B, $42000000 Z3A, $43000000 RTG, no holes) - to verify on
  Kickstart 3.1/3.2. No hard-coded RTG base anywhere (grep).
- Timing: the static base/configured registers feed the TG68K -> sdram_ctrl address path,
  which is multicycle-2 only from `*cpu_inst_p/*` (CORE.xdc l.151-152): add a false path /
  multicycle for `z3*_base`/`z3*_configured`.

## 3. AP68040

- `rtl/cpu_wrapper.v` CPU040=2 (l.753-757) passes only base0/ena0 to the island; CPU040=1
  (l.646-650) ties base1/ena1 off.
- `rtl/ap040_island.v`: ports l.84-86 (add `cache_z3_base1[6:0]`, `cache_z3_ena1`), the window
  sync l.117/121 (widen), pass on at l.264-265; decode l.377-382: add `e_z3b`, include it in
  `e_fp`; `fp_addr` l.436 three-way (Z3B `{1, e_addr[24:2]}`), output l.95 -> `[25:2]`.
  **Trap:** every line fill (`e_fill`) goes to the fp port; without `e_z3b` a Z3B fill reads
  Zorro II bank 1.
- `rtl/ap040/ap040_pipe_tg68k_compat.v`: `cache_z3_base1` is `[3:0]` comparing A31..A28 (a
  256 MB window, l.101): retype to `[6:0]` / `[31:25]` (base0 was narrowed for the same reason,
  l.95-97). Uses: store posting l.338-363, `cache_zwin` l.660-663 (cacheability + `fill_ok`),
  `cb_win` l.677-678, `w_z3b1` l.701/707, I-path `ia_win` l.714-719, D-path `da_win` l.763.

## 4. Menu

- Today: profile toggle `C_PROF_Z3 = 13` (mega65.vhd l.1078) -> `main_z3_ram` (l.1401, 020/040
  only) -> `main.vhd z3_ram_i` -> `cpu_wrapper z3ena`; also `amiga_cold_boot` (topology change).
- No free line: the profile separator at offset 14 (lines 37/55/73/91) can become "Zorro III
  RAM: 48 MB" (precedent: the 68040 and Gayle lines replaced separators), new groups, new
  `C_PROF_Z3_48 = 14` -> `main.vhd` -> `cpu_wrapper z3ena48` (gated with z3ena) ->
  `amiga_cold_boot`. Help text config.vhd l.105-107/577-579. Note: `main_z3_ram` is not gated by
  `C_HAS_SDRAM` (the Fast RAM bit is): gate both.

## 5. Tests to write

e2e with TG68K and AP68040 (the e2e020/e2e040 harnesses): autoconfig of both boards on the
Kickstart-like sequence, writes/reads in every half bank of both boards with distinct
patterns (an address bit that wraps would alias two halves silently), 040 line fills,
copyback and posted stores in Z3B, chipset snoop not matching Z3B.
