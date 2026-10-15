# HRTmon cartridge image

Megamiga's built-in HRTmon freezer cartridge ("Cart: HRTmon" in each profile of
Profile Settings). The core keeps the image in a block RAM and copies it to the
cartridge bank (`$A10000`) at every cold boot; Minimig's `cart.v` provides the
freeze button, the NMI vector override (entry `$A1000C`) and the custom register
mirror at `$A9F000`.

| File            | What                                                        |
|-----------------|-------------------------------------------------------------|
| `hrtmon238.lha` | HRTmon 2.38, unmodified, from http://www.whdload.de/whdload/Tools/hrtmon238.lha |
| `hrtmon.rom`    | the cartridge build of it (199,540 bytes, 99,770 words)      |
| `hrtmon_0..3.hex` | the same, one 16-bit word per line, in four 32K-word parts (`HRTMON_ROM_PREFIX` in `CORE/vhdl/globals.vhd`; Vivado's file loader stops at 65536 lines) |
| `build.sh`      | rebuilds both from the archive (vasm + NDK 3.2 `Include_I` + 7z) |

HRTmon is by Alain Malek (Hornet of Alcatraz), later maintained by Bert Jahn and
others. Its sources are licensed under the GNU GPL, version 2 or (at your option)
any later version (see the headers in `src/` of the archive), so the image may ship
with the GPL v3 core; the archive is kept here as its corresponding source.

`build.sh` selects the same cartridge build WinUAE and MiSTer use (`UAE = 1`:
`ORG $A10000`, `CARTRIDGE = 1`: no AmigaDOS hunks) and comments out one line that
NDK 3.2 already defines; nothing else is changed. It assembles with `-opt-a-`: vasm's
absolute -> PC-relative optimisation (on because the source selects MC68030) made
instructions only a 68020+ can execute, so the 68000 crashed in HRTmon's init (the
prebuilt `HRTmon.data` of the archive has the same flaw). The build is reproducible:
`sha256sum hrtmon.rom` =
`51d8592a0e05c670446d4fe7e9c2289ab85786aa51a3cce98e5e758aada7ef35`.

If the image size changes, `C_HRTMON_WORDS` in `globals.vhd` must be the new word
count (`build.sh` prints it).
