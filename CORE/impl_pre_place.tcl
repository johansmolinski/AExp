# place_design TCL.PRE hook of impl_1 (set by build_bitstream.tcl): reference
# checkpoint and placement margin, see impl_margin.tcl.
source [file join $::env(IMPL_TCL_DIR) impl_margin.tcl]
impl_reference
impl_margin on
