![CI](https://github.com/markfirmware/zig-vector-table/workflows/CI/badge.svg?branch=prep)[![Gitpod Ready-to-Code](https://img.shields.io/badge/Gitpod-ready--to--code-blue?logo=gitpod)](https://gitpod.io/#https://github.com/markfirmware/zig-vector-table)

It starts at the vector table which specifies the initial stack and the reset entry point 
[code](https://github.com/markfirmware/zig-vector-table/blob/master/main.zig#L1-L3), [Section 2.3.4 Vector table](
https://static.docs.arm.com/dui0497/a/DUI0497A_cortex_m0_r0p0_generic_ug.pdf#page=37)

    export var vector_table linksection(".vector_table") = packed struct {
        initial_sp: u32 = model.stack_bottom,
        reset: EntryPoint = reset,
