const std = @import("std");
const c = @import("../c.zig").c;
const Screen = @import("../terminal/screen.zig").Screen;
const bitmap = @import("../font/bitmap.zig");

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

    const vert_src =
        \\#version 330 core
        \\layout(location = 0) in vec2 a_pos;
        \\layout(location = 1) in vec2 a_uv;
        \\out vec2 v_uv;
        \\void main() {
        \\  gl_Position = vec4(a_pos, 0.0, 1.0);
        \\  v_uv = a_uv;
        \\}
    ;

    const frag_src =
        \\#version 330 core
        \\in vec2 v_uv;
        \\uniform sampler2D u_atlas;
        \\uniform vec3 u_fg;
        \\out vec4 out_color;
        \\void main() {
        \\  float a = texture(u_atlas, v_uv).a;
        \\  if (a < 0.1) discard;
        \\  out_color = vec4(u_fg, 1.0);
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
        c.glEnableVertexAttribArray(0);
        c.glVertexAttribPointer(0, 2, c.GL_FLOAT, c.GL_FALSE, 4 * @sizeOf(f32), null);
        c.glEnableVertexAttribArray(1);
        c.glVertexAttribPointer(1, 2, c.GL_FLOAT, c.GL_FALSE, 4 * @sizeOf(f32), @ptrFromInt(2 * @sizeOf(f32)));
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
    }

    pub fn setFramebufferSize(self: *Renderer, w: i32, h: i32) void {
        self.fb_w = w;
        self.fb_h = h;
        c.glViewport(0, 0, w, h);
    }

    pub fn draw(self: *Renderer, screen: *const Screen) !void {
        c.glClearColor(0.07, 0.08, 0.10, 1.0);
        c.glClear(c.GL_COLOR_BUFFER_BIT);

        if (self.fb_w <= 0 or self.fb_h <= 0) return;

        self.vertices.clearRetainingCapacity();

        const fw: f32 = @floatFromInt(self.fb_w);
        const fh: f32 = @floatFromInt(self.fb_h);
        const cell_w = self.cell_w;
        const cell_h = self.cell_h;
        const glyph_count: f32 = @floatFromInt(bitmap.last_codepoint - bitmap.first_codepoint + 1);

        var row: u16 = 0;
        while (row < screen.rows) : (row += 1) {
            var col: u16 = 0;
            while (col < screen.cols) : (col += 1) {
                const cell = screen.cellAtConst(col, row);
                const cp = cell.codepoint;
                if (cp < bitmap.first_codepoint or cp > bitmap.last_codepoint) continue;
                if (cp == ' ') continue;

                const gi: f32 = @floatFromInt(cp - bitmap.first_codepoint);
                const uv_left = gi / glyph_count;
                const uv_right = (gi + 1.0) / glyph_count;
                const uv_top: f32 = 0.0;
                const uv_bot: f32 = 1.0;

                const x0 = @as(f32, @floatFromInt(col)) * cell_w;
                const y0 = @as(f32, @floatFromInt(row)) * cell_h;
                const x1 = x0 + cell_w;
                const y1 = y0 + cell_h;

                // Pixel → NDC (y flips: OpenGL bottom-left, terminal top-left)
                const nx0 = (x0 / fw) * 2.0 - 1.0;
                const nx1 = (x1 / fw) * 2.0 - 1.0;
                const ny0 = 1.0 - (y0 / fh) * 2.0;
                const ny1 = 1.0 - (y1 / fh) * 2.0;

                try self.vertices.appendSlice(self.allocator, &.{
                    nx0, ny0, uv_left, uv_top,
                    nx1, ny0, uv_right, uv_top,
                    nx0, ny1, uv_left, uv_bot,
                    nx1, ny0, uv_right, uv_top,
                    nx1, ny1, uv_right, uv_bot,
                    nx0, ny1, uv_left, uv_bot,
                });
            }
        }

        // Cursor block
        {
            const x0 = @as(f32, @floatFromInt(screen.cursor_col)) * cell_w;
            const y0 = @as(f32, @floatFromInt(screen.cursor_row)) * cell_h;
            const x1 = x0 + cell_w;
            const y1 = y0 + cell_h;
            const nx0 = (x0 / fw) * 2.0 - 1.0;
            const nx1 = (x1 / fw) * 2.0 - 1.0;
            const ny0 = 1.0 - (y0 / fh) * 2.0;
            const ny1 = 1.0 - (y1 / fh) * 2.0;
            // Use space glyph UV as solid-ish via a thin strip — instead draw as solid by
            // using full atlas alpha of '█' substitute: emit with u of '#' which is dense.
            const gi: f32 = @floatFromInt('#' - bitmap.first_codepoint);
            const uv_left = gi / glyph_count;
            const uv_right = (gi + 1.0) / glyph_count;
            try self.vertices.appendSlice(self.allocator, &.{
                nx0, ny0, uv_left, 0.0,
                nx1, ny0, uv_right, 0.0,
                nx0, ny1, uv_left, 1.0,
                nx1, ny0, uv_right, 0.0,
                nx1, ny1, uv_right, 1.0,
                nx0, ny1, uv_left, 1.0,
            });
        }

        if (self.vertices.items.len == 0) return;

        c.glUseProgram(self.program);
        c.glActiveTexture(c.GL_TEXTURE0);
        c.glBindTexture(c.GL_TEXTURE_2D, self.atlas_tex);
        const loc_atlas = c.glGetUniformLocation(self.program, "u_atlas");
        const loc_fg = c.glGetUniformLocation(self.program, "u_fg");
        c.glUniform1i(loc_atlas, 0);
        c.glUniform3f(loc_fg, 0.90, 0.92, 0.94);

        c.glBindVertexArray(self.vao);
        c.glBindBuffer(c.GL_ARRAY_BUFFER, self.vbo);
        c.glBufferData(
            c.GL_ARRAY_BUFFER,
            @intCast(self.vertices.items.len * @sizeOf(f32)),
            self.vertices.items.ptr,
            c.GL_STREAM_DRAW,
        );
        const count: c.GLsizei = @intCast(self.vertices.items.len / 4);
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
