const std = @import("std");
const builtin = @import("builtin");
const Pkg = std.build.Pkg;
const string = []const u8;

pub const cache = ".zigmod/deps";

pub fn addAllTo(exe: *std.build.LibExeObjStep) void {
    checkMinZig(builtin.zig_version, exe);
    @setEvalBranchQuota(1_000_000);
    for (packages) |pkg| {
        exe.addPackage(pkg.pkg.?);
    }
    var llc = false;
    var vcpkg = false;
    inline for (comptime std.meta.declarations(package_data)) |decl| {
        const pkg = @as(Package, @field(package_data, decl.name));
        inline for (pkg.system_libs) |item| {
            exe.linkSystemLibrary(item);
            llc = true;
        }
        inline for (pkg.c_include_dirs) |item| {
            exe.addIncludeDir(@field(dirs, decl.name) ++ "/" ++ item);
            llc = true;
        }
        inline for (pkg.c_source_files) |item| {
            exe.addCSourceFile(@field(dirs, decl.name) ++ "/" ++ item, pkg.c_source_flags);
            llc = true;
        }
        vcpkg = vcpkg or pkg.vcpkg;
    }
    if (llc) exe.linkLibC();
    if (builtin.os.tag == .windows and vcpkg) exe.addVcpkgPaths(.static) catch |err| @panic(@errorName(err));
}

pub const Package = struct {
    directory: string,
    pkg: ?Pkg = null,
    c_include_dirs: []const string = &.{},
    c_source_files: []const string = &.{},
    c_source_flags: []const string = &.{},
    system_libs: []const string = &.{},
    vcpkg: bool = false,
};

fn checkMinZig(current: std.SemanticVersion, exe: *std.build.LibExeObjStep) void {
    const min = std.SemanticVersion.parse("null") catch return;
    if (current.order(min).compare(.lt)) @panic(exe.builder.fmt("Your Zig version v{} does not meet the minimum build requirement of v{}", .{current, min}));
}

pub const dirs = struct {
    pub const _root = "";
    pub const _0swf8h5rdusx = cache ++ "/../..";
    pub const _s84v9o48ucb0 = cache ++ "/v/git/github.com/nektro/zig-ansi/commit-d4a53bcac5b87abecc65491109ec22aaf5f3dc2f";
    pub const _o6ogpor87xc2 = cache ++ "/v/git/github.com/marlersoft/zigwin32/commit-032a1b51b83b8fe64e0a97d7fe5da802065244c6";
};

pub const package_data = struct {
    pub const _0swf8h5rdusx = Package{
        .directory = dirs._0swf8h5rdusx,
    };
    pub const _s84v9o48ucb0 = Package{
        .directory = dirs._s84v9o48ucb0,
        .pkg = Pkg{ .name = "ansi", .path = .{ .path = dirs._s84v9o48ucb0 ++ "/src/lib.zig" }, .dependencies = null },
    };
    pub const _o6ogpor87xc2 = Package{
        .directory = dirs._o6ogpor87xc2,
        .pkg = Pkg{ .name = "win32", .path = .{ .path = dirs._o6ogpor87xc2 ++ "/win32.zig" }, .dependencies = null },
    };
    pub const _root = Package{
        .directory = dirs._root,
    };
};

pub const packages = &[_]Package{
    package_data._s84v9o48ucb0,
    package_data._o6ogpor87xc2,
};

pub const pkgs = struct {
    pub const ansi = package_data._s84v9o48ucb0;
    pub const win32 = package_data._o6ogpor87xc2;
};

pub const imports = struct {
    pub const ansi = @import(".zigmod/deps/v/git/github.com/nektro/zig-ansi/commit-d4a53bcac5b87abecc65491109ec22aaf5f3dc2f/src/lib.zig");
    pub const win32 = @import(".zigmod/deps/v/git/github.com/marlersoft/zigwin32/commit-032a1b51b83b8fe64e0a97d7fe5da802065244c6/win32.zig");
};
