const std = @import("std");
const Linker = @import("linker.zig");
pub const flash = struct {
    pub const name = "flash";
    pub const size = 256 * 1024;
    pub const start = 0;
    pub fn linkSections() void {
        Linker.linkSections(.{ .keep = true }, &[_][]const u8{".vector_table*"});
        Linker.linkSections(.{}, &[_][]const u8{".text*"});
        Linker.linkSections(.{}, &[_][]const u8{".rodata*"});
    }
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
pub const ram = struct {
    pub const name = "ram";
    pub const size = 16 * 1024;
    pub const start = 0x20000000;
    pub fn linkSections() void {
        Linker.linkSections(.{ .name = "data", .prepare_by_copying_from = flash }, &[_][]const u8{".data*"});
        Linker.linkSections(.{ .name = "bss", .prepare_by_setting_to_zero = true }, &[_][]const u8{".bss*"});
    }
};
pub const stack_bottom = ram.start + ram.size;
pub const target = std.zig.CrossTarget{
    .cpu_arch = .thumb,
    .os_tag = .freestanding,
    .abi = .none,
    .cpu_model = std.zig.CrossTarget.CpuModel{ .explicit = &std.Target.arm.cpu.cortex_m0 },
};
pub fn linkModel() void {
    Linker.discardSections(&[_][]const u8{".ARM.exidx"});
    Linker.linkMemory(flash);
    Linker.linkMemory(ram);
}