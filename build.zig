const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Absolute repo path so Orbit can refresh ~/.config/orbit/source_root on launch.
    const source_root: []const u8 = b.build_root.path orelse ".";
    const build_opts = b.addOptions();
    build_opts.addOption([]const u8, "source_root", source_root);

    const root_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    root_module.addOptions("build_options", build_opts);

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
        // Dock icon via NSApplication setApplicationIconImage.
        root_module.addCSourceFile(.{
            .file = b.path("src/platform/macos_icon.m"),
            .flags = &.{ "-fobjc-arc", "-fno-sanitize=undefined" },
        });
    }
    root_module.linkSystemLibrary("glfw", .{});

    if (target.result.os.tag == .macos) {
        root_module.linkFramework("OpenGL", .{});
        root_module.linkFramework("Cocoa", .{});
        root_module.linkFramework("IOKit", .{});
        root_module.linkFramework("CoreVideo", .{});
        root_module.linkFramework("AppKit", .{});
    } else if (target.result.os.tag == .linux) {
        root_module.linkSystemLibrary("GL", .{});
        root_module.linkSystemLibrary("util", .{}); // openpty
        root_module.linkSystemLibrary("X11", .{});
        root_module.linkSystemLibrary("dl", .{});
        root_module.linkSystemLibrary("pthread", .{});
    }

    b.installArtifact(exe);

    // ── Run ──────────────────────────────────────────────────────────────
    const run_step = b.step("run", "Build and launch Orbit (detached)");
    const run_fg_step = b.step("run-fg", "Build and launch Orbit in the foreground (logs in this terminal)");
    var bundle_step: ?*std.Build.Step = null;
    if (target.result.os.tag == .macos) {
        // Package Orbit.app so Launch Services / Dock use AppIcon.icns.
        const bundle = b.addSystemCommand(&.{
            "bash",
            "scripts/bundle-macos-app.sh",
        });
        bundle.setCwd(b.path("."));
        bundle.step.dependOn(b.getInstallStep());
        bundle.addFileArg(b.path("assets/icon/Info.plist"));
        bundle.addFileArg(b.path("assets/icon/AppIcon.icns"));
        bundle_step = &bundle.step;

        // Detached launch — shell returns immediately with a success message.
        const run_detached = b.addSystemCommand(&.{
            "bash",
            "scripts/launch-detached.sh",
        });
        run_detached.setCwd(b.path("."));
        run_detached.step.dependOn(&bundle.step);
        if (b.args) |args| {
            run_detached.addArgs(args);
        }
        run_step.dependOn(&run_detached.step);

        // Foreground launch for debugging.
        const run_fg = b.addSystemCommand(&.{
            "bash",
            "scripts/launch-detached.sh",
        });
        run_fg.setCwd(b.path("."));
        run_fg.setEnvironmentVariable("ORBIT_FOREGROUND", "1");
        run_fg.step.dependOn(&bundle.step);
        if (b.args) |args| {
            run_fg.addArgs(args);
        }
        run_fg_step.dependOn(&run_fg.step);
    } else {
        const run_detached = b.addSystemCommand(&.{
            "bash",
            "scripts/launch-detached.sh",
        });
        run_detached.setCwd(b.path("."));
        run_detached.step.dependOn(b.getInstallStep());
        if (b.args) |args| {
            run_detached.addArgs(args);
        }
        run_step.dependOn(&run_detached.step);

        const run_fg = b.addRunArtifact(exe);
        run_fg.step.dependOn(b.getInstallStep());
        if (b.args) |args| {
            run_fg.addArgs(args);
        }
        run_fg_step.dependOn(&run_fg.step);
    }

    // ── Global setup (PATH + zig build run from any directory) ───────────
    const setup_cmd = b.addSystemCommand(&.{
        "bash",
        "scripts/setup-global.sh",
    });
    setup_cmd.setCwd(b.path("."));
    setup_cmd.step.dependOn(b.getInstallStep());
    if (bundle_step) |bs| setup_cmd.step.dependOn(bs);
    const setup_step = b.step("setup", "Install Orbit globally (PATH + zig build run from anywhere)");
    setup_step.dependOn(&setup_cmd.step);

    // ── Unit tests (feature-organized under src/tests/) ─────────────────
    const test_module = b.createModule(.{
        .root_source_file = b.path("src/tests.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    test_module.addOptions("build_options", build_opts);
    test_module.addIncludePath(b.path("vendor"));
    test_module.addCSourceFile(.{
        .file = b.path("vendor/stb_truetype_impl.c"),
        .flags = &.{ "-std=c99", "-fno-sanitize=undefined" },
    });

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
        test_module.addCSourceFile(.{
            .file = b.path("src/platform/macos_icon.m"),
            .flags = &.{ "-fobjc-arc", "-fno-sanitize=undefined" },
        });
        test_module.linkFramework("AppKit", .{});
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
        .test_runner = .{
            .path = b.path("src/tests/runner.zig"),
            .mode = .simple,
        },
    });
    const run_unit_tests = b.addRunArtifact(unit_tests);
    run_unit_tests.expectExitCode(0);
    run_unit_tests.stdio = .inherit;
    const test_step = b.step("test", "Run feature unit tests (with live status)");
    test_step.dependOn(&run_unit_tests.step);

    // ── Security scan (secrets + injection heuristics) ───────────────────
    const security_module = b.createModule(.{
        .root_source_file = b.path("src/security/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    security_module.addOptions("build_options", build_opts);
    const security_exe = b.addExecutable(.{
        .name = "orbit-security-scan",
        .root_module = security_module,
    });
    const run_security = b.addRunArtifact(security_exe);
    run_security.expectExitCode(0);
    run_security.stdio = .inherit;
    if (b.args) |args| {
        run_security.addArgs(args);
    }
    const security_step = b.step("security-scan", "Scan codebase for secrets and injection risks");
    security_step.dependOn(&run_security.step);
}
