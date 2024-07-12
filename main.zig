// button/rx update leds/terminal/radio
// check random count state history

// multi app with selection
//  flash data api
// qemu buttons, leds, radio
// kitty, row/column
// animated Z
// usb or serial wires?
//  serial to zig pi
// internal ppi task/event

// implicit if (timed(text, condition)) {
// v1 v1.qemu v2
//  reallocate stack first thing?
//  set memory allocator
// qemu api exit

export var vector_table linksection(".vector_table") = extern struct {
    initial_sp: [1]u32 = .{model.memory.ram.stack_bottom},
    system_reset: [1]EntryPoint = .{system_reset_handler},
    system_exceptions: [14]EntryPoint = .{system_exception_handler} ** 14,
    interrupts: [model.number_of_peripherals]EntryPoint = .{system_exception_handler} ** model.number_of_peripherals,
    const EntryPoint = *const fn () callconv(.C) noreturn;
}{};

fn system_reset_handler() callconv(.C) noreturn {
    model.memory.ram.prepare();
    LedPattern.prepare();
    Gpio.Mask.inputs.connectInput();
    Uart.prepare();
    Timers[0].prepare();
    Terminal.prepare();
    Terminal.enableKitty();
    Terminal.attribute(Terminal.background_green);
    Terminal.attribute(Terminal.foreground_black);
    Terminal.clearScreen();
    Terminal.move(1, 1);
    log("https://github.com/markfirmware/zig-vector-table is running on a microbit!", .{});
    var status_line_number = Terminal.current_row;
    if (Ficr.is_qemu()) {
        Terminal.attribute(Terminal.foreground_magenta);
        log("actually qemu -M microbit", .{});
        log("the emulated timer can be slower than a real one and also slightly erratic", .{});
        Terminal.attribute(Terminal.foreground_black);
        status_line_number = Terminal.current_row;
        Terminal.move(status_line_number, 1);
        log("waiting for timer ...", .{});
        log("", .{});
    } else {
        log("terminal mode ...", .{});
        Gpiote.registers.config[0].write(.{
            .mode = .event,
            .pin_number = @bitOffsetOf(Gpio.Pins, "ring0"),
            .polarity = .toggle,
        });
        Gpiote.registers.config[1].write(.{
            .mode = .task,
            .pin_number = @bitOffsetOf(Gpio.Pins, "target_txd"),
            .polarity = .toggle,
            .out_init = 1,
        });
        Ppi.registers.channel0.event_endpoint.write(Gpiote.in_event[0].address);
        Ppi.registers.channel0.task_endpoint.write(Gpiote.out_task[1].address);
        Ppi.registers.channel_enable.set(1);
    }
    var t = TimeKeeper.ofMilliseconds(1000);
    var i: u32 = 0;
    LedPattern.hexagon.show();

    while (true) {
        idle();

        if (t.isFinishedThenReset()) {
            i += 1;
            if (i % 2 == 0) {
                LedPattern.hexagon.show();
            } else {
                LedPattern.all_off.show();
            }
            // const here_row = Terminal.current_row;
            // const here_col = Terminal.current_col;
            if (Ficr.is_qemu()) {
                Terminal.saveCursorAndAttributes();
                // Terminal.move(status_line_number, 1);
                log("up and running for {} seconds!", .{i});
                Terminal.restoreCursorAndAttributes();
            }
            // Terminal.move(here_row, here_col);
        }
    }
}

fn idle() void {
    if (Uart.isReadByteReady()) {
        const byte = Uart.readByte();
        Uart.writeByteBlocking(if (byte != 27) byte else " "[0]);
    }
    Uart.update();
}

fn system_exception_handler() callconv(.C) noreturn {
    const ipsr_interrupt_program_status_register = asm ("mrs %[ipsr_interrupt_program_status_register], ipsr"
        : [ipsr_interrupt_program_status_register] "=r" (-> usize),
    );
    const isr_number = ipsr_interrupt_program_status_register & 0xff;
    panicf("arm exception ipsr.isr_number {}", .{isr_number});
}

pub fn panic(message: []const u8, trace: ?*std.builtin.StackTrace, status_code: ?usize) noreturn {
    _ = trace;
    _ = status_code;
    panicf("panic(): {s}", .{message});
}

