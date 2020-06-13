export var vector_table linksection(".vector_table") = packed struct {
    initial_sp: u32 = model.memory.stack_bottom,
    reset: EntryPoint = reset,
    system_exceptions: [14]EntryPoint = [1]EntryPoint{exception} ** 14,
    interrupts: [model.number_of_peripherals]EntryPoint = [1]EntryPoint{exception} ** model.number_of_peripherals,
    const EntryPoint = fn () callconv(.C) noreturn;
}{};

fn reset() callconv(.C) noreturn {
    @import("generated/generated_linker_files/generated_prepare_memory.zig").prepareMemory();
    Uart.prepare();
    Timers[0].prepare();
    Terminal.reset();
    Terminal.clearScreen();
    Terminal.move(1, 1);
    log("https://github.com/markfirmware/zig-vector-table is running on a microbit!", .{});
    var status_line_number: u32 = 2;
    if (Ficr.isQemu()) {
        Terminal.attribute(35);
        log("actually qemu -M microbit", .{});
        Terminal.attribute(0);
        status_line_number += 1;
    }
    var t = TimeKeeper.ofMilliseconds(1000);
    var i: u32 = 0;
    while (true) {
        Uart.update();
        if (t.isFinishedThenReset()) {
            i += 1;
            Terminal.move(status_line_number, 1);
            log("up and running for {} seconds!", .{i});
        }
    }
}

pub fn panic(message: []const u8, trace: ?*std.builtin.StackTrace) noreturn {
    panicf("panic(): {}", .{message});
}

fn exception() callconv(.C) noreturn {
    const ipsr_interrupt_program_status_register = asm ("mrs %[ipsr_interrupt_program_status_register], ipsr"
        : [ipsr_interrupt_program_status_register] "=r" (-> usize)
    );
    const isr_number = ipsr_interrupt_program_status_register & 0xff;
    panicf("arm exception ipsr.isr_number {}", .{isr_number});
}

const Ficr = struct {
    pub fn deviceId() u64 {
        return @as(u64, contents[0x64 / 4]) << 32 | contents[0x60 / 4];
    }
    pub fn isQemu() bool {
        return deviceId() == 0x1234567800000003;
    }
    pub const contents = @intToPtr(*[64]u32, 0x10000000);
};

const Gpio = struct {
    const p = Peripheral.at(0x50000000);
    pub const registers = struct {
        pub const out = p.typedRegistersWriteSetClear(0x504, 0x508, 0x50c, Pins);
        pub const in = p.typedRegister(0x510, Pins);
        pub const direction = p.typedRegistersWriteSetClear(0x514, 0x518, 0x51c, Pins);
        pub const config = p.typedRegisterArray(32, 0x700, Config);
        pub const Config = packed struct {
            output_connected: u1,
            input_disconnected: u1,
            pull: enum(u2) { disabled, down, up = 3 },
            unused1: u4 = 0,
            drive: enum(u3) { s0s1, h0s1, s0h1, h0h1, d0s1, d0h1, s0d1, h0d1 },
            unused2: u5 = 0,
            sense: enum(u2) { disabled, high = 2, low },
            unused3: u14 = 0,
        };
    };
};

