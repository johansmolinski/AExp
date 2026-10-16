#!/bin/sh
# Megamiga: the PrismRTG test disk (FFS) - the PrismRTG release drawer with MEGAMIGA.driver added to
# its Drivers drawer (Install_PrismRTG copies every driver there to LIBS:Prism), the PrismCheck
# drawer (PrismTest, tmpltest, p96test, PrismBench, ...; built by PrismRTG's build.sh +
# tools/mkcheck.sh) with the driver in Tools/Drivers too, so PrismTest runs before anything is
# installed, and ReadMe.txt as Megamiga-ReadMe.
#
#     LHA=PrismRTG-1.1b9.lha CHECK=/path/to/PrismRTG/out/pkg-check sh CORE/prism/make_adf.sh [out.adf]
#
# Needs lha and amitools' xdftool.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
X=${XDFTOOL:-xdftool}
A=$(realpath -m "${1:-$HERE/Megamiga_PrismRTG.adf}")
: "${LHA:?set LHA to the PrismRTG release archive}"
: "${CHECK:?set CHECK to PrismRTG out/pkg-check}"
LHA=$(realpath "$LHA"); CHECK=$(realpath "$CHECK")
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
(cd "$T" && lha -xq "$LHA")
cp -r "$CHECK/PrismCheck" "$CHECK/PrismCheck.info" "$T/"
cp "$HERE/MEGAMIGA.driver" "$T/PrismRTG/Drivers/"
mkdir -p "$T/PrismCheck/Tools/Drivers"
cp "$HERE/MEGAMIGA.driver" "$T/PrismCheck/Tools/Drivers/"
cp "$HERE/ReadMe.txt" "$T/Megamiga-ReadMe"
set -- create + format "Megamiga PrismRTG" ffs
for d in $(cd "$T" && find . -mindepth 1 -type d | sed 's|^\./||' | sort); do
    set -- "$@" + makedir "$d"
done
for f in $(cd "$T" && find . -type f | sed 's|^\./||' | sort); do
    set -- "$@" + write "$T/$f" "$f"
done
rm -f "$A"
$X "$A" "$@"
$X "$A" list
$X "$A" info
