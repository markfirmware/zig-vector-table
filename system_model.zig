pub const compiler = struct {
    pub const bss: InputSections = .{ .names = &[_][]const u8{".bss"} };
    pub const data: InputSections = .{ .names = &[_][]const u8{".data"} };
    pub const rodata: InputSections = .{ .names = &[_][]const u8{ ".rodata", ".rodata.*" } };
    pub const text: InputSections = .{ .names = &[_][]const u8{".text.*"} };
    pub const vector_table: InputSections = .{ .names = &[_][]const u8{".vector_table"} };
};
pub const memories = [_]Memory{ flash, ram };
pub const flash = Memory{
    .name = "flash",
    .size = 256 * 1024,
    .start = 0,
    .sections = &[_]OutputSection{
        .{ .name = "system_exceptions_vector_table", .start_symbol = true, .keep = true, .input = compiler.vector_table },
        .{ .name = "cpu_instructions", .input = compiler.text },
        .{ .name = "read_only_data_kept_in_flash", .input = compiler.rodata },
    },
};
pub const ram = Memory{
    .name = "ram",
    .size = 16 * 1024,
    .start = 0x20000000,
    .sections = &[_]OutputSection{
        .{ .name = "data_loaded_in_flash_that_program_must_copy_to_ram", .prepare_by_copying_from = flash, .input = compiler.data },
        .{ .name = "data_that_program_must_set_to_zero", .prepare_by_setting_to_zero = true, .input = compiler.bss },
    },
};
pub const stack_bottom = ram.start + ram.size;
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

const InputSections = Linker.InputSections;
const Linker = @import("linker.zig");
const Memory = Linker.Memory;
const OutputSection = Linker.OutputSection;
const std = @import("std");