fn panicf(comptime fmt: []const u8, args: anytype) noreturn {
    log("\npanicf(): " ++ fmt, args);
    hangf("panic completed", .{});
}

fn hangf(comptime fmt: []const u8, args: anytype) noreturn {
    log(fmt, args);
    Uart.drainTx();
    while (true) {}
}

const LedPattern = enum(Gpio.Bits) {
    all_off = @bitCast(Gpio.Pins{ .led_anodes_active_high = 0, .led_cathodes_active_low = @truncate(-1) }),
    all_on = @bitCast(Gpio.Pins{ .led_anodes_active_high = @truncate(-1), .led_cathodes_active_low = 0 }),
    hexagon = @bitCast(Gpio.Pins{ .led_anodes_active_high = 0x2, .led_cathodes_active_low = 0 }),
    fn prepare() void {
        Gpio.Mask.leds.connectOutput();
    }
    fn show(pattern: LedPattern) void {
        Gpio.Mask.leds.write(pattern);
    }
};

const Ficr = struct {
    fn deviceId() u64 {
        return contents64[0x60 >> 3];
    }
    fn is_qemu() bool {
        return deviceId() == 0x1234567800000003;
    }
    const contents64 = @as(*[32]u64, @ptrFromInt(0x10000000));
    const contents32 = @as(*[64]u32, @ptrCast(contents64));
};

