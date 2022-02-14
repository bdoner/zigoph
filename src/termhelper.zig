const builtin = @import("builtin");
const std = @import("std");
const ansi = @import("ansi");

const win32 = @import("win32");

// *** windows ***
const console = win32.system.console;
const HANDLE = win32.foundation.HANDLE;
const WIN32_ERROR = win32.foundation.WIN32_ERROR;

var h_in: HANDLE = undefined;
var h_out: HANDLE = undefined;

var originalStdInMode: u32 = 0;
var originalStdOutMode: u32 = 0;

// *** *nix stuff ***
const TIOCGWINSZ = 0x5413;
var original_termios: std.os.termios = undefined;
var tty: std.fs.File = undefined;

pub fn init() !void {
    errdefer deinit();
    if (builtin.os.tag == .windows) {
        // Store initial consolemode for stdin and stdout
        h_in = console.GetStdHandle(console.STD_INPUT_HANDLE);
        h_out = console.GetStdHandle(console.STD_OUTPUT_HANDLE);

        originalStdInMode = try getConsoleMode(h_in);
        originalStdOutMode = try getConsoleMode(h_out);
    } else {
        tty = try std.fs.cwd().openFile("/dev/tty", .{ .mode = .read_write });
        original_termios = try std.os.tcgetattr(tty.handle);
    }

    try enableVt100Parsing();

    // Hide Cursor
    try _write("\x1B[?25l", .{});

    // Switch to alternate screen buffer
    try _write("\x1B[?1049h", .{});

    try setScrollRegion();
}

pub fn deinit() void {

    // Show cursor.
    _write("\x1B[?25h", .{}) catch {};

    // Reset scroll region
    _write("\x1B[r", .{}) catch {};

    // Switch to main screen buffer
    _write("\x1B[?1049l", .{}) catch {};

    if (builtin.os.tag == .windows) {
        // Restore ConsoleMode to original values
        setConsoleMode(h_in, originalStdInMode) catch {};
        setConsoleMode(h_out, originalStdOutMode) catch {};
    } else {
        std.os.tcsetattr(tty.handle, .FLUSH, original_termios) catch {};
        tty.close();
    }
}

fn setScrollRegion() !void {
    const cSize = try getConsoleSize();
    // Set scroll region to exclude top and bottom.
    try _write("\x1B[{d};{d}r", .{ 2, cSize.nRows - 1 });
}

pub fn setTopLine(disp: []const u8, domain: []const u8, selector: []const u8) !void {
    try setScrollRegion();
    try _write(comptime ansi.csi.CursorPos(1, 1), .{});
    try _write(comptime ansi.csi.EraseInLine(2), .{});
    try _write(comptime ansi.color.Fg(.Red, "{s}") ++ " - " ++ ansi.color.Bold("{s}") ++ "{s}", .{ disp, domain, selector });
}

pub fn setCursorPos(x: u32, y: u32) !void {
    try _write("\x1B[{d};{d}H", .{ y, x }); // SetCurPos (y, x)
}

pub fn setBottomLine(hist: [][]const u8) !void {
    try setScrollRegion();

    var cSize = try getConsoleSize();

    try _write("\x1B[{d};{d}H", .{ cSize.nRows, 1 }); // SetCurPos (y, x)
    try _write(comptime ansi.csi.EraseInLine(2), .{});

    if (hist.len == 0) {
        return;
    }

    var i: u32 = @intCast(u32, hist.len);
    while (i > 0) : (i -= 1) {
        if (i < hist.len) {
            try _write(" < ", .{});
        }

        if (i == 1) { // this is the current item
            try _write("[" ++ comptime ansi.color.Underline("{s}") ++ "]", .{hist[i - 1]});
        } else {
            try _write("[{s}]", .{hist[i - 1]});
        }
    }
}

