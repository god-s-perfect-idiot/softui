const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const native = b.standardTargetOptions(.{});

    const wasm_target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
    });

    // --- SoftASM assembler (native) ---
    const asm_mod = b.createModule(.{
        .root_source_file = b.path("softasm/asm_main.zig"),
        .target = native,
        .optimize = optimize,
    });
    const softasm_exe = b.addExecutable(.{
        .name = "softasm",
        .root_module = asm_mod,
    });
    b.installArtifact(softasm_exe);

    // --- SoftFS packer ---
    const pack_mod = b.createModule(.{
        .root_source_file = b.path("tools/pack_sofs.zig"),
        .target = native,
        .optimize = optimize,
    });
    const pack_exe = b.addExecutable(.{
        .name = "pack_sofs",
        .root_module = pack_mod,
    });
    b.installArtifact(pack_exe);

    // --- Desktop SVG → SIMG pipeline ---
    const gen_svgs_exe = b.addExecutable(.{
        .name = "gen_desktop_svgs",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/gen_desktop_svgs.zig"),
            .target = native,
            .optimize = optimize,
        }),
    });
    b.installArtifact(gen_svgs_exe);

    const svg_to_simg_exe = b.addExecutable(.{
        .name = "svg_to_simg",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/svg_to_simg.zig"),
            .target = native,
            .optimize = optimize,
        }),
    });
    b.installArtifact(svg_to_simg_exe);

    const rasterize_exe = b.addExecutable(.{
        .name = "rasterize_desktop",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/rasterize_desktop.zig"),
            .target = native,
            .optimize = optimize,
        }),
    });
    b.installArtifact(rasterize_exe);

    const run_raster = b.addRunArtifact(rasterize_exe);
    run_raster.setCwd(b.path("."));
    run_raster.addArtifactArg(gen_svgs_exe);
    run_raster.addArtifactArg(svg_to_simg_exe);
    run_raster.has_side_effects = true;

    // Assemble SoftASM demos into bootstrap/web/*.sox
    const demos = [_]struct { soft: []const u8, sox: []const u8 }{
        .{ .soft = "sysroot/donut.soft", .sox = "bootstrap/web/donut.sox" },
        .{ .soft = "sysroot/plasma.soft", .sox = "bootstrap/web/plasma.sox" },
        .{ .soft = "sysroot/stars.soft", .sox = "bootstrap/web/stars.sox" },
        .{ .soft = "sysroot/cube.soft", .sox = "bootstrap/web/cube.sox" },
        .{ .soft = "sysroot/fire.soft", .sox = "bootstrap/web/fire.sox" },
    };

    const run_pack = b.addRunArtifact(pack_exe);
    run_pack.setCwd(b.path("."));
    run_pack.addArg("bootstrap/web/init.sofs");
    run_pack.addArgs(&.{
        "donut.sox=bootstrap/web/donut.sox",
        "plasma.sox=bootstrap/web/plasma.sox",
        "stars.sox=bootstrap/web/stars.sox",
        "cube.sox=bootstrap/web/cube.sox",
        "fire.sox=bootstrap/web/fire.sox",
        "logo.simg=sysroot/logo.simg",
        "sample.png=sysroot/sample.png",
        "wallpaper.simg=sysroot/generated/wallpaper.simg",
        "icon_shell.simg=sysroot/generated/icon_shell.simg",
        "icon_clock.simg=sysroot/generated/icon_clock.simg",
        "icon_cursor.simg=sysroot/generated/icon_cursor.simg",
        "icon_keys.simg=sysroot/generated/icon_keys.simg",
        "icon_image.simg=sysroot/generated/icon_image.simg",
        "icon_music.simg=sysroot/generated/icon_music.simg",
        "icon_paint.simg=sysroot/generated/icon_paint.simg",
        "icon_uikit.simg=sysroot/generated/icon_uikit.simg",
        "icon_colors.simg=sysroot/generated/icon_colors.simg",
        "icon_text.simg=sysroot/generated/icon_text.simg",
        "icon_donut.simg=sysroot/generated/icon_donut.simg",
        "icon_plasma.simg=sysroot/generated/icon_plasma.simg",
        "icon_stars.simg=sysroot/generated/icon_stars.simg",
        "icon_cube.simg=sysroot/generated/icon_cube.simg",
        "icon_fire.simg=sysroot/generated/icon_fire.simg",
        "icon_calc.simg=sysroot/generated/icon_calc.simg",
        "icon_hello.simg=sysroot/generated/icon_hello.simg",
        "icon_drawer.simg=sysroot/generated/icon_drawer.simg",
    });
    run_pack.has_side_effects = true;
    run_pack.step.dependOn(&run_raster.step);

    for (demos) |d| {
        const run_asm = b.addRunArtifact(softasm_exe);
        run_asm.setCwd(b.path("."));
        run_asm.addArgs(&.{ d.soft, d.sox });
        run_asm.has_side_effects = true;
        run_pack.step.dependOn(&run_asm.step);
    }

    const sysroot_step = b.step("sysroot", "Assemble .sox demos, desktop icons, and pack init.sofs");
    sysroot_step.dependOn(&run_pack.step);

    // --- WASM runtime ---
    // SoftUI paints a full software framebuffer every frame; Debug WASM is too
    // slow for interactive browsing, so default the guest to ReleaseFast unless
    // the user explicitly passes -Doptimize=ReleaseSafe / ReleaseSmall / Debug.
    const wasm_optimize: std.builtin.OptimizeMode = switch (optimize) {
        .Debug => .ReleaseFast,
        else => optimize,
    };
    const runtime_mod = b.createModule(.{
        .root_source_file = b.path("runtime/src/main.zig"),
        .target = wasm_target,
        .optimize = wasm_optimize,
    });
    // Shared SoftASM ISA definitions for the VM.
    runtime_mod.addAnonymousImport("isa", .{
        .root_source_file = b.path("softasm/isa.zig"),
    });

    const softui = b.addExecutable(.{
        .name = "softui",
        .root_module = runtime_mod,
    });
    softui.entry = .disabled;
    softui.rdynamic = true;
    softui.import_memory = false;
    softui.initial_memory = 32 * 1024 * 1024;
    softui.max_memory = 64 * 1024 * 1024;
    softui.stack_size = 1 * 1024 * 1024;
    softui.export_memory = true;

    const install_wasm = b.addInstallArtifact(softui, .{
        .dest_dir = .{ .override = .{ .custom = "../bootstrap/web" } },
    });
    install_wasm.step.dependOn(&run_pack.step);

    b.getInstallStep().dependOn(&b.addInstallArtifact(softui, .{}).step);
    b.getInstallStep().dependOn(&install_wasm.step);
    b.getInstallStep().dependOn(&run_pack.step);

    // --- Localhost static server ---
    const serve_mod = b.createModule(.{
        .root_source_file = b.path("tools/serve.zig"),
        .target = native,
        .optimize = optimize,
    });
    const serve_exe = b.addExecutable(.{
        .name = "softui-serve",
        .root_module = serve_mod,
    });
    b.installArtifact(serve_exe);

    const run_serve = b.addRunArtifact(serve_exe);
    run_serve.step.dependOn(b.getInstallStep());
    run_serve.setCwd(b.path("."));
    run_serve.addArgs(&.{"bootstrap/web"});

    const serve_step = b.step("serve", "Build SoftUI + sysroot and serve bootstrap/web on :8080");
    serve_step.dependOn(&run_serve.step);

    const wasm_step = b.step("wasm", "Build softui.wasm + init.sofs into bootstrap/web");
    wasm_step.dependOn(&install_wasm.step);
}
