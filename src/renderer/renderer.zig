const std = @import("std");
const c = @import("../c.zig").c;
const Screen = @import("../terminal/screen.zig").Screen;
const Selection = @import("../terminal/selection.zig").Selection;
const Color = @import("../terminal/cell.zig").Color;
const bitmap = @import("../font/bitmap.zig");
const theme_mod = @import("../config/theme.zig");

pub const Renderer = struct {
    program: c.GLuint = 0,
    vao: c.GLuint = 0,
    vbo: c.GLuint = 0,
    atlas_tex: c.GLuint = 0,
    atlas_w: f32 = 0,
    atlas_h: f32 = 0,
    cell_w: f32 = @floatFromInt(bitmap.glyph_width),
    cell_h: f32 = @floatFromInt(bitmap.glyph_height),
    fb_w: i32 = 0,
    fb_h: i32 = 0,
    vertices: std.ArrayList(f32) = .empty,
    allocator: std.mem.Allocator,
    theme: theme_mod.Theme = theme_mod.orbit_dark,
    opacity: f32 = 1.0,

    // Vertex: x y u v r g b a  (8 floats) — mode via a: 1=glyph, 0=solid
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
        \\out vec4 out_color;
        \\void main() {
        \\  if (v_uv.x < 0.0) {
        \\    // solid rect (background / cursor / selection)
        \\    out_color = v_color;
        \\  } else {
        \\    float a = texture(u_atlas, v_uv).a;
        \\    if (a < 0.1) discard;
        \\    out_color = vec4(v_color.rgb, v_color.a * a);
        \\  }
        \\}
    ;

    pub fn init(allocator: std.mem.Allocator) !Renderer {
        var self: Renderer = .{ .allocator = allocator };
        try self.initGl();
        return self;
    }

    pub fn deinit(self: *Renderer) void {
        self.vertices.deinit(self.allocator);
        if (self.atlas_tex != 0) c.glDeleteTextures(1, &self.atlas_tex);
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

        const aw = bitmap.atlasWidth();
        const ah = bitmap.atlasHeight();
        self.atlas_w = @floatFromInt(aw);
        self.atlas_h = @floatFromInt(ah);

        const atlas = try self.allocator.alloc(u8, aw * ah * 4);
        defer self.allocator.free(atlas);
        bitmap.buildAtlas(atlas);

        c.glGenTextures(1, &self.atlas_tex);
        c.glBindTexture(c.GL_TEXTURE_2D, self.atlas_tex);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, c.GL_NEAREST);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, c.GL_NEAREST);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_S, c.GL_CLAMP_TO_EDGE);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_T, c.GL_CLAMP_TO_EDGE);
        c.glPixelStorei(c.GL_UNPACK_ALIGNMENT, 1);
        c.glTexImage2D(
            c.GL_TEXTURE_2D,
            0,
            c.GL_RGBA,
            @intCast(aw),
            @intCast(ah),
            0,
            c.GL_RGBA,
            c.GL_UNSIGNED_BYTE,
            atlas.ptr,
        );

        c.glEnable(c.GL_BLEND);
        c.glBlendFunc(c.GL_SRC_ALPHA, c.GL_ONE_MINUS_SRC_ALPHA);
    }

    pub fn setFramebufferSize(self: *Renderer, w: i32, h: i32) void {
        self.fb_w = w;
        self.fb_h = h;
        c.glViewport(0, 0, w, h);
    }

    pub fn setTheme(self: *Renderer, theme: theme_mod.Theme) void {
        self.theme = theme;
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

    /// Draw a screen into a pixel rect (origin top-left of framebuffer).
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
        if (self.fb_w <= 0 or self.fb_h <= 0) return;

        self.vertices.clearRetainingCapacity();

        const fw: f32 = @floatFromInt(self.fb_w);
        const fh: f32 = @floatFromInt(self.fb_h);
        const cell_w = self.cell_w;
        const cell_h = self.cell_h;
        const glyph_count: f32 = @floatFromInt(bitmap.last_codepoint - bitmap.first_codepoint + 1);
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

                // Background quad (uv.x < 0 => solid)
                try self.appendSolid(ox, oy, fw, fh, col, row, cell_w, cell_h, bg, self.opacity);

                const cp = cell.codepoint;
                if (cp < bitmap.first_codepoint or cp > bitmap.last_codepoint) continue;
                if (cp == ' ') continue;

                const gi: f32 = @floatFromInt(cp - bitmap.first_codepoint);
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

        // Cursor
        if (screen.cursor_visible and screen.view_offset == 0) {
            try self.appendSolid(
                ox,
                oy,
                fw,
                fh,
                screen.cursor_col,
                screen.cursor_row,
                cell_w,
                cell_h,
                self.theme.cursor,
                0.55,
            );
        }

        try self.flush();
    }

    /// Simple filled bar for tab UI / search chrome.
    pub fn drawRect(self: *Renderer, x: i32, y: i32, w: i32, h: i32, color: Color, alpha: f32) !void {
        self.vertices.clearRetainingCapacity();
        const fw: f32 = @floatFromInt(self.fb_w);
        const fh: f32 = @floatFromInt(self.fb_h);
        try self.appendPixelRect(fw, fh, @floatFromInt(x), @floatFromInt(y), @floatFromInt(w), @floatFromInt(h), color, alpha);
        try self.flush();
    }

    pub fn drawText(self: *Renderer, x: i32, y: i32, text: []const u8, color: Color) !void {
        self.vertices.clearRetainingCapacity();
        const fw: f32 = @floatFromInt(self.fb_w);
        const fh: f32 = @floatFromInt(self.fb_h);
        const glyph_count: f32 = @floatFromInt(bitmap.last_codepoint - bitmap.first_codepoint + 1);
        var i: usize = 0;
        while (i < text.len) : (i += 1) {
            const cp: u21 = text[i];
            if (cp < bitmap.first_codepoint or cp > bitmap.last_codepoint) continue;
            const gi: f32 = @floatFromInt(cp - bitmap.first_codepoint);
            const uv_left = gi / glyph_count;
            const uv_right = (gi + 1.0) / glyph_count;
            const px = @as(f32, @floatFromInt(x)) + @as(f32, @floatFromInt(i)) * self.cell_w;
            const py = @as(f32, @floatFromInt(y));
            try self.appendGlyphPx(fw, fh, px, py, self.cell_w, self.cell_h, uv_left, uv_right, color);
        }
        try self.flush();
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
        // uv.x = -1 marks solid
        try self.vertices.appendSlice(self.allocator, &.{
            nx0, ny0, -1, 0, r, g, b, alpha,
            nx1, ny0, -1, 0, r, g, b, alpha,
            nx0, ny1, -1, 0, r, g, b, alpha,
            nx1, ny0, -1, 0, r, g, b, alpha,
            nx1, ny1, -1, 0, r, g, b, alpha,
            nx0, ny1, -1, 0, r, g, b, alpha,
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
        const y0 = oy + @as(f32, @floatFromInt(row)) * cell_h;
        try self.appendGlyphPx(fw, fh, x0, y0, cell_w, cell_h, uv_left, uv_right, color);
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
        if (self.vertices.items.len == 0) return;
        c.glUseProgram(self.program);
        c.glActiveTexture(c.GL_TEXTURE0);
        c.glBindTexture(c.GL_TEXTURE_2D, self.atlas_tex);
        const loc_atlas = c.glGetUniformLocation(self.program, "u_atlas");
        c.glUniform1i(loc_atlas, 0);

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
