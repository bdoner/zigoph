const std = @import("std");
const Item = @import("gopher.zig").Item;
const ItemType = @import("gopher.zig").ItemType;
const builtin = @import("builtin");

pub const Client = struct {
    displayBuffer: []u8,
    allocator: std.mem.Allocator,
    host: []const u8,
    port: u16,
    selectedIndex: usize,
    history: std.ArrayList(Item),
    lastResp: *Response,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, host: []const u8, port: u16) Client {
        if (builtin.os.tag == .windows) {
            _ = std.os.windows.WSAStartup(2, 2) catch @panic("failed to call WSAStartup");
        }

        return .{
            .allocator = allocator,
            .host = host,
            .port = port,
            .selectedIndex = 0,
            .displayBuffer = &"".*,
            .lastResp = Response.init(allocator),
            .history = std.ArrayList(Item).init(allocator),
        };
    }

    pub fn deinit(self: Self) void {
        self.history.deinit();
        self.allocator.free(self.displayBuffer);
        if (builtin.os.tag == .windows) {
            std.os.windows.WSACleanup() catch {}; // Don't care :))
        }
    }

    pub fn getIndex(self: *Self) !?Item {
        const itm = Item{
            .itemType = .menu,
            .displayStr = "/",
            .selectorStr = "",
            .host = self.host,
            .port = self.port,
        };
        return try self.navigateTo(itm);
    }

    pub fn navDown(self: *Self) !void {
        var newIndex = (self.selectedIndex + 1) % (self.lastResp.items.items.len);
        while (true) {
            if (newIndex == self.selectedIndex) break; // We came around and found nothing.

            const i = self.lastResp.items.items[newIndex];
            if (i.itemType.isSelectable()) {
                self.selectedIndex = newIndex;
                break;
            }
            newIndex = (newIndex + 1) % (self.lastResp.items.items.len);
        }

        try self.renderStateToDisplayBuffer();
    }

    pub fn navUp(self: *Self) !void {
        var newIndex = if (self.selectedIndex == 0) self.lastResp.items.items.len - 1 else self.selectedIndex - 1;
        while (true) {
            if (newIndex == self.selectedIndex) break; // We came around and found nothing.

            const i = self.lastResp.items.items[newIndex];
            if (i.itemType.isSelectable()) {
                self.selectedIndex = newIndex;
                break;
            }
            if (newIndex == 0) {
                newIndex = self.lastResp.items.items.len - 1;
            } else {
                newIndex -= 1;
            }
        }

        try self.renderStateToDisplayBuffer();
    }

    pub fn refreshPage(self: *Self) !?Item {
        const currentPage = self.history.items[self.history.items.len - 1];
        return try self.navigateTo(currentPage);
    }

    pub fn navigateToSelected(self: *Self) !?Item {
        var selectedItem = self.lastResp.items.items[self.selectedIndex];
        return try self.navigateTo(selectedItem);
    }

    /// Caller owns the returned memory
    pub fn getHistory(self: Self) ![][]const u8 {
        const stack = try self.allocator.alloc([]const u8, self.history.items.len);
        for (self.history.items) |itm, i| {
            stack[i] = itm.displayStr;
        }
        return stack;
    }

    fn navigateTo(self: *Self, item: Item) !?Item {
        try self.history.append(item);

        self.host = item.host;
        self.port = item.port;
        self.selectedIndex = 0;

        const conn = try self.openConnection();
        defer conn.close();

        try conn.writer().print("{s}\r\n", .{item.selectorStr});
        var respBody = try conn.reader().readAllAlloc(self.allocator, std.math.maxInt(usize));
        defer self.allocator.free(respBody);

        var resp = Response.init(self.allocator);
        if (item.itemType.isSelectable()) {
            self.lastResp.deinit();
            self.lastResp = resp;
        }

        try resp.fill(item.itemType, respBody);
        try self.renderStateToDisplayBuffer();

        return item;
    }

    fn openConnection(self: Self) !std.net.Stream {
        return try std.net.tcpConnectToHost(self.allocator, self.host, self.port);
    }

    fn renderStateToDisplayBuffer(self: *Self) !void {
        var al = std.ArrayList(u8).init(self.allocator);
        defer al.deinit();
        for (self.lastResp.items.items) |item, index| {
            const cur = if (index == self.selectedIndex)
                ">"
            else
                " ";
            try std.fmt.format(al.writer(), "{s}", .{cur});
            try std.fmt.format(al.writer(), " [{s:>8}] {s}\n", .{ @tagName(item.itemType), item.displayStr });
        }

        self.allocator.free(self.displayBuffer);
        self.displayBuffer = try self.allocator.dupe(u8, al.toOwnedSlice());
    }
};

pub const Response = struct {
    buffer: ?[]u8,
    items: std.ArrayList(Item),
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) *Response {
        var r = allocator.create(Response) catch @panic("OOM Creating response");
        r.buffer = null;
        r.allocator = allocator;
        r.items = std.ArrayList(Item).init(allocator);

        return r;
    }

    pub fn deinit(self: *Self) void {
        if (self.buffer) |b| {
            self.allocator.free(b);
        }
        for(self.items.items) |item| {
            self.allocator.free(item.host);
            self.allocator.free(item.selectorStr);
            self.allocator.free(item.displayStr);

        }
        self.items.deinit();
    }

    pub fn fill(self: *Self, itemType: ItemType, body: []const u8) !void {
        if (self.buffer) |b| {
            self.allocator.free(b);
        }
        self.buffer = try self.allocator.dupe(u8, body);
        self.items.clearAndFree();

        if (itemType.isSelectable()) {
            var lineIt = std.mem.tokenize(u8, body, "\r\n");
            while (lineIt.next()) |line| {
                if (try Item.parseDirItem(self.allocator, line)) |item| {
                    try self.items.append(item);
                } else {
                    break;
                }
            }
        }
    }
};
