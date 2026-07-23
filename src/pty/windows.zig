//! Windows ConPTY backend.

const std = @import("std");
const options = @import("options.zig");
const paths = @import("../platform/paths.zig");

pub const CreateOptions = options.CreateOptions;
pub const ReadResult = options.ReadResult;

const windows = std.os.windows;
const HANDLE = windows.HANDLE;
const BOOL = windows.BOOL;
const DWORD = windows.DWORD;
const HRESULT = i32;
const SIZE_T = windows.SIZE_T;

const HPCON = *anyopaque;
const COORD = extern struct { X: i16, Y: i16 };

const STARTUPINFOEXW = extern struct {
    StartupInfo: windows.STARTUPINFOW,
    lpAttributeList: ?*anyopaque,
};

const PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE: usize = 0x00020016;
const HANDLE_FLAG_INHERIT: DWORD = 0x00000001;
const S_OK: HRESULT = 0;

const w = struct {
    extern "kernel32" fn CreatePipe(
        hReadPipe: *HANDLE,
        hWritePipe: *HANDLE,
        lpPipeAttributes: ?*windows.SECURITY_ATTRIBUTES,
        nSize: DWORD,
    ) callconv(.winapi) BOOL;

    extern "kernel32" fn SetHandleInformation(
        hObject: HANDLE,
        dwMask: DWORD,
        dwFlags: DWORD,
    ) callconv(.winapi) BOOL;

    extern "kernel32" fn CreatePseudoConsole(
        size: COORD,
        hInput: HANDLE,
        hOutput: HANDLE,
        dwFlags: DWORD,
        phPC: *HPCON,
    ) callconv(.winapi) HRESULT;

    extern "kernel32" fn ResizePseudoConsole(hPC: HPCON, size: COORD) callconv(.winapi) HRESULT;
    extern "kernel32" fn ClosePseudoConsole(hPC: HPCON) callconv(.winapi) void;

    extern "kernel32" fn InitializeProcThreadAttributeList(
        lpAttributeList: ?*anyopaque,
        dwAttributeCount: DWORD,
        dwFlags: DWORD,
        lpSize: *SIZE_T,
    ) callconv(.winapi) BOOL;

    extern "kernel32" fn UpdateProcThreadAttribute(
        lpAttributeList: *anyopaque,
        dwFlags: DWORD,
        Attribute: usize,
        lpValue: ?*anyopaque,
        cbSize: SIZE_T,
        lpPreviousValue: ?*anyopaque,
        lpReturnSize: ?*SIZE_T,
    ) callconv(.winapi) BOOL;

    extern "kernel32" fn DeleteProcThreadAttributeList(lpAttributeList: *anyopaque) callconv(.winapi) void;

    extern "kernel32" fn ReadFile(
        hFile: HANDLE,
        lpBuffer: [*]u8,
        nNumberOfBytesToRead: DWORD,
        lpNumberOfBytesRead: ?*DWORD,
        lpOverlapped: ?*anyopaque,
    ) callconv(.winapi) BOOL;

    extern "kernel32" fn WriteFile(
        hFile: HANDLE,
        lpBuffer: [*]const u8,
        nNumberOfBytesToWrite: DWORD,
        lpNumberOfBytesWritten: ?*DWORD,
        lpOverlapped: ?*anyopaque,
    ) callconv(.winapi) BOOL;

    extern "kernel32" fn PeekNamedPipe(
        hNamedPipe: HANDLE,
        lpBuffer: ?[*]u8,
        nBufferSize: DWORD,
        lpBytesRead: ?*DWORD,
        lpTotalBytesAvail: ?*DWORD,
        lpBytesLeftThisMessage: ?*DWORD,
    ) callconv(.winapi) BOOL;

    extern "kernel32" fn TerminateProcess(hProcess: HANDLE, uExitCode: UINT) callconv(.winapi) BOOL;
    extern "kernel32" fn GetExitCodeProcess(hProcess: HANDLE, lpExitCode: *DWORD) callconv(.winapi) BOOL;
    extern "kernel32" fn WaitForSingleObject(hHandle: HANDLE, dwMilliseconds: DWORD) callconv(.winapi) DWORD;
    extern "kernel32" fn Sleep(dwMilliseconds: DWORD) callconv(.winapi) void;
    extern "kernel32" fn CloseHandle(hObject: HANDLE) callconv(.winapi) BOOL;

    const UINT = u32;
    const WAIT_OBJECT_0: DWORD = 0;
    const STILL_ACTIVE: DWORD = 259;
};

