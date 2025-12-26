const std = @import("std");
const manifest = @import("build.zig.zon");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lua_dep = b.dependency("lua", .{});
    const lua_lib = b.addLibrary(.{
        .name = "lua",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
        .linkage = .static,
    });
    lua_lib.root_module.addCSourceFiles(.{
        .root = lua_dep.path("src"),
        .files = lua_src_files,
    });
    lua_lib.root_module.addIncludePath(lua_dep.path("src"));

    const translate_lua = b.addTranslateC(.{
        .root_source_file = b.path("include.h"),
        .target = target,
        .optimize = optimize,
    });
    translate_lua.addIncludePath(lua_dep.path("src"));

    const mod = b.addModule("zlua", .{
        .root_source_file = b.path("src/root.zig"),
        .optimize = optimize,
        .target = target,
    });
    mod.linkLibrary(lua_lib);
    mod.addImport("c", translate_lua.createModule());

    const zlua_lib = b.addLibrary(.{
        .name = @tagName(manifest.name),
        .root_module = mod,
    });
    b.installArtifact(zlua_lib);
}

const lua_src_files = &.{
    "lapi.c",
    "lcode.c",
    "lctype.c",
    "ldebug.c",
    "ldo.c",
    "ldump.c",
    "lfunc.c",
    "lgc.c",
    "llex.c",
    "lmem.c",
    "lobject.c",
    "lopcodes.c",
    "lparser.c",
    "lstate.c",
    "lstring.c",
    "ltable.c",
    "ltm.c",
    "lundump.c",
    "lvm.c",
    "lzio.c",
    "lauxlib.c",
    "lbaselib.c",
    "lcorolib.c",
    "ldblib.c",
    "liolib.c",
    "lmathlib.c",
    "loadlib.c",
    "loslib.c",
    "lstrlib.c",
    "ltablib.c",
    "lutf8lib.c",
    "linit.c",
};