/// Prompt the user for a single-line input such as a query or a hostname for searching or navigating.
/// The user can cancel a prompt by hitting ESC in which case the result is null.
pub fn promptUserInput(allocator: std.mem.Allocator, comptime title: []const u8) !?[]const u8 {
    comptime {
        const max_chars = 16;
        if (title.len > max_chars) {
            @compileError(std.fmt.comptimePrint("title cannot exceed {d} characters, but '" ++ title ++ "'' is {d} characters.", .{ max_chars, title.len }));
        }

        if (title.len == 0) {
            @compileError("title must be given, but lenght of title was 0.");
        }
    }
    const boxMinWidth = comptime title.len + 2 + 4 + 5; // 2 = margin around title, 4 for left side, 5 for right side (includes shadow)
    const consSize = try getConsoleSize();
    const consWidthHalf = @divFloor(consSize.nCols, 2);

    const boxWidth: u16 = @truncate(u16, @maximum(boxMinWidth, @divFloor(consSize.nCols, 100) * 70));
    const boxWidthHalf = @divFloor(boxWidth, 2);

    const boxColOffset = consWidthHalf - boxWidthHalf;

    const consHalfHeight = @divFloor(consSize.nRows, 2);
    // --------- draw input box
    // Box is a total of 7 rows tall. Topmost row is at consHalfHeight-3 and bottommost row is at consHalfHeight+3
    // The input starts at consHalfHeight+4.
    // The width is variable. Starts at boxColOffset and goes to boxColOffset+boxWidth
    //
    // Box is ▒ (177)
    // Shadow is ░ (176)
    // lines are ┐└│┘┌ ─

    const isWin = builtin.os.tag == .windows;
    const box: []const u8 = if (isWin) &"\xb1".* else &"\u{2592}".*;
    const shadow: []const u8 = if(isWin) &"\xb0".* else &"\u{2591}".*;// &.{176};
    const line: []const u8 = if(isWin) &"\xc3".* else &"\u{2500}".*;// &.{196};
    const pipe: []const u8 = if(isWin) &"\xb3".* else &"\u{2502}".*;// &.{179};
    const cornBR: []const u8 = if(isWin) &"\xd9".* else &"\u{2518}".*;// &.{217};
    const cornTL: []const u8 = if(isWin) &"\xda".* else &"\u{250c}".*;// &.{218};
    const cornTR: []const u8 = if(isWin) &"\xbf".* else &"\u{2510}".*;// &.{191};
    const cornBL: []const u8 = if(isWin) &"\xc0".* else &"\u{2514}".*;// &.{192};

    // top line
    try _write("\x1B[{d};{d}H", .{ consHalfHeight - 3, boxColOffset });
    var i: u16 = 0;
    while (i < boxWidth - 1) : (i += 1) {
        try _write(box, .{});
    }

    // title line part 1
    try _write("\x1B[{d};{d}H", .{ consHalfHeight - 2, boxColOffset });
    i = 0;
    while (i < @divFloor(boxWidth - (title.len + 2 + 5), 2)) : (i += 1) { // (title.len + padding) + right side box
        try _write(box, .{});
    }

    // title here
    try _write(" {s} ", .{title});

    // title line part 2
    i += @truncate(u16, title.len + 2);
    while (i < boxWidth - 1) : (i += 1) {
        try _write(box, .{});
    }
    try _write(shadow, .{});

    // Top text border
    try _write("\x1B[{d};{d}H", .{ consHalfHeight - 1, boxColOffset });
    try _write(box ++ " " ++ cornTL, .{});
    i = 3; // already offset from above write
    while (i < boxWidth - 4) : (i += 1) {
        try _write(line, .{});
    }
    try _write(cornTR ++ " " ++ box ++ shadow, .{});

    // Input row
    try _write("\x1B[{d};{d}H", .{ consHalfHeight, boxColOffset });
    try _write(box ++ " " ++ pipe, .{});
    i = 3; // already offset from above write
    while (i < boxWidth - 4) : (i += 1) {
        try _write(" ", .{});
    }
    try _write(pipe ++ " " ++ box ++ shadow, .{});

    // Bottom text border
    try _write("\x1B[{d};{d}H", .{ consHalfHeight + 1, boxColOffset });
    try _write(box ++ " " ++ cornBL, .{});
    i = 3; // already offset from above write
    while (i < boxWidth - 4) : (i += 1) {
        try _write(line, .{});
    }
    try _write(cornBR ++ " " ++ box ++ shadow, .{});

    // Bottom box
    try _write("\x1B[{d};{d}H", .{ consHalfHeight + 2, boxColOffset });
    i = 0;
    while (i < boxWidth - 1) : (i += 1) {
        try _write(box, .{});
    }
    try _write(shadow, .{});

    // Bottom shadow
    try _write("\x1B[{d};{d}H", .{ consHalfHeight + 3, boxColOffset + 1 });
    i = 0;
    while (i < boxWidth - 1) : (i += 1) {
        try _write(shadow, .{});
    }

    // place cursor to input
    try _write("\x1B[{d};{d}H", .{ consHalfHeight, boxColOffset + 4 });

    // Show cursor.
    try _write("\x1B[?25h", .{});

    // Hide Cursor
    defer _write("\x1B[?25l", .{}) catch {};

    var query = std.ArrayList(u8).init(allocator);
    defer query.deinit();
    loop: while (true) {
        const chr = try std.io.getStdIn().reader().readByte();

        // TODO: Handle backspace, ESC, NL, ... more?
        switch (chr) {
            '\r', '\n' => break :loop,
            '\x1B' => { // ESC key
                return null;
            },
            '\x08' => { // Backspace key
                if (query.popOrNull()) |_| {
                    try _write("{c} {c}", .{ chr, chr }); // BS, erase, BS
                }
            },
            else => {
                if (query.items.len >= boxWidth) {
                    continue;
                }
                try query.append(chr);
                try _write("{c}", .{chr});
            },
        }
    }

    return query.toOwnedSlice();
}

