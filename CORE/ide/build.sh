#!/bin/sh
# Megamiga: build C:DMATest (the IDE DMA test, DMATest.c) and CacheTime (CacheTime.c) with vbcc 0.9h and the NDK 3.2
# (like CORE/share/build.sh: VBCC = the vbcc installation, NDK = the unpacked NDK 3.2).
set -e
cd "$(dirname "$0")"
: "${VBCC:?set VBCC to the vbcc installation}"
: "${NDK:?set NDK to the unpacked NDK 3.2}"
PATH="$VBCC/bin:$PATH"
export VBCC
vc +aos68k DMATest.c -O2 -I"$NDK/Include_H" -o DMATest
vc +aos68k CacheTime.c -O2 -I"$NDK/Include_H" -o CacheTime
ls -l DMATest CacheTime
