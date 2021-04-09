pub const memory = struct {
    pub const flash = struct {
        pub const size = 256 * 1024;
        pub const start = 0;
    };
    pub const ram = struct {
        pub const size = 16 * 1024;
        pub const start = 0x20000000;
        pub const stack_bottom = start + size;
        extern var _ram_bss_start: u8;
        extern var _ram_bss_end: u8;
        extern var _ram_data_start: u8;
        extern var _ram_data_end: u8;
        extern var _ram_data_initial_values: u8;
        pub fn prepare() void {
            const ram_bss = asSlice(&_ram_bss_start, &_ram_data_end);
            std.mem.set(u8, ram_bss, 0);
            const ram_data = asSlice(&_ram_data_start, &_ram_data_end);
            std.mem.copy(u8, ram_data, @ptrCast([*]u8, &_ram_data_initial_values)[0..ram_data.len]);
        }
        fn asSlice(start_ptr: *u8, end_ptr: *u8) []u8 {
            return @ptrCast([*]u8, start_ptr)[0 .. @ptrToInt(end_ptr) - @ptrToInt(start_ptr)];
        }
    };
};
pub const number_of_peripherals = 32;
pub const options = struct {
    pub const low_frequency_crystal = false;
    pub const systick_timer = false;
    pub const vector_table_relocation_register = false;
};
pub const qemu = struct {
    pub const machine = "microbit";
};
pub const target = std.zig.CrossTarget{
    .cpu_arch = .thumb,
    .os_tag = .freestanding,
    .abi = .none,
    .cpu_model = std.zig.CrossTarget.CpuModel{ .explicit = &std.Target.arm.cpu.cortex_m0 },
};

const std = @import("std");
