#!/bin/sh
# Megamiga: run test_megamiga.c, the host fixture of the PrismRTG driver (fake registers + a model
# of rtg_blitter.vhd, every blit compared with the CPU), the way PrismRTG's tests/architecture.sh
# runs its own: built with amiga-gcc, run under vamos (pip install amitools).
#
#     PRISM=/path/to/PrismRTG [CONTAINER=podman] [VAMOS=vamos] sh CORE/prism/test.sh
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
: "${PRISM:?set PRISM to a PrismRTG checkout}"
PRISM=$(cd "$PRISM" && pwd)
VAMOS=${VAMOS:-$(command -v vamos || echo "$HOME/amitools-venv/bin/vamos")}
cp "$HERE/drv_megamiga.c" "$PRISM/src/drv_megamiga.c"
cp "$HERE/test_megamiga.c" "$PRISM/tests/megamiga.c"
mkdir -p "$PRISM/out/tests"
FLAGS="-O2 -ffunction-sections -fdata-sections -Wl,--gc-sections -m68020-60 -noixemul"
FLAGS="$FLAGS -Wall -Wextra -Wno-pointer-sign -Wno-missing-field-initializers -Wno-unused-parameter"
FLAGS="$FLAGS -Wno-sign-compare -fno-strict-aliasing -Isrc -Isrc/p96sdk"
BUILD="m68k-amigaos-gcc $FLAGS -o out/tests/megamiga tests/megamiga.c src/boardops.c"
if [ -n "$CONTAINER" ]; then
    $CONTAINER run --rm -v "$PRISM:/work:z" -w /work docker.io/sacredbanana/amiga-compiler:m68k-amigaos \
        sh -c "export PATH=/opt/m68k-amigaos/bin:\$PATH; $BUILD"
else
    (cd "$PRISM" && PATH=/opt/amiga/bin:$PATH && $BUILD)
fi
cd "$PRISM"
"$VAMOS" --vols-base-dir out/tests/volumes -C 68020 -s 128 -m 10240 out/tests/megamiga
