const std = @import("std");
const builtin = @import("builtin");
const console = win32.system.console;
const HANDLE = win32.foundation.HANDLE;
const WIN32_ERROR = win32.foundation.WIN32_ERROR;

const ansi = @import("ansi");
const win32 = @import("win32");

pub const Display = struct {
    contentBuffer: *[]const u8,

    const Self = @This();

    var h_in: HANDLE = undefined;
    var h_out: HANDLE = undefined;

    var originalStdInMode: u32 = 0;
    var originalStdOutMode: u32 = 0;

    pub fn init(contentBuffer: *[]const u8) !Display {

        // Store initial consolemode for stdin and stdout
        h_in = console.GetStdHandle(console.STD_INPUT_HANDLE);
        h_out = console.GetStdHandle(console.STD_OUTPUT_HANDLE);

        originalStdInMode = try getConsoleMode(h_in);
        originalStdOutMode = try getConsoleMode(h_out);

        // Enable vt100 sequence handling on windows. Changes the ConsoleMode
        try enableVt100Parsing();

        var s = Display{
            .contentBuffer = contentBuffer,
        };
        // Hide Cursor
        //try s.write("\x1B[?25l", .{});

        // Switch to alternate screen buffer
        try s.write("\x1B[?1049h", .{});

        // Set scroll margins for top and bottom.
        try s.write("\x1B[{d};{d}r", .{ 1, 1 });
        return s;
    }

    pub fn deinit(self: *Self) void {

        // Show cursor.
        self.write("\x1B[?25h", .{}) catch {};

        // Switch to main screen buffer
        self.write("\x1B[?1049l", .{}) catch {};

        // Restore ConsoleMode to original values
        setConsoleMode(h_in, originalStdInMode) catch {};
        setConsoleMode(h_out, originalStdOutMode) catch {};
    }

    pub fn setTopLine(self: Self, disp: []const u8, domain: []const u8, selector: []const u8) !void {
        try self.write(comptime ansi.csi.CursorPos(1, 1), .{});
        try self.write(comptime ansi.csi.EraseInLine(2), .{});
        try self.write(comptime ansi.color.Fg(.Red, "{s} - {s}{s}"), .{ disp, domain, selector });
    }

    pub fn setBottomLine(self: Self, hist: [][]const u8) !void {
        var botLine = try getConsoleHeight();

        try self.write("\x1B[{d};{d}H", .{ botLine, 1 });
        try self.write(comptime ansi.csi.EraseInLine(2), .{});

        if (hist.len == 0) {
            return;
        }
        if (hist.len == 1) {
            try self.write("[" ++ comptime ansi.color.Underline("{s}") ++ "]", .{hist[0]});
        } else if (hist.len == 2) {
            try self.write("{s} [" ++ comptime ansi.color.Underline("{s}") ++ "]", .{ hist[0], hist[1] });
        } else {
            try self.write("{s} [" ++ comptime ansi.color.Underline("{s}]") ++ "] {s}", .{ hist[0], hist[1], hist[2] });
        }
    }

    pub fn redraw(self: Self) !void {
        try self.write(comptime ansi.csi.CursorPos(2, 1), .{});
        try self.write("{s}", .{self.contentBuffer.*});
    }

    fn write(_: Self, comptime format: []const u8, args: anytype) !void {
        try std.io.getStdOut().writer().print(format, args);
    }

    // ..
    // **** Win32 API stuff ****
    // ..

    const consoleerror = error{
        getHeightFailed,
    };
    fn getConsoleHeight() !i32 {
        var info: console.CONSOLE_SCREEN_BUFFER_INFO = undefined;
        const r = console.GetConsoleScreenBufferInfo(h_out, &info);
        if (r == 0) {
            const lastErr = win32.foundation.GetLastError();
            std.log.err("Failed GetConsoleScreenBufferInfoEx: {s}\n", .{lastErr});
            return consoleerror.getHeightFailed;
        }

        return @intCast(i32, info.srWindow.Bottom);
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
};
