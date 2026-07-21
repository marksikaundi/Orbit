pub const Cell = struct {
    /// Unicode codepoint (ASCII for Phase 1).
    codepoint: u21 = ' ',
    dirty: bool = true,

    pub fn blank() Cell {
        return .{};
    }

    pub fn set(self: *Cell, codepoint: u21) void {
        if (self.codepoint != codepoint) {
            self.codepoint = codepoint;
            self.dirty = true;
        }
    }
};
