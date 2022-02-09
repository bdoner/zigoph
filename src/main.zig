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
    defer _ = gpa.deinit();
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

    var trns = try gopher.Transaction.execute(allocator, rqst);
    defer trns.deinit();

    state = .{
        .selectedLine = 0,
        .request = rqst,
        .transaction = &trns,
        .history = &history,
    };

    try history.append(state.request);
    try printTransactionResult();

    loop: while (true) {
        const chr = try std.io.getStdIn().reader().readByte();
        //std.log.warn("0x{x:0>2} ({d}) = '{c}'", .{ chr, chr, chr });
        switch (chr) {
            'r' => {
                // reload current page.
                // done by re-issuing the previous request.
                // the previous transaction is first free'd.

                state.transaction.deinit();
                state.transaction = &(try gopher.Transaction.execute(allocator, state.request));

                state.selectedLine = 0;

                try printTransactionResult();
            },
            'l' => {
                // follow selected link if possible.
                // done by reading the currently selected Entry and create and execute a new request,
                const entity = try getSelectedEntity();
                if (entity) |ent| {
                    state.request = try gopher.Request.new(
                        allocator,
                        ent.fieldType.toTransactionType().?,
                        ent.displayStr,
                        ent.selectorStr,
                        ent.host,
                        ent.port,
                        null,
                    );

                    try state.history.append(state.request);

                    state.transaction.deinit();
                    state.transaction = &(try gopher.Transaction.execute(allocator, state.request));

                    state.selectedLine = 0;

                    try printTransactionResult();
                }
            },
            'h' => {
                // pop a request from the history stack and request the request.
                var curReq = state.history.popOrNull(); // remove current request
                if (curReq) |r| { 
                    r.deinit(); // if it's removed from the history list it must be deinitialized. 
                }
                var prevRequest = state.history.popOrNull(); // take previous
                if (prevRequest) |req| {
                    state.request = req;

                    state.transaction.deinit();
                    state.transaction = &(try gopher.Transaction.execute(allocator, state.request));

                    state.selectedLine = 0;

                    try state.history.append(state.request);
                    try printTransactionResult();
                }
            },
            'k' => {
                if (state.selectedLine == 0) {
                    continue;
                }

                state.selectedLine -= 1;
                try printTransactionResult();
            },
            'j' => {
                if (state.selectedLine == state.transaction.lines()) {
                    continue;
                }

                state.selectedLine += 1;
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
    const bufferArea = (try termhelper.getConsoleHeight()) - 3; // -1 for the top, -2 for the bottom
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

    try std.io.getStdOut().writer().print(comptime ansi.csi.EraseInDisplay(2), .{});
    try updateMetadata();

    try std.io.getStdOut().writer().print(comptime ansi.csi.CursorPos(2, 1), .{});
    switch (state.transaction.*) {
        .Menu, .FullTextSearch => |*m| {
            for (try m.getEntities()) |ent, idx| {
                if (idx < sliceStart) continue;
                if (idx > sliceEnd) continue;

                try std.io.getStdOut().writer().print(comptime ansi.csi.EraseInLine(2), .{});
                if (idx == state.selectedLine) {
                    try std.io.getStdOut().writer().print(comptime ansi.color.Underline("[{s:>8}] {s}"), .{ @tagName(ent.fieldType), ent.displayStr });
                } else {
                    try std.io.getStdOut().writer().print("[{s:>8}] {s}", .{ @tagName(ent.fieldType), ent.displayStr });
                }

                if (idx != sliceEnd) {
                    try std.io.getStdOut().writer().print("\n", .{});
                }
            }
        },
        .TextFile => |m| {
            //try std.io.getStdOut().writer().print("{s}", .{m.getText()});

            var txtIt = std.mem.split(u8, m.getText(), "\n");
            var idx: u32 = 0;
            while (txtIt.next()) |ent| {
                defer idx += 1;

                if (idx < sliceStart) continue;
                if (idx > sliceEnd) continue;

                if (idx == state.selectedLine) {
                    try std.io.getStdOut().writer().print(comptime ansi.color.Bold("{s}"), .{ent});
                } else {
                    try std.io.getStdOut().writer().print("{s}", .{ent});
                }

                if (idx != sliceEnd) {
                    try std.io.getStdOut().writer().print("\n", .{});
                }
            }
        },
        else => @panic("transaction type not implemented"),
    }
}
