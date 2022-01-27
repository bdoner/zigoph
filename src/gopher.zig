const std = @import("std");

pub const Item = struct {
    itemType: ItemType,
    displayStr: []const u8,
    selectorStr: []const u8,
    domain: []const u8,
    port: u16,
    //buffer: []const u8,

    pub fn parseDirItem(item: []const u8) ?Item {
        if (item.len == 0) return null;

        const type_txt = item[0];
        const type_enum = ItemType.getType(type_txt) orelse {
            std.log.warn("Unknown item type: {c}", .{type_txt});
            std.log.warn("Seen here: {s}", .{item});
            return null; // Ignore unknown types.
        };

        var colIt = std.mem.tokenize(u8, item, "\t");
        const displ = colIt.next() orelse return null;
        const selector = colIt.next() orelse return null;
        const domain = colIt.next() orelse return null;
        const port_txt = colIt.next() orelse return null;
        const port = std.fmt.parseInt(u16, port_txt, 10) catch return null;

        return Item{
            .itemType = type_enum,
            .displayStr = displ[1..], //Skip the first type char
            .selectorStr = selector,
            .domain = domain,
            .port = port,
        };
    }
};

pub const ItemType = enum(u8) {
    txt_f = '0',
    menu = '1',
    cso_book = '2',
    err = '3',
    binhex_f = '4',
    msdos_f = '5',
    uuenc_f = '6',
    idx_srch = '7',
    tel_sess = '8',
    binary_f = '9',
    red_srv = '+',
    gif = 'g',
    image = 'I',
    tn3270 = 'T',

    // Unofficial types?
    info = 'i',
    hlink = 'h',

    pub fn getType(fv: u8) ?ItemType {
        const fields = comptime std.meta.fields(ItemType);
        inline for (fields) |field| {
            if (field.value == fv) {
                return std.meta.stringToEnum(ItemType, field.name);
            }
        }
        return null;
    }

    pub fn isSelectable(self: ItemType) bool {
        // zig fmt: off
        return switch (self) {
            .txt_f, 
            .menu,
            .cso_book,
            .binhex_f,
            .msdos_f,
            .uuenc_f,
            .idx_srch,
            .tel_sess,
            .binary_f,
            .gif,
            .image,
            .tn3270,
            .hlink => true,
            
            else => false,
        };
        // zig fmt: on
    }
};