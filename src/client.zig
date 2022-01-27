const std = @import("std");
const Item = @import("gopher.zig").Item;
const builtin = @import("builtin");

pub const Client = struct {
    items: std.ArrayList(Item),
    allocator: std.mem.Allocator,
    domain: []const u8,
    port: u16,
    selectedIndex: usize,
    history: std.ArrayList(Item),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, domain: []const u8, port: u16) Client {
        if (builtin.os.tag == .windows) {
            _ = std.os.windows.WSAStartup(2, 2) catch @panic("failed to call WSAStartup");
        }
        return .{
            .allocator = allocator,
            .domain = domain,
            .port = port,
            .selectedIndex = 0,
            .items = std.ArrayList(Item).init(allocator),
            .history = std.ArrayList(Item).init(allocator),
        };
    }

    pub fn deinit(self: Self) void {
        self.history.deinit();
        self.items.deinit();
        if (builtin.os.tag == .windows) {
            std.os.windows.WSACleanup() catch {}; // Don't care :))
        }
    }

    pub fn getIndex(self: *Self) !*Item {
        try self.history.append(.{
            .itemType = .menu,
            .displayStr = "/",
            .selectorStr = "",
            .domain = self.domain,
            .port = self.port,
        });
        try self.getDirectory("");

        return &self.history.items[0];
    }

    pub fn navDown(self: *Self) void {
        var newIndex = (self.selectedIndex + 1) % (self.items.items.len);
        while (true) {
            if (newIndex == self.selectedIndex) break; // We came around and found nothing.

            const i = self.items.items[newIndex];
            if (i.itemType.isSelectable()) {
                self.selectedIndex = newIndex;
                break;
            }
            newIndex = (newIndex + 1) % (self.items.items.len);
        }

        // self.printDirectory() catch {};
    }

    pub fn navUp(self: *Self) void {
        var newIndex = if (self.selectedIndex == 0) self.items.items.len - 1 else self.selectedIndex - 1;
        while (true) {
            if (newIndex == self.selectedIndex) break; // We came around and found nothing.

            const i = self.items.items[newIndex];
            if (i.itemType.isSelectable()) {
                self.selectedIndex = newIndex;
                break;
            }
            if (newIndex == 0) {
                newIndex = self.items.items.len - 1;
            } else {
                newIndex -= 1;
            }
        }

        // self.printDirectory() catch {};
    }

    pub fn refreshPage(self: *Self) !void {
        const currentPage = self.history.items[self.history.items.len - 1];
        try self.navigateTo(currentPage);
    }

    pub fn navigateToSelected(self: *Self) !void {
        var selectedItem = self.items.items[self.selectedIndex];
        try self.navigateTo(selectedItem);
    }

    /// Caller owns the returned memory
    pub fn getHistory(self: Self) ![][]const u8 {
        const stack = try self.allocator.alloc([]const u8, self.history.items.len);
        for(self.history.items) |itm, i| {
            stack[i] = itm.displayStr;
        }
        return stack;
    }

    fn navigateTo(self: *Self, item: Item) !void {
        try self.history.append(item);
        self.domain = item.domain;
        self.port = item.port;
        switch (item.itemType) {
            .menu => try self.getDirectory(item.selectorStr),
            else => try self.getTextFile(item.selectorStr),
        }
    }

    fn getDirectory(self: *Self, selectorStr: []const u8) !void {
        const stream = try self.getStream();

        try stream.writer().print("{s}\r\n", .{selectorStr});
        var resp = try stream.reader().readAllAlloc(self.allocator, std.math.maxInt(usize));
        //defer self.allocator.free(resp);

        self.items.clearAndFree();
        var lineIt = std.mem.tokenize(u8, resp, "\r\n");
        while (lineIt.next()) |line| {
            if (Item.parseDirItem(line)) |item| {
                try self.items.append(item);
            }
        }

        // try self.printDirectory();
    }

    /// Caller owns the memory returned
    fn getTextFile(self: *Self, selectorStr: []const u8) !void {
        const stream = try self.getStream();
        try stream.writer().print("{s}\r\n", .{selectorStr});
        var resp = try stream.reader().readAllAlloc(self.allocator, std.math.maxInt(usize));

        try std.io.getStdOut().writer().writeAll(resp);
    }

    // fn printDirectory(self: Self) !void {
    //     var i: usize = 0;
    //     while (i < 60) : (i += 1) {
    //         try std.io.getStdOut().writer().print("\n", .{});
    //     }
    //     for (self.items.items) |item, index| {
    //         const cur = if (index == self.selectedIndex)
    //             ">"
    //         else
    //             " ";
    //         try std.io.getStdOut().writer().print("{s}", .{cur});
    //         try std.io.getStdOut().writer().print(" [{s:>8}] {s}\n", .{ @tagName(item.itemType), item.displayStr });
    //     }
    // }

    fn getStream(self: Self) !std.net.Stream {
        return try std.net.tcpConnectToHost(self.allocator, self.domain, self.port);
    }
};

pub const ClientCommand = enum {
    ListDirectory,
    DownloadText,
    DownloadBinary,
};
