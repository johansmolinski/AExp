#!/bin/sh
# Megamiga: the RTG install disk - Megamiga.card (build.sh) plus MiSTer's monitor and Picasso96
# settings files from the Minimig submodule's MiSTer_RTG.lha, with the board renamed from "MiSTer"
# to "Megamiga" by rename_board.py. Needs lha, python3 and amitools' xdftool (pip install amitools).
set -e; cd "$(dirname "$0")"; X=${XDFTOOL:-xdftool}; A=${1:-Megamiga_RTG.adf}
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
(cd "$T" && lha -xq "$OLDPWD/../Minimig_MiSTerMEGA65/extra/rtg_driver/MiSTer_RTG.lha")
python3 rename_board.py "$T"
rm -f "$A"
$X "$A" create + format "Megamiga RTG" + makedir Libs + makedir Libs/Picasso96 + makedir Devs \
   + makedir Devs/Monitors \
   + write Megamiga.card Libs/Picasso96/Megamiga.card \
   + write "$T/Devs/Monitors/Megamiga" Devs/Monitors/Megamiga \
   + write "$T/Devs/Monitors/Megamiga.info" Devs/Monitors/Megamiga.info \
   + write "$T/Devs/Picasso96Settings" Devs/Picasso96Settings \
   + write ReadMe.txt ReadMe
$X "$A" list