const Peripheral = struct {
    fn at(base: u32) type {
        assert(base == 0xe000e000 or base == 0x50000000 or base & 0xfffe0fff == 0x40000000);
        return struct {
            const peripheral_id = base >> 12 & 0x1f;
            fn mmio(address: u32, comptime T: type) *align(4) volatile T {
                return @intToPtr(*align(4) volatile T, address);
            }
            fn event(offset: u32) Event {
                var e: Event = undefined;
                e.address = base + offset;
                return e;
            }
            fn typedRegister(offset: u32, comptime the_layout: type) type {
                return struct {
                    pub const layout = the_layout;
                    pub noinline fn read() layout {
                        return mmio(base + offset, layout).*;
                    }
                    pub noinline fn write(x: layout) void {
                        mmio(base + offset, layout).* = x;
                    }
                };
            }
            fn register(offset: u32) type {
                return typedRegister(offset, u32);
            }
            fn registersWriteSetClear(write_offset: u32, set_offset: u32, clear_offset: u32) type {
                return typedRegistersWriteSetClear(write_offset, set_offset, clear_offset, u32);
            }
            fn typedRegistersWriteSetClear(write_offset: u32, set_offset: u32, clear_offset: u32, comptime T: type) type {
                return struct {
                    pub fn read() T {
                        return typedRegister(write_offset, T).read();
                    }
                    pub fn write(x: T) void {
                        typedRegister(write_offset, T).write(x);
                    }
                    pub fn set(x: T) void {
                        typedRegister(set_offset, T).write(x);
                    }
                    pub fn clear(x: T) void {
                        typedRegister(clear_offset, T).write(x);
                    }
                };
            }
            fn Register(comptime T: type) type {
                return struct {
                    address: u32,
                    pub noinline fn read(self: @This()) T {
                        return mmio(self.address, T).*;
                    }
                    pub noinline fn write(self: @This(), x: T) void {
                        mmio(self.address, T).* = x;
                    }
                };
            }
            fn typedRegisterArray(comptime length: u32, offset: u32, comptime T: type) [length]Register(T) {
                return addressedArray(length, offset, 4, Register(T));
            }
            fn registerArray(comptime length: u32, offset: u32) [length]Register(u32) {
                return addressedArray(length, offset, 4, Register(u32));
            }
            fn registerArrayDelta(comptime length: u32, offset: u32, delta: u32) [length]Register(u32) {
                return addressedArray(length, offset, delta, Register(u32));
            }
            fn shorts(comptime EventsType: type, comptime TasksType: type, event2: EventsType.enums, task2: TasksType.enums) type {
                return struct {
                    fn enable(pairs: []struct { event: EventsType.enums, task: TasksType.enums }) void {}
                };
            }
            fn task(offset: u32) Task {
                var t: Task = undefined;
                t.address = base + offset;
                return t;
            }
            fn addressedArray(comptime length: u32, offset: u32, delta: u32, comptime T: type) [length]T {
                var t: [length]T = undefined;
                var i: u32 = 0;
                while (i < length) : (i += 1) {
                    t[i].address = base + offset + i * delta;
                }
                return t;
            }
            fn eventArray(comptime length: u32, offset: u32) [length]Event {
                return addressedArray(length, offset, 4, Event);
            }
            fn taskArray(comptime length: u32, offset: u32) [length]Task {
                return addressedArray(length, offset, 4, Task);
            }
            fn taskArrayDelta(comptime length: u32, offset: u32, delta: u32) [length]Task {
                return addressedArray(length, offset, delta, Task);
            }
            const Event = struct {
                address: u32,
                pub fn clear(self: Event) void {
                    mmio(self.address, u32).* = 0;
                }
                pub fn occurred(self: Event) bool {
                    return mmio(self.address, u32).* == 1;
                }
            };
            const Task = struct {
                address: u32,
                pub fn do(self: Task) void {
                    mmio(self.address, u32).* = 1;
                }
            };
        };
    }
};

