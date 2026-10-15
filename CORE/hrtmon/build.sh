#!/bin/bash
# build.sh: build the HRTmon cartridge image (hrtmon.rom) and the block RAM init file
# (hrtmon.hex) of the core from the unmodified HRTmon 2.38 source archive in this folder.
#
#   VASM=/path/to/vasmm68k_mot NDK_INCLUDE=/path/to/NDK3.2/Include_I ./build.sh
#
# HRTmon by Alain Malek (Hornet of Alcatraz), maintained by Bert Jahn and others,
# licensed under the GNU GPL version 2 or later; the archive comes from
# http://www.whdload.de/whdload/Tools/hrtmon238.lha (see README.md).
#
# Two settings in src/HRTmonV2.s select the cartridge build, the same image WinUAE uses
# (UAE = 1: ORG $A10000; CARTRIDGE = 1: no AmigaDOS hunks), and one line is commented out
# because NDK 3.2 already defines that symbol (with the same value). Needs vasm and 7z.
#
# -opt-a- keeps absolute addresses absolute. The source switches vasm to MC68030 (for its
# 68030/68040 routines), and vasm's default absolute -> PC-relative optimisation then also
# makes destinations PC-relative ("cmp.b #1,config_screen" -> "cmpi.b #1,(d16,PC)"), which
# only a 68020+ can execute: the 68000 took an illegal instruction in mon_setscreen at the
# first freeze (Guru 00000004). The prebuilt HRTmon.data of the 2.38 archive has the same
# problem. The cartridge has a fixed ORG, so absolute addressing costs only 800 bytes.
#
# Megamiga, October 2026. Licensed under the GPL v3.
set -euo pipefail
cd "$(dirname "$0")"
: "${VASM:?set VASM to vasmm68k_mot}" "${NDK_INCLUDE:?set NDK_INCLUDE to the NDK 3.2 Include_I folder}"

W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
7z x -y -o"$W" hrtmon238.lha >/dev/null
S="$W/hrtmon"
sed -i 's/^UAE = 0/UAE = 1/; s/^CARTRIDGE = 0/CARTRIDGE = 1/' "$S/src/HRTmonV2.s"
sed -i 's/^ BITDEF AF,68060,7/; BITDEF AF,68060,7 (NDK 3.2 defines AFB_68060 = 7)/' "$S/src/HRTmonV2.s"
grep -a -q '^UAE = 1' "$S/src/HRTmonV2.s" && grep -a -q '^CARTRIDGE = 1' "$S/src/HRTmonV2.s"
printf '(13.10.2026)' > "$S/.date"          # the version date (the Makefile writes "date")
(cd "$S" && "$VASM" -I. -I"$NDK_INCLUDE" -ignore-mult-inc -nosym -quiet -m68010 -opt-a- -Fbin \
    -o "$W/hrtmon.rom" src/HRTmonV2.s)

cp "$W/hrtmon.rom" hrtmon.rom
# one 16-bit big-endian word per line in hex, the format of tdp_ram's ROM_FILE_HEX, in four
# parts of 32K words (hrtmon_0..3.hex): Vivado's file loader stops at 65536 lines
python3 -c "
d = open('hrtmon.rom', 'rb').read()
d += b'\0' * (len(d) & 1)
w = ['%02X%02X\n' % (d[i], d[i + 1]) for i in range(0, len(d), 2)]
assert len(w) <= 4 * 32768
for p in range(4):
    open('hrtmon_%d.hex' % p, 'w').write(''.join(w[p * 32768:(p + 1) * 32768]))
print('hrtmon.rom: %d bytes, %d words' % (len(d), len(w)))
"
md5sum hrtmon.rom
