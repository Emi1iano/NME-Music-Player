const std = @import("std");

pub fn build(b: *std.Build) void {
    const target1 = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const exe = b.addExecutable(.{
        .name = "client",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target1,
            .optimize = optimize,
        }),
    });
    b.installArtifact(exe);
    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    //
    // Windows x64
    //
    const windows = b.addLibrary(.{
        .name = "backend",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/api.zig"),
            .target = b.resolveTargetQuery(.{
                .cpu_arch = .x86_64,
                .os_tag = .windows,
                .abi = .msvc,
            }),
            .optimize = optimize,
        }),
        .linkage = .dynamic,
    });

    const windows_install = b.addInstallArtifact(windows, .{
        .dest_dir = .{ .override = .{ .custom = "windows" } },
    });

    //
    // Linux x64
    //
    const linux = b.addLibrary(.{
        .name = "backend",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/api.zig"),
            .target = b.resolveTargetQuery(.{
                .cpu_arch = .x86_64,
                .os_tag = .linux,
                .abi = .gnu,
            }),
            .optimize = optimize,
        }),
        .linkage = .dynamic,
    });

    const linux_install = b.addInstallArtifact(linux, .{
        .dest_dir = .{ .override = .{ .custom = "linux" } },
    });

    //
    // Android ARM64
    //
    const android_arm64 = b.addLibrary(.{
        .name = "backend",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/api.zig"),
            .target = b.resolveTargetQuery(.{
                .cpu_arch = .aarch64,
                .os_tag = .linux,
                .abi = .android,
            }),
            .optimize = optimize,
        }),
        .linkage = .dynamic,
    });

    const android_arm64_install = b.addInstallArtifact(android_arm64, .{
        .dest_dir = .{ .override = .{ .custom = "android/arm64-v8a" } },
    });

    //
    // Android ARM32
    //
    const android_arm32 = b.addLibrary(.{
        .name = "backend",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/api.zig"),
            .target = b.resolveTargetQuery(.{
                .cpu_arch = .arm,
                .os_tag = .linux,
                .abi = .androideabi,
            }),
            .optimize = optimize,
        }),
        .linkage = .dynamic,
    });

    const android_arm32_install = b.addInstallArtifact(android_arm32, .{
        .dest_dir = .{ .override = .{ .custom = "android/armeabi-v7a" } },
    });

    //
    // Android x64
    //
    const android_x64 = b.addLibrary(.{
        .name = "backend",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/api.zig"),
            .target = b.resolveTargetQuery(.{
                .cpu_arch = .x86_64,
                .os_tag = .linux,
                .abi = .android,
            }),
            .optimize = optimize,
        }),
        .linkage = .dynamic,
    });

    const android_x64_install = b.addInstallArtifact(android_x64, .{
        .dest_dir = .{ .override = .{ .custom = "android/x86_64" } },
    });

    //
    // macOS ARM64
    //
    // const macos_arm64 = b.addLibrary(.{
    //     .name = "backend",
    //     .root_module = b.createModule(.{
    //         .root_source_file = b.path("api.zig"),
    //         .target = b.resolveTargetQuery(.{
    //             .cpu_arch = .aarch64,
    //             .os_tag = .macos,
    //         }),
    //         .optimize = optimize,
    //     }),
    //     .linkage = .dynamic,
    // });

    // const macos_arm64_install = b.addInstallArtifact(macos_arm64, .{
    //     .dest_dir = .{ .override = .{ .custom = "macos/arm64" } },
    // });

    //
    // macOS x64
    //
    // const macos_x64 = b.addLibrary(.{
    //     .name = "backend",
    //     .root_module = b.createModule(.{
    //         .root_source_file = b.path("api.zig"),
    //         .target = b.resolveTargetQuery(.{
    //             .cpu_arch = .x86_64,
    //             .os_tag = .macos,
    //         }),
    //         .optimize = optimize,
    //     }),
    //     .linkage = .dynamic,
    // });

    // const macos_x64_install = b.addInstallArtifact(macos_x64, .{
    //     .dest_dir = .{ .override = .{ .custom = "macos/x86_64" } },
    // });

    //
    // iOS ARM64
    //
    // const ios_arm64 = b.addLibrary(.{
    //     .name = "backend",
    //     .root_module = b.createModule(.{
    //         .root_source_file = b.path("api.zig"),
    //         .target = b.resolveTargetQuery(.{
    //             .cpu_arch = .aarch64,
    //             .os_tag = .ios,
    //         }),
    //         .optimize = optimize,
    //     }),
    //     .linkage = .dynamic,
    // });

    // const ios_arm64_install = b.addInstallArtifact(ios_arm64, .{
    //     .dest_dir = .{ .override = .{ .custom = "ios/device" } },
    // });

    //
    // iOS Simulator ARM64
    //
    // const ios_sim_arm64 = b.addLibrary(.{
    //     .name = "backend",
    //     .root_module = b.createModule(.{
    //         .root_source_file = b.path("api.zig"),
    //         .target = b.resolveTargetQuery(.{
    //             .cpu_arch = .aarch64,
    //             .os_tag = .ios,
    //         }),
    //         .optimize = optimize,
    //     }),
    //     .linkage = .dynamic,
    // });

    // const ios_sim_arm64_install = b.addInstallArtifact(ios_sim_arm64, .{
    //     .dest_dir = .{ .override = .{ .custom = "ios/simulator-arm64" } },
    // });

    //
    // Build everything
    //
    const all = b.step("all", "Build all native libraries");

    all.dependOn(&windows_install.step);
    all.dependOn(&linux_install.step);

    all.dependOn(&android_arm64_install.step);
    all.dependOn(&android_arm32_install.step);
    all.dependOn(&android_x64_install.step);

    // all.dependOn(&macos_arm64_install.step);
    // all.dependOn(&macos_x64_install.step);

    // all.dependOn(&ios_arm64_install.step);
    // all.dependOn(&ios_sim_arm64_install.step);

}
