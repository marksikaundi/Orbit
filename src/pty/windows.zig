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
    extern "kernel32" fn GetEnvironmentStringsW() callconv(.winapi) ?[*:0]u16;
    extern "kernel32" fn FreeEnvironmentStringsW(penv: [*:0]u16) callconv(.winapi) BOOL;

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

        var cmdline_buf: [2048]u8 = undefined;
        const shell = opts.shell orelse paths.defaultShell();
        const cmdline_utf8 = buildCommandLine(&cmdline_buf, shell, opts.command, opts.wait_after_command) catch return error.CommandLineTooLong;

        var cmdline_w: [2048]u16 = undefined;
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

        // Child-only environment: never mutate Orbit's process env.
        // Always overlay TERM so vim/less get 256-color + alternate screen.
        var env_block: ?[:0]u16 = null;
        defer if (env_block) |eb| std.heap.c_allocator.free(eb);
        env_block = try buildChildEnvironmentBlock(std.heap.c_allocator, opts.env);

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
            if (env_block) |eb| @ptrCast(eb.ptr) else null,
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

fn buildCommandLine(buf: []u8, shell: []const u8, command: []const []const u8, wait_after: bool) ![]const u8 {
    // Quotes in the shell path break CreateProcess command-line parsing.
    if (std.mem.indexOfScalar(u8, shell, '"') != null) return error.InvalidShellPath;
    if (std.mem.indexOfScalar(u8, shell, '\n') != null or std.mem.indexOfScalar(u8, shell, '\r') != null) {
        return error.InvalidShellPath;
    }
    if (command.len == 0) {
        return buildShellLine(buf, shell);
    }
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(std.heap.c_allocator);
    if (wait_after) {
        // Keep a prompt after the program exits (debug / -e).
        try out.appendSlice(std.heap.c_allocator, "cmd.exe /c \"");
        try appendQuotedArgs(&out, std.heap.c_allocator, command);
        try out.appendSlice(std.heap.c_allocator, " & pause\"");
    } else {
        try appendQuotedArgs(&out, std.heap.c_allocator, command);
    }
    if (out.items.len >= buf.len) return error.CommandLineTooLong;
    @memcpy(buf[0..out.items.len], out.items);
    return buf[0..out.items.len];
}

fn buildShellLine(buf: []u8, shell: []const u8) ![]const u8 {
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

fn appendQuotedArgs(out: *std.ArrayList(u8), allocator: std.mem.Allocator, command: []const []const u8) !void {
    for (command, 0..) |arg, i| {
        if (std.mem.indexOfScalar(u8, arg, '\n') != null or std.mem.indexOfScalar(u8, arg, '\r') != null) {
            return error.InvalidShellPath;
        }
        if (i > 0) try out.append(allocator, ' ');
        const need_quotes = std.mem.indexOfAny(u8, arg, " \t\"") != null;
        if (need_quotes) try out.append(allocator, '"');
        for (arg) |ch| {
            if (ch == '"') {
                try out.appendSlice(allocator, "\\\"");
            } else {
                try out.append(allocator, ch);
            }
        }
        if (need_quotes) try out.append(allocator, '"');
    }
}

/// Build a Unicode environment block for CreateProcessW (child-only; parent unchanged).
/// Format: KEY=VALUE\0 KEY=VALUE\0 \0 as UTF-16LE.
fn buildChildEnvironmentBlock(allocator: std.mem.Allocator, extra: []const []const u8) ![:0]u16 {
    const env_w = w.GetEnvironmentStringsW() orelse return error.GetEnvironmentFailed;
    defer _ = w.FreeEnvironmentStringsW(env_w);

    var entries: std.ArrayList([]u8) = .empty;
    defer {
        for (entries.items) |e| allocator.free(e);
        entries.deinit(allocator);
    }

    // Copy parent environment (UTF-16 → UTF-8).
    var p: [*]const u16 = env_w;
    while (true) {
        if (p[0] == 0) break;
        var len: usize = 0;
        while (p[len] != 0) : (len += 1) {}
            var utf8_buf: [32 * 1024]u8 = undefined;
            const n = std.unicode.utf16LeToUtf8(utf8_buf[0..], p[0..len]) catch {
                p += len + 1;
                continue;
            };
        try entries.append(allocator, try allocator.dupe(u8, utf8_buf[0..n]));
        p += len + 1;
    }

    // Overlay workspace extras (skip hijack keys; replace matching keys case-insensitively).
    for (extra) |entry| {
        const eq = std.mem.indexOfScalar(u8, entry, '=') orelse continue;
        const key = entry[0..eq];
        if (key.len == 0 or options.isUnsafeEnvKey(key)) continue;

        var replaced = false;
        for (entries.items, 0..) |existing, i| {
            const existing_eq = std.mem.indexOfScalar(u8, existing, '=') orelse continue;
            if (!std.ascii.eqlIgnoreCase(existing[0..existing_eq], key)) continue;
            allocator.free(existing);
            entries.items[i] = try allocator.dupe(u8, entry);
            replaced = true;
            break;
        }
        if (!replaced) {
            try entries.append(allocator, try allocator.dupe(u8, entry));
        }
    }

    try upsertEnv(&entries, allocator, "TERM=xterm-256color");
    try upsertEnv(&entries, allocator, "COLORTERM=truecolor");

    // Serialize to double-NUL-terminated UTF-16LE block.
    var out: std.ArrayList(u16) = .empty;
    errdefer out.deinit(allocator);
    for (entries.items) |entry| {
        var wbuf: [32 * 1024]u16 = undefined;
        const wn = std.unicode.wtf8ToWtf16Le(wbuf[0..], entry) catch continue;
        try out.appendSlice(allocator, wbuf[0..wn]);
        try out.append(allocator, 0);
    }
    try out.append(allocator, 0); // final terminator

    const owned = try out.toOwnedSlice(allocator);
    // Ensure Zig [:0]u16 — last element is already 0.
    return owned[0 .. owned.len - 1 :0];
}

fn upsertEnv(entries: *std.ArrayList([]u8), allocator: std.mem.Allocator, entry: []const u8) !void {
    const eq = std.mem.indexOfScalar(u8, entry, '=') orelse return;
    const key = entry[0..eq];
    for (entries.items, 0..) |existing, i| {
        const existing_eq = std.mem.indexOfScalar(u8, existing, '=') orelse continue;
        if (!std.ascii.eqlIgnoreCase(existing[0..existing_eq], key)) continue;
        allocator.free(existing);
        entries.items[i] = try allocator.dupe(u8, entry);
        return;
    }
    try entries.append(allocator, try allocator.dupe(u8, entry));
}
