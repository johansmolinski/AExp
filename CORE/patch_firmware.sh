#!/usr/bin/env bash
# Firmware-only changes without synthesis: patch the QNICE firmware of an existing
# build into its bitstream (a few minutes instead of a full build).
#
# Usage:
#   ./patch_firmware.sh save <dir> [board]    after a full build: keep what a patch needs
#   ./patch_firmware.sh patch <dir> [out.bit] assemble the current firmware and write a
#                                             bitstream of that build with it
#
#   save   copies the routed checkpoint, the bitstream and the firmware images the build
#          was made with (m2m-rom.rom, m2m-rodata.rom) from CORE-<board>.runs into <dir>
#          (board: R3..R6, default R6). The next synthesis overwrites the runs folder, so
#          save right after the build.
#   patch  runs m2m-rom/make_rom.sh, then Vivado opens the saved checkpoint, checks that
#          its firmware block RAMs hold exactly the saved images, puts the new images in
#          and writes the bitstream (default <dir>/patched.bit).
#
# What can be patched: everything in m2m-rom.asm (the QNICE ROM). The read-only data
# (m2m-rodata.asm: texts, filter tables) only in builds where it sits in block RAM; in
# older builds it is a LUT ROM, and a change there stops the patch (synthesize).
# What cannot: anything in the HDL - config.vhd (menu, help texts, CORE_VERSION) is
# hardware too - and a firmware change that needs a matching HDL change.
#
# Vivado must be on the PATH (source settings64.sh first).

set -eu
cd "$(dirname "$0")"

die() { echo "ERROR: $*" >&2; exit 1; }
usage() { sed -n '2,/^[^#]/ s/^# \{0,1\}//p' "$(basename "$0")"; exit 1; }
tohex() { python3 -c "
import sys
for l in open(sys.argv[1]):
    l = l.strip()
    if l: print('%04X' % int(l, 2))" "$1" > "$2"; }

[ $# -ge 2 ] || usage
cmd=$1; dir=$2

case "${cmd}" in
save)
    board=$(echo "${3:-R6}" | tr a-z A-Z); b=$(echo "${board}" | tr A-Z a-z)
    impl=CORE-${board}.runs/impl_1
    dcp=${impl}/mega65_${b}_postroute_physopt.dcp
    [ -f "${dcp}" ] || dcp=${impl}/mega65_${b}_routed.dcp
    [ -f "${dcp}" ] || die "no routed checkpoint in ${impl}"
    [ -f "${impl}/mega65_${b}.bit" ] || die "no bitstream in ${impl}"
    [ "${impl}/mega65_${b}.bit" -nt m2m-rom/m2m-rom.rom ] || \
        die "m2m-rom.rom is newer than the bitstream: the firmware changed after the build"
    mkdir -p "${dir}"
    cp "${dcp}" "${dir}/routed.dcp"
    cp "${impl}/mega65_${b}.bit" "${dir}/"
    cp m2m-rom/m2m-rom.rom m2m-rom/m2m-rodata.rom "${dir}/"
    echo "saved ${board} build to ${dir}"
    ;;
patch)
    out=${3:-${dir}/patched.bit}
    for f in routed.dcp m2m-rom.rom m2m-rodata.rom; do
        [ -f "${dir}/${f}" ] || die "${dir}/${f} missing - was the build saved with 'save'?"
    done
    command -v vivado >/dev/null 2>&1 || die "vivado is not on the PATH - source settings64.sh first"
    tmp=$(mktemp -d)
    # (no pipe: the assembler wrapper hands the listing to a clipboard tool that keeps it open)
    ( cd m2m-rom && ./make_rom.sh > "${tmp}/make_rom.log" 2>&1 ) || \
        { tail -20 "${tmp}/make_rom.log"; die "firmware does not assemble"; }
    grep "Shell ROM" "${tmp}/make_rom.log" || true
    tohex "${dir}/m2m-rom.rom" "${tmp}/rom_ref.hex"
    tohex m2m-rom/m2m-rom.rom "${tmp}/rom_new.hex"
    if cmp -s "${dir}/m2m-rodata.rom" m2m-rom/m2m-rodata.rom; then
        rref=-; rnew=-
    else
        tohex "${dir}/m2m-rodata.rom" "${tmp}/rod_ref.hex"; rref=${tmp}/rod_ref.hex
        tohex m2m-rom/m2m-rodata.rom "${tmp}/rod_new.hex"; rnew=${tmp}/rod_new.hex
    fi
    vivado -mode batch -nojournal -log "${tmp}/vivado.log" -source patch_firmware.tcl \
        -tclargs "${dir}/routed.dcp" "$(realpath -m "${out}")" "${tmp}/rom_ref.hex" \
        "${tmp}/rom_new.hex" "${rref}" "${rnew}" > /dev/null 2>&1 || true
    grep "^PATCH:\|^ERROR" "${tmp}/vivado.log" || true
    grep -q "^PATCH: OK" "${tmp}/vivado.log" || die "patch failed, see ${tmp}/vivado.log"
    rm -rf "${tmp}"
    ;;
*)  usage ;;
esac
