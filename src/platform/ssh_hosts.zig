//! SSH host manager — ~/.ssh/config plus Orbit-saved hosts, keys, jump, mux.

const std = @import("std");
const paths = @import("paths.zig");

pub const max_hosts = 64;
pub const max_field = 96;

pub const Host = struct {
    name: [max_field]u8 = undefined,
    name_len: u8 = 0,
    hostname: [max_field]u8 = undefined,
    hostname_len: u8 = 0,
    user: [max_field]u8 = undefined,
    user_len: u8 = 0,
    identity: [max_field]u8 = undefined,
    identity_len: u8 = 0,
    jump: [max_field]u8 = undefined,
    jump_len: u8 = 0,
    port: u16 = 0,
    mux: bool = true,

    pub fn nameSlice(self: *const Host) []const u8 {
        return self.name[0..self.name_len];
    }
    pub fn hostnameSlice(self: *const Host) []const u8 {
        return if (self.hostname_len == 0) self.nameSlice() else self.hostname[0..self.hostname_len];
    }
    pub fn userSlice(self: *const Host) []const u8 {
        return self.user[0..self.user_len];
    }
    pub fn identitySlice(self: *const Host) []const u8 {
        return self.identity[0..self.identity_len];
    }
    pub fn jumpSlice(self: *const Host) []const u8 {
        return self.jump[0..self.jump_len];
    }

    fn setField(buf: []u8, len: *u8, val: []const u8) void {
        const n = @min(val.len, buf.len);
        @memcpy(buf[0..n], val[0..n]);
        len.* = @intCast(n);
    }

    pub fn setName(self: *Host, val: []const u8) void {
        setField(&self.name, &self.name_len, val);
    }
    pub fn setHostname(self: *Host, val: []const u8) void {
        setField(&self.hostname, &self.hostname_len, val);
    }
    pub fn setUser(self: *Host, val: []const u8) void {
        setField(&self.user, &self.user_len, val);
    }
    pub fn setIdentity(self: *Host, val: []const u8) void {
        setField(&self.identity, &self.identity_len, val);
    }
    pub fn setJump(self: *Host, val: []const u8) void {
        setField(&self.jump, &self.jump_len, val);
    }
};

pub fn parseConfig(data: []const u8, out: []Host) usize {
    var n: usize = 0;
    var current: ?*Host = null;
    var lines = std.mem.splitScalar(u8, data, '\n');
    while (lines.next()) |raw| {
        var line = std.mem.trim(u8, raw, " \t\r");
        if (line.len == 0 or line[0] == '#') continue;
        if (startsIgnoreCase(line, "host ") or startsIgnoreCase(line, "host\t")) {
            current = null;
            const rest = std.mem.trim(u8, line[4..], " \t");
            var toks = std.mem.tokenizeAny(u8, rest, " \t");
            while (toks.next()) |tok| {
                if (n >= out.len) break;
                if (tok.len == 0 or tok[0] == '*' or tok[0] == '!' or tok[0] == '?') continue;
                if (findName(out[0..n], tok) != null) continue;
                out[n] = .{};
                out[n].setName(tok);
                current = &out[n];
                n += 1;
            }
            continue;
        }
        const host = current orelse continue;
        const sp = std.mem.indexOfAny(u8, line, " \t") orelse continue;
        const key = std.mem.trim(u8, line[0..sp], " \t");
        const val = std.mem.trim(u8, line[sp + 1 ..], " \t");
        if (eql(key, "hostname")) host.setHostname(val);
        if (eql(key, "user")) host.setUser(val);
        if (eql(key, "identityfile")) host.setIdentity(val);
        if (eql(key, "proxyjump") or eql(key, "proxycommand")) {
            if (eql(key, "proxyjump")) host.setJump(val);
        }
        if (eql(key, "port")) host.port = std.fmt.parseInt(u16, val, 10) catch 0;
        if (eql(key, "controlmaster")) host.mux = !eql(val, "no");
    }
    return n;
}

