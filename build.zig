pub fn build(b: *std.build.Builder) !void {
    const display_option = b.option(bool, "display", "graphics display for qemu") orelse false;
    const build_exe = b.addExecutable("main", "main.zig");
    _ = buildExeDetails: {
        build_exe.emit_asm = true;
        build_exe.install();
        build_exe.setBuildMode(b.standardReleaseOptions());
        build_exe.setLinkerScriptPath("linker_script.ld");
        build_exe.setTarget(model.target);
        build_exe.link_function_sections = true;
        break :buildExeDetails 0;
    };
    const format_source = b.addFmt(&[_][]const u8{ "build.zig", "main.zig" });
    const install_raw = b.addInstallRaw(build_exe, "main.img");
    const make_hex_file = addCustomStep(b, MakeHexFileStep{ .input_name = "zig-cache/bin/main.img", .output_name = "main.hex" });
    const run_qemu = b.addSystemCommand(&[_][]const u8{
        "qemu-system-arm",
        "-kernel",
        "zig-cache/bin/main.img",
        "-M",
        model.qemu.machine,
        "-serial",
        "stdio",
        "-display",
        if (display_option) "gtk" else "none",
    });

    _ = declareDependencies: {
        build_exe.step.dependOn(&format_source.step);
        install_raw.step.dependOn(&build_exe.step);
        make_hex_file.step.dependOn(&install_raw.step);
        run_qemu.step.dependOn(&install_raw.step);
        break :declareDependencies 0;
    };

    _ = declareCommandLineSteps: {
        b.step("make-hex", "make hex file to copy to device").dependOn(&make_hex_file.step);
        b.step("qemu", "run in qemu").dependOn(&run_qemu.step);
        b.default_step.dependOn(&build_exe.step);
        break :declareCommandLineSteps 0;
    };
}

const MakeHexFileStep = struct {
    step: std.build.Step = undefined,
    input_name: []const u8,
    output_name: []const u8,
    pub fn make(step: *std.build.Step) anyerror!void {
        const self = @fieldParentPtr(MakeHexFileStep, "step", step);
        const cwd = fs.cwd();
        const image = try cwd.openFile(self.input_name, fs.File.OpenFlags{});
        defer image.close();
        const hex = try cwd.createFile(self.output_name, fs.File.CreateFlags{});
        defer hex.close();
        var offset: usize = 0;
        var read_buf: [model.memory.flash.size]u8 = undefined;
        while (true) {
            var n = try image.read(&read_buf);
            if (n == 0) {
                break;
            }
            while (offset < n) {
                if (offset % 0x10000 == 0) {
                    try writeHexRecord(hex, 0, 0x04, &[_]u8{ @truncate(u8, offset >> 24), @truncate(u8, offset >> 16) });
                }
                const i = std.math.min(hex_record_len, n - offset);
                try writeHexRecord(hex, offset % 0x10000, 0x00, read_buf[offset .. offset + i]);
                offset += i;
            }
        }
        try writeHexRecord(hex, 0, 0x01, &[_]u8{});
    }
    fn writeHexRecord(file: fs.File, offset: usize, code: u8, bytes: []u8) !void {
        var record_buf: [1 + 2 + 1 + hex_record_len + 1]u8 = undefined;
        var record: []u8 = record_buf[0 .. 1 + 2 + 1 + bytes.len + 1];
        record[0] = @truncate(u8, bytes.len);
        record[1] = @truncate(u8, offset >> 8);
        record[2] = @truncate(u8, offset >> 0);
        record[3] = code;
        for (bytes) |b, i| {
            record[4 + i] = b;
        }
        var checksum: u8 = 0;
        for (record[0 .. record.len - 1]) |b| {
            checksum = checksum -% b;
        }
        record[record.len - 1] = checksum;
        var line_buf: [1 + record_buf.len * 2 + 1]u8 = undefined;
        _ = try file.write(try std.fmt.bufPrint(&line_buf, ":{}\n", .{std.fmt.fmtSliceHexUpper(record)}));
    }
    const hex_record_len = 32;
};

pub fn addCustomStep(self: *std.build.Builder, customStep: anytype) *@TypeOf(customStep) {
    var allocated = self.allocator.create(@TypeOf(customStep)) catch unreachable;
    allocated.* = customStep;
    allocated.*.step = std.build.Step.init(.Custom, @typeName(@TypeOf(customStep)), self.allocator, @TypeOf(customStep).make);
    return allocated;
}

const fs = std.fs;
const model = @import("system_model.zig");
const std = @import("std");
