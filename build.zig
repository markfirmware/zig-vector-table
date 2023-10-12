// qemu working, real working, emit asm, symbol table, readme

pub fn build(b: *std.build.Builder) !void {
    const display_option = b.option(bool, "display", "graphics display for qemu") orelse false;
    const build_exe = b.addExecutable(.{ .name = "main", .optimize = b.standardOptimizeOption(.{}), .root_source_file = .{ .path = "main.zig" }, .target = model.target });
    _ = build_exe_details: {
        //        build_exe.emit_asm = .emit;
        build_exe.setLinkerScriptPath(std.build.FileSource.relative("linker_script.ld"));
        build_exe.link_function_sections = true;
        break :build_exe_details 0;
    };
    const format_source = b.addFmt(.{ .paths = &[_][]const u8{ "build.zig", "main.zig" } });
    const install_raw = b.addInstallArtifact(build_exe, .{ .dest_sub_path = "main.img" });
    const make_hex_file = addCustomStep(b, MakeHexFileStep{ .input_name = "zig-out/bin/main.img", .output_name = "main.hex" });
    const run_qemu = b.addSystemCommand(&[_][]const u8{
        "qemu-system-arm",
        "-kernel",
        "zig-out/bin/main.img",
        "-M",
        model.qemu.machine,
        "-serial",
        "stdio",
        "-display",
        if (display_option) "gtk" else "none",
    });

    _ = declare_dependencies: {
        build_exe.step.dependOn(&format_source.step);
        install_raw.step.dependOn(&build_exe.step);
        make_hex_file.step.dependOn(&install_raw.step);
        run_qemu.step.dependOn(&install_raw.step);
        break :declare_dependencies 0;
    };

    _ = declare_command_line_steps: {
        b.step("hex", "make hex file to copy to device").dependOn(&make_hex_file.step);
        b.step("qemu", "run in qemu").dependOn(&run_qemu.step);
        b.default_step.dependOn(&build_exe.step);
        break :declare_command_line_steps 0;
    };
}

const MakeHexFileStep = struct {
    step: std.build.Step = undefined,
    input_name: []const u8,
    output_name: []const u8,
    pub fn make(step: *std.build.Step, _: *std.Progress.Node) anyerror!void {
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
                    var two: [2]u8 = undefined;
                    two[0] = @truncate(offset >> 24);
                    two[1] = @truncate(offset >> 16);
                    try writeHexRecord(hex, 0, 0x04, &two);
                }
                const i = @min(hex_record_len, n - offset);
                try writeHexRecord(hex, offset % 0x10000, 0x00, read_buf[offset .. offset + i]);
                offset += i;
            }
        }
        try writeHexRecord(hex, 0, 0x01, &[_]u8{});
    }
    fn writeHexRecord(file: fs.File, offset: usize, code: u8, bytes: []u8) !void {
        var record_buf: [1 + 2 + 1 + hex_record_len + 1]u8 = undefined;
        var record: []u8 = record_buf[0 .. 1 + 2 + 1 + bytes.len + 1];
        record[0] = @truncate(bytes.len);
        record[1] = @truncate(offset >> 8);
        record[2] = @truncate(offset >> 0);
        record[3] = code;
        for (0.., bytes) |i, b| {
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
    var options: std.build.Step.StepOptions = undefined;
    options.id = .custom;
    options.name = @typeName(@TypeOf(customStep));
    options.owner = self;
    options.makeFn = @TypeOf(customStep).make;
    options.max_rss = 100 * 1024 * 1024;
    allocated.*.step = std.build.Step.init(options);
    return allocated;
}

const fs = std.fs;
const model = @import("system_model.zig");
const std = @import("std");
