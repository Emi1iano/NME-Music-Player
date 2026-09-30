const std = @import("std");

const build_targets = struct {
    target: std.Target.Query,
    path: []const u8,
};
const targets: [2]build_targets = .{
    .{ .target = .{ .cpu_arch = .x86_64, .os_tag = .windows, .abi = .msvc }, .path = "windows" },
    .{ .target = .{ .cpu_arch = .aarch64, .os_tag = .linux, .abi = .android }, .path = "android/arm64" },
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const server = b.addExecutable(.{
        .name = "server",
        .root_module = b.createModule(.{
            .root_source_file = b.path("server.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const mod = b.addModule("server", .{
        .root_source_file = b.path("server.zig"),
        .target = target,
    });
    const client = b.addExecutable(.{
        .name = "client",
        .root_module = b.createModule(.{
            .root_source_file = b.path("client.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "server", .module = mod },
            },
        }),
    });

    b.installArtifact(server);
    b.installArtifact(client);

    const server_step = b.step("server", "Run the server");
    const client_step = b.step("client", "Run the client");

    const server_cmd = b.addRunArtifact(server);
    const client_cmd = b.addRunArtifact(client);

    server_step.dependOn(&server_cmd.step);
    client_step.dependOn(&client_cmd.step);

    server_cmd.step.dependOn(b.getInstallStep());
    client_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        client_cmd.addArgs(args);
    }

    const all = b.step("all", "Build all native libraries");
    for (targets) |system| {
        const lib = b.addLibrary(.{
            .name = "backend",
            .root_module = b.createModule(.{
                .root_source_file = b.path("api.zig"),
                .target = b.resolveTargetQuery(system.target),
                .optimize = optimize,
            }),
            .linkage = .dynamic,
        });
        const install = b.addInstallArtifact(lib, .{
            .dest_dir = .{ .override = .{ .custom = system.path } },
        });
        all.dependOn(&install.step);
    }
}
