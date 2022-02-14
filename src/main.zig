const builtin = @import("builtin");
const std = @import("std");
const ansi = @import("ansi");
const gopher = @import("gopher.zig");
const termhelper = @import("termhelper.zig");

const State = struct {
    selectedLine: u32,
    request: *gopher.Request,
    transaction: *gopher.Transaction,
    history: *std.ArrayList(*gopher.Request),
};

var state: State = undefined;

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .verbose_log = false }){};
    defer std.debug.assert(!gpa.deinit());
    var allocator = gpa.allocator();

    try gopher.init();
    defer gopher.deinit();

    try termhelper.init();
    defer termhelper.deinit();

    var history = std.ArrayList(*gopher.Request).init(allocator);
    defer {
        for (history.items) |item| {
            item.deinit();
        }
        history.deinit();
    }

    const rqst = try gopher.Request.new(
        allocator,
        .Menu,
        "/",
        "/",
        "adamsgaard.dk",
        70,
        null,
    );

    state = .{
        .selectedLine = 0,
        .request = rqst,
        .transaction = try allocator.create(gopher.Transaction),
        .history = &history,
    };

    state.transaction.* = try gopher.Transaction.execute(allocator, rqst);
    defer {
        state.transaction.deinit();
        allocator.destroy(state.transaction);
    }

    try history.append(state.request);
    try printTransactionResult();

    loop: while (true) {
        const chr = try std.io.getStdIn().reader().readByte();
        //std.log.warn("0x{x:0>2} ({d}) = '{c}'", .{ chr, chr, chr });
        switch (chr) {
            'o' => {
                // Open connection to new server
                var hostPrompt = try termhelper.promptUserInput(allocator, "Enter hostname");
                if (hostPrompt == null) {
                    try printTransactionResult(); // Clear prompt
                    continue;
                }
                const host = hostPrompt.?;

                defer allocator.free(host);

                state.request = try gopher.Request.new(
                    allocator,
                    .Menu,
                    "/",
                    "/",
                    host,
                    70,
                    null,
                );

                try state.history.append(state.request);

                state.transaction.deinit();
                state.transaction.* = try gopher.Transaction.execute(allocator, state.request);

                state.selectedLine = 0;

                try printTransactionResult();
            },
            'r' => {
                // reload current page.
                // done by re-issuing the previous request.
                // the previous transaction is first free'd.

                state.transaction.deinit();
                state.transaction.* = try gopher.Transaction.execute(allocator, state.request);

                state.selectedLine = 0;

                try printTransactionResult();
            },
            'l' => {
                // follow selected link if possible.
                // done by reading the currently selected Entry and create and execute a new request,

                const entity = try getSelectedEntity();
                if (entity) |ent| {
                    var query: ?[]const u8 = null;
                    if (ent.fieldType.toTransactionType()) |tt| {
                        if (tt == .FullTextSearch) {
                            query = try termhelper.promptUserInput(allocator, "Enter query");
                            if (query == null) {
                                try printTransactionResult(); // Clear prompt
                                continue;
                            }
                        }
                    }

                    state.request = try gopher.Request.new(
                        allocator,
                        ent.fieldType.toTransactionType().?,
                        ent.displayStr,
                        ent.selectorStr,
                        ent.host,
                        ent.port,
                        query,
                    );

                    if (query) |q| {
                        allocator.free(q);
                    }

                    try state.history.append(state.request);

                    state.transaction.deinit();
                    state.transaction.* = try gopher.Transaction.execute(allocator, state.request);

                    state.selectedLine = 0;

                    try printTransactionResult();
                }
            },
            'h' => {
                // pop a request from the history stack and request the request.
                if (state.history.items.len < 2) {
                    continue;
                }

                var curReq = state.history.popOrNull(); // remove current request
                if (curReq) |r| {
                    r.deinit(); // if it's removed from the history list it must be deinitialized.
                }
                var prevRequest = state.history.popOrNull(); // take previous
                if (prevRequest) |req| {
                    state.request = req;

                    state.transaction.deinit();
                    state.transaction.* = try gopher.Transaction.execute(allocator, state.request);

                    state.selectedLine = 0;

                    try state.history.append(state.request);
                    try printTransactionResult();
                }
            },
            'k' => {
                if (state.selectedLine == 0) {
                    state.selectedLine = state.transaction.lines() - 1;
                } else {
                    state.selectedLine -= 1;
                }
                try printTransactionResult();
            },
            'j' => {
                if (state.selectedLine == state.transaction.lines() - 1) {
                    state.selectedLine = 0;
                } else {
                    state.selectedLine += 1;
                }
                try printTransactionResult();
            },
            'q' => break :loop,
            else => {},
        }
    }
}