const Gpio = struct {
    const p = Peripheral.at(0x50000000);
    const registers = struct {
        const out = p.typedRegisterGroup(0x504, Pins);
        const in = p.typedRegister(0x510, Pins);
        const direction = p.typedRegisterGroup(0x514, Pins);
        const config = p.typedRegisterArray(32, 0x700, Config);
    };
    const Bits = u32;
    const Pins = packed struct {
        i2c_scl: u1 = 0,
        ring2: u1 = 0,
        ring1: u1 = 0,
        ring0: u1 = 0,
        led_cathodes_active_low: u9 = 0,
        led_anodes_active_high: u3 = 0,
        unused1: u1 = 0,
        button_a: u1 = 0,
        unused2: u6 = 0,
        target_txd: u1 = 0,
        target_rxd: u1 = 0,
        button_b: u1 = 0,
        unused3: u3 = 0,
        i2c_sda: u1 = 0,
        unused4: u1 = 0,
    };
    const Config = packed struct {
        output_connected: u1,
        input_disconnected: u1,
        pull: enum(u2) { disabled, down, up = 3 },
        unused1: u4 = 0,
        drive: enum(u3) { s0s1, h0s1, s0h1, h0h1, d0s1, d0h1, s0d1, h0d1 },
        unused2: u5 = 0,
        sense: enum(u2) { disabled, high = 2, low },
        unused3: u14 = 0,
    };

    const Mask3 = @as(Pins, @bitCast(@as(u32, (@truncate(-1)))));

    const Mask2 = enum(Bits) { // none all leds buttons inputs
        none = asBits(Pins{}),
        all = bitinv(asBits(Pins{ .unused1 = @truncate(-1), .unused2 = @truncate(-1), .unused3 = @truncate(-1), .unused4 = @truncate(-1) })),
        i2c_scl = asBits(Pins{ .i2c_scl = @truncate(-1) }),
        ring2 = asBits(Pins{ .ring2 = @truncate(-1) }),
        ring1 = asBits(Pins{ .ring1 = @truncate(-1) }),
        ring0 = asBits(Pins{ .ring0 = @truncate(-1) }),
        led_cathodes_active_low = asBits(Pins{ .led_cathodes_active_low = @truncate(-1) }),
        led_anodes_active_high = asBits(Pins{ .led_anodes_active_high = @truncate(-1) }),
        leds = asBits(Pins{ .led_cathodes_active_low = @truncate(-1), .led_anodes_active_high = @truncate(-1) }),
        button_a = asBits(Pins{ .button_a = @truncate(-1) }),
        target_txd = asBits(Pins{ .target_txd = @truncate(-1) }),
        target_rxd = asBits(Pins{ .target_rxd = @truncate(-1) }),
        button_b = asBits(Pins{ .button_b = @truncate(-1) }),
        buttons = asBits(Pins{ .button_a = @truncate(-1), .button_b = @truncate(-1) }),
        inputs = asBits(Pins{
            .button_a = @truncate(-1),
            .button_b = @truncate(-1),
            .ring0 = @truncate(-1),
            .ring1 = @truncate(-1),
            .ring2 = @truncate(-1),
        }),
        i2c_sda = asBits(Pins{ .i2c_sda = @truncate(-1) }),
        _,
    };

    const Mask = enum(Bits) { // none all leds buttons inputs
        none = asBits(Pins{}),
        all = bitinv(asBits(Pins{ .unused1 = @truncate(-1), .unused2 = @truncate(-1), .unused3 = @truncate(-1), .unused4 = @truncate(-1) })),
        i2c_scl = asBits(Pins{ .i2c_scl = @truncate(-1) }),
        ring2 = asBits(Pins{ .ring2 = @truncate(-1) }),
        ring1 = asBits(Pins{ .ring1 = @truncate(-1) }),
        ring0 = asBits(Pins{ .ring0 = @truncate(-1) }),
        led_cathodes_active_low = asBits(Pins{ .led_cathodes_active_low = @truncate(-1) }),
        led_anodes_active_high = asBits(Pins{ .led_anodes_active_high = @truncate(-1) }),
        leds = asBits(Pins{ .led_cathodes_active_low = @truncate(-1), .led_anodes_active_high = @truncate(-1) }),
        button_a = asBits(Pins{ .button_a = @truncate(-1) }),
        target_txd = asBits(Pins{ .target_txd = @truncate(-1) }),
        target_rxd = asBits(Pins{ .target_rxd = @truncate(-1) }),
        button_b = asBits(Pins{ .button_b = @truncate(-1) }),
        buttons = asBits(Pins{ .button_a = @truncate(-1), .button_b = @truncate(-1) }),
        inputs = asBits(Pins{
            .button_a = @truncate(-1),
            .button_b = @truncate(-1),
            .ring0 = @truncate(-1),
            .ring1 = @truncate(-1),
            .ring2 = @truncate(-1),
        }),
        i2c_sda = asBits(Pins{ .i2c_sda = @truncate(-1) }),
        _,

        fn write(comptime self: Mask, data: anytype) void {
            const new = bitor(bitand(registers.out.read(), bitinv(self)), bitand(data, self));
            registers.out.write(new);
        }
        fn read(comptime self: Mask) Pins {
            return bitand(registers.in.read(), self);
        }
        fn config(comptime self: Mask, comptime the_config: Config) void {
            comptime var i: u32 = 0;
            var m: u32 = 1;
            const bits = asBits(self);
            inline while (i < @bitSizeOf(u32)) : (i += 1) {
                if (bits & m != 0) {
                    registers.config[i].write(the_config);
                }
                m <<= 1;
            }
        }
        fn connectOutput(comptime self: Mask) void {
            self.config(.{
                .output_connected = 1,
                .input_disconnected = 1,
                .pull = .disabled,
                .drive = .s0s1,
                .sense = .disabled,
            });
        }
        fn connectI2c(self: Pins) void {
            self.config(.{ .output_connected = 0, .input_disconnected = 0, .pull = .disabled, .drive = .s0d1, .sense = .disabled });
        }
        fn connectInput(comptime self: Mask) void {
            self.config(.{
                .output_connected = 0,
                .input_disconnected = 0,
                .pull = .disabled,
                .drive = .s0s1,
                .sense = .disabled,
            });
        }
        fn connectIo(self: Pins) void {
            self.config(.{ .output_connected = 1, .input_disconnected = 0, .pull = .disabled, .drive = .s0s1, .sense = .disabled });
        }
        fn directionClear(self: @This()) void {
            registers.direction.clear(self);
        }
        fn directionSet(self: @This()) void {
            registers.direction.set(self);
        }
    };
};

const Gpiote = struct {
    const p = Peripheral.at(0x40006000);
    const out_task = p.taskArray(4, 0x000);
    const in_event = p.eventArray(4, 0x100);
    const registers = struct {
        const config = p.typedRegisterArray(4, 0x510, packed struct {
            mode: enum(u2) { disabled, event, task = 3 } = .disabled,
            unused1: u6 = 0,
            pin_number: u5 = 0,
            unused2: u3 = 0,
            polarity: enum(u2) { none, loToHi, hiToLo, toggle } = .none,
            unused3: u2 = 0,
            out_init: u1 = 0,
            unused4: u3 = 0,
            unused5: u8 = 0,
        });
    };
};

