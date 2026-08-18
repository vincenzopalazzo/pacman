const std = @import("std");
const pacman = @import("pacman");

const ECHO: std.c.tc_lflag_t = @bitCast(@as(u64, 0x8));
const ICANON: std.c.tc_lflag_t = @bitCast(@as(u64, 0x100));
const VMIN = 16;
const VTIME = 17;

pub fn main() !void {
    const io = std.Io.Threaded.global_single_threaded.io();
    const gpa = std.heap.page_allocator;
    var stdout_buf: [1024]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(io, &stdout_buf);
    const stdout_writer = &stdout.interface;

    const stdin_fd = 0;
    var original_termios: std.c.termios = undefined;
    _ = std.c.tcgetattr(stdin_fd, &original_termios);
    var raw = original_termios;
    var lflag: u64 = @bitCast(raw.lflag);
    lflag &= ~(@as(u64, 0x8) | @as(u64, 0x100));
    const tc_lflag_type = std.c.tc_lflag_t;
    raw.lflag = lflag: {
        const result: tc_lflag_type = @bitCast(lflag);
        break :lflag result;
    };
    raw.cc[VMIN] = 1;
    raw.cc[VTIME] = 0;
    _ = std.c.tcsetattr(stdin_fd, std.c.TCSA.NOW, &raw);
    errdefer _ = std.c.tcsetattr(stdin_fd, std.c.TCSA.NOW, &original_termios);

    var state = try pacman.game.loadClassicMaze(gpa, 28, 31);
    defer {
        for (state.tiles) |row| {
            gpa.free(row);
        }
        gpa.free(state.tiles);
    }

    var running = true;
    var score: u32 = 0;
    const lives: usize = 3;

    while (running) {
        try stdout_writer.print("\x1b[H\x1b[J", .{});
        try stdout_writer.print("Pac-Man (Zig) - Arrow keys to move, Q to quit\n", .{});
        try stdout_writer.print("Score: {}  Lives: {}  Level: 1\n", .{score, lives});
        try stdout_writer.print("\n", .{});

        var y: usize = 0;
        while (y < state.tiles.len) : (y += 1) {
            var line_buf: [64]u8 = undefined;
            var line_len: usize = 0;
            var x: usize = 0;
            while (x < state.tiles[y].len) : (x += 1) {
                const px: usize = @as(usize, @intFromFloat(state.pacman.x));
                const py: usize = @as(usize, @intFromFloat(state.pacman.y));
                var ch: u8 = ' ';
                if (x == px and y == py) {
                    ch = 'C';
                } else {
                    var g: usize = 0;
                    while (g < state.ghosts.len) : (g += 1) {
                        const gx: usize = @as(usize, @intFromFloat(state.ghosts[g].x));
                        const gy: usize = @as(usize, @intFromFloat(state.ghosts[g].y));
                        if (x == gx and y == gy) {
                            ch = 'G';
                            break;
                        }
                    }
                    if (ch == ' ') {
                        ch = switch (state.tiles[y][x].entity) {
                            .wall => '#',
                            .dot => '.',
                            .power_pellet => 'O',
                            else => ' ',
                        };
                    }
                }
                line_buf[line_len] = ch;
                line_len += 1;
            }
            try stdout_writer.writeAll(line_buf[0..line_len]);
            try stdout_writer.writeAll("\n");
        }
        try stdout.flush();

        var buf: [8]u8 = undefined;
        const bytes_read = try std.posix.read(stdin_fd, &buf);
        if (bytes_read > 0) {
            if (buf[0] == 'q' or buf[0] == 'Q') {
                running = false;
            } else if (buf[0] == '\x1b') {
                if (bytes_read >= 3 and buf[1] == '[') {
                    var dx: i32 = 0;
                    var dy: i32 = 0;
                    if (buf[2] == 'C') dx = 1;
                    if (buf[2] == 'D') dx = -1;
                    if (buf[2] == 'A') dy = -1;
                    if (buf[2] == 'B') dy = 1;
                    const new_x = state.pacman.x + @as(f32, @floatFromInt(dx));
                    const new_y = state.pacman.y + @as(f32, @floatFromInt(dy));
                    const new_ix: usize = @as(usize, @intFromFloat(new_x));
                    const new_iy: usize = @as(usize, @intFromFloat(new_y));
                    if (new_ix >= 0 and new_ix < state.tiles[0].len and
                        new_iy >= 0 and new_iy < state.tiles.len) {
                        if (state.tiles[new_iy][new_ix].entity != .wall) {
                            state.pacman.x = new_x;
                            state.pacman.y = new_y;
                            if (state.tiles[new_iy][new_ix].entity == .dot) {
                                state.tiles[new_iy][new_ix].entity = .empty;
                                score += 10;
                                state.score = score;
                            }
                        }
                    }
                }
            }
        }
    }
}
