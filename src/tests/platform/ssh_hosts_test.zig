const std = @import("std");
const ssh = @import("../../platform/ssh_hosts.zig");

test "parses Host with user port jump and identity" {
    const data =
        \\Host jump
        \\  HostName 10.0.0.1
        \\  User deploy
        \\  Port 2222
        \\  IdentityFile ~/.ssh/id_ed25519
        \\  ProxyJump bastion
        \\Host *
        \\  User ignore
        \\
    ;
    var hosts: [8]ssh.Host = undefined;
    const n = ssh.parseConfig(data, &hosts);
    try std.testing.expectEqual(@as(usize, 1), n);
    try std.testing.expectEqualStrings("jump", hosts[0].nameSlice());
    try std.testing.expectEqualStrings("10.0.0.1", hosts[0].hostnameSlice());
    try std.testing.expectEqualStrings("deploy", hosts[0].userSlice());
    try std.testing.expectEqual(@as(u16, 2222), hosts[0].port);
    try std.testing.expectEqualStrings("~/.ssh/id_ed25519", hosts[0].identitySlice());
    try std.testing.expectEqualStrings("bastion", hosts[0].jumpSlice());
}

test "orbit toml appends saved hosts" {
    var hosts: [4]ssh.Host = undefined;
    const n = ssh.parseOrbitToml(
        \\[[hosts]]
        \\name = "box"
        \\hostname = "box.example"
        \\user = "me"
        \\mux = false
        \\
    , &hosts, 0);
    try std.testing.expectEqual(@as(usize, 1), n);
    try std.testing.expectEqualStrings("box", hosts[0].nameSlice());
    try std.testing.expect(!hosts[0].mux);
}

test "buildCommand includes identity jump port and user" {
    var h: ssh.Host = .{};
    h.setName("prod");
    h.setHostname("10.1.2.3");
    h.setUser("deploy");
    h.setIdentity("~/.ssh/id_ed25519");
    h.setJump("bastion");
    h.port = 2222;
    h.mux = false;
    var buf: [256]u8 = undefined;
    const cmd = ssh.buildCommand(&h, &buf);
    try std.testing.expect(std.mem.indexOf(u8, cmd, "ssh") != null);
    try std.testing.expect(std.mem.indexOf(u8, cmd, "-i ~/.ssh/id_ed25519") != null);
    try std.testing.expect(std.mem.indexOf(u8, cmd, "-J bastion") != null);
    try std.testing.expect(std.mem.indexOf(u8, cmd, "-p 2222") != null);
    try std.testing.expect(std.mem.indexOf(u8, cmd, "deploy@10.1.2.3") != null);
    try std.testing.expect(std.mem.indexOf(u8, cmd, "ControlMaster") == null);
}

test "parseTyped user host port" {
    const h = ssh.parseTyped("alice@db.internal:2200");
    try std.testing.expectEqualStrings("alice", h.userSlice());
    try std.testing.expectEqualStrings("db.internal", h.hostnameSlice());
    try std.testing.expectEqual(@as(u16, 2200), h.port);
}