fn _write(comptime format: []const u8, args: anytype) !void {
    try std.io.getStdOut().writer().print(format, args);
}

// ..
// **** Win32 API stuff ****
// ..

const winsize = packed struct {
    ws_row: u16,
    ws_col: u16,
    ws_xpixel: u16,
    ws_ypixel: u16,
};

const consoleerror = error{
    getHeightFailed,
};

const ConsoleSize = struct {
    nCols: u32,
    nRows: u32,
};

pub fn getConsoleSize() !ConsoleSize {
    if (builtin.os.tag == .windows) {
        var info: console.CONSOLE_SCREEN_BUFFER_INFO = undefined;
        const r = console.GetConsoleScreenBufferInfo(h_out, &info);
        if (r == 0) {
            const lastErr = win32.foundation.GetLastError();
            std.log.err("Failed GetConsoleScreenBufferInfoEx: {s}\n", .{lastErr});
            return consoleerror.getHeightFailed;
        }

        return ConsoleSize{ .nRows = @intCast(u32, info.srWindow.Bottom), .nCols = @intCast(u32, info.srWindow.Right) };
    } else {
        // struct winsize { unsigned short ws_row, ws_col, ws_xpixel, ws_ypixel; };
        var w: winsize = undefined;
        _ = std.os.linux.ioctl(1, TIOCGWINSZ, @ptrToInt(&w));

        return ConsoleSize{ .nRows = w.ws_row, .nCols = w.ws_col };
    }
}

fn getConsoleMode(handle: HANDLE) !u32 {
    if (builtin.os.tag != .windows) {
        return null;
    }

    var cmode: console.CONSOLE_MODE = undefined;
    _ = console.GetConsoleMode(handle, &cmode);

    return @enumToInt(cmode);
}

fn enableVt100Parsing() !void {
    if (builtin.os.tag == .windows) {

        // Set stdout to process vt100 escape sequences
        _ = console.SetConsoleMode(h_out, console.CONSOLE_MODE.initFlags(.{
            .ENABLE_PROCESSED_INPUT = 1, //ENABLE_PROCESSED_OUTPUT
            .ENABLE_LINE_INPUT = 1, //ENABLE_WRAP_AT_EOL_OUTPUT
            .ENABLE_ECHO_INPUT = 1, //ENABLE_VIRTUAL_TERMINAL_PROCESSING
        }));

        // Set stdin to not wait for newline
        _ = console.SetConsoleMode(h_in, console.CONSOLE_MODE.initFlags(.{
            .ENABLE_LINE_INPUT = 0, //ENABLE_WRAP_AT_EOL_OUTPUT
            .ENABLE_ECHO_INPUT = 0, //ENABLE_VIRTUAL_TERMINAL_PROCESSING
        }));
    } else {
        var raw = original_termios;
        raw.lflag &= ~@as(
            std.os.linux.tcflag_t,
            std.os.linux.ECHO | std.os.linux.ICANON | std.os.linux.ISIG | std.os.linux.IEXTEN,
        );
        raw.iflag &= ~@as(
            std.os.linux.tcflag_t,
            std.os.linux.IXON | std.os.linux.ICRNL | std.os.linux.BRKINT | std.os.linux.INPCK | std.os.linux.ISTRIP,
        );
        raw.cc[std.os.system.V.TIME] = 0;
        raw.cc[std.os.system.V.MIN] = 1;
        try std.os.tcsetattr(tty.handle, .FLUSH, raw);
    }
}

fn setConsoleMode(handle: HANDLE, mode: u32) !void {
    if (builtin.os.tag != .windows) {
        return;
    }

    _ = console.SetConsoleMode(handle, @intToEnum(console.CONSOLE_MODE, mode));
}
