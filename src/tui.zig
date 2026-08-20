const std = @import("std");
const game = @import("game/state.zig");
const vaxis = @import("vaxis");

pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,

    pub fn init(r: u8, g: u8, b: u8) Color {
        return Color{ .r = r, .g = g, .b = b };
    }

    pub fn toStyle(self: Color) vaxis.Style {
        return vaxis.Style{
            .fg = .{ .rgb = .{ self.r, self.g, self.b } },
        };
    }

    pub fn toBgStyle(self: Color) vaxis.Style {
        return vaxis.Style{
            .bg = .{ .rgb = .{ self.r, self.g, self.b } },
        };
    }
};


/// Old-style positional print: formats text, then prints one Segment at (x, y).
fn printAt(win: vaxis.Window, x: usize, y: usize, style: vaxis.Style, comptime fmt: []const u8, args: anytype) void {
    var buf: [128]u8 = undefined;
    const text = std.fmt.bufPrint(&buf, fmt, args) catch return;
    _ = win.printSegment(
        .{ .text = text, .style = style },
        .{ .row_offset = @intCast(y), .col_offset = @intCast(x), .wrap = .none },
    );
}

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
    vx: *vaxis.Vaxis,
    win: vaxis.Window,
    state: *const game.GameState,
    anim: *AnimationState,
    palette: Palette,
) void {
    _ = vx;
    win.clear();

    renderHeader(win, state, palette);
    renderMaze(win, state, anim, palette);
    renderFooter(win, palette);
}

fn renderHeader(win: vaxis.Window, state: *const game.GameState, palette: Palette) void {
    const y: usize = 0;
    var x: usize = 0;

    printAt(win, x, y, palette.border.toStyle(), "{s}", .{"╭ PAC-MAN (ZIG) ╮"});
    x += 24;
    printAt(win, x, y, palette.text.toStyle(), "{s}", .{"SCORE:"});
    x += 7;
    printAt(win, x, y, palette.text_bright.toStyle(), "{d}", .{state.score});
    x += 10;
    printAt(win, x, y, palette.text.toStyle(), "{s}", .{"LIVES:"});
    var i: usize = 0;
    while (i < state.lives) : (i += 1) {
        printAt(win, x, y, palette.pacman.toStyle(), "{s}", .{"♥"});
        x += 3;
    }
    x += 2;
    printAt(win, x, y, palette.text.toStyle(), "{s}", .{"LEVEL:"});
    x += 7;
    printAt(win, x, y, palette.text_bright.toStyle(), "{d}", .{state.level});
}

fn renderMaze(win: vaxis.Window, state: *const game.GameState, anim: *AnimationState, palette: Palette) void {
    var y: usize = 1;
    while (y < state.tiles.len + 1) : (y += 1) {
        var x: usize = 0;
        while (x < state.tiles[0].len) : (x += 1) {
            const px: usize = @as(usize, @intFromFloat(state.pacman.x));
            const py: usize = @as(usize, @intFromFloat(state.pacman.y));
            var ch: []const u8 = " ";
            var style = palette.text_dim.toStyle();

            if (x == px and y - 1 == py) {
                ch = "▶";
                style = palette.pacman.toStyle();
            } else {
                var g_idx: usize = 0;
                var ghost_here = false;
                while (g_idx < 4) : (g_idx += 1) {
                    const gx: usize = @as(usize, @intFromFloat(state.ghosts[g_idx].x));
                    const gy: usize = @as(usize, @intFromFloat(state.ghosts[g_idx].y));
                    if (x == gx and y - 1 == gy) {
                        ch = ghostCharStr(g_idx);
                        style = if (state.frightened_timer > 0)
                            if ((anim.flash_tick / 10) % 2 == 0) palette.ghost_frightened.toStyle() else palette.ghost_eaten.toStyle()
                            else if (g_idx == 0) palette.ghost_red.toStyle()
                            else if (g_idx == 1) palette.ghost_pink.toStyle()
                            else if (g_idx == 2) palette.ghost_cyan.toStyle()
                            else palette.ghost_orange.toStyle();
                        ghost_here = true;
                        break;
                    }
                }
                if (!ghost_here) {
                    switch (state.tiles[y - 1][x].entity) {
                        .wall => {
                            ch = "█";
                            style = palette.wall.toStyle();
                        },
                        .dot => {
                            ch = "·";
                            style = palette.dot.toStyle();
                        },
                        .power_pellet => {
                            ch = if ((anim.flash_tick / 8) % 2 == 0) "●" else "·";
                            style = palette.power_pellet.toStyle();
                        },
                        else => {
                            ch = " ";
                            style = palette.text_dim.toStyle();
                        },
                    }
                }
            }

            printAt(win, x, y, style, "{s}", .{ch});
        }
    }
}

