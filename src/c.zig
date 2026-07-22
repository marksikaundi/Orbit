//! Central C bindings for GLFW, OpenGL, and PTY helpers.

const builtin = @import("builtin");

pub const c = @cImport({
    @cDefine("GL_SILENCE_DEPRECATION", "1");
    @cInclude("GLFW/glfw3.h");
    if (builtin.os.tag == .macos) {
        @cInclude("OpenGL/gl3.h");
        @cInclude("util.h");
        @cInclude("unistd.h");
        @cInclude("stdlib.h");
        @cInclude("fcntl.h");
        @cInclude("termios.h");
        @cInclude("sys/ioctl.h");
        @cInclude("signal.h");
        @cInclude("errno.h");
        @cInclude("sys/wait.h");
        @cInclude("time.h");
    } else if (builtin.os.tag == .linux) {
        @cInclude("GLES3/gl3.h");
        @cInclude("pty.h");
        @cInclude("unistd.h");
        @cInclude("stdlib.h");
        @cInclude("fcntl.h");
        @cInclude("termios.h");
        @cInclude("sys/ioctl.h");
        @cInclude("signal.h");
        @cInclude("errno.h");
        @cInclude("sys/wait.h");
        @cInclude("time.h");
    }
});
