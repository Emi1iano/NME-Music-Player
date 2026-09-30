const std = @import("std");

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
}