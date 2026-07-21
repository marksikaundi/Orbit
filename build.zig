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

    // stb_truetype (public domain) for Ghostty-like font rasterization.
    root_module.addIncludePath(b.path("vendor"));
    root_module.addCSourceFile(.{
        .file = b.path("vendor/stb_truetype_impl.c"),
        .flags = &.{ "-std=c99", "-fno-sanitize=undefined" },
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

    // ── Unit tests (feature-organized under src/tests/) ─────────────────
    // Separate from the app module so GLFW/OpenGL are not required.
    const test_module = b.createModule(.{
        .root_source_file = b.path("src/tests.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    test_module.addIncludePath(b.path("vendor"));
    test_module.addCSourceFile(.{
        .file = b.path("vendor/stb_truetype_impl.c"),
        .flags = &.{ "-std=c99", "-fno-sanitize=undefined" },
    });

    // Some UI modules reference the renderer types (no window required at runtime).
    if (target.result.os.tag == .macos) {
        if (target.result.cpu.arch == .aarch64) {
            test_module.addIncludePath(.{ .cwd_relative = "/opt/homebrew/include" });
            test_module.addLibraryPath(.{ .cwd_relative = "/opt/homebrew/lib" });
        } else {
            test_module.addIncludePath(.{ .cwd_relative = "/usr/local/include" });
            test_module.addLibraryPath(.{ .cwd_relative = "/usr/local/lib" });
        }
        test_module.linkSystemLibrary("glfw", .{});
        test_module.linkFramework("OpenGL", .{});
        test_module.linkFramework("Cocoa", .{});
        test_module.linkFramework("IOKit", .{});
        test_module.linkFramework("CoreVideo", .{});
    } else if (target.result.os.tag == .linux) {
        test_module.linkSystemLibrary("GL", .{});
        test_module.linkSystemLibrary("glfw", .{});
        test_module.linkSystemLibrary("util", .{});
        test_module.linkSystemLibrary("X11", .{});
        test_module.linkSystemLibrary("dl", .{});
        test_module.linkSystemLibrary("pthread", .{});
    }
    const unit_tests = b.addTest(.{
        .name = "orbit-tests",
        .root_module = test_module,
    });
    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run feature unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
