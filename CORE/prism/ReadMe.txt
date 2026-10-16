Megamiga RTG - PrismRTG driver
==============================

MEGAMIGA.driver drives the Megamiga graphics card under PrismRTG
(https://github.com/lainejones/PrismRTG, GPL-3.0), an open-source RTG system
for AmigaOS 3.x that replaces Picasso96: its own cybergraphics.library and
Picasso96API.library, PRISM: screen modes. Built against PrismRTG 1.1 beta 9
(board ABI 3, module protocol 4: later PrismD releases keep loading it).

What it does: CLUT8, 16-bit (R5G6B5PC), 24-bit (B8G8R8) and 32-bit
(R8G8B8A8) screens from 320x200 up to 1920x1200 (as far as the 4 MB of board
memory goes: 1920x1080 at 8 bit only), oversized autoscroll screens, the
palette, the RTG/Amiga switch, and the card's blitter for fills, copies and
text (8/16/32-bit). Not there (the card has none): a hardware pointer (PrismD
draws it), vertical-blank sync, monitor power-saving.

Status (2026-10-16): works with the 68020; with the 68040 PrismD starts but
Prefs/ScreenMode quits at once and no PRISM: screen opens (Picasso96 with
Megamiga.card works there). Not released; see doc/developers/history.md,
"PrismRTG driver".

Requirements: a profile with the 68020 or 68040 (the card is a Zorro III
board then), Kickstart/Workbench 3.x, PrismRTG installed.

The disk (Megamiga_PrismRTG.adf, FFS):
  PrismRTG/     the PrismRTG 1.1 beta 9 release drawer, MEGAMIGA.driver
                added to its Drivers drawer
  PrismCheck/   PrismRTG's test kit, built from the same source; the driver
                is also in PrismCheck/Tools/Drivers, so PrismTest finds it
                without installing anything

1. First, without installing anything (Picasso96 may stay as it is; PrismTest
   borrows the board and hands it back). From a Shell:
     CD "Megamiga PrismRTG:PrismCheck/Tools"
     PrismTest BOARD=MEGAMIGA DEPTH=8     (then 16, 24, 32; WIDTH=800 HEIGHT=600)
     PrismTest BOARD=MEGAMIGA BLIT        (every blit compared with the CPU)
   The pattern: hue bars, a grey ramp, a checkerboard. Wrong colours = wrong
   format, a sheared picture = wrong pitch.
2. Install: run PrismRTG/Install_PrismRTG (it parks an existing Picasso96
   installation in SYS:Storage/Picasso96-parked; our card is not in its list
   yet: "Install anyway"). It copies MEGAMIGA.driver to LIBS:Prism. With the
   board on Auto, PrismD finds the card; or BOARD=MEGAMIGA in PrismPrefs
   ("Other"). Reboot and pick a PRISM: mode. Hold the left mouse button at
   boot to skip PrismD if something goes wrong.
3. With PrismD running:  Run >RAM:PrismD.log C:PrismD BOARD=MEGAMIGA LOG  and
   the PrismCheck tools on a PRISM: screen (tmpltest, p96test, vramcheck,
   PrismBench) - every line "0 wrong".

Build:  PRISM=/path/to/PrismRTG [CONTAINER=podman] sh CORE/prism/build.sh
Test:   PRISM=/path/to/PrismRTG [CONTAINER=podman] sh CORE/prism/test.sh
        (host fixture under vamos: fake registers + a model of rtg_blitter.vhd,
        3000 random blits compared with the CPU)
