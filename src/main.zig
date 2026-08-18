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
    lflag &=  ~(@as(u64, 0x8) | @as(u64, 0x100));
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

    var ghosts_ai: [4]pacman.ai.GhostAI = undefined;
    const personalities = pacman.ai.getDefaultPersonalities();
    for (personalities, 0..) |p, i| {
        ghosts_ai[i] = pacman.ai.GhostAI.init(p);
    }

    const ghost_start_x = [4]f32{ 6.0, 6.0, 21.0, 21.0 };
    const ghost_start_y = [4]f32{ 11.0, 13.0, 11.0, 13.0 };
    var g: usize = 0;
    while (g < 4) : (g += 1) {
        state.ghosts[g].x = ghost_start_x[g];
        state.ghosts[g].y = ghost_start_y[g];
    }

    var running = true;
    var paused = false;
    var score: u32 = 0;
    var lives: u8 = 3;
    var tick: u32 = 0;
    var anim = pacman.tui.AnimationState.init();

    while (running) : (tick += 1) {
        if (paused) {
            try pacman.tui.renderFrame(stdout_writer, &state, &anim, pacman.tui.default_palette);
            var buf: [8]u8 = undefined;
            const bytes_read = try std.posix.read(stdin_fd, &buf);
            if (bytes_read > 0) {
                if (buf[0] == 'q' or buf[0] == 'Q') {
                    running = false;
                } else if (buf[0] == 'p' or buf[0] == 'P') {
                    paused = false;
                }
            }
            continue;
        }
        g = 0;
        while (g < 4) : (g += 1) {
            if (state.frightened_timer > 0) {
                ghosts_ai[g].frightened = true;
            } else {
                ghosts_ai[g].frightened = false;
            }
            try ghosts_ai[g].decideDirection(gpa, &state, g, tick);
            ghosts_ai[g].moveGhost(&state, g, if (ghosts_ai[g].frightened) 0.5 else 1.0);
        }

        var collided = false;
        g = 0;
        while (g < 4) : (g += 1) {
            const dx = state.ghosts[g].x - state.pacman.x;
            const dy = state.ghosts[g].y - state.pacman.y;
            if (dx * dx + dy * dy < 1.0) {
                    if (ghosts_ai[g].frightened) {
                        ghosts_ai[g].direction = pacman.game.Direction.none;
                        state.ghosts[g].x = ghost_start_x[g];
                        state.ghosts[g].y = ghost_start_y[g];
                        score += 200;
                        state.score = score;
                    } else {
                    collided = true;
                }
            }
        }
        if (collided) {
            lives -= 1;
            if (lives == 0) {
                try pacman.tui.renderGameOver(stdout_writer, score, pacman.tui.default_palette);
                var buf: [8]u8 = undefined;
                _ = try std.posix.read(stdin_fd, &buf);
                running = false;
            } else {
                state.pacman.x = 14.0;
                state.pacman.y = 23.0;
                var gi: usize = 0;
                while (gi < 4) : (gi += 1) {
                    state.ghosts[gi].x = ghost_start_x[gi];
                    state.ghosts[gi].y = ghost_start_y[gi];
                }
            }
        }

        if (state.frightened_timer > 0) {
            state.frightened_timer -= 1;
        }

        anim.update();
        try pacman.tui.renderFrame(stdout_writer, &state, &anim, pacman.tui.default_palette);

        var buf: [8]u8 = undefined;
        const bytes_read = try std.posix.read(stdin_fd, &buf);
        if (bytes_read > 0) {
            if (buf[0] == 'q' or buf[0] == 'Q') {
                running = false;
            } else if (buf[0] == 'p' or buf[0] == 'P') {
                paused = true;
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
                            } else if (state.tiles[new_iy][new_ix].entity == .power_pellet) {
                                state.tiles[new_iy][new_ix].entity = .empty;
                                score += 50;
                                state.score = score;
                                state.frightened_timer = 300;
                            }
                        }
                    }
                }
            }
        }
        try std.Io.sleep(io, .{ .nanoseconds = 16_000_000 }, .awake);
    }
}
