const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const server = b.addExecutable(.{
        .name = "server",
        .root_module = b.createModule(.{
            .root_source_file = b.path("ssimple.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const client = b.addExecutable(.{
        .name = "client",
        .root_module = b.createModule(.{
            .root_source_file = b.path("csimple.zig"),
            .target = target,
            .optimize = optimize,
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

    client_cmd.addPassthruArgs();
}