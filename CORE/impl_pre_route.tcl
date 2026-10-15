# route_design TCL.PRE hook of impl_1 (set by build_bitstream.tcl): back to the
# real constraints before routing, see impl_margin.tcl.
source [file join $::env(IMPL_TCL_DIR) impl_margin.tcl]
impl_margin off
