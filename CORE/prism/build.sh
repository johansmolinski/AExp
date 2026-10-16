#!/bin/sh
# Megamiga: build MEGAMIGA.driver, the PrismRTG board driver for the Megamiga RTG card.
#
#     PRISM=/path/to/PrismRTG sh CORE/prism/build.sh
#
# PRISM is a checkout of https://github.com/lainejones/PrismRTG (1.1 beta 8 or later: board
# ABI 3, module protocol 4); the driver is built with its tools/mkdriver.sh, which needs
# Bebbo's amiga-gcc (m68k-amigaos-gcc; /opt/amiga/bin is searched). Without a local
# toolchain: CONTAINER=podman (or docker) runs it in sacredbanana/amiga-compiler:m68k-amigaos.
# Output: CORE/prism/MEGAMIGA.driver.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
: "${PRISM:?set PRISM to a PrismRTG checkout}"
PRISM=$(cd "$PRISM" && pwd)
cp "$HERE/drv_megamiga.c" "$PRISM/src/drv_megamiga.c"
if [ -n "$CONTAINER" ]; then
    $CONTAINER run --rm -v "$PRISM:/work:z" -w /work docker.io/sacredbanana/amiga-compiler:m68k-amigaos \
        sh -c 'export PATH=/opt/m68k-amigaos/bin:$PATH; OUT=out/Drivers sh tools/mkdriver.sh MEGAMIGA src/drv_megamiga.c'
else
    (cd "$PRISM" && OUT=out/Drivers sh tools/mkdriver.sh MEGAMIGA src/drv_megamiga.c)
fi
cp "$PRISM/out/Drivers/MEGAMIGA.driver" "$HERE/MEGAMIGA.driver"
ls -l "$HERE/MEGAMIGA.driver"
