fn discardSections(patterns: []const []const u8) void {
    script.begin("\nSECTIONS", .{});
    script.begin("/DISCARD/ :", .{});
    for (patterns) |p| {
        script.line("*({s})", .{p});
    }
    script.end("", .{});
    script.end("", .{});
}

fn link(builder: *std.build.Builder, comptime model: type) void {
    fs.cwd().makeDir(generated_path1) catch |_| {};
    fs.cwd().makeDir(generated_path) catch |_| {};
    prepare_memory = IndentedStream.open(prepare_memory_file_name);
    script = IndentedStream.open(script_file_name);
    prepare_memory.line("// {s} - do not edit - generated by build.zig", .{prepare_memory_file_name});
    prepare_memory.begin("\npub fn prepareMemory() void", .{});
    script.line("# {s} - do not edit - generated by build.zig", .{script_file_name});
    inline for (model.memories) |memory| {
        linkMemory(memory);
    }
    script.line("\n# .ARM.exidx must be discarded until \"Provide -fno-unwind-tables\" is resolved https://github.com/ziglang/zig/issues/5464", .{});
    discardSections(&[_][]const u8{".ARM.exidx"});
    prepare_memory.end("", .{});
    prepare_memory.line("\nconst std = @import(\"std\");", .{});
    prepare_memory.close();
    script.close();
}

fn stepType(comptime some_model: type) type {
    const SomeStep = struct {
        builder: *std.build.Builder = undefined,
        step: std.build.Step = undefined,
        const model = some_model;
        pub fn make(step: *std.build.Step) anyerror!void {
            link(@fieldParentPtr(@This(), "step", step).builder, model);
        }
    };
    return SomeStep;
}

pub fn addGenerateLinkerFilesStep(builder: *std.build.Builder, comptime model: type) *stepType(model) {
    const t = stepType(model);
    var allocated = builder.allocator.create(t) catch unreachable;
    allocated.*.step = std.build.Step.init(.Custom, @typeName(t), builder.allocator, t.make);
    allocated.*.builder = builder;
    return allocated;
}

pub fn linkMemory(comptime memory: Memory) void {
    current_memory_name = memory.name;
    script.begin("\nMEMORY", .{});
    script.line("{s} : ORIGIN = 0x{x}, LENGTH = 0x{x}", .{ memory.name, memory.start, memory.size });
    script.end("", .{});
    script.begin("\nSECTIONS", .{});
    inline for (memory.sections) |section| {
        linkSection(section);
    }
    script.end("", .{});
}

pub fn linkSection(comptime section: OutputSection) void {
    var preparation_option_processed: bool = false;
    if (section.prepare_by_copying_from) |mem| {
        assert(!preparation_option_processed);
        preparation_option_processed = true;
        script.begin(".determine_load_start_for_{s} :", .{section.name});
        script.line("__{s}_load_start = .;", .{section.name});
        script.end(" > {s}", .{mem.name});
        script.begin(".{s} : AT(__{s}_load_start)", .{ section.name, section.name });
        script.line("__{s}_start = .;", .{section.name});
        prepare_memory.begin("_ = {s}:", .{section.name});
        prepare_memory.begin("const e = struct", .{});
        prepare_memory.line("extern var __{s}_start: u8;", .{section.name});
        prepare_memory.line("extern var __{s}_end: u8;", .{section.name});
        prepare_memory.line("extern var __{s}_load_start: u8;", .{section.name});
        prepare_memory.end(";", .{});
        prepare_memory.line("const start = &e.__{s}_start;", .{section.name});
        prepare_memory.line("const end = &e.__{s}_end;", .{section.name});
        prepare_memory.line("const slice = @ptrCast([*]u8, start)[0 .. @ptrToInt(end) - @ptrToInt(start)];", .{});
        prepare_memory.line("const load_start = &e.__{s}_load_start;", .{section.name});
        prepare_memory.line("const loaded_slice = @ptrCast([*]u8, load_start)[0..slice.len];", .{});
        prepare_memory.line("std.mem.copy(u8, slice, loaded_slice);", .{});
        prepare_memory.line("break :{s} 0;", .{section.name});
        prepare_memory.end(";", .{});
    }
    if (section.prepare_by_setting_to_zero) {
        assert(!preparation_option_processed);
        preparation_option_processed = true;
        script.begin(".{s} (NOLOAD) :", .{section.name});
        script.line("__{s}_start = .;", .{section.name});
        prepare_memory.begin("_ = {s}:", .{section.name});
        prepare_memory.begin("const e = struct", .{});
        prepare_memory.line("extern var __{s}_start: u8;", .{section.name});
        prepare_memory.line("extern var __{s}_end: u8;", .{section.name});
        prepare_memory.end(";", .{});
        prepare_memory.line("const start = &e.__{s}_start;", .{section.name});
        prepare_memory.line("const end = &e.__{s}_end;", .{section.name});
        prepare_memory.line("const slice = @ptrCast([*]u8, start)[0 .. @ptrToInt(end) - @ptrToInt(start)];", .{});
        prepare_memory.line("std.mem.set(u8, slice, 0);", .{});
        prepare_memory.line("break :{s} 0;", .{section.name});
        prepare_memory.end(";", .{});
    } else {
        script.begin(".{s} :", .{section.name});
    }
    inline for (section.input.names) |pattern| {
        if (section.start_symbol) {
            script.line("_start = .;", .{});
        }
        if (section.keep) {
            script.line("KEEP(*({s}))", .{pattern});
        } else {
            script.line("*({s})", .{pattern});
        }
    }
    if (section.prepare_by_setting_to_zero or section.prepare_by_copying_from != null) {
        script.line("__{s}_end = .;", .{section.name});
    }
    script.end(" > {s}", .{current_memory_name});
}

