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
    });
    run_pack.has_side_effects = true;

    for (demos) |d| {
        const run_asm = b.addRunArtifact(softasm_exe);
        run_asm.setCwd(b.path("."));
        run_asm.addArgs(&.{ d.soft, d.sox });
        run_asm.has_side_effects = true;
        run_pack.step.dependOn(&run_asm.step);
    }

    const sysroot_step = b.step("sysroot", "Assemble .sox demos and pack init.sofs");
    sysroot_step.dependOn(&run_pack.step);

    // --- WASM runtime ---
    const runtime_mod = b.createModule(.{
        .root_source_file = b.path("runtime/src/main.zig"),
        .target = wasm_target,
        .optimize = optimize,
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