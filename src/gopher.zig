const std = @import("std");
const builtin = @import("builtin");

pub const Request = struct {
    allocator: std.mem.Allocator,

    requestType: TransactionType,
    display: []const u8,
    selector: []const u8,
    host: []const u8,
    port: u16,
    query: ?[]const u8,

    const Self = @This();

    pub fn new(allocator: std.mem.Allocator, requestType: TransactionType, display: []const u8, selector: []const u8, host: []const u8, port: u16, query: ?[]const u8) !*Request {
        const request = try allocator.create(Request);

        request.* = Request{
            .allocator = allocator,
            .requestType = requestType,
            .display = try allocator.dupe(u8, display),
            .selector = try allocator.dupe(u8, selector),
            .host = try allocator.dupe(u8, host),
            .port = port,
            .query = if (query) |q| try allocator.dupe(u8, q) else null,
        };

        return request;
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.display);
        self.allocator.free(self.selector);
        self.allocator.free(self.host);
        if (self.query) |*q| {
            self.allocator.free(q.*);
        }
        self.allocator.destroy(self);
    }

    // pub fn dupe(self: Self) !Request {
    //     return Request{
    //         .requestType = self.requestType,
    //         .display = try self.allocator.dupe(u8, self.display),
    //         .selector = try self.allocator.dupe(u8, self.selector),
    //         .host = try self.allocator.dupe(u8, self.host),
    //         .port = self.port,
    //         .query = if (self.query) |q| try self.allocator.dupe(u8, q) else null,
    //     };
    // }
};

pub const Entity = struct {
    fieldType: FieldType,
    displayStr: []const u8,
    selectorStr: []const u8,
    host: []const u8,
    port: u16,
};

const MenuTransaction = struct {
    allocator: std.mem.Allocator,
    body: []const u8,
    entities: ?[]Entity,

    const Self = @This();

    pub fn deinit(self: Self) void {
        self.allocator.free(self.body);
        if (self.entities) |*ents| {
            // std.log.warn("\n@TypeName(ents) = {s}", .{@typeName(@TypeOf(ents))});
            // std.log.warn("*) free self.entities {x}", .{&self.entities.?});
            // std.log.warn("*) free ents          {x}", .{ents});

            self.allocator.free(ents.*);
        }
    }

    /// Returns an owned slice of Entities
    pub fn getEntities(self: *Self) ![]Entity {
        if (self.entities) |ents| {
            //std.log.warn("1) self.entities reused {x}", .{&self.entities.?});
            //std.log.warn("2) self.entities reused {x}", .{&ents});

            return ents;
        }

        var al = std.ArrayList(Entity).init(self.allocator);
        defer al.deinit();
        var lineIt = std.mem.tokenize(u8, self.body, "\r\n");
        while (lineIt.next()) |line| {
            if (line.len == 1 and line[0] == '.') {
                break;
            }
            if (parse(line)) |item| {
                try al.append(item);
            }
        }

        self.entities = al.toOwnedSlice();

        //std.log.warn("self.entities assigned {x}", .{&self.entities.?});
        return self.entities.?;
    }

    pub fn lines(self: Self) u32 {
        if (self.entities) |e| {
            return @intCast(u32, e.len);
        } else {
            var c: u32 = 0;
            var lineIt = std.mem.tokenize(u8, self.body, "\r\n");
            while (lineIt.next()) |line| {
                if (line.len == 1 and line[0] == '.') {
                    break;
                }
                c += 1;
            }
            return c;
        }
    }

    pub fn parse(item: []const u8) ?Entity {
        if (item.len == 0) return null;

        const type_txt = item[0];
        const type_enum = FieldType.getType(type_txt) orelse {
            std.log.warn("Unknown item type: {c}", .{type_txt});
            std.log.warn("Seen here: {s}", .{item});
            return null; // Ignore unknown types.
        };

        var colIt = std.mem.split(u8, item, "\t");
        const displ = colIt.next() orelse return null;
        const selector = colIt.next() orelse return null;
        const host = colIt.next() orelse return null;
        const port_txt = colIt.next() orelse return null;
        const port = std.fmt.parseInt(u16, port_txt, 10) catch 0;

        return Entity{
            .fieldType = type_enum,
            .displayStr = displ[1..], //Skip the first type char
            .selectorStr = selector,
            .host = host,
            .port = port,
        };
    }
};
const TextFileTransaction = struct {
    allocator: std.mem.Allocator,
    body: []const u8,

    const Self = @This();

    pub fn deinit(self: Self) void {
        self.allocator.free(self.body);
    }

    pub fn getText(self: Self) []const u8 {
        return self.body;
    }
};
const BinaryFileTransaction = struct {
    allocator: std.mem.Allocator,
    body: []const u8,

    const Self = @This();

    pub fn deinit(self: Self) void {
        self.allocator.free(self.body);
    }

    pub fn getContent(self: Self) []const u8 {
        return self.body;
    }
};
const FullTextSearchTransaction = MenuTransaction;

pub fn init() !void {
    if (builtin.os.tag == .windows) {
        _ = try std.os.windows.WSAStartup(2, 2);
    }
}