const IndentedStream = struct {
    pub fn begin(self: *IndentedStream, comptime format: []const u8, args: anytype) void {
        self.indent();
        self.out.print(format, args) catch unreachable;
        self.writeAll(" {\n");
        self.indent_depth += 1;
    }
    pub fn close(self: *IndentedStream) void {
        self.file.close();
    }
    pub fn end(self: *IndentedStream, comptime format: []const u8, args: anytype) void {
        self.indent_depth -= 1;
        self.indent();
        self.writeAll("}");
        self.out.print(format, args) catch unreachable;
        self.writeAll("\n");
    }
    fn indent(self: *IndentedStream) void {
        var i: u32 = 0;
        while (i < self.indent_depth) : (i += 1) {
            self.writeAll("    ");
        }
    }
    pub fn line(self: *IndentedStream, comptime format: []const u8, args: anytype) void {
        self.indent();
        self.out.print(format, args) catch unreachable;
        self.writeAll("\n");
    }
    pub fn open(file_name: []const u8) IndentedStream {
        var self: IndentedStream = undefined;
        self.indent_depth = 0;
        self.file = fs.cwd().createFile(file_name, fs.File.CreateFlags{}) catch unreachable;
        self.out = self.file.writer();
        return self;
    }
    fn writeAll(self: *IndentedStream, bytes: []const u8) void {
        self.file.writeAll(bytes) catch unreachable;
    }
    file: fs.File,
    indent_depth: u32,
    in_buffer: [200]u8,
    out: std.io.Writer(fs.File, std.os.WriteError, fs.File.write),
};

const assert = std.debug.assert;
const fs = std.fs;
const prepare_memory_file_name = generated_path ++ "generated_prepare_memory.zig";
const std = @import("std");
pub const generated_path = generated_path1 ++ generated_path2;
pub const generated_path1 = "generated/";
pub const generated_path2 = "generated_linker_files/";
pub const script_file_name = generated_path ++ "generated_linker_script.ld";
pub const Memory = struct {
    name: []const u8,
    size: u32,
    start: u32,
    sections: []const OutputSection,
};
pub const InputSections = struct {
    names: []const []const u8,
};
pub const OutputSection = struct {
    input: InputSections,
    name: []const u8,
    keep: bool = false,
    prepare_by_copying_from: ?Memory = null,
    prepare_by_setting_to_zero: bool = false,
    start_symbol: bool = false,
};
var current_memory_name: []const u8 = undefined;
var prepare_memory: IndentedStream = undefined;
var script: IndentedStream = undefined;
