const std = @import("std");

const gclient = @import("client.zig");
const gopher = @import("gopher.zig");
const gdisplay = @import("display.zig");

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    
    var allocator = gpa.allocator();

    // adamsgaard.dk
    // 46.23.94.178
    var client = gclient.Client.init(allocator, "sdf.org", 70);
    defer client.deinit();

    var display = try gdisplay.Display.init();
    defer display.deinit();

    const indexPage = client.getIndex() catch @panic("Error listing index directory.");
    try display.setTopLine(indexPage.displayStr, indexPage.domain, indexPage.selectorStr);

    const hist = try client.getHistory();
    try display.setBottomLine(hist);
    allocator.free(hist);

    loop: while (true) {
        const chr = try std.io.getStdIn().reader().readByte();
        switch (chr) {
            'r' => {
                client.refreshPage() catch |err| {
                    try std.io.getStdErr().writer().print("Error listing directory: {s}\n", .{err});
                };
            },
            'l' => try client.navigateToSelected(),
            //'l' => try client.goBack(),
            'j' => client.navDown(),
            'k' => client.navUp(),
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