fn getSelectedEntity() !?gopher.Entity {
    switch (state.transaction.*) {
        .Menu, .FullTextSearch => |*m| {
            for (try m.getEntities()) |ent, idx| {
                if (idx == state.selectedLine) {
                    if (ent.fieldType.isBrowsable()) {
                        return ent;
                    } else {
                        return null;
                    }
                }
            }
            return null;
        },
        else => return null,
    }
}

fn updateMetadata() !void {
    try termhelper.setTopLine(state.request.display, state.request.host, state.request.selector);
    var hist: [3][]const u8 = undefined;
    const histItems = @minimum(3, state.history.items.len);
    var i: u32 = 0;
    while (i < histItems) : (i += 1) {
        hist[i] = state.history.items[state.history.items.len - 1 - i].display;
    }
    try termhelper.setBottomLine(hist[0..histItems]);
}

fn printTransactionResult() !void {
    const bufferArea = (try termhelper.getConsoleSize()).nRows - 3; // -1 for the top, -2 for the bottom
    var halfBufferArea = @divFloor(bufferArea, 2);
    //if (halfBufferArea % 2 != 0) halfBufferArea -= 1;

    var sliceStart: u32 = 0;
    var sliceEnd: u32 = 0;
    if (state.transaction.lines() < bufferArea) {
        sliceStart = 0;
        sliceEnd = state.transaction.lines();
    } else {

        // If at the beginning
        if (state.selectedLine < halfBufferArea) {
            sliceStart = 0;
            sliceEnd = bufferArea;
        } // else if at the end
        else if (state.selectedLine + halfBufferArea > state.transaction.lines()) {
            sliceStart = state.transaction.lines() - bufferArea;
            sliceEnd = state.transaction.lines();
        } //else somewhere in between
        else {
            sliceStart = state.selectedLine - halfBufferArea;
            sliceEnd = state.selectedLine + halfBufferArea;
        }
    }

    const stdio = struct {
        pub fn print(comptime format: []const u8, args: anytype) !void {
            try std.io.getStdOut().writer().print(format, args);
        }
    };

    try stdio.print(comptime ansi.csi.EraseInDisplay(2), .{});
    try updateMetadata();

    try stdio.print(comptime ansi.csi.CursorPos(2, 1), .{});
    switch (state.transaction.*) {
        .Menu, .FullTextSearch => |*m| {
            for (try m.getEntities()) |ent, idx| {
                if (idx < sliceStart) continue;
                if (idx > sliceEnd) continue;

                // switch (ent.fieldType) {
                //     txt_f => '0',
                //     menu => '1',
                //     cso_book => '2',
                //     err => '3',
                //     binhex_f => '4',
                //     msdos_f => '5',
                //     uuenc_f => '6',
                //     idx_srch => '7',
                //     tel_sess => '8',
                //     bin_f => '9',
                //     red_srv => '+',
                //     gif => 'g',
                //     image => 'I',
                //     tn3270 => 'T',
                //     // Unofficial types?
                //     info => 'i',
                //     hlink => 'h',
                // }

                if (idx == state.selectedLine) {
                    try stdio.print(comptime ansi.color.Underline("[{s:>8}] {s}"), .{ @tagName(ent.fieldType), ent.displayStr });
                } else {
                    try stdio.print("[{s:>8}] {s}", .{ @tagName(ent.fieldType), ent.displayStr });
                }

                if (idx != sliceEnd) {
                    try stdio.print("\n", .{});
                }
            }
        },
        .TextFile => |m| {
            //try stdio.print("{s}", .{m.getText()});

            var txtIt = std.mem.split(u8, m.getText(), "\n");
            var idx: u32 = 0;
            while (txtIt.next()) |ent| {
                defer idx += 1;

                if (idx < sliceStart) continue;
                if (idx > sliceEnd) continue;

                if (idx == state.selectedLine) {
                    try stdio.print(comptime ansi.color.Bold("{s}"), .{ent});
                } else {
                    try stdio.print("{s}", .{ent});
                }

                if (idx != sliceEnd) {
                    try stdio.print("\n", .{});
                }
            }
        },
        else => try stdio.print(comptime ansi.color.Fg(.Red, "Handler for {s} is not implemented."), .{@tagName(state.transaction.*)}),
    }
}
