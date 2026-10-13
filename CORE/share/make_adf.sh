#!/bin/sh
# Megamiga: the shared folder disk - L:MegamigaFS, C/ShareInfo, dummy.device, the DOSDriver and the
# 1.3 MountList (build.sh first). Needs amitools' xdftool (pip install amitools).
set -e; cd "$(dirname "$0")"; X=${XDFTOOL:-xdftool}; A=${1:-Megamiga_Share.adf}
rm -f "$A"
$X "$A" create + format "Megamiga Share" + makedir C + makedir L + makedir Devs + makedir Devs/DOSDrivers \
   + write MegamigaFS L/MegamigaFS \
   + write ShareInfo C/ShareInfo \
   + write dummy.device Devs/dummy.device \
   + write SD Devs/DOSDrivers/SD \
   + write MountList Devs/MountList \
   + write ReadMe.txt ReadMe
$X "$A" list