pub fn parseOrbitToml(data: []const u8, out: []Host, start: usize) usize {
    var n = start;
    var current: ?*Host = null;
    var lines = std.mem.splitScalar(u8, data, '\n');
    while (lines.next()) |raw| {
        var line = std.mem.trim(u8, raw, " \t\r");
        if (line.len == 0 or line[0] == '#') continue;
        if (std.mem.eql(u8, line, "[[hosts]]")) {
            if (n >= out.len) break;
            out[n] = .{};
            current = &out[n];
            n += 1;
            continue;
        }
        const host = current orelse continue;
        const eq = std.mem.indexOfScalar(u8, line, '=') orelse continue;
        const key = std.mem.trim(u8, line[0..eq], " \t");
        var val = std.mem.trim(u8, line[eq + 1 ..], " \t");
        if (val.len >= 2 and val[0] == '"' and val[val.len - 1] == '"') {
            val = val[1 .. val.len - 1];
        }
        if (eql(key, "name")) host.setName(val);
        if (eql(key, "hostname") or eql(key, "host")) host.setHostname(val);
        if (eql(key, "user")) host.setUser(val);
        if (eql(key, "identity") or eql(key, "identityfile")) host.setIdentity(val);
        if (eql(key, "jump") or eql(key, "proxyjump")) host.setJump(val);
        if (eql(key, "port")) host.port = std.fmt.parseInt(u16, val, 10) catch 0;
        if (eql(key, "mux") or eql(key, "control_master")) host.mux = !(eql(val, "false") or eql(val, "no"));
    }
    return n;
}

/// Build `ssh` argv into `argv_store` (max 24 slots). Returns the slice to pass to the shell.
pub fn buildCommand(host: *const Host, buf: []u8) []const u8 {
    var n: usize = 0;
    const write = struct {
        fn go(out: []u8, i: *usize, s: []const u8) void {
            const room = if (i.* < out.len) out.len - i.* else 0;
            const take = @min(room, s.len);
            if (take > 0) @memcpy(out[i.* .. i.* + take], s[0..take]);
            i.* += take;
        }
    }.go;
    write(buf, &n, "ssh");
    if (host.mux) {
        write(buf, &n, " -o ControlMaster=auto -o ControlPath=~/.ssh/orbit-%r@%h:%p -o ControlPersist=10m");
    }
    if (host.identity_len > 0) {
        write(buf, &n, " -i ");
        write(buf, &n, host.identitySlice());
    }
    if (host.jump_len > 0) {
        write(buf, &n, " -J ");
        write(buf, &n, host.jumpSlice());
    }
    if (host.port != 0 and host.port != 22) {
        var pbuf: [8]u8 = undefined;
        const p = std.fmt.bufPrint(&pbuf, " -p {d}", .{host.port}) catch "";
        write(buf, &n, p);
    }
    write(buf, &n, " -- ");
    if (host.user_len > 0) {
        write(buf, &n, host.userSlice());
        write(buf, &n, "@");
    }
    write(buf, &n, host.hostnameSlice());
    return buf[0..n];
}

pub fn findName(hosts: []const Host, name: []const u8) ?*const Host {
    for (hosts) |*h| {
        if (std.mem.eql(u8, h.nameSlice(), name)) return h;
    }
    return null;
}

pub fn parseTyped(spec: []const u8) Host {
    var h: Host = .{};
    var s = spec;
    if (std.mem.indexOfScalar(u8, s, '@')) |at| {
        h.setUser(s[0..at]);
        s = s[at + 1 ..];
    }
    if (std.mem.lastIndexOfScalar(u8, s, ':')) |colon| {
        const port = std.fmt.parseInt(u16, s[colon + 1 ..], 10) catch 0;
        if (port != 0) {
            h.port = port;
            s = s[0..colon];
        }
    }
    h.setName(s);
    h.setHostname(s);
    return h;
}

