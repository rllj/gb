const Pins = @import("SM83.zig").Pins;

// Must be extern to guarantee struct field order, so that it may be
// type-punned over the memory array
pub const Timer = extern struct {
    sysclk_lo: u8,
    div: u8,
    tima: u8,
    tma: u8,
    tac: TimerControl,

    pub const SYSCLK_LO = 0xFF03;
    pub const DIV = 0xFF04;
    pub const TIMA = 0xFF05;
    pub const TMA = 0xFF06;
    pub const TAC = 0xFF07;

    const TimerControl = packed struct(u8) {
        clock_select: u2,
        enable: bool,
        unused: u5,
    };

    pub const TimerEvents = struct {
        apu_event: bool = false,
        overflow: bool = false,
    };

    /// To be called every M-cycle
    pub fn tick(
        self: *Timer,
        prev_timer: Timer,
        has_overflow_delay: bool,
        bus: Pins,
    ) TimerEvents {
        var events: TimerEvents = .{};

        self.sysclk_lo, const carry = @addWithOverflow(self.sysclk_lo, 1);
        self.div +%= carry;

        if (self.div & (1 << 4) < prev_timer.div & (1 << 4)) {
            events.apu_event = true;
        }

        const freq_bit = switch (self.tac.clock_select) {
            0b00 => (self.sysclk_lo >> 7) & 1,
            0b01 => (self.sysclk_lo >> 1) & 1,
            0b10 => (self.sysclk_lo >> 3) & 1,
            0b11 => (self.sysclk_lo >> 5) & 1,
        } & @intFromBool(self.tac.enable);
        const prev_freq_bit = switch (prev_timer.tac.clock_select) {
            0b00 => (prev_timer.sysclk_lo >> 7) & 1,
            0b01 => (prev_timer.sysclk_lo >> 1) & 1,
            0b10 => (prev_timer.sysclk_lo >> 3) & 1,
            0b11 => (prev_timer.sysclk_lo >> 5) & 1,
        } & @intFromBool(prev_timer.tac.enable);

        if (freq_bit < prev_freq_bit) {
            self.tima, const overflow = @addWithOverflow(self.tima, 1);
            if (overflow == 1 and !bus_tima_write(bus)) {
                events.overflow = true;
            }
        }

        if (has_overflow_delay) {
            self.tima = self.tma;
        }

        return events;
    }

    fn bus_tima_write(bus: Pins) bool {
        return bus.abus == TIMA and bus.mreq == 1 and bus.wr == 1;
    }
};