pub const Pins = packed struct {
    i2c_scl: u1 = 0,
    ring2: u1 = 0,
    ring1: u1 = 0,
    ring0: u1 = 0,
    led_cathodes: u9 = 0,
    led_anodes: u3 = 0,
    unused1: u1 = 0,
    button_a: u1 = 0,
    unused2: u6 = 0,
    target_txd: u1 = 0,
    target_rxd: u1 = 0,
    button_b: u1 = 0,
    unused3: u3 = 0,
    i2c_sda: u1 = 0,
    unused4: u1 = 0,
    pub const of = struct {
        pub const i2c_scl = Pins{ .i2c_scl = 1 };
        pub const ring2 = Pins{ .ring2 = 1 };
        pub const ring1 = Pins{ .ring1 = 1 };
        pub const ring0 = Pins{ .ring0 = 1 };
        pub const led_anodes = Pins{ .led_anodes = 0x7 };
        pub const led_cathodes = Pins{ .led_cathodes = 0x1ff };
        pub const leds = led_anodes.maskUnion(led_cathodes);
        pub const button_a = Pins{ .button_a = 1 };
        pub const target_txd = Pins{ .target_txd = 1 };
        pub const target_rxd = Pins{ .target_rxd = 1 };
        pub const button_b = Pins{ .button_b = 1 };
        pub const i2c_sda = Pins{ .i2c_sda = 1 };
    };
    pub fn clear(self: Pins) void {
        Gpio.registers.out.clear(self);
    }
    pub fn config(self: Pins, the_config: Gpio.registers.Config) void {
        var i: u32 = 0;
        while (i < self.width()) : (i += 1) {
            Gpio.registers.config[self.position(i)].write(the_config);
        }
    }
    pub fn connectI2c(self: Pins) void {
        self.config(.{ .output_connected = 0, .input_disconnected = 0, .pull = .disabled, .drive = .s0d1, .sense = .disabled });
    }
    pub fn connectInput(self: Pins) void {
        self.config(.{ .output_connected = 0, .input_disconnected = 0, .pull = .disabled, .drive = .s0s1, .sense = .disabled });
    }
    pub fn connectIo(self: Pins) void {
        self.config(.{ .output_connected = 1, .input_disconnected = 0, .pull = .disabled, .drive = .s0s1, .sense = .disabled });
    }
    pub fn connectOutput(self: Pins) void {
        self.config(.{ .output_connected = 1, .input_disconnected = 1, .pull = .disabled, .drive = .s0s1, .sense = .disabled });
    }
    pub fn directionClear(self: @This()) void {
        Gpio.registers.direction.clear(self);
    }
    pub fn directionSet(self: @This()) void {
        Gpio.registers.direction.set(self);
    }
    pub fn mask(self: Pins) u32 {
        assert(@sizeOf(Pins) == 4);
        return @bitCast(u32, self);
    }
    pub fn maskUnion(self: Pins, other: Pins) Pins {
        return @bitCast(Pins, self.mask() | other.mask());
    }
    pub fn outRead(self: Pins) u32 {
        return (@bitCast(u32, Gpio.registers.out.read()) & self.mask()) >> self.position(0);
    }
    fn position(self: Pins, i: u32) u5 {
        return @truncate(u5, @ctz(u32, self.mask()) + i);
    }
    pub fn read(self: Pins) u32 {
        return (@bitCast(u32, Gpio.registers.in.read()) & self.mask()) >> self.position(0);
    }
    pub fn set(self: Pins) void {
        Gpio.registers.out.set(self);
    }
    fn width(self: Pins) u32 {
        return 32 - @clz(u32, self.mask()) - @ctz(u32, self.mask());
    }
    pub fn write(self: Pins, x: u32) void {
        var new = Gpio.registers.out.read().mask() & ~self.mask();
        new |= (x << self.position(0)) & self.mask();
        Gpio.registers.out.write(@bitCast(Pins, new));
    }
    pub fn writeWholeMask(self: Pins) void {
        Gpio.registers.out.write(self);
    }
};

pub const Terminal = struct {
    pub fn attribute(n: u32) void {
        pair(n, 0, "m");
    }
    pub fn clearScreen() void {
        pair(2, 0, "J");
    }
    pub fn hideCursor() void {
        Uart.writeText(csi ++ "?25l");
    }
    pub fn line(comptime fmt: []const u8, args: var) void {
        print(fmt, args);
        pair(0, 0, "K");
        Uart.writeText("\n");
    }
    pub fn move(row: u32, column: u32) void {
        pair(row, column, "H");
    }
    pub fn pair(a: u32, b: u32, letter: []const u8) void {
        if (a <= 1 and b <= 1) {
            print("{}{}", .{ csi, letter });
        } else if (b <= 1) {
            print("{}{}{}", .{ csi, a, letter });
        } else if (a <= 1) {
            print("{};{}{}", .{ csi, b, letter });
        } else {
            print("{}{};{}{}", .{ csi, a, b, letter });
        }
    }
    pub fn requestCursorPosition() void {
        Uart.writeText(csi ++ "6n");
    }
    pub fn requestDeviceCode() void {
        Uart.writeText(csi ++ "c");
    }
    pub fn reset() void {
        Uart.writeText("\x1bc");
    }
    pub fn restoreCursorAndAttributes() void {
        Uart.writeText("\x1b8");
    }
    pub fn saveCursorAndAttributes() void {
        Uart.writeText("\x1b7");
    }
    pub fn setLineWrap(enabled: bool) void {
        pair(0, 0, if (enabled) "7h" else "7l");
    }
    pub fn setScrollingRegion(top: u32, bottom: u32) void {
        pair(top, bottom, "r");
    }
    pub fn showCursor() void {
        Uart.writeText(csi ++ "?25h");
    }
    const csi = "\x1b[";
    var height: u32 = 24;
    var width: u32 = 80;
};