pub const Pty = struct {
    hpcon: ?HPCON = null,
    input_write: ?HANDLE = null,
    output_read: ?HANDLE = null,
    process: ?HANDLE = null,
    thread: ?HANDLE = null,
    cols: u16,
    rows: u16,
    alive: bool = true,

    pub fn create(cols: u16, rows: u16) !Pty {
        return createWith(.{ .cols = cols, .rows = rows });
    }

    pub fn createWith(opts: CreateOptions) !Pty {
        var sa = windows.SECURITY_ATTRIBUTES{
            .nLength = @sizeOf(windows.SECURITY_ATTRIBUTES),
            .lpSecurityDescriptor = null,
            .bInheritHandle = .TRUE,
        };

        // Pipe A: we write -> ConPTY input
        var pty_input_read: HANDLE = undefined;
        var input_write: HANDLE = undefined;
        if (!w.CreatePipe(&pty_input_read, &input_write, &sa, 0).toBool()) return error.CreatePipeFailed;
        errdefer _ = w.CloseHandle(input_write);
        // Don't let our write end be inherited.
        _ = w.SetHandleInformation(input_write, HANDLE_FLAG_INHERIT, 0);

        // Pipe B: ConPTY output -> we read
        var output_read: HANDLE = undefined;
        var pty_output_write: HANDLE = undefined;
        if (!w.CreatePipe(&output_read, &pty_output_write, &sa, 0).toBool()) {
            _ = w.CloseHandle(pty_input_read);
            return error.CreatePipeFailed;
        }
        errdefer _ = w.CloseHandle(output_read);
        _ = w.SetHandleInformation(output_read, HANDLE_FLAG_INHERIT, 0);

        const size = COORD{
            .X = @intCast(@max(opts.cols, 1)),
            .Y = @intCast(@max(opts.rows, 1)),
        };

        var hpcon: HPCON = undefined;
        const hr = w.CreatePseudoConsole(size, pty_input_read, pty_output_write, 0, &hpcon);
        // ConPTY duplicates these; close our copies of the PTY-side ends.
        _ = w.CloseHandle(pty_input_read);
        _ = w.CloseHandle(pty_output_write);
        if (hr != S_OK) return error.CreatePseudoConsoleFailed;
        errdefer w.ClosePseudoConsole(hpcon);

        var attr_size: SIZE_T = 0;
        _ = w.InitializeProcThreadAttributeList(null, 1, 0, &attr_size);
        const attr_bytes = try std.heap.c_allocator.alloc(u8, attr_size);
        var attr_owned = true;
        var attr_initialized = false;
        errdefer if (attr_owned) {
            if (attr_initialized) w.DeleteProcThreadAttributeList(attr_bytes.ptr);
            std.heap.c_allocator.free(attr_bytes);
        };
        @memset(attr_bytes, 0);

        if (!w.InitializeProcThreadAttributeList(attr_bytes.ptr, 1, 0, &attr_size).toBool()) {
            return error.AttributeListFailed;
        }
        attr_initialized = true;

        if (!w.UpdateProcThreadAttribute(
            attr_bytes.ptr,
            0,
            PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE,
            hpcon,
            @sizeOf(HPCON),
            null,
            null,
        ).toBool()) {
            return error.AttributeListFailed;
        }

        var si: STARTUPINFOEXW = std.mem.zeroes(STARTUPINFOEXW);
        si.StartupInfo.cb = @sizeOf(STARTUPINFOEXW);
        si.lpAttributeList = attr_bytes.ptr;

        var cmdline_buf: [1024]u8 = undefined;
        const shell = opts.shell orelse paths.defaultShell();
        const cmdline_utf8 = buildCommandLine(&cmdline_buf, shell) catch return error.CommandLineTooLong;

        var cmdline_w: [1024]u16 = undefined;
        const cmdline_len = try std.unicode.wtf8ToWtf16Le(cmdline_w[0 .. cmdline_w.len - 1], cmdline_utf8);
        cmdline_w[cmdline_len] = 0;

        var cwd_w_buf: [std.fs.max_path_bytes]u16 = undefined;
        const cwd_w: ?[:0]u16 = blk: {
            const cwd = opts.cwd orelse break :blk null;
            if (cwd.len == 0) break :blk null;
            const n = std.unicode.wtf8ToWtf16Le(cwd_w_buf[0 .. cwd_w_buf.len - 1], cwd) catch break :blk null;
            cwd_w_buf[n] = 0;
            break :blk cwd_w_buf[0..n :0];
        };

        // Apply extra env vars to the current process so the child inherits them.
        for (opts.env) |entry| {
            applyEnvEntry(entry);
        }

        var pi: windows.PROCESS.INFORMATION = undefined;
        @memset(std.mem.asBytes(&pi), 0);

        const ok = windows.kernel32.CreateProcessW(
            null,
            @ptrCast(&cmdline_w),
            null,
            null,
            .FALSE, // handles already attached via ConPTY attribute
            .{
                .extended_startupinfo_present = true,
                .create_unicode_environment = true,
            },
            null,
            if (cwd_w) |cw| cw.ptr else null,
            @ptrCast(&si),
            &pi,
        );
        if (!ok.toBool()) return error.CreateProcessFailed;

        // Attribute list only needed during CreateProcess.
        w.DeleteProcThreadAttributeList(attr_bytes.ptr);
        std.heap.c_allocator.free(attr_bytes);
        attr_owned = false;

        return .{
            .hpcon = hpcon,
            .input_write = input_write,
            .output_read = output_read,
            .process = pi.hProcess,
            .thread = pi.hThread,
            .cols = opts.cols,
            .rows = opts.rows,
            .alive = true,
        };
    }

    pub fn deinit(self: *Pty) void {
        if (self.alive) {
            self.terminateSession();
        }
        if (self.input_write) |h| _ = w.CloseHandle(h);
        if (self.output_read) |h| _ = w.CloseHandle(h);
        if (self.thread) |h| _ = w.CloseHandle(h);
        if (self.process) |h| _ = w.CloseHandle(h);
        if (self.hpcon) |h| w.ClosePseudoConsole(h);
        self.* = undefined;
    }

    fn terminateSession(self: *Pty) void {
        if (self.process) |proc| {
            _ = w.TerminateProcess(proc, 1);
            _ = w.WaitForSingleObject(proc, 200);
        }
        self.alive = false;
    }

    pub fn resize(self: *Pty, cols: u16, rows: u16) void {
        self.cols = cols;
        self.rows = rows;
        if (self.hpcon) |h| {
            const size = COORD{
                .X = @intCast(@max(cols, 1)),
                .Y = @intCast(@max(rows, 1)),
            };
            _ = w.ResizePseudoConsole(h, size);
        }
    }

    pub fn write(self: *Pty, bytes: []const u8) void {
        if (!self.alive) return;
        const handle = self.input_write orelse return;
        var offset: usize = 0;
        while (offset < bytes.len) {
            var written: DWORD = 0;
            const chunk: DWORD = @intCast(@min(bytes.len - offset, std.math.maxInt(DWORD)));
            if (!w.WriteFile(handle, bytes.ptr + offset, chunk, &written, null).toBool()) return;
            if (written == 0) return;
            offset += written;
        }
    }

    pub fn read(self: *Pty, buffer: []u8) ReadResult {
        if (!self.alive) return .{ .len = 0, .eof = true };
        const handle = self.output_read orelse {
            self.alive = false;
            return .{ .len = 0, .eof = true };
        };

        var avail: DWORD = 0;
        if (!w.PeekNamedPipe(handle, null, 0, null, &avail, null).toBool()) {
            self.markExited();
            return .{ .len = 0, .eof = true };
        }
        if (avail == 0) {
            if (self.processExited()) {
                self.markExited();
                return .{ .len = 0, .eof = true };
            }
            return .{ .len = 0, .eof = false };
        }

        var got: DWORD = 0;
        const to_read: DWORD = @intCast(@min(buffer.len, @as(usize, avail)));
        if (!w.ReadFile(handle, buffer.ptr, to_read, &got, null).toBool()) {
            self.markExited();
            return .{ .len = 0, .eof = true };
        }
        if (got == 0) {
            self.markExited();
            return .{ .len = 0, .eof = true };
        }
        return .{ .len = got, .eof = false };
    }

    fn processExited(self: *const Pty) bool {
        const proc = self.process orelse return true;
        var code: DWORD = 0;
        if (!w.GetExitCodeProcess(proc, &code).toBool()) return true;
        return code != w.STILL_ACTIVE;
    }

    fn markExited(self: *Pty) void {
        self.alive = false;
    }
};

