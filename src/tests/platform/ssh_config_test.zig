const std = @import("std");
const ssh = @import("../../platform/ssh_config.zig");

test "parses Host lines and skips wildcards" {
    const data =
        \\Host github.com
        \\  User git
        \\Host *
        \\  IdentityFile ~/.ssh/id_ed25519
        \\Host jump prod
        \\  HostName 10.0.0.1
        \\
    ;
    var hosts: [8]ssh.Host = undefined;
    const n = ssh.parse(data, &hosts);
    try std.testing.expectEqual(@as(usize, 3), n);
    try std.testing.expectEqualStrings("github.com", hosts[0].slice());
    try std.testing.expectEqualStrings("jump", hosts[1].slice());
    try std.testing.expectEqualStrings("prod", hosts[2].slice());
}
