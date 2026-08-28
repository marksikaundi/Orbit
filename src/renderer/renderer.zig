const std = @import("std");
const c = @import("../c.zig").c;
const Screen = @import("../terminal/screen.zig").Screen;
const Selection = @import("../terminal/selection.zig").Selection;
const Color = @import("../terminal/cell.zig").Color;
const atlas_mod = @import("../font/atlas.zig");
const faces = @import("../font/faces.zig");
const theme_mod = @import("../config/theme.zig");
const CursorStyle = @import("../config/config.zig").CursorStyle;

const logo_png = @embedFile("../platform/orbit-icon-256.png");

extern fn stbi_load_from_memory(
    buffer: [*]const u8,
    len: c_int,
    x: *c_int,
    y: *c_int,
    channels_in_file: *c_int,
    desired_channels: c_int,
) ?[*]u8;
extern fn stbi_image_free(retval_from_stbi_load: ?*anyopaque) void;

pub const Renderer = struct {
    program: c.GLuint = 0,
    vao: c.GLuint = 0,
    vbo: c.GLuint = 0,
    atlas_tex: c.GLuint = 0,
    logo_tex: c.GLuint = 0,
    logo_px: i32 = 0,
    atlas: ?atlas_mod.Atlas = null,
    cell_w: f32 = 8,
    cell_h: f32 = 16,
    /// Logical point size (Ghostty-style). Scaled by content_scale for Retina.
    font_size: f32 = 14.0,
    /// Face id from `font/faces.zig` (e.g. "menlo", "sf-mono").
    font_face: []const u8 = "sf-mono",
    content_scale: f32 = 2.0,
    fb_w: i32 = 0,
    fb_h: i32 = 0,
    vertices: std.ArrayList(f32) = .empty,
    allocator: std.mem.Allocator,
    theme: theme_mod.Theme = theme_mod.orbit_dark,
    opacity: f32 = 1.0,
    /// Extra vertical cell space (Ghostty adjust-cell-height). 1.0 = font metrics.
    line_height: f32 = 1.0,
    /// Unscaled glyph height from the atlas (glyphs stay crisp when line_height > 1).
    glyph_h: f32 = 16,
    cursor_style: CursorStyle = .block,
    cursor_blink: bool = true,
    /// Frame counter for cursor blink (incremented each draw).
    frame_tick: u64 = 0,

    // Vertex: x y u v r g b a  (8 floats)
    const vert_src =
        \\#version 330 core
        \\layout(location = 0) in vec2 a_pos;
        \\layout(location = 1) in vec2 a_uv;
        \\layout(location = 2) in vec4 a_color;
        \\out vec2 v_uv;
        \\out vec4 v_color;
        \\void main() {
        \\  gl_Position = vec4(a_pos, 0.0, 1.0);
        \\  v_uv = a_uv;
        \\  v_color = a_color;
        \\}
    ;

    const frag_src =
        \\#version 330 core
        \\in vec2 v_uv;
        \\in vec4 v_color;
        \\uniform sampler2D u_atlas;
        \\uniform int u_tex_mode;
        \\out vec4 out_color;
        \\void main() {
        \\  if (v_uv.x < 0.0) {
        \\    out_color = v_color;
        \\  } else if (u_tex_mode == 1) {
        \\    vec4 t = texture(u_atlas, v_uv);
        \\    out_color = t * v_color;
        \\    if (out_color.a < 0.02) discard;
        \\  } else {
        \\    float a = texture(u_atlas, v_uv).a;
        \\    if (a < 0.02) discard;
        \\    out_color = vec4(v_color.rgb, v_color.a * a);
        \\  }
        \\}
    ;

    pub fn init(allocator: std.mem.Allocator) !Renderer {
        var self: Renderer = .{ .allocator = allocator };
        try self.initGl();
        try self.rebuildAtlas();
        self.loadLogo();
        return self;
    }

    pub fn deinit(self: *Renderer) void {
        self.vertices.deinit(self.allocator);
        if (self.atlas) |*a| a.deinit();
        if (self.atlas_tex != 0) c.glDeleteTextures(1, &self.atlas_tex);
        if (self.logo_tex != 0) c.glDeleteTextures(1, &self.logo_tex);
        if (self.vbo != 0) c.glDeleteBuffers(1, &self.vbo);
        if (self.vao != 0) c.glDeleteVertexArrays(1, &self.vao);
        if (self.program != 0) c.glDeleteProgram(self.program);
        self.* = undefined;
    }

    fn initGl(self: *Renderer) !void {
        self.program = try compileProgram(vert_src, frag_src);

        c.glGenVertexArrays(1, &self.vao);
        c.glGenBuffers(1, &self.vbo);
        c.glBindVertexArray(self.vao);
        c.glBindBuffer(c.GL_ARRAY_BUFFER, self.vbo);
        const stride: c.GLsizei = 8 * @sizeOf(f32);
        c.glEnableVertexAttribArray(0);
        c.glVertexAttribPointer(0, 2, c.GL_FLOAT, c.GL_FALSE, stride, null);
        c.glEnableVertexAttribArray(1);
        c.glVertexAttribPointer(1, 2, c.GL_FLOAT, c.GL_FALSE, stride, @ptrFromInt(2 * @sizeOf(f32)));
        c.glEnableVertexAttribArray(2);
        c.glVertexAttribPointer(2, 4, c.GL_FLOAT, c.GL_FALSE, stride, @ptrFromInt(4 * @sizeOf(f32)));
        c.glBindVertexArray(0);

        c.glGenTextures(1, &self.atlas_tex);
        c.glEnable(c.GL_BLEND);
        c.glBlendFunc(c.GL_SRC_ALPHA, c.GL_ONE_MINUS_SRC_ALPHA);
    }

    pub fn rebuildAtlas(self: *Renderer) !void {
        const px: u32 = @intFromFloat(@round(@max(10.0, self.font_size * self.content_scale)));
        const path = faces.pathForId(self.font_face);
        const new_atlas = try atlas_mod.Atlas.create(self.allocator, px, path);
        if (self.atlas) |*old| old.deinit();
        self.atlas = new_atlas;
        self.cell_w = @floatFromInt(new_atlas.cell_w);
        self.glyph_h = @floatFromInt(new_atlas.cell_h);
        self.cell_h = self.glyph_h * @max(1.0, self.line_height);
        self.uploadAtlas();
    }

    fn uploadAtlas(self: *Renderer) void {
        const a = self.atlas orelse return;
        c.glBindTexture(c.GL_TEXTURE_2D, self.atlas_tex);
        // NEAREST keeps terminal cells crisp; scaled UI temporarily switches to LINEAR.
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, c.GL_NEAREST);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, c.GL_NEAREST);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_S, c.GL_CLAMP_TO_EDGE);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_T, c.GL_CLAMP_TO_EDGE);
        c.glPixelStorei(c.GL_UNPACK_ALIGNMENT, 1);
        c.glTexImage2D(
            c.GL_TEXTURE_2D,
            0,
            c.GL_RGBA,
            @intCast(a.width),
            @intCast(a.height),
            0,
            c.GL_RGBA,
            c.GL_UNSIGNED_BYTE,
            a.rgba.ptr,
        );
    }

    pub fn setFramebufferSize(self: *Renderer, w: i32, h: i32) void {
        self.fb_w = w;
        self.fb_h = h;
        c.glViewport(0, 0, w, h);
    }

    pub fn setContentScale(self: *Renderer, scale: f32) void {
        const s = @max(1.0, scale);
        if (@abs(s - self.content_scale) < 0.01) return;
        self.content_scale = s;
        self.rebuildAtlas() catch {};
    }

    pub fn setTheme(self: *Renderer, theme: theme_mod.Theme) void {
        self.theme = theme;
    }

    pub fn setFontSize(self: *Renderer, size: f32) void {
        self.font_size = @min(28.0, @max(9.0, size));
        self.rebuildAtlas() catch {};
    }

    pub fn setFontFace(self: *Renderer, face_id: []const u8) void {
        self.font_face = face_id;
        self.rebuildAtlas() catch {};
    }

    pub fn setLineHeight(self: *Renderer, height: f32) void {
        self.line_height = @min(1.5, @max(1.0, height));
        if (self.glyph_h > 0) {
            self.cell_h = self.glyph_h * self.line_height;
        }
    }

    pub fn bumpFontSize(self: *Renderer, delta: f32) void {
        self.setFontSize(self.font_size + delta);
    }

    /// Back-compat with older font_scale config (2.0 ≈ 14pt).
    pub fn setFontScale(self: *Renderer, scale: f32) void {
        self.setFontSize(14.0 * scale / 2.0);
    }

    pub fn bumpFontScale(self: *Renderer, delta: f32) void {
        // Map old ±0.25 scale steps to ±1pt.
        const pts = if (delta > 0) 1.0 else -1.0;
        self.bumpFontSize(pts);
    }

    pub fn clearBackground(self: *Renderer) void {
        const bg = self.theme.background;
        const a = self.opacity;
        c.glClearColor(
            @as(f32, @floatFromInt(bg.r)) / 255.0,
            @as(f32, @floatFromInt(bg.g)) / 255.0,
            @as(f32, @floatFromInt(bg.b)) / 255.0,
            a,
        );
        c.glClear(c.GL_COLOR_BUFFER_BIT);
    }

    pub fn drawScreen(
        self: *Renderer,
        screen: *const Screen,
        selection: *const Selection,
        origin_x: i32,
        origin_y: i32,
        highlight_row: ?u16,
        highlight_col: ?u16,
        highlight_len: u16,
    ) !void {
        self.vertices.clearRetainingCapacity();
        const fw: f32 = @floatFromInt(self.fb_w);
        const fh: f32 = @floatFromInt(self.fb_h);
        const cell_w = self.cell_w;
        const cell_h = self.cell_h;
        const glyph_count: f32 = @floatFromInt(atlas_mod.glyph_count);
        const ox: f32 = @floatFromInt(origin_x);
        const oy: f32 = @floatFromInt(origin_y);

        var row: u16 = 0;
        while (row < screen.rows) : (row += 1) {
            var col: u16 = 0;
            while (col < screen.cols) : (col += 1) {
                const cell = screen.visibleCell(col, row);
                var bg = cell.bg;
                if (selection.contains(col, row)) {
                    bg = self.theme.selection_bg;
                }
                if (highlight_row) |hr| {
                    if (hr == row) {
                        if (highlight_col) |hc| {
                            if (col >= hc and col < hc + highlight_len) {
                                bg = Color.rgb(180, 140, 40);
                            }
                        }
                    }
                }

                try self.appendSolid(ox, oy, fw, fh, col, row, cell_w, cell_h, bg, self.opacity);

                const cp = cell.codepoint;
                if (cp < atlas_mod.first_codepoint or cp > atlas_mod.last_codepoint) continue;
                if (cp == ' ') continue;

                const gi: f32 = @floatFromInt(cp - atlas_mod.first_codepoint);
                const uv_left = gi / glyph_count;
                const uv_right = (gi + 1.0) / glyph_count;

                var fg = cell.fg;
                if (cell.attrs.bold) {
                    fg = Color.rgb(
                        @min(255, fg.r +| 20),
                        @min(255, fg.g +| 20),
                        @min(255, fg.b +| 20),
                    );
                }
                try self.appendGlyph(ox, oy, fw, fh, col, row, cell_w, cell_h, uv_left, uv_right, fg);
            }
        }

        self.frame_tick +%= 1;
        if (screen.cursor_visible and screen.view_offset == 0) {
            // ~530ms at 60fps
            const blink_on = if (self.cursor_blink)
                ((self.frame_tick / 32) % 2) == 0
            else
                true;
            if (blink_on) {
                try self.appendCursor(
                    ox,
                    oy,
                    fw,
                    fh,
                    screen.cursor_col,
                    screen.cursor_row,
                    cell_w,
                    cell_h,
                    self.theme.cursor,
                );
            }
        }

        try self.flush();
    }

    fn appendCursor(
        self: *Renderer,
        ox: f32,
        oy: f32,
        fw: f32,
        fh: f32,
        col: u16,
        row: u16,
        cell_w: f32,
        cell_h: f32,
        color: Color,
    ) !void {
        const x0 = ox + @as(f32, @floatFromInt(col)) * cell_w;
        const y0 = oy + @as(f32, @floatFromInt(row)) * cell_h;
        switch (self.cursor_style) {
            .block => try self.appendPixelRect(fw, fh, x0, y0, cell_w, cell_h, color, 0.9),
            .underline => {
                const h = @max(2.0, cell_h * 0.12);
                try self.appendPixelRect(fw, fh, x0, y0 + cell_h - h, cell_w, h, color, 1.0);
            },
            .bar => {
                const w = @max(2.0, cell_w * 0.15);
                try self.appendPixelRect(fw, fh, x0, y0, w, cell_h, color, 1.0);
            },
        }
    }

    pub fn drawRect(self: *Renderer, x: i32, y: i32, w: i32, h: i32, color: Color, alpha: f32) !void {
        self.vertices.clearRetainingCapacity();
        const fw: f32 = @floatFromInt(self.fb_w);
        const fh: f32 = @floatFromInt(self.fb_h);
        try self.appendPixelRect(fw, fh, @floatFromInt(x), @floatFromInt(y), @floatFromInt(w), @floatFromInt(h), color, alpha);
        try self.flush();
    }

    /// Powerline-style parallelogram: both vertical edges slant by `slant` px.
    /// Shape: top runs (x+slant..x+w), bottom runs (x..x+w-slant).
    pub fn drawSlantRect(self: *Renderer, x: i32, y: i32, w: i32, h: i32, slant: i32, color: Color, alpha: f32) !void {
        if (w <= 0 or h <= 0) return;
        const s = @min(slant, @divTrunc(w, 2));
        self.vertices.clearRetainingCapacity();
        const fw: f32 = @floatFromInt(self.fb_w);
        const fh: f32 = @floatFromInt(self.fb_h);
        try self.appendPixelParallelogram(
            fw,
            fh,
            @floatFromInt(x + s),
            @floatFromInt(y),
            @floatFromInt(x + w),
            @floatFromInt(y),
            @floatFromInt(x + w - s),
            @floatFromInt(y + h),
            @floatFromInt(x),
            @floatFromInt(y + h),
            color,
            alpha,
        );
        try self.flush();
    }

    pub fn drawText(self: *Renderer, x: i32, y: i32, text: []const u8, color: Color) !void {
        try self.drawTextScaled(x, y, text, color, 1.0);
    }

    /// Draw UI text at `scale` × cell size. Uses LINEAR when scaled so glyphs stay smooth.
    pub fn drawTextScaled(self: *Renderer, x: i32, y: i32, text: []const u8, color: Color, scale: f32) !void {
        const s = @max(0.5, scale);
        const use_linear = @abs(s - 1.0) > 0.02;
        if (use_linear and self.atlas_tex != 0) {
            c.glBindTexture(c.GL_TEXTURE_2D, self.atlas_tex);
            c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, c.GL_LINEAR);
            c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, c.GL_LINEAR);
        }
        defer if (use_linear and self.atlas_tex != 0) {
            c.glBindTexture(c.GL_TEXTURE_2D, self.atlas_tex);
            c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, c.GL_NEAREST);
            c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, c.GL_NEAREST);
        };

        self.vertices.clearRetainingCapacity();
        const fw: f32 = @floatFromInt(self.fb_w);
        const fh: f32 = @floatFromInt(self.fb_h);
        const glyph_count: f32 = @floatFromInt(atlas_mod.glyph_count);
        const cw = self.cell_w * s;
        const ch = @max(1.0, self.glyph_h) * s;
        var i: usize = 0;
        while (i < text.len) : (i += 1) {
            const cp: u21 = text[i];
            if (cp < atlas_mod.first_codepoint or cp > atlas_mod.last_codepoint) continue;
            const gi: f32 = @floatFromInt(cp - atlas_mod.first_codepoint);
            const uv_left = gi / glyph_count;
            const uv_right = (gi + 1.0) / glyph_count;
            const px = @as(f32, @floatFromInt(x)) + @as(f32, @floatFromInt(i)) * cw;
            const py = @as(f32, @floatFromInt(y));
            try self.appendGlyphPx(fw, fh, px, py, cw, ch, uv_left, uv_right, color);
        }
        try self.flushMode(self.atlas_tex, 0);
    }

    /// Draw the embedded Orbit logo centered at `(cx, y)` with side length `size`.
    pub fn drawLogo(self: *Renderer, cx: i32, y: i32, size: i32) !void {
        if (self.logo_tex == 0 or size <= 0) return;
        const side = @max(16, size);
        const x = cx - @divTrunc(side, 2);
        try self.drawTexture(self.logo_tex, x, y, side, side);
    }

    pub fn drawTexture(self: *Renderer, tex: c.GLuint, x: i32, y: i32, w: i32, h: i32) !void {
        if (tex == 0 or w <= 0 or h <= 0) return;
        self.vertices.clearRetainingCapacity();
        const fw: f32 = @floatFromInt(self.fb_w);
        const fh: f32 = @floatFromInt(self.fb_h);
        const x0: f32 = @floatFromInt(x);
        const y0: f32 = @floatFromInt(y);
        const x1 = x0 + @as(f32, @floatFromInt(w));
        const y1 = y0 + @as(f32, @floatFromInt(h));
        // Flip V — stb loads top-down, GL samples bottom-up.
        const nx0 = (x0 / fw) * 2.0 - 1.0;
        const nx1 = (x1 / fw) * 2.0 - 1.0;
        const ny0 = 1.0 - (y0 / fh) * 2.0;
        const ny1 = 1.0 - (y1 / fh) * 2.0;
        try self.vertices.appendSlice(self.allocator, &.{
            nx0, ny0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0,
            nx1, ny0, 1.0, 0.0, 1.0, 1.0, 1.0, 1.0,
            nx0, ny1, 0.0, 1.0, 1.0, 1.0, 1.0, 1.0,
            nx1, ny0, 1.0, 0.0, 1.0, 1.0, 1.0, 1.0,
            nx1, ny1, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0,
            nx0, ny1, 0.0, 1.0, 1.0, 1.0, 1.0, 1.0,
        });
        try self.flushMode(tex, 1);
    }

    fn loadLogo(self: *Renderer) void {
        var w: c_int = 0;
        var h: c_int = 0;
        var channels: c_int = 0;
        const pixels = stbi_load_from_memory(
            logo_png.ptr,
            @intCast(logo_png.len),
            &w,
            &h,
            &channels,
            4,
        ) orelse {
            std.log.warn("home logo: failed to decode PNG", .{});
            return;
        };
        defer stbi_image_free(pixels);

        var tex: c.GLuint = 0;
        c.glGenTextures(1, &tex);
        c.glBindTexture(c.GL_TEXTURE_2D, tex);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, c.GL_LINEAR);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, c.GL_LINEAR);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_S, c.GL_CLAMP_TO_EDGE);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_T, c.GL_CLAMP_TO_EDGE);
        c.glPixelStorei(c.GL_UNPACK_ALIGNMENT, 1);
        c.glTexImage2D(
            c.GL_TEXTURE_2D,
            0,
            c.GL_RGBA,
            w,
            h,
            0,
            c.GL_RGBA,
            c.GL_UNSIGNED_BYTE,
            pixels,
        );
        c.glBindTexture(c.GL_TEXTURE_2D, 0);
        self.logo_tex = tex;
        self.logo_px = w;
    }

    fn appendSolid(
        self: *Renderer,
        ox: f32,
        oy: f32,
        fw: f32,
        fh: f32,
        col: u16,
        row: u16,
        cell_w: f32,
        cell_h: f32,
        color: Color,
        alpha: f32,
    ) !void {
        const x0 = ox + @as(f32, @floatFromInt(col)) * cell_w;
        const y0 = oy + @as(f32, @floatFromInt(row)) * cell_h;
        try self.appendPixelRect(fw, fh, x0, y0, cell_w, cell_h, color, alpha);
    }

    fn appendPixelRect(self: *Renderer, fw: f32, fh: f32, x0: f32, y0: f32, w: f32, h: f32, color: Color, alpha: f32) !void {
        const x1 = x0 + w;
        const y1 = y0 + h;
        const nx0 = (x0 / fw) * 2.0 - 1.0;
        const nx1 = (x1 / fw) * 2.0 - 1.0;
        const ny0 = 1.0 - (y0 / fh) * 2.0;
        const ny1 = 1.0 - (y1 / fh) * 2.0;
        const r = @as(f32, @floatFromInt(color.r)) / 255.0;
        const g = @as(f32, @floatFromInt(color.g)) / 255.0;
        const b = @as(f32, @floatFromInt(color.b)) / 255.0;
        try self.vertices.appendSlice(self.allocator, &.{
            nx0, ny0, -1, 0, r, g, b, alpha,
            nx1, ny0, -1, 0, r, g, b, alpha,
            nx0, ny1, -1, 0, r, g, b, alpha,
            nx1, ny0, -1, 0, r, g, b, alpha,
            nx1, ny1, -1, 0, r, g, b, alpha,
            nx0, ny1, -1, 0, r, g, b, alpha,
        });
    }

    fn appendPixelParallelogram(
        self: *Renderer,
        fw: f32,
        fh: f32,
        x_tl: f32,
        y_tl: f32,
        x_tr: f32,
        y_tr: f32,
        x_br: f32,
        y_br: f32,
        x_bl: f32,
        y_bl: f32,
        color: Color,
        alpha: f32,
    ) !void {
        const toNdcX = struct {
            fn f(px: f32, width: f32) f32 {
                return (px / width) * 2.0 - 1.0;
            }
        }.f;
        const toNdcY = struct {
            fn f(py: f32, height: f32) f32 {
                return 1.0 - (py / height) * 2.0;
            }
        }.f;
        const r = @as(f32, @floatFromInt(color.r)) / 255.0;
        const g = @as(f32, @floatFromInt(color.g)) / 255.0;
        const b = @as(f32, @floatFromInt(color.b)) / 255.0;
        const nx_tl = toNdcX(x_tl, fw);
        const ny_tl = toNdcY(y_tl, fh);
        const nx_tr = toNdcX(x_tr, fw);
        const ny_tr = toNdcY(y_tr, fh);
        const nx_br = toNdcX(x_br, fw);
        const ny_br = toNdcY(y_br, fh);
        const nx_bl = toNdcX(x_bl, fw);
        const ny_bl = toNdcY(y_bl, fh);
        try self.vertices.appendSlice(self.allocator, &.{
            nx_tl, ny_tl, -1, 0, r, g, b, alpha,
            nx_tr, ny_tr, -1, 0, r, g, b, alpha,
            nx_bl, ny_bl, -1, 0, r, g, b, alpha,
            nx_tr, ny_tr, -1, 0, r, g, b, alpha,
            nx_br, ny_br, -1, 0, r, g, b, alpha,
            nx_bl, ny_bl, -1, 0, r, g, b, alpha,
        });
    }

    fn appendGlyph(
        self: *Renderer,
        ox: f32,
        oy: f32,
        fw: f32,
        fh: f32,
        col: u16,
        row: u16,
        cell_w: f32,
        cell_h: f32,
        uv_left: f32,
        uv_right: f32,
        color: Color,
    ) !void {
        const x0 = ox + @as(f32, @floatFromInt(col)) * cell_w;
        const extra = cell_h - self.glyph_h;
        const y0 = oy + @as(f32, @floatFromInt(row)) * cell_h + extra * 0.5;
        try self.appendGlyphPx(fw, fh, x0, y0, cell_w, self.glyph_h, uv_left, uv_right, color);
    }

    fn appendGlyphPx(
        self: *Renderer,
        fw: f32,
        fh: f32,
        x0: f32,
        y0: f32,
        cell_w: f32,
        cell_h: f32,
        uv_left: f32,
        uv_right: f32,
        color: Color,
    ) !void {
        const x1 = x0 + cell_w;
        const y1 = y0 + cell_h;
        const nx0 = (x0 / fw) * 2.0 - 1.0;
        const nx1 = (x1 / fw) * 2.0 - 1.0;
        const ny0 = 1.0 - (y0 / fh) * 2.0;
        const ny1 = 1.0 - (y1 / fh) * 2.0;
        const r = @as(f32, @floatFromInt(color.r)) / 255.0;
        const g = @as(f32, @floatFromInt(color.g)) / 255.0;
        const b = @as(f32, @floatFromInt(color.b)) / 255.0;
        try self.vertices.appendSlice(self.allocator, &.{
            nx0, ny0, uv_left, 0.0, r, g, b, 1.0,
            nx1, ny0, uv_right, 0.0, r, g, b, 1.0,
            nx0, ny1, uv_left, 1.0, r, g, b, 1.0,
            nx1, ny0, uv_right, 0.0, r, g, b, 1.0,
            nx1, ny1, uv_right, 1.0, r, g, b, 1.0,
            nx0, ny1, uv_left, 1.0, r, g, b, 1.0,
        });
    }

    fn flush(self: *Renderer) !void {
        try self.flushMode(self.atlas_tex, 0);
    }

    fn flushMode(self: *Renderer, tex: c.GLuint, mode: c_int) !void {
        if (self.vertices.items.len == 0) return;
        c.glUseProgram(self.program);
        c.glActiveTexture(c.GL_TEXTURE0);
        c.glBindTexture(c.GL_TEXTURE_2D, tex);
        const loc_atlas = c.glGetUniformLocation(self.program, "u_atlas");
        c.glUniform1i(loc_atlas, 0);
        const loc_mode = c.glGetUniformLocation(self.program, "u_tex_mode");
        if (loc_mode >= 0) c.glUniform1i(loc_mode, mode);

        c.glBindVertexArray(self.vao);
        c.glBindBuffer(c.GL_ARRAY_BUFFER, self.vbo);
        c.glBufferData(
            c.GL_ARRAY_BUFFER,
            @intCast(self.vertices.items.len * @sizeOf(f32)),
            self.vertices.items.ptr,
            c.GL_STREAM_DRAW,
        );
        const count: c.GLsizei = @intCast(self.vertices.items.len / 8);
        c.glDrawArrays(c.GL_TRIANGLES, 0, count);
        c.glBindVertexArray(0);
    }
};

