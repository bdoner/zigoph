const std = @import("std");

const gclient = @import("client.zig");
const gopher = @import("gopher.zig");
const gdisplay = @import("display.zig");

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    //defer _ = gpa.deinit();

    var allocator = gpa.allocator();

    // adamsgaard.dk
    // 46.23.94.178
    var client = gclient.Client.init(allocator, "sdf.org", 70);
    defer client.deinit();

    var display = try gdisplay.Display.init(&client.displayBuffer);
    defer display.deinit();

    const dispHelper = struct {
        pub fn update(a: std.mem.Allocator, d: gdisplay.Display, c: gclient.Client, item: gopher.Item) !void {
            try d.setTopLine(item.displayStr, item.host, item.selectorStr);

            const h = try c.getHistory();
            defer a.free(h);

            try d.setBottomLine(h);
        }
    };

    const indexPage = client.getIndex() catch @panic("Error listing index directory.");
    if (indexPage) |ip| {
        try dispHelper.update(allocator, display, client, ip);
    }

    loop: while (true) {
        try display.redraw();

        const chr = try std.io.getStdIn().reader().readByte();
        switch (chr) {
            'r' => {
                const _rp = try client.refreshPage();
                if (_rp) |rp| {
                    try dispHelper.update(allocator, display, client, rp);
                }
            },
            'l' => {
                const _np = try client.navigateToSelected();
                if (_np) |np| {
                    try dispHelper.update(allocator, display, client, np);
                }
            },
            //'l' => try client.goBack(),
            'k' => try client.navUp(),
            'j' => try client.navDown(),
            'q' => break :loop,
            else => {},
        }
    }
}

test "basic test" {
    try std.testing.expectEqual(@as(?gopher.ItemType, null), gopher.ItemType.getType('_'));
    try std.testing.expectEqual(gopher.ItemType.one, gopher.ItemType.getType('1').?);
    try std.testing.expectEqual(gopher.ItemType.plus, gopher.ItemType.getType('+').?);
}
