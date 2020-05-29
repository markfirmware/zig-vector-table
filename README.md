![CI](https://github.com/markfirmware/zig-vector-table/workflows/CI/badge.svg?branch=prep)[![Gitpod Ready-to-Code](https://img.shields.io/badge/Gitpod-ready--to--code-blue?logo=gitpod)](https://gitpod.io/#https://github.com/markfirmware/zig-vector-table)

It starts at the vector table which specifies the initial stack and the reset entry point. 
[main.zig](https://github.com/markfirmware/zig-vector-table/blob/master/main.zig#L1-L3)/[1][Section 2.3.4 Vector table, p37)](
https://static.docs.arm.com/dui0497/a/DUI0497A_cortex_m0_r0p0_generic_ug.pdf#page=37)

    export var vector_table linksection(".vector_table") = packed struct {
        initial_sp: u32 = model.stack_bottom,
        reset: EntryPoint = reset,

The reset function prepares memory (copies initial data from flash to ram and sets other data
to 0.) It then prepares the uart and timer and displays the up-time every second.
[main.zig](https://github.com/markfirmware/zig-vector-table/blob/master/main.zig#L9-L24)

    fn reset() callconv(.C) noreturn {
        @import("generated/generated_linker_files/generated_prepare_memory.zig").prepareMemory();
        Uart.prepare();
        Timers[0].prepare();
        Terminal.clearScreen();
        var t = TimeKeeper.ofMilliseconds(1000);
        var i: u32 = 0;
        while (true) {
            Uart.update();
            if (t.isFinishedThenReset()) {
                i += 1;
                Terminal.move(1, 1);
                log("uptime {}s", .{i});

The system is comprised of 256KB of flash and 16KB of ram memories: [system_model.zig](https://github.com/markfirmware/zig-vector-table/blob/master/system_model.zig#L3-L12)/[2][Memory Organization, p21](https://infocenter.nordicsemi.com/pdf/nRF51822_PS_v3.1.pdf#page=21)

### References
[1] [Cortex-M0 Devices Generic User Guide](https://static.docs.arm.com/dui0497/a/DUI0497A_cortex_m0_r0p0_generic_ug.pdf)

[2] [nRF51822 Product Specification](https://infocenter.nordicsemi.com/pdf/nRF51822_PS_v3.1.pdf)

[3] [nRF51 Series Reference Manual](https://infocenter.nordicsemi.com/pdf/nRF51_RM_v3.0.1.pdf)