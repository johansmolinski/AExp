#!/usr/bin/env python3
"""rename_board.py <dir>: rename the Picasso96 board in MiSTer_RTG.lha's files from "MiSTer"
to "Megamiga" (Megamiga, October 2026): Devs/Monitors/MiSTer(.info) -> Devs/Monitors/Megamiga(.info)
with the icon's tool type BOARDTYPE=Megamiga (Picasso96 then loads LIBS:Picasso96/Megamiga.card),
and the board and mode names in Devs/Picasso96Settings ("Megamiga:640x480", ...). Every name in
the settings file sits in a fixed-size field, so the file keeps its layout and length."""
import os, struct, sys

OLD, NEW = b"MiSTer", b"Megamiga"
d = sys.argv[1]
mon = os.path.join(d, "Devs", "Monitors")

# the monitor (Picasso96's generic monitor program, unchanged) and its icon
os.rename(os.path.join(mon, "MiSTer"), os.path.join(mon, "Megamiga"))
icon = open(os.path.join(mon, "MiSTer.info"), "rb").read()
old_tt, new_tt = b"BOARDTYPE=" + OLD + b"\0", b"BOARDTYPE=" + NEW + b"\0"
i = icon.index(old_tt)
assert struct.unpack(">I", icon[i - 4:i])[0] == len(old_tt)   # a tool type: length, string
icon = icon[:i - 4] + struct.pack(">I", len(new_tt)) + new_tt + icon[i + len(old_tt):]
open(os.path.join(mon, "Megamiga.info"), "wb").write(icon)
os.remove(os.path.join(mon, "MiSTer.info"))

# the settings: an IFF FORM P96S; names in STHD (from byte 8), BDNM (32 bytes), RSHD (from byte 14)
p = os.path.join(d, "Devs", "Picasso96Settings")
b = bytearray(open(p, "rb").read())
assert b[:4] == b"FORM" and b[8:12] == b"P96S"
o, end, n_names = 12, 8 + struct.unpack(">I", b[4:8])[0], 0
while o < end:
    cid, size = bytes(b[o:o + 4]), struct.unpack(">I", b[o + 4:o + 8])[0]
    start = {b"STHD": 8, b"BDNM": 0, b"RSHD": 14}.get(cid)
    if start is not None:
        f0, f1 = o + 8 + start, o + 8 + size
        name = bytes(b[f0:f1]).split(b"\0")[0]
        assert name.startswith(OLD), name
        new = NEW + name[len(OLD):]
        assert len(new) < f1 - f0, new
        b[f0:f1] = new + b"\0" * (f1 - f0 - len(new))
        n_names += 1
    o += 8 + size + (size & 1)
open(p, "wb").write(b)
print("rename_board: monitor, icon and %d settings names -> %s" % (n_names, NEW.decode()))
