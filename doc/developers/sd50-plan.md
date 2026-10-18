# SD card at 50 MHz (high speed mode) - plan

Branch `sd50` (from `ide-dma`, 2026-10-18). Goal: the native 4-bit SD bus at 50 MHz
(SD high speed mode, 25 MB/s raw) instead of 25 MHz (12.5 MB/s raw), so that the IDE DMA
(about 10 MB/s now, card-bound) and the floppy/SDCard: paths get the card's real limit.

## Why the controller needs a faster clock

`sdhost.vhd` (M2M exception 18) runs on the QNICE clock (50 MHz) and makes SD_CLK with a
register that toggles every `half` clocks: `half` = 1 is 25 MHz, its ceiling. The state
machine does one "step" per SD cycle, on the clock after the falling SD edge, and many
states rely on the clock between two steps (one-clock states like N_RD_NEXT, S_DISPATCH,
N_RD_RESP fit between two steps without losing one).

Chosen: **the controller process (`ctrl`) runs on 100 MHz**, the framework's HyperRAM clock
`hr_clk` (same MMCM as the QNICE clock, phase 0: the two domains are synchronous). All
`half` values double (init 126, 25 MHz = 2, 12.5 MHz = 4, 50 MHz = 1), `G_MS` = 100_000.
The bit-level behaviour stays exactly as it is in controller clocks, so SPI mode, the
init, the retries and every state stay unchanged.

Rejected: a step on every 50 MHz clock with SD_CLK from an ODDR (every one-clock state would
eat a step - a lost start bit); double-pumping only the data states (start-bit alignment
inside a step, clock rate switching at block boundaries).

## The two clock domains inside sdhost

* QNICE side (50 MHz, as now): `q_regs`, `q_buffer` (falling edge), `q_read`. The values
  `q_read` shows that the controller writes (busy, error, card type, mode bits, retries,
  `q_seen_*`) are copied into 50 MHz registers first, so the QNICE read path keeps its
  timing.
* Controller writes into the QNICE buffer (`cb_we`): held for two controller clocks, so the
  falling QNICE edge takes each byte exactly once (bytes come at most every 4 clocks).
* Engine port: the outputs are registered on the QNICE clock (one clock later than now);
  pulses (`e_done`, `e_blk`, `e_rd_we`) are held two controller clocks so the QNICE register
  takes them exactly once. Inputs are QNICE registers already (start is seen twice by the
  controller; `e_pend` takes it once).
* Write data: the engine's byte is valid from 6 controller clocks after the address changed
  until 5 clocks after the next change (output register + the clients' block RAM). At 50 MHz
  a byte goes out every 4 clocks: the engine address runs two bytes ahead (one ahead at
  25 MHz and in SPI mode, and for the QNICE buffer, whose latency is 2 clocks).

## High speed mode

After the 4-bit bus switch (ACMD6) and the 25 MHz test read:

1. CMD6 (SWITCH_FUNC) mode 1, function group 1 = 1 (high speed): R1, then a 64-byte status
   block on DAT0..3 with CRC16. Bits 379..376 = 1: switched. Anything else (no response,
   CRC error, function not supported): stay at 25 MHz, as today.
2. 8 clocks, then `half` = 1 (50 MHz).
3. The card now launches its outputs after the RISING SD edge (default mode: falling), up to
   14 ns later (t_ODLY), held at least 2.5 ns after the next rising edge. Plus the MEGA65's
   pad and board delays (unknown, a few ns each way). The input sample point is chosen by
   a calibration: each of the candidate points (5 ns apart: the controller's rising and
   falling edges) gets a few test reads of block 0 (CRC checked); the middle of the
   passing range is kept. None passes: back to default mode (re-init at 25 MHz).
4. Register 6 gets a bit for "50 MHz" and the chosen sample point (diagnostics, firmware
   unchanged).

A data CRC error at 50 MHz later: the existing retry chain gets one more step in front of
it (50 MHz -> 25 MHz native -> SPI 25 -> SPI 12.5).

## Tests

* `~/aexp-work/sdhost`: TB with a 100 MHz controller clock; the card model gets CMD6 and
  high speed timing (launch after the rising edge with a configurable output delay, a
  board delay each way) so the calibration can be swept; all existing scenarios at 25 MHz
  unchanged; new scenarios: 50 MHz reads/writes through the engine port and QNICE, a card
  without high speed, a delay that only some sample points survive, a CRC error at 50 MHz.
* `~/aexp-work/ideng` (the IDE engine through sdhost) and the adf_sd TB if they use sdhost.
* Mutants on the new parts.
* Hardware: SysInfo / DMATest, ShareInfo, an ADF from SD, both card slots.
