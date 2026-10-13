#!/bin/sh
# Megamiga: build L:MegamigaFS (the shared folder handler) with vbcc 0.9h and the NDK 3.2
# (like CORE/eth/build.sh: VBCC = the vbcc installation, NDK = the unpacked NDK 3.2).
# A BCPL-style module, as a314fs builds it: everything in one section, bcpl_start.asm in
# front (the startup packet comes in D1), bcpl_end.asm behind (the global vector), and the
# module length patched into its first long word.
set -e
cd "$(dirname "$0")"
: "${VBCC:?set VBCC to the vbcc installation}"
: "${NDK:?set NDK to the unpacked NDK 3.2}"
PATH="$VBCC/bin:$PATH"
export VBCC
T=$(mktemp -d)
vc +aos68k -c99 -O2 -S -I"$NDK/Include_H" MegamigaFS.c -o "$T/MegamigaFS.asm"
sed -i 's/^\([ \t]*\)section/\1;section/' "$T/MegamigaFS.asm"
for f in bcpl_start.asm "$T/MegamigaFS.asm" bcpl_end.asm; do
    vc +aos68k -c "$f" -o "$T/$(basename "$f" .asm).o"
done
# -Rstd: plain HUNK_RELOC32, which the LoadSeg of Kickstart 1.3 reads, too
vlink -bamigahunk -Bstatic -Rstd -s -nostdlib -o MegamigaFS "$T/bcpl_start.o" "$T/MegamigaFS.o" "$T/bcpl_end.o"
python3 -c "
f = open('MegamigaFS', 'r+b'); f.seek(0x1c); b = f.read(4); f.seek(0x20); f.write(b)"
rm -rf "$T"
# dummy.device: Mount wants a device for a FileSystem entry (moveq #1,d0; rts, as MiSTer's)
python3 -c "
import struct
open('dummy.device', 'wb').write(struct.pack('>7L', 0x3F3, 0, 1, 0, 0, 1, 0x3E9) +
    struct.pack('>L', 1) + bytes.fromhex('70014e75') + struct.pack('>L', 0x3F2))"
# ShareInfo: the firmware status and event counters (diagnostics)
vc +aos68k ShareInfo.c -O2 -I"$NDK/Include_H" -o ShareInfo
ls -l MegamigaFS dummy.device ShareInfo
