const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const root_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    const exe = b.addExecutable(.{
        .name = "orbit",
        .root_module = root_module,
    });

    // System GLFW via Homebrew.
    if (target.result.os.tag == .macos) {
        if (target.result.cpu.arch == .aarch64) {
            root_module.addIncludePath(.{ .cwd_relative = "/opt/homebrew/include" });
            root_module.addLibraryPath(.{ .cwd_relative = "/opt/homebrew/lib" });
        } else {
            root_module.addIncludePath(.{ .cwd_relative = "/usr/local/include" });
            root_module.addLibraryPath(.{ .cwd_relative = "/usr/local/lib" });
        }
    }
    root_module.linkSystemLibrary("glfw", .{});

    if (target.result.os.tag == .macos) {
        root_module.linkFramework("OpenGL", .{});
        root_module.linkFramework("Cocoa", .{});
        root_module.linkFramework("IOKit", .{});
        root_module.linkFramework("CoreVideo", .{});
    } else if (target.result.os.tag == .linux) {
        root_module.linkSystemLibrary("GL", .{});
        root_module.linkSystemLibrary("util", .{}); // openpty
        root_module.linkSystemLibrary("X11", .{});
        root_module.linkSystemLibrary("dl", .{});
        root_module.linkSystemLibrary("pthread", .{});
    }

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run Orbit");
    run_step.dependOn(&run_cmd.step);

    const exe_tests = b.addTest(.{
        .root_module = root_module,
    });
    const run_exe_tests = b.addRunArtifact(exe_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_tests.step);
}