pub const TimeKeeper = struct {
    duration: u32,
    max_elapsed: u32,
    start_time: u32,

    fn capture(self: *TimeKeeper) u32 {
        Timers[0].tasks.capture[0].do();
        return Timers[0].registers.capture_compare[0].read();
    }
    fn elapsed(self: *TimeKeeper) u32 {
        return self.capture() -% self.start_time;
    }
    fn ofMilliseconds(ms: u32) TimeKeeper {
        var t: TimeKeeper = undefined;
        t.prepare(1000 * ms);
        return t;
    }
    fn prepare(self: *TimeKeeper, duration: u32) void {
        self.duration = duration;
        self.max_elapsed = 0;
        self.reset();
    }
    fn isFinishedThenReset(self: *TimeKeeper) bool {
        const since = self.elapsed();
        if (since >= self.duration) {
            if (since > self.max_elapsed) {
                self.max_elapsed = since;
            }
            self.reset();
            return true;
        } else {
            return false;
        }
    }
    fn reset(self: *TimeKeeper) void {
        self.start_time = self.capture();
    }
    fn wait(self: *TimeKeeper) void {
        while (!self.isFinishedThenReset()) {}
    }
    pub fn delay(duration: u32) void {
        var time_keeper: TimeKeeper = undefined;
        time_keeper.prepare(duration);
        time_keeper.wait();
    }
};

pub const Timers = [_]@TypeOf(Timer(0x40008000)){ Timer(0x40008000), Timer(0x40009000), Timer(0x4000a000) };

fn Timer(base: u32) type {
    return struct {
        const max_width = if (base == 0x40008000) @as(u32, 32) else 16;
        const p = Peripheral.at(base);
        pub const tasks = struct {
            pub const start = p.task(0x000);
            pub const stop = p.task(0x004);
            pub const count = p.task(0x008);
            pub const clear = p.task(0x00c);
            pub const capture = p.taskArray(4, 0x040);
        };
        pub const events = struct {
            pub const compare = p.eventArray(4, 0x140);
        };
        pub const registers = struct {
            pub const shorts = p.register(0x200);
            pub const interrupts = p.registerSetClear(0x304, 0x308);
            pub const mode = p.register(0x504);
            pub const bit_mode = p.register(0x508);
            pub const prescaler = p.register(0x510);
            pub const capture_compare = p.registerArray(4, 0x540);
        };
        pub fn captureAndRead() u32 {
            tasks.capture[0].do();
            return registers.capture_compare[0].read();
        }
        pub fn prepare() void {
            registers.mode.write(0x0);
            registers.bit_mode.write(if (base == 0x40008000) @as(u32, 0x3) else 0x0);
            registers.prescaler.write(if (base == 0x40008000) @as(u32, 4) else 9);
            tasks.start.do();
            const now = captureAndRead();
            var i: u32 = 0;
            while (captureAndRead() == now) : (i += 1) {
                if (i == 1000) {
                    panicf("timer 0x{x} is not responding", .{base});
                }
            }
        }
    };
}

