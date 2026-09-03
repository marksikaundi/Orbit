const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Optional GLFW discovery for Windows (vcpkg / manual SDK).
    // Example: zig build -Dglfw-path=C:/path/to/glfw
    const glfw_path = b.option([]const u8, "glfw-path", "Root path containing GLFW include/ and lib/ (Windows)");
    const glfw_include = b.option([]const u8, "glfw-include", "Path to GLFW headers");
    const glfw_lib = b.option([]const u8, "glfw-lib", "Path to GLFW library directory");

    // Absolute repo path so Orbit can refresh config source_root on launch.
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
    root_module.addCSourceFile(.{
        .file = b.path("vendor/stb_image_impl.c"),
        .flags = &.{ "-std=c99", "-fno-sanitize=undefined" },
    });

    addGlfwPaths(b, root_module, target, glfw_path, glfw_include, glfw_lib);

    // System GLFW via Homebrew / pkg / vcpkg.
    if (target.result.os.tag == .macos) {
        // Dock icon via NSApplication setApplicationIconImage.
        root_module.addCSourceFile(.{
            .file = b.path("src/platform/macos_icon.m"),
            .flags = &.{ "-fobjc-arc", "-fno-sanitize=undefined" },
        });
        root_module.addCSourceFile(.{
            .file = b.path("src/platform/macos_open.m"),
            .flags = &.{ "-fobjc-arc", "-fno-sanitize=undefined" },
        });
    } else if (target.result.os.tag == .windows) {
        root_module.addIncludePath(b.path("vendor/glad"));
        root_module.addCSourceFile(.{
            .file = b.path("vendor/glad/glad.c"),
            .flags = &.{ "-std=c99", "-fno-sanitize=undefined" },
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
    } else if (target.result.os.tag == .windows) {
        root_module.linkSystemLibrary("opengl32", .{});
        root_module.linkSystemLibrary("gdi32", .{});
        root_module.linkSystemLibrary("user32", .{});
        root_module.linkSystemLibrary("shell32", .{});
        root_module.linkSystemLibrary("ole32", .{});
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
    } else if (target.result.os.tag == .windows) {
        const run_detached = b.addSystemCommand(&.{
            "powershell",
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            "scripts/launch-detached.ps1",
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
    const setup_step = b.step("setup", "Install Orbit globally (PATH + launcher from anywhere)");
    if (target.result.os.tag == .windows) {
        const setup_cmd = b.addSystemCommand(&.{
            "powershell",
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            "scripts/setup-global.ps1",
        });
        setup_cmd.setCwd(b.path("."));
        setup_cmd.step.dependOn(b.getInstallStep());
        setup_step.dependOn(&setup_cmd.step);
    } else {
        const setup_cmd = b.addSystemCommand(&.{
            "bash",
            "scripts/setup-global.sh",
        });
        setup_cmd.setCwd(b.path("."));
        setup_cmd.step.dependOn(b.getInstallStep());
        if (bundle_step) |bs| setup_cmd.step.dependOn(bs);
        setup_step.dependOn(&setup_cmd.step);
    }

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
    test_module.addCSourceFile(.{
        .file = b.path("vendor/stb_image_impl.c"),
        .flags = &.{ "-std=c99", "-fno-sanitize=undefined" },
    });

    addGlfwPaths(b, test_module, target, glfw_path, glfw_include, glfw_lib);

    if (target.result.os.tag == .macos) {
        test_module.linkSystemLibrary("glfw", .{});
        test_module.linkFramework("OpenGL", .{});
        test_module.linkFramework("Cocoa", .{});
        test_module.linkFramework("IOKit", .{});
        test_module.linkFramework("CoreVideo", .{});
        test_module.addCSourceFile(.{
            .file = b.path("src/platform/macos_icon.m"),
            .flags = &.{ "-fobjc-arc", "-fno-sanitize=undefined" },
        });
        test_module.addCSourceFile(.{
            .file = b.path("src/platform/macos_open.m"),
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
    } else if (target.result.os.tag == .windows) {
        test_module.addIncludePath(b.path("vendor/glad"));
        test_module.addCSourceFile(.{
            .file = b.path("vendor/glad/glad.c"),
            .flags = &.{ "-std=c99", "-fno-sanitize=undefined" },
        });
        test_module.linkSystemLibrary("glfw", .{});
        test_module.linkSystemLibrary("opengl32", .{});
        test_module.linkSystemLibrary("gdi32", .{});
        test_module.linkSystemLibrary("user32", .{});
        test_module.linkSystemLibrary("shell32", .{});
        test_module.linkSystemLibrary("ole32", .{});
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

fn addGlfwPaths(
    b: *std.Build,
    module: *std.Build.Module,
    target: std.Build.ResolvedTarget,
    glfw_path: ?[]const u8,
    glfw_include: ?[]const u8,
    glfw_lib: ?[]const u8,
) void {
    if (target.result.os.tag == .macos) {
        if (target.result.cpu.arch == .aarch64) {
            module.addIncludePath(.{ .cwd_relative = "/opt/homebrew/include" });
            module.addLibraryPath(.{ .cwd_relative = "/opt/homebrew/lib" });
        } else {
            module.addIncludePath(.{ .cwd_relative = "/usr/local/include" });
            module.addLibraryPath(.{ .cwd_relative = "/usr/local/lib" });
        }
        return;
    }

    if (target.result.os.tag != .windows) return;

    if (glfw_include) |inc| {
        module.addIncludePath(.{ .cwd_relative = inc });
    } else if (glfw_path) |root| {
        module.addIncludePath(.{ .cwd_relative = b.fmt("{s}/include", .{root}) });
    } else {
        // Common defaults: vcpkg, local SDK folder.
        module.addIncludePath(.{ .cwd_relative = "C:/vcpkg/installed/x64-windows/include" });
        module.addIncludePath(.{ .cwd_relative = "C:/glfw/include" });
    }

    if (glfw_lib) |lib| {
        module.addLibraryPath(.{ .cwd_relative = lib });
    } else if (glfw_path) |root| {
        module.addLibraryPath(.{ .cwd_relative = b.fmt("{s}/lib", .{root}) });
    } else {
        module.addLibraryPath(.{ .cwd_relative = "C:/vcpkg/installed/x64-windows/lib" });
        module.addLibraryPath(.{ .cwd_relative = "C:/glfw/lib" });
    }
}
