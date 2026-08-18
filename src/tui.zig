const std = @import("std");
const game = @import("game/state.zig");

pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,

    pub fn init(r: u8, g: u8, b: u8) Color {
        return Color{ .r = r, .g = g, .b = b };
    }

    pub fn formatFg(self: Color, buf: []u8) ![]const u8 {
        return try std.fmt.bufPrint(buf, "\x1b[38;2;{d};{d};{d}m", .{ self.r, self.g, self.b });
    }

    pub fn formatBg(self: Color, buf: []u8) ![]const u8 {
        return try std.fmt.bufPrint(buf, "\x1b[48;2;{d};{d};{d}m", .{ self.r, self.g, self.b });
    }
};

pub const Palette = struct {
    bg: Color,
    surface: Color,
    border: Color,
    text: Color,
    text_dim: Color,
    text_bright: Color,
    accent: Color,
    pacman: Color,
    ghost_red: Color,
    ghost_pink: Color,
    ghost_cyan: Color,
    ghost_orange: Color,
    ghost_frightened: Color,
    ghost_eaten: Color,
    wall: Color,
    dot: Color,
    power_pellet: Color,
};

pub const modern_palette = Palette{
    .bg = Color.init(17, 24, 39),
    .surface = Color.init(30, 41, 59),
    .border = Color.init(71, 85, 105),
    .text = Color.init(203, 213, 225),
    .text_dim = Color.init(100, 116, 139),
    .text_bright = Color.init(248, 250, 252),
    .accent = Color.init(56, 189, 248),
    .pacman = Color.init(250, 204, 21),
    .ghost_red = Color.init(248, 113, 113),
    .ghost_pink = Color.init(244, 114, 182),
    .ghost_cyan = Color.init(34, 211, 238),
    .ghost_orange = Color.init(251, 146, 60),
    .ghost_frightened = Color.init(59, 130, 246),
    .ghost_eaten = Color.init(148, 163, 184),
    .wall = Color.init(59, 130, 246),
    .dot = Color.init(203, 213, 225),
    .power_pellet = Color.init(248, 113, 113),
};

pub const default_palette = modern_palette;

pub const AnimationState = struct {
    mouth_phase: u8,
    flash_tick: u32,
    pacman_trail: [8]usize,
    trail_idx: usize,

    pub fn init() AnimationState {
        return AnimationState{
            .mouth_phase = 0,
            .flash_tick = 0,
            .pacman_trail = [_]usize{0} ** 8,
            .trail_idx = 0,
        };
    }

    pub fn update(self: *AnimationState) void {
        self.mouth_phase = (self.mouth_phase + 1) % 4;
        self.flash_tick += 1;
    }
};

pub fn renderFrame(
    writer: anytype,
    state: *const game.GameState,
    anim: *AnimationState,
    palette: Palette,
) !void {
    var buf: [64]u8 = undefined;
    try writer.print("{s}{s}", .{ reset(), try palette.bg.formatBg(&buf) });
    try writer.print("{s}", .{ clearScreen() });
    try writer.print("{s}", .{ hideCursor() });

    try renderHeader(writer, state, palette);
    try writer.writeAll("\n");

    try renderMaze(writer, state, anim, palette);
    try writer.writeAll("\n");

    try renderFooter(writer, palette);

    try writer.print("{s}", .{ reset() });
    try writer.print("{s}", .{ showCursor() });
}

fn renderHeader(writer: anytype, state: *const game.GameState, palette: Palette) !void {
    var buf: [64]u8 = undefined;
    try writer.print("{s}{s}╭{s} PAC-MAN (ZIG) {s}╮{s}", .{
        try palette.bg.formatBg(&buf),
        try palette.border.formatFg(&buf),
        palette.accent.formatFg(&buf) catch try palette.border.formatFg(&buf),
        try palette.border.formatFg(&buf),
        try palette.text.formatFg(&buf),
    });

    try writer.print("  {s}{s}SCORE:{s} {s}{d}", .{ try palette.text.formatFg(&buf), try palette.border.formatFg(&buf), try palette.text.formatFg(&buf), try palette.text_bright.formatFg(&buf), state.score });
    try writer.print("  {s}{s}LIVES:{s} ", .{ try palette.text.formatFg(&buf), try palette.border.formatFg(&buf), try palette.text.formatFg(&buf) });
    var i: usize = 0;
    while (i < state.lives) : (i += 1) {
        try writer.print("{s}♥{s}", .{ try palette.pacman.formatFg(&buf), try palette.text.formatFg(&buf) });
    }
    try writer.print("  {s}{s}LEVEL:{s} {s}{d}{s}\n", .{ try palette.text.formatFg(&buf), try palette.border.formatFg(&buf), try palette.text.formatFg(&buf), try palette.text_bright.formatFg(&buf), state.level, try palette.text.formatFg(&buf) });
}

