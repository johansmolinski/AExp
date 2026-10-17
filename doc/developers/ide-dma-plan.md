# IDE DMA: plan (2026-10-17, branch `ide-dma`, not implemented)

Goal: the IDE board moves sector data between its rings and Amiga Fast RAM itself, so no CPU
copies words through the data register. Today (build main-ids-a, SysInfo): lide.device on the
68040 9.5-10.5 MB/s through the IDE data stream, the 68020 ~5 MB/s, the 68000 far less, and
every CPU is busy for the whole transfer. With DMA the card is the limit for every CPU
(4-bit SD at 25 MHz: 12.5 MB/s raw) and the CPU is free; native SD at 50 MHz would follow as
a separate step (25 MB/s raw).

## What stays as it is

- The ATA protocol. The driver still writes the task file, issues READ/WRITE (MULTIPLE),
  waits for DRQ. DMA replaces only the data loop: "copy multipleCount x 256 words" becomes
  "tell the board where they go, wait until it has moved them". The board's DRQ/BSY/ptr
  logic, the sector engine, the firmware ATA server and the IDE data stream are untouched;
  the DMA unit is one more consumer (read) / producer (write) of the ring, beside the CPU.
- Gayle mode (the Kickstart's scsi.device in ROM cannot use it) and every driver that does
  not know the DMA registers: PIO as today.

## Hardware

1. **DMA unit in `ide_board.vhd` (core clock).** New board registers (RIPPLE window, free
   offsets beside the task file, exact layout when implementing):
   - `DMA_ADDR` (32 bits, two words): the Amiga address of the buffer, long-aligned.
   - `DMA_CTRL` write: sector count (1..256) + direction; starts the transfer.
   - `DMA_STAT` read: busy, done, error (address outside DMA-able RAM, ATA error, abort).
   - `DMA_ID` read: a magic value + version, so the driver can tell a DMA-capable board from
     a plain RIPPLE (and from an older Megamiga).

   Read direction: for each sector, wait until DRQ and the ring holds it (the same condition
   the CPU's data reads use), then stream its 256 words out of the ring as 128 longs, and
   advance `ptr` exactly as 256 data reads would (end of sector, end of block, end of command
   follow from there - the existing code). Write direction: fill the write ring from SDRAM,
   as 256 data writes would. The CPU must not touch the data register while DMA runs (the
   driver's contract; the board ignores data accesses then and flags them).
2. **SDRAM port.** One long (two 16-bit WRITEs into the open row) per 7 MHz slot is what the
   68040's `fp_*` port does today: 28 MB/s peak, shared with the CPU and below the chipset's
   priority - enough for 25 MHz SD, marginal for 50 MHz. Plan: a new requester in
   `sdram_ctrl.v` modelled on the `fp_*` write path (address `[24:2]`, 32 bits, byte enables
   all set, toggle handshake), plus a long read for the write direction. Burst writes (4 longs
   per slot) only if 50 MHz needs them. The `flp*` port is not an option: one word per slot
   and only bank 0's upper half.
3. **Address translation.** The board accepts Z2 Fast RAM ($200000-$9FFFFF -> bank 1) and the
   Z3 board (its autoconfig base from cpu_wrapper -> banks 2/3; the 48 MB plan adds Z3B). The
   same decode as `cpu_wrapper.v`'s `ramaddr`, exported to the board. Anything else (Chip RAM,
   Slow RAM, RTG, ROM) -> error, and the driver falls back to PIO for that request.
4. **Coherency.**
   - 68040: its caches live in the core; the driver calls `CachePreDMA`/`CachePostDMA`
     (68040.library flushes/invalidates). To check: whether the island keeps a line or
     prefetch buffer of its own that could serve stale data after a DMA write.
   - TG68K: `cpu_cache_new` in sdram_ctrl snoops only chipset write slots today; DMA write
     slots must snoop it the same way (or invalidate the line).
   - fx68k: no cache.
5. **Clock domains.** The ring's CPU port, `ptr` and DRQ are in the core clock; the DMA unit
   sits there too. sdram_ctrl runs at 113.5 MHz with toggle handshakes, like `fp_*`.

## Driver (our lide.device fork, `~/aexp-work/lide-build`)

- At unit init: read `DMA_ID`; if present, set a `dma` flag on the board.
- `ata_read` (ata.c:457): after `ata_wait_drq`, when the buffer is long-aligned and the board
  has DMA: `CachePreDMA` (first block of the request), write `DMA_ADDR` + count
  (= the sectors until the next DRQ wait: multipleCount, or what is left), poll `DMA_STAT`
  until done (later: the board IRQ), `buffer += n * 512`. After the request `CachePostDMA`.
  On a DMA error: PIO for the rest of the request (and remember a buffer range that failed?
  Not needed: the check is per request and cheap).
- `ata_write` (ata.c:546) the same way in the other direction.
- Unaligned buffers: PIO as now.
- The built ROM must stay RIPPLE-compatible: on a board without `DMA_ID` nothing changes.

## Tests

- VHDL: `~/aexp-work/ideng` grows a DMA mode (an SDRAM-port model checking every long against
  the sector pattern, both directions, DRQ blocks of 1/16/128 sectors, a bad address, a
  command error in the middle of a block).
- e2e: `~/aexp-work/cpu060/e2e040` (TG68K and 68040) with a DMA variant of `prog_lide.S`
  (and a write test), the real `sdram_ctrl`, the snoop checked by reading the buffer back
  through the TG68K's cache.
- Hardware: SysInfo with the patched lide.rom on 68000/68020/68040, a copy test of a large
  file (checksum), and floppy + hard disk at once.

## Steps

1. sdram_ctrl DMA port + its testbench (both directions, snoop).
2. DMA unit in ide_board + registers + address decode; ideng DMA mode.
3. e2e with prog_lide DMA variant; build.
4. lide.device DMA path; hardware test.
5. Later: native SD at 50 MHz (CMD6 high speed, `sdhost.vhd` clocking), burst writes if
   needed.