fn renderFooter(win: vaxis.Window, palette: Palette) void {
    const y = win.height - 1;
    printAt(win, 0, y, palette.border.toStyle(), "{s}", .{"╰"});
    printAt(win, 1, y, palette.border.toStyle(), "{s}", .{"───────"});
    printAt(win, 8, y, palette.border.toStyle(), "{s}", .{"╯"});
    printAt(win, 10, y, palette.text_dim.toStyle(), "{s}", .{"Arrow Keys: Move  |  Q: Quit  |  P: Pause"});
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

pub fn renderGameOver(vx: *vaxis.Vaxis, score: u32, palette: Palette) void {
    const title = "GAME OVER";
    const border_len = title.len + 20;
    const win = vx.window();
    win.clear();

    var y: usize = win.height / 2 - 5;
    const x: usize = (win.width - border_len) / 2;

    var i: usize = 0;
    while (i < border_len) : (i += 1) {
        printAt(win, x + i, y, palette.border.toStyle(), "{s}", .{"═"});
    }
    y += 1;
    i = 0;
    while (i < border_len) : (i += 1) {
        printAt(win, x + i, y, palette.border.toStyle(), "{s}", .{"║"});
    }
    y += 1;
    printAt(win, x, y, palette.border.toStyle(), "{s}", .{"║"});
    printAt(win, x + 1, y, palette.text_dim.toStyle(), "{s}", .{" "});
    printAt(win, x + 2, y, palette.accent.toStyle(), "{s}", .{title});
    printAt(win, x + 2 + title.len, y, palette.text_dim.toStyle(), "{s}", .{" "});
    printAt(win, x + border_len - 1, y, palette.border.toStyle(), "{s}", .{"║"});
    y += 1;
    i = 0;
    while (i < border_len) : (i += 1) {
        printAt(win, x + i, y, palette.border.toStyle(), "{s}", .{"║"});
    }
    y += 2;
    i = 0;
    while (i < border_len) : (i += 1) {
        printAt(win, x + i, y, palette.border.toStyle(), "{s}", .{"═"});
    }
    y += 1;
    printAt(win, x, y, palette.text.toStyle(), "{s}", .{"Final Score: "});
    printAt(win, x + 13, y, palette.text_bright.toStyle(), "{d}", .{score});
    y += 1;
    printAt(win, x, y, palette.text_dim.toStyle(), "{s}", .{"Press any key to exit..."});
}

pub fn renderWin(vx: *vaxis.Vaxis, score: u32, palette: Palette) void {
    const title = "YOU WIN!";
    const border_len = title.len + 20;
    const win = vx.window();
    win.clear();

    var y: usize = win.height / 2 - 5;
    const x: usize = (win.width - border_len) / 2;

    var i: usize = 0;
    while (i < border_len) : (i += 1) {
        printAt(win, x + i, y, palette.border.toStyle(), "{s}", .{"═"});
    }
    y += 1;
    i = 0;
    while (i < border_len) : (i += 1) {
        printAt(win, x + i, y, palette.border.toStyle(), "{s}", .{"║"});
    }
    y += 1;
    printAt(win, x, y, palette.border.toStyle(), "{s}", .{"║"});
    printAt(win, x + 1, y, palette.text_dim.toStyle(), "{s}", .{" "});
    printAt(win, x + 2, y, palette.accent.toStyle(), "{s}", .{title});
    printAt(win, x + 2 + title.len, y, palette.text_dim.toStyle(), "{s}", .{" "});
    printAt(win, x + border_len - 1, y, palette.border.toStyle(), "{s}", .{"║"});
    y += 1;
    i = 0;
    while (i < border_len) : (i += 1) {
        printAt(win, x + i, y, palette.border.toStyle(), "{s}", .{"║"});
    }
    y += 2;
    i = 0;
    while (i < border_len) : (i += 1) {
        printAt(win, x + i, y, palette.border.toStyle(), "{s}", .{"═"});
    }
    y += 1;
    printAt(win, x, y, palette.text.toStyle(), "{s}", .{"Final Score: "});
    printAt(win, x + 13, y, palette.text_bright.toStyle(), "{d}", .{score});
    y += 1;
    printAt(win, x, y, palette.text_dim.toStyle(), "{s}", .{"Press any key to exit..."});
}