fn startsIgnoreCase(s: []const u8, prefix: []const u8) bool {
    if (s.len < prefix.len) return false;
    return std.ascii.eqlIgnoreCase(s[0..prefix.len], prefix);
}

fn eql(a: []const u8, b: []const u8) bool {
    return std.ascii.eqlIgnoreCase(a, b);
}

pub fn loadAll(allocator: std.mem.Allocator, io: std.Io, out: []Host) usize {
    var n: usize = 0;
    if (sshConfigPath(allocator)) |path| {
        defer allocator.free(path);
        if (readFile(allocator, io, path)) |data| {
            defer allocator.free(data);
            n = parseConfig(data, out);
        }
    }
    if (orbitSshPath(allocator)) |path| {
        defer allocator.free(path);
        if (readFile(allocator, io, path)) |data| {
            defer allocator.free(data);
            n = parseOrbitToml(data, out, n);
        }
    }
    return n;
}

pub fn appendSaved(allocator: std.mem.Allocator, io: std.Io, host: *const Host) void {
    const path = orbitSshPath(allocator) orelse return;
    defer allocator.free(path);
    if (std.fs.path.dirname(path)) |dir| paths.ensureDir(dir);
    var existing: []u8 = &.{};
    if (readFile(allocator, io, path)) |data| {
        existing = data;
    }
    defer if (existing.len > 0) allocator.free(existing);

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(allocator);
    if (existing.len > 0) out.appendSlice(allocator, existing) catch return;
    if (existing.len > 0 and existing[existing.len - 1] != '\n') {
        out.append(allocator, '\n') catch return;
    }
    out.appendSlice(allocator, "\n[[hosts]]\n") catch return;
    appendKv(&out, allocator, "name", host.nameSlice());
    if (host.hostname_len > 0) appendKv(&out, allocator, "hostname", host.hostnameSlice());
    if (host.user_len > 0) appendKv(&out, allocator, "user", host.userSlice());
    if (host.port != 0) {
        var pbuf: [8]u8 = undefined;
        const ps = std.fmt.bufPrint(&pbuf, "{d}", .{host.port}) catch return;
        out.appendSlice(allocator, "port = ") catch return;
        out.appendSlice(allocator, ps) catch return;
        out.append(allocator, '\n') catch return;
    }
    if (host.identity_len > 0) appendKv(&out, allocator, "identity", host.identitySlice());
    if (host.jump_len > 0) appendKv(&out, allocator, "jump", host.jumpSlice());
    const file = std.Io.Dir.createFileAbsolute(io, path, .{}) catch return;
    defer file.close(io);
    file.writeStreamingAll(io, out.items) catch {};
}

fn appendKv(out: *std.ArrayList(u8), allocator: std.mem.Allocator, key: []const u8, val: []const u8) void {
    out.appendSlice(allocator, key) catch return;
    out.appendSlice(allocator, " = \"") catch return;
    out.appendSlice(allocator, val) catch return;
    out.appendSlice(allocator, "\"\n") catch return;
}

fn readFile(allocator: std.mem.Allocator, io: std.Io, path: []const u8) ?[]u8 {
    const file = std.Io.Dir.openFileAbsolute(io, path, .{}) catch return null;
    defer file.close(io);
    var buf: [4096]u8 = undefined;
    var reader = file.reader(io, &buf);
    return reader.interface.allocRemaining(allocator, .limited(128 * 1024)) catch null;
}

fn sshConfigPath(allocator: std.mem.Allocator) ?[]u8 {
    const home = paths.homeDir() orelse return null;
    return std.fmt.allocPrint(allocator, "{s}{c}.ssh{c}config", .{
        home, std.fs.path.sep, std.fs.path.sep,
    }) catch null;
}

fn orbitSshPath(allocator: std.mem.Allocator) ?[]u8 {
    return paths.joinConfig(allocator, &.{"ssh.toml"}) catch null;
}