pub fn deinit() void {
    if (builtin.os.tag == .windows) {
        std.os.windows.WSACleanup() catch {};
    }
}

pub const RequestError = error{
    MissingSearchParams,
};

/// The returned Transaction must be .deinit()'ed to free it's allocated memory.
pub const Transaction = union(TransactionType) {
    Menu: MenuTransaction,
    TextFile: TextFileTransaction,
    BinaryFile: BinaryFileTransaction,
    FullTextSearch: FullTextSearchTransaction,

    const Self = @This();

    /// executes a request and returns the response in the form of a Transaction. Each type of transaction should be handled individually.
    /// The caller must call `deinit()` on either the returned transaction *or* the active union member, but **not** both.
    pub fn execute(allocator: std.mem.Allocator, request: *const Request) !Transaction {
        var query: []const u8 = undefined;
        var buff: [255]u8 = undefined;
        if (request.requestType == .FullTextSearch) {
            if (request.query) |p| {
                query = try std.fmt.bufPrint(&buff, "{s}\t{s}\r\n", .{ request.selector, p });
            } else {
                return RequestError.MissingSearchParams;
            }
        } else {
            query = try std.fmt.bufPrint(&buff, "{s}\r\n", .{request.selector});
        }

        var stream = try std.net.tcpConnectToHost(allocator, request.host, request.port);
        defer stream.close();

        try stream.writer().writeAll(query);
        const result = try stream.reader().readAllAlloc(allocator, std.math.maxInt(usize));
        defer allocator.free(result);

        return switch (request.requestType) {
            .Menu => Transaction{
                .Menu = MenuTransaction{
                    .allocator = allocator,
                    .body = try allocator.dupe(u8, result),
                    .entities = null,
                },
            },
            .TextFile => Transaction{
                .TextFile = TextFileTransaction{
                    .allocator = allocator,
                    .body = try allocator.dupe(u8, result),
                },
            },
            .BinaryFile => Transaction{
                .BinaryFile = BinaryFileTransaction{
                    .allocator = allocator,
                    .body = try allocator.dupe(u8, result),
                },
            },
            .FullTextSearch => Transaction{
                .FullTextSearch = FullTextSearchTransaction{
                    .allocator = allocator,
                    .body = try allocator.dupe(u8, result),
                    .entities = null,
                },
            },
        };
    }

    /// This is equvalent to calling deinit on the active union tag.
    pub fn deinit(self: Self) void {
        switch (self) {
            .Menu => |t| t.deinit(),
            .TextFile => |t| t.deinit(),
            .BinaryFile => |t| t.deinit(),
            .FullTextSearch => |t| t.deinit(),
        }
    }

    pub fn lines(self: Self) u32 {
        return switch (self) {
            .Menu => |t| t.lines(),
            .TextFile => |t| @intCast(u32, std.mem.count(u8, t.getText(), "\n")),
            .BinaryFile => 0,
            .FullTextSearch => |t| t.lines(),
        };
    }
};

pub const TransactionType = enum {
    //None, // Some things cannot be requested

    Menu, // 1
    TextFile, // 0
    FullTextSearch, // 7
    BinaryFile, //9 or 5
};

pub const FieldType = enum(u8) {
    // zig fmt: off
    txt_f       = '0',
    menu        = '1',
    cso_book    = '2',
    err         = '3',
    binhex_f    = '4',
    msdos_f     = '5',
    uuenc_f     = '6',
    idx_srch    = '7',
    tel_sess    = '8',
    bin_f       = '9',
    red_srv     = '+',
    gif         = 'g',
    image       = 'I',
    tn3270      = 'T',
    // Unofficial types?
    info        = 'i',
    hlink       = 'h',
    // zig fmt: on
    pub fn getType(fv: u8) ?FieldType {
        const fields = comptime std.meta.fields(FieldType);
        inline for (fields) |field| {
            if (field.value == fv) {
                return std.meta.stringToEnum(FieldType, field.name);
            }
        }
        return null;
    }

    pub fn isBrowsable(self: FieldType) bool {
        // zig fmt: off
        return switch(self) {
            .menu              ,
            .txt_f             ,
            .bin_f             ,
            .binhex_f          ,
            .gif               ,
            .image             ,
            .msdos_f           ,
            .uuenc_f           ,
            .idx_srch   => true,

            .cso_book           ,
            .err                ,
            .hlink              ,
            .info               ,
            .red_srv            ,
            .tel_sess           ,
            .tn3270     => false,
        };
        // zig fmt: on
    }

    pub fn toTransactionType(self: FieldType) ?TransactionType {
        // zig fmt: off
        return switch (self) {
            .menu       => .Menu,

            .txt_f      => .TextFile,
            .uuenc_f    => .TextFile,

            .gif        => .BinaryFile,
            .image      => .BinaryFile,
            .bin_f      => .BinaryFile,
            .msdos_f    => .BinaryFile,
            .binhex_f   => .BinaryFile,

            .idx_srch   => .FullTextSearch,

            .cso_book, .err, 
            .hlink, .info, 
            .red_srv, .tel_sess, 
            .tn3270 => null,
        };
        // zig fmt: on
    }
};
