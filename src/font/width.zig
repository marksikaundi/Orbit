//! Terminal cell width (wcwidth-style) and box-drawing helpers.

pub const CellWidth = enum(u8) {
    empty = 0,
    narrow = 1,
    wide = 2,
};

/// Columns occupied by `cp` on a typical xterm-256 grid.
pub fn columns(cp: u21) u8 {
    if (cp == 0 or cp < 0x20 or cp == 0x7F) return 0;
    if (isWide(cp)) return 2;
    return 1;
}

pub fn isWide(cp: u21) bool {
    // Hangul Jamo
    if (cp >= 0x1100 and cp <= 0x115F) return true;
    if (cp >= 0x2329 and cp <= 0x232A) return true;
    // CJK punctuation / kana / hangul / ideographs (common ranges)
    if (cp >= 0x2E80 and cp <= 0xA4CF) return cp != 0x303F;
    if (cp >= 0xAC00 and cp <= 0xD7A3) return true;
    if (cp >= 0xF900 and cp <= 0xFAFF) return true;
    if (cp >= 0xFE10 and cp <= 0xFE19) return true;
    if (cp >= 0xFE30 and cp <= 0xFE6F) return true;
    if (cp >= 0xFF00 and cp <= 0xFF60) return true;
    if (cp >= 0xFFE0 and cp <= 0xFFE6) return true;
    // CJK Unified Ideographs Extension A / B (partial)
    if (cp >= 0x20000 and cp <= 0x2FFFD) return true;
    if (cp >= 0x30000 and cp <= 0x3FFFD) return true;
    // Emoji (presentation) — treat as double-width in the grid
    if (cp >= 0x1F300 and cp <= 0x1FAFF) return true;
    if (cp >= 0x1F600 and cp <= 0x1F64F) return true;
    if (cp >= 0x2600 and cp <= 0x27BF) {
        return switch (cp) {
            0x2600...0x26FF, 0x2700...0x27BF => true,
            else => false,
        };
    }
    return false;
}

pub fn isBoxDrawing(cp: u21) bool {
    return (cp >= 0x2500 and cp <= 0x257F) or (cp >= 0x2580 and cp <= 0x259F);
}

/// Continuation cell after a wide glyph (not independently selected as text).
pub const wide_cont: u21 = 0;