fn renderMaze(writer: anytype, state: *const game.GameState, anim: *AnimationState, palette: Palette) !void {
    var y: usize = 0;
    while (y < state.tiles.len) : (y += 1) {
        var x: usize = 0;
        while (x < state.tiles[y].len) : (x += 1) {
            const px: usize = @as(usize, @intFromFloat(state.pacman.x));
            const py: usize = @as(usize, @intFromFloat(state.pacman.y));
            var ch: []const u8 = " ";
            var fg = palette.text;

            if (x == px and y == py) {
                ch = "▶";
                fg = palette.pacman;
            } else {
                var g_idx: usize = 0;
                var ghost_here = false;
                while (g_idx < 4) : (g_idx += 1) {
                    const gx: usize = @as(usize, @intFromFloat(state.ghosts[g_idx].x));
                    const gy: usize = @as(usize, @intFromFloat(state.ghosts[g_idx].y));
                    if (x == gx and y == gy) {
                        ch = ghostCharStr(g_idx);
                        fg = if (state.frightened_timer > 0)
                            if ((anim.flash_tick / 10) % 2 == 0) palette.ghost_frightened else palette.ghost_eaten
                            else if (g_idx == 0) palette.ghost_red
                            else if (g_idx == 1) palette.ghost_pink
                            else if (g_idx == 2) palette.ghost_cyan
                            else palette.ghost_orange;
                        ghost_here = true;
                        break;
                    }
                }
                if (!ghost_here) {
                    switch (state.tiles[y][x].entity) {
                        .wall => {
                            ch = "█";
                            fg = palette.wall;
                        },
                        .dot => {
                            ch = "·";
                            fg = palette.dot;
                        },
                        .power_pellet => {
                            ch = if ((anim.flash_tick / 8) % 2 == 0) "●" else "·";
                            fg = palette.power_pellet;
                        },
                        else => {
                            ch = " ";
                            fg = palette.text_dim;
                        },
                    }
                }
            }

            var buf: [64]u8 = undefined;
            try writer.print("{s}{s}", .{ try fg.formatFg(&buf), ch });
        }
        try writer.print("{s}\n", .{ reset() });
    }
}

fn renderFooter(writer: anytype, palette: Palette) !void {
    var buf: [64]u8 = undefined;
    try writer.print("{s}{s}╰{s}", .{ try palette.text.formatFg(&buf), try palette.border.formatFg(&buf), try palette.text_dim.formatFg(&buf) });
    try writer.print("───────", .{});
    try writer.print("{s}{s}╯{s}", .{ try palette.border.formatFg(&buf), try palette.text.formatFg(&buf), try palette.text_dim.formatFg(&buf) });
    try writer.print("  {s}Arrow Keys: Move  |  Q: Quit  |  P: Pause{s}\n", .{ try palette.text_dim.formatFg(&buf), try palette.text.formatFg(&buf) });
}

fn pacmanChar(_: u8) []const u8 {
    return "▶";
}

fn ghostCharStr(index: usize) []const u8 {
    return switch (index) {
        0 => "◥",
        1 => "◤",
        2 => "◣",
        3 => "◢",
        else => "?",
    };
}

pub fn renderGameOver(writer: anytype, score: u32, palette: Palette) !void {
    var buf: [64]u8 = undefined;
    try writer.print("{s}{s}", .{ reset(), try palette.bg.formatBg(&buf) });
    try writer.print("{s}", .{ clearScreen() });
    try writer.print("{s}", .{ hideCursor() });

    const title = "GAME OVER";
    const border_len = title.len + 20;
    var i: usize = 0;
    try writer.print("\n\n\n  {s}", .{try palette.border.formatFg(&buf)});
    while (i < border_len) : (i += 1) {
        try writer.print("═", .{});
    }
    try writer.print("{s}\n", .{try palette.text.formatFg(&buf)});

    i = 0;
    try writer.print("  {s}", .{try palette.border.formatFg(&buf)});
    while (i < border_len) : (i += 1) {
        try writer.print("║", .{});
    }
    try writer.print("{s}\n", .{try palette.text.formatFg(&buf)});

    try writer.print("  {s}║{s} {s}{s}{s} {s}║{s}\n", .{
        try palette.border.formatFg(&buf),
        try palette.text_dim.formatFg(&buf),
        try palette.accent.formatFg(&buf),
        title,
        try palette.text_dim.formatFg(&buf),
        try palette.border.formatFg(&buf),
        try palette.text.formatFg(&buf),
    });

    i = 0;
    try writer.print("  {s}", .{try palette.border.formatFg(&buf)});
    while (i < border_len) : (i += 1) {
        try writer.print("║", .{});
    }
    try writer.print("{s}\n\n", .{try palette.text.formatFg(&buf)});

    i = 0;
    try writer.print("  {s}", .{try palette.border.formatFg(&buf)});
    while (i < border_len) : (i += 1) {
        try writer.print("═", .{});
    }
    try writer.print("{s}\n", .{try palette.text.formatFg(&buf)});

    try writer.print("  {s}Final Score: {s}{d}{s}\n", .{ try palette.text.formatFg(&buf), try palette.text_bright.formatFg(&buf), score, try palette.text.formatFg(&buf) });
    try writer.print("  {s}Press any key to exit...{s}\n", .{ try palette.text_dim.formatFg(&buf), try palette.text.formatFg(&buf) });

    try writer.print("{s}", .{ reset() });
    try writer.print("{s}", .{ showCursor() });
}

fn reset() []const u8 { return "\x1b[0m"; }
fn clearScreen() []const u8 { return "\x1b[2J\x1b[H"; }
fn hideCursor() []const u8 { return "\x1b[?25l"; }
fn showCursor() []const u8 { return "\x1b[?25h"; }
