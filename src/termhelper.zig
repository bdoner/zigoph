const std = @import("std");
const builtin = @import("builtin");
const console = win32.system.console;
const HANDLE = win32.foundation.HANDLE;
const WIN32_ERROR = win32.foundation.WIN32_ERROR;

const ansi = @import("ansi");
const win32 = @import("win32");

const TIOCGWINSZ = 0x5413;
var h_in: HANDLE = undefined;
var h_out: HANDLE = undefined;

var originalStdInMode: u32 = 0;
var originalStdOutMode: u32 = 0;

pub fn init() !void {
    errdefer deinit();
    if (builtin.os.tag == .windows) {
        // Store initial consolemode for stdin and stdout
        h_in = console.GetStdHandle(console.STD_INPUT_HANDLE);
        h_out = console.GetStdHandle(console.STD_OUTPUT_HANDLE);

        originalStdInMode = try getConsoleMode(h_in);
        originalStdOutMode = try getConsoleMode(h_out);

        // Enable vt100 sequence handling on windows. Changes the ConsoleMode
        try enableVt100Parsing();
    }

    // Hide Cursor
    //try _write("\x1B[?25l", .{});

    // Switch to alternate screen buffer
    try _write("\x1B[?1049h", .{});

    const consoleHeight = try getConsoleHeight();
    // Set scroll region to exclude top and bottom.
    try _write("\x1B[{d};{d}r", .{ 2, consoleHeight - 1 });
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
    }
}

pub fn setTopLine(disp: []const u8, domain: []const u8, selector: []const u8) !void {
    try _write(comptime ansi.csi.CursorPos(1, 1), .{});
    try _write(comptime ansi.csi.EraseInLine(2), .{});
    try _write(comptime ansi.color.Fg(.Red, "{s}") ++ " - " ++ ansi.color.Bold("{s}") ++ "{s}", .{ disp, domain, selector });
}

pub fn setCursorPos(x: u32, y: u32) !void {
    try _write("\x1B[{d};{d}H", .{ y, x }); // SetCurPos (y, x)
}

pub fn setBottomLine(hist: [][]const u8) !void {
    var botLine = try getConsoleHeight();

    try _write("\x1B[{d};{d}H", .{ botLine, 1 }); // SetCurPos (y, x)
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

pub fn scrollTextUp() !void {
    //const consoleHeight = try getConsoleHeight();
    try _write(comptime ansi.csi.CursorPos(2, 1), .{}); // SetCurPos (y, x)
    // try _write(comptime ansi.csi.CursorPos(consoleHeight - 2, 1), .{});
    try _write(comptime ansi.csi.ScrollUp(1), .{});
}

pub fn scrollTextDown() !void {
    try _write(comptime ansi.csi.CursorPos(2, 1), .{});
    try _write(comptime ansi.csi.ScrollDown(1), .{});
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
pub fn getConsoleHeight() !u32 {
    if (builtin.os.tag == .windows) {
        var info: console.CONSOLE_SCREEN_BUFFER_INFO = undefined;
        const r = console.GetConsoleScreenBufferInfo(h_out, &info);
        if (r == 0) {
            const lastErr = win32.foundation.GetLastError();
            std.log.err("Failed GetConsoleScreenBufferInfoEx: {s}\n", .{lastErr});
            return consoleerror.getHeightFailed;
        }

        return @intCast(u32, info.srWindow.Bottom);
    } else {
        // struct winsize { unsigned short ws_row, ws_col, ws_xpixel, ws_ypixel; };
        var w: winsize = undefined;
        _ = std.os.linux.ioctl(1, TIOCGWINSZ, @ptrToInt(&w));

        return @intCast(u32, w.ws_row);
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
    if (builtin.os.tag != .windows) {
        return;
    }

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
}

fn setConsoleMode(handle: HANDLE, mode: u32) !void {
    if (builtin.os.tag != .windows) {
        return;
    }

    _ = console.SetConsoleMode(handle, @intToEnum(console.CONSOLE_MODE, mode));
}