const Uart = struct {
    const p = Peripheral.at(0x40002000);
    pub const tasks = struct {
        pub const start_rx = p.task(0x000);
        pub const stop_rx = p.task(0x004);
        pub const start_tx = p.task(0x008);
        pub const stop_tx = p.task(0x00c);
    };
    pub const events = struct {
        pub const cts = p.event(0x100);
        pub const not_cts = p.event(0x104);
        pub const rx_ready = p.event(0x108);
        pub const tx_ready = p.event(0x11c);
        pub const error_detected = p.event(0x124);
        pub const rx_timeout = p.event(0x144);
    };
    pub const registers = struct {
        pub const interrupts = p.registersWriteSetClear(0x300, 0x304, 0x308);
        pub const error_source = p.register(0x480);
        pub const enable = p.register(0x500);
        pub const pin_select_rts = p.register(0x508);
        pub const pin_select_txd = p.register(0x50c);
        pub const pin_select_cts = p.register(0x510);
        pub const pin_select_rxd = p.register(0x514);
        pub const rxd = p.register(0x518);
        pub const txd = p.register(0x51c);
        pub const baud_rate = p.register(0x524);
    };
    var stream: std.io.OutStream(Uart, stream_error, writeTextError) = undefined;
    var tx_busy: bool = undefined;
    var tx_queue: [3]u8 = undefined;
    var tx_queue_read: usize = undefined;
    var tx_queue_write: usize = undefined;
    var updater: ?fn () void = undefined;
    const stream_error = error{UartError};
    pub fn drainTx() void {
        while (tx_queue_read != tx_queue_write) {
            loadTxd();
        }
    }
    pub fn prepare() void {
        Pins.of.target_txd.connectOutput();
        registers.pin_select_rxd.write(Pins.of.target_rxd.position(0));
        registers.pin_select_txd.write(Pins.of.target_txd.position(0));
        registers.enable.write(0x04);
        tasks.start_rx.do();
        tasks.start_tx.do();
    }
    pub fn isReadByteReady() bool {
        return events.rx_ready.occurred();
    }
    pub fn print(comptime fmt: []const u8, args: var) void {
        std.fmt.format(stream, fmt, args) catch |_| {};
    }
    pub fn loadTxd() void {
        if (tx_queue_read != tx_queue_write and (!tx_busy or events.tx_ready.occurred())) {
            events.tx_ready.clear();
            registers.txd.write(tx_queue[tx_queue_read]);
            tx_queue_read = (tx_queue_read + 1) % tx_queue.len;
            tx_busy = true;
            if (updater) |an_updater| {
                an_updater();
            }
        }
    }
    pub fn log(comptime fmt: []const u8, args: var) void {
        print(fmt ++ "\n", args);
    }
    pub fn writeText(buffer: []const u8) void {
        for (buffer) |c| {
            switch (c) {
                '\n' => {
                    writeByteBlocking('\r');
                    writeByteBlocking('\n');
                },
                else => writeByteBlocking(c),
            }
        }
    }
    pub fn writeTextError(self: Uart, buffer: []const u8) stream_error!usize {
        writeText(buffer);
        return buffer.len;
    }
    pub fn setUpdater(new_updater: fn () void) void {
        updater = new_updater;
    }
    pub fn update() void {
        loadTxd();
    }
    pub fn writeByteBlocking(byte: u8) void {
        const next = (tx_queue_write + 1) % tx_queue.len;
        while (next == tx_queue_read) {
            loadTxd();
        }
        tx_queue[tx_queue_write] = byte;
        tx_queue_write = next;
        loadTxd();
    }
    pub fn readByte() u8 {
        events.rx_ready.clear();
        return @truncate(u8, registers.rxd.read());
    }
};

fn hangf(comptime fmt: []const u8, args: var) noreturn {
    log(fmt, args);
    Uart.drainTx();
    while (true) {}
}

fn panicf(comptime fmt: []const u8, args: var) noreturn {
    @setCold(true);
    log("\npanicf(): " ++ fmt, args);
    hangf("panic completed", .{});
}

const assert = std.debug.assert;
const log = Uart.log;
const model = @import("system_model.zig");
const print = Uart.print;
const std = @import("std");