fn buildCommandLine(buf: []u8, shell: []const u8) ![]const u8 {
    // Quotes in the shell path break CreateProcess command-line parsing.
    if (std.mem.indexOfScalar(u8, shell, '"') != null) return error.InvalidShellPath;
    if (std.mem.indexOfScalar(u8, shell, '\n') != null or std.mem.indexOfScalar(u8, shell, '\r') != null) {
        return error.InvalidShellPath;
    }
    // Prefer PowerShell / pwsh as login-like interactive shells.
    if (std.ascii.endsWithIgnoreCase(shell, "powershell.exe") or
        std.ascii.endsWithIgnoreCase(shell, "pwsh.exe") or
        std.mem.eql(u8, shell, "powershell") or
        std.mem.eql(u8, shell, "pwsh"))
    {
        return std.fmt.bufPrint(buf, "\"{s}\" -NoLogo", .{shell}) catch return error.CommandLineTooLong;
    }
    if (std.ascii.endsWithIgnoreCase(shell, "cmd.exe") or std.mem.eql(u8, shell, "cmd")) {
        return std.fmt.bufPrint(buf, "\"{s}\" /K", .{shell}) catch return error.CommandLineTooLong;
    }
    return std.fmt.bufPrint(buf, "\"{s}\"", .{shell}) catch return error.CommandLineTooLong;
}

fn applyEnvEntry(entry: []const u8) void {
    const eq = std.mem.indexOfScalar(u8, entry, '=') orelse return;
    const key = entry[0..eq];
    if (isUnsafeEnvKey(key)) return;
    paths.setEnv(key, entry[eq + 1 ..]);
}

fn isUnsafeEnvKey(key: []const u8) bool {
    const blocked = [_][]const u8{
        "LD_PRELOAD",
        "LD_LIBRARY_PATH",
        "DYLD_INSERT_LIBRARIES",
        "DYLD_LIBRARY_PATH",
        "PATH",
        "PATHEXT",
        "ComSpec",
        "PSModulePath",
        "BASH_ENV",
        "ENV",
        "NODE_OPTIONS",
        "PYTHONPATH",
    };
    for (blocked) |b| {
        if (std.ascii.eqlIgnoreCase(key, b)) return true;
    }
    return false;
}