const Ppi = struct {
    const p = Peripheral.at(0x4001f000);
    const registers = struct {
        const channel_enable = p.registerGroup(0x500);
        const channel0 = struct {
            const event_endpoint = p.register(0x510);
            const task_endpoint = p.register(0x514);
        };
    };
};

const Peripheral = struct {
    fn at(comptime base: u32) type {
        assert(base == 0xe000e000 or base == 0x50000000 or base & 0xfffe0fff == 0x40000000);
        return struct {
            const peripheral_id = base >> 12 & 0x1f;
            fn mmio(address: u32, comptime T: type) *align(4) volatile T {
                return @as(*align(4) volatile T, @ptrFromInt(address));
            }
            fn event(offset: u32) Event {
                var e: Event = undefined;
                e.address = base + offset;
                return e;
            }
            fn typedRegister(comptime offset: u32, comptime the_layout: type) type {
                return struct {
                    const layout = the_layout;
                    noinline fn read() layout {
                        return mmio(base + offset, layout).*;
                    }
                    noinline fn write(x: layout) void {
                        mmio(base + offset, layout).* = x;
                    }
                };
            }
            fn register(comptime offset: u32) type {
                return typedRegister(offset, u32);
            }
            fn registerGroup(comptime offset: u32) type {
                return typedRegisterGroup(offset, u32);
            }
            fn typedRegisterGroup(comptime offset: u32, comptime T: type) type {
                const offsets = RegisterGroup{ .read = offset, .write = offset, .set = offset + 4, .clear = offset + 8 };
                return struct {
                    fn read() T {
                        return typedRegister(offsets.read, T).read();
                    }
                    fn write(x: T) void {
                        typedRegister(offsets.write, T).write(x);
                    }
                    fn set(x: T) void {
                        typedRegister(offsets.set, T).write(x);
                    }
                    fn clear(x: T) void {
                        typedRegister(offsets.clear, T).write(x);
                    }
                };
            }
            fn Register(comptime T: type) type {
                return struct {
                    address: u32,
                    noinline fn read(self: @This()) T {
                        return mmio(self.address, T).*;
                    }
                    noinline fn write(self: @This(), x: T) void {
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
                _ = event2;
                _ = task2;
                return struct {
                    fn enable(pairs: []struct { event: EventsType.enums, task: TasksType.enums }) void {
                        _ = pairs;
                    }
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
                fn clearEvent(self: Event) void {
                    mmio(self.address, u32).* = 0;
                }
                fn eventOccurred(self: Event) bool {
                    return mmio(self.address, u32).* == 1;
                }
            };
            const RegisterGroup = struct {
                read: u32,
                write: u32,
                set: u32,
                clear: u32,
            };
            const Task = struct {
                address: u32,
                fn doTask(self: Task) void {
                    mmio(self.address, u32).* = 1;
                }
            };
        };
    }
};

const Terminal = struct {
    var current_row: u32 = 1;
    var current_col: u32 = 1;
    fn prepare() void {
        reset();
    }
    fn enableKitty() void {
        Uart.writeText(csi ++ ">31u");
    }
    fn attribute(n: u32) void {
        pair(n, 0, "m");
    }
    fn clearScreen() void {
        pair(2, 0, "J");
    }
    fn hideCursor() void {
        Uart.writeText(csi ++ "?25l");
    }
    fn line(comptime fmt: []const u8, args: anytype) void {
        print(fmt, args);
        pair(0, 0, "K");
        Uart.writeText("\n");
    }
    fn move(row: u32, column: u32) void {
        current_row = row;
        current_col = column;
        pair(row, column, "H");
    }
    fn pair(a: u32, b: u32, letter: []const u8) void {
        if (a <= 1 and b <= 1) {
            print("{s}{s}", .{ csi, letter });
        } else if (b <= 1) {
            print("{s}{}{s}", .{ csi, a, letter });
        } else if (a <= 1) {
            print("{s};{}{s}", .{ csi, b, letter });
        } else {
            print("{s}{};{}{s}", .{ csi, a, b, letter });
        }
    }
    fn requestCursorPosition() void {
        Uart.writeText(csi ++ "6n");
    }
    fn requestDeviceCode() void {
        Uart.writeText(csi ++ "c");
    }
    fn reset() void {
        current_row = 1;
        current_col = 1;
        Uart.writeText("\x1bc");
    }
    fn restoreCursorAndAttributes() void {
        Uart.writeText("\x1b8");
    }
    fn saveCursorAndAttributes() void {
        Uart.writeText("\x1b7");
    }
    fn setLineWrap(enabled: bool) void {
        pair(0, 0, if (enabled) "7h" else "7l");
    }
    fn setScrollingRegion(top: u32, bottom: u32) void {
        pair(top, bottom, "r");
    }
    fn showCursor() void {
        Uart.writeText(csi ++ "?25h");
    }
    const csi = "\x1b[";
    const background_green = 42;
    const background_yellow = 43;
    const foreground_black = 30;
    const foreground_magenta = 35;
    var height: u32 = 24;
    var width: u32 = 80;
};

const TimeCounter = struct {
    duration: u32,
    start_time: u32,
    fn capture(self: *@This()) u32 {
        _ = self;
        Timers[0].tasks.capture[0].doTask();
        return Timers[0].registers.capture_compare[0].read();
    }
    fn elapsed(self: *@This()) u32 {
        const now = self.capture();
        const x = (now - self.start_time) / self.duration;
        self.start_time = now;
        return x;
    }
    fn ofMilliseconds(ms: u32) @This() {
        var t: @This() = undefined;
        t.prepare(1000 * ms);
        return t;
    }
    fn ofMicroseconds(us: u32) @This() {
        var t: @This() = undefined;
        t.prepare(us);
        return t;
    }
    fn prepare(self: *@This(), duration: u32) void {
        self.duration = duration;
        self.start_time = self.capture();
    }
};

const TimeKeeper = struct {
    duration: u32,
    max_elapsed: u32,
    start_time: u32,

    fn capture(self: *TimeKeeper) u32 {
        _ = self;
        Timers[0].tasks.capture[0].doTask();
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
    fn delay(duration: u32) void {
        var time_keeper: TimeKeeper = undefined;
        time_keeper.prepare(duration);
        time_keeper.wait();
    }
};

const Timers = .{ Timer(0x40008000), Timer(0x40009000), Timer(0x4000a000) };

fn Timer(comptime base: u32) type {
    return struct {
        const max_width = if (base == 0x40008000) @as(u32, 32) else 16;
        const p = Peripheral.at(base);
        const tasks = struct {
            const start = p.task(0x000);
            const stop = p.task(0x004);
            const count = p.task(0x008);
            const clear = p.task(0x00c);
            const capture = p.taskArray(4, 0x040);
        };
        const events = struct {
            const compare = p.eventArray(4, 0x140);
        };
        const registers = struct {
            const shorts = p.register(0x200);
            const interrupts = p.registerSetClear(0x304, 0x308);
            const mode = p.register(0x504);
            const bit_mode = p.register(0x508);
            const prescaler = p.register(0x510);
            const capture_compare = p.registerArray(4, 0x540);
        };
        fn captureAndRead() u32 {
            tasks.capture[0].doTask();
            return registers.capture_compare[0].read();
        }
        fn prepare() void {
            registers.mode.write(0x0);
            registers.bit_mode.write(if (base == 0x40008000) @as(u32, 0x3) else 0x0);
            registers.prescaler.write(if (base == 0x40008000) @as(u32, 4) else 9);
            tasks.start.doTask();
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
    const tasks = struct {
        const start_rx = p.task(0x000);
        const stop_rx = p.task(0x004);
        const start_tx = p.task(0x008);
        const stop_tx = p.task(0x00c);
    };

    const events = struct {
        const cts = p.event(0x100);
        const not_cts = p.event(0x104);
        const rx_ready = p.event(0x108);
        const tx_ready = p.event(0x11c);
        const error_detected = p.event(0x124);
        const rx_timeout = p.event(0x144);
    };
    const registers = struct {
        const interrupts = p.registerGroup(.{ .read = 0x300, .write = 0x300, .set = 0x304, .clear = 0x308 });
        const error_source = p.register(0x480);
        const enable = p.register(0x500);
        const pin_select_rts = p.register(0x508);
        const pin_select_txd = p.register(0x50c);
        const pin_select_cts = p.register(0x510);
        const pin_select_rxd = p.register(0x514);
        const rxd = p.register(0x518);
        const txd = p.register(0x51c);
        const baud_rate = p.register(0x524);
        const config = p.register(0x56C);
    };
    fn write(_: void, buffer: []const u8) error{UartError}!usize {
        Uart.writeText(buffer);
        return buffer.len;
    }
    const writer = std.io.Writer(void, error{UartError}, write){ .context = {} };
    var tx_busy: bool = undefined;
    // var tx_queue: [3]u8 = undefined;
    var tx_queue: [32]u8 = undefined;
    var tx_queue_read: usize = undefined;
    var tx_queue_write: usize = undefined;
    fn drainTx() void {
        while (tx_queue_read != tx_queue_write) {
            loadTxd();
        }
    }
    fn prepare() void {
        // Gpio.Mask.target_txd.connectOutput();
        Gpio.Mask.ring1.connectOutput();
        const enable_entire_uart = 0x04;
        registers.enable.write(enable_entire_uart);
        // registers.pin_select_rxd.write(@bitOffsetOf(Gpio.Pins, "target_rxd"));
        // registers.pin_select_txd.write(@bitOffsetOf(Gpio.Pins, "target_txd"));
        registers.pin_select_rxd.write(@bitOffsetOf(Gpio.Pins, "target_rxd"));
        registers.pin_select_txd.write(@bitOffsetOf(Gpio.Pins, "ring1"));
        const baud_rate_115200 = 0x01d7e000;
        // const baud_rate_1200 = 0x0004F000;
        registers.baud_rate.write(baud_rate_115200);
        const disable_parity_disable_control_flow = 0;
        registers.config.write(disable_parity_disable_control_flow);
        tasks.start_rx.doTask();
        tasks.start_tx.doTask();
    }
    fn print(comptime fmt: []const u8, args: anytype) void {
        std.fmt.format(writer, fmt, args) catch {};
    }
    fn loadTxd() void {
        if (tx_queue_read != tx_queue_write and (!tx_busy or events.tx_ready.eventOccurred())) {
            events.tx_ready.clearEvent();
            registers.txd.write(tx_queue[tx_queue_read]);
            tx_queue_read = (tx_queue_read + 1) % tx_queue.len;
            tx_busy = true;
        }
    }
    fn log(comptime fmt: []const u8, args: anytype) void {
        Uart.print(fmt ++ "\n", args);
    }
    fn writeText(buffer: []const u8) void {
        for (buffer) |c| {
            switch (c) {
                '\n' => {
                    Terminal.current_row += 1;
                    Terminal.current_col = 1;
                    writeByteBlocking('\r');
                    writeByteBlocking('\n');
                },
                else => {
                    Terminal.current_col += 1;
                    writeByteBlocking(c);
                },
            }
        }
    }
    fn update() void {
        loadTxd();
    }
    fn writeByteBlocking(byte: u8) void {
        const next = (tx_queue_write + 1) % tx_queue.len;
        while (next == tx_queue_read) {
            update();
            idle();
        }
        tx_queue[tx_queue_write] = byte;
        tx_queue_write = next;
        loadTxd();
    }
    fn isReadByteReady() bool {
        return events.rx_ready.eventOccurred();
    }
    fn readByte() u8 {
        events.rx_ready.clearEvent();
        return @truncate(registers.rxd.read());
    }
};

fn asBool(data: anytype) bool {
    return asBits(data) != 0;
}

fn asBits(data: anytype) Gpio.Bits {
    return switch (@typeInfo(@TypeOf(data))) {
        .Enum => @intFromEnum(data),
        else => @bitCast(data),
    };
}

fn of(a: anytype, b: anytype) @TypeOf(a) {
    return switch (@typeInfo(@TypeOf(a))) {
        .Enum => @enumFromInt(b),
        else => @bitCast(b),
    };
}

fn bitinv(a: anytype) @TypeOf(a) {
    return of(a, ~asBits(a));
}

fn bitand(a: anytype, b: anytype) @TypeOf(a) {
    return of(a, asBits(a) & asBits(b));
}

fn bitor(a: anytype, b: anytype) @TypeOf(a) {
    return of(a, asBits(a) | asBits(b));
}

fn bitxor(a: anytype, b: anytype) @TypeOf(a) {
    return of(a, asBits(a) ^ asBits(b));
}

const assert = std.debug.assert;
const log = Uart.log;
const model = @import("system_model.zig");
const print = Uart.print;
const std = @import("std");