fn compileProgram(vert_src: [:0]const u8, frag_src: [:0]const u8) !c.GLuint {
    const vs = try compileShader(c.GL_VERTEX_SHADER, vert_src);
    defer c.glDeleteShader(vs);
    const fs = try compileShader(c.GL_FRAGMENT_SHADER, frag_src);
    defer c.glDeleteShader(fs);

    const program = c.glCreateProgram();
    c.glAttachShader(program, vs);
    c.glAttachShader(program, fs);
    c.glLinkProgram(program);

    var ok: c.GLint = 0;
    c.glGetProgramiv(program, c.GL_LINK_STATUS, &ok);
    if (ok == c.GL_FALSE) {
        var log_len: c.GLint = 0;
        c.glGetProgramiv(program, c.GL_INFO_LOG_LENGTH, &log_len);
        var buf: [1024]u8 = undefined;
        c.glGetProgramInfoLog(program, @min(log_len, buf.len), null, &buf);
        std.log.err("shader link: {s}", .{buf[0..@intCast(@min(log_len, buf.len))]});
        return error.ShaderLinkFailed;
    }
    return program;
}

fn compileShader(kind: c.GLenum, source: [:0]const u8) !c.GLuint {
    const shader = c.glCreateShader(kind);
    const ptr: [*c]const u8 = source.ptr;
    c.glShaderSource(shader, 1, &ptr, null);
    c.glCompileShader(shader);

    var ok: c.GLint = 0;
    c.glGetShaderiv(shader, c.GL_COMPILE_STATUS, &ok);
    if (ok == c.GL_FALSE) {
        var log_len: c.GLint = 0;
        c.glGetShaderiv(shader, c.GL_INFO_LOG_LENGTH, &log_len);
        var buf: [1024]u8 = undefined;
        c.glGetShaderInfoLog(shader, @min(log_len, buf.len), null, &buf);
        std.log.err("shader compile: {s}", .{buf[0..@intCast(@min(log_len, buf.len))]});
        return error.ShaderCompileFailed;
    }
    return shader;
}
