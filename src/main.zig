const std = @import("std");
const pacman = @import("pacman");
const vaxis = @import("vaxis");

const Event = union(enum) {
    key_press: vaxis.Key,
    winsize: vaxis.Winsize,
};

pub fn main() !void {
    const io = std.Io.Threaded.global_single_threaded.io();
    const gpa = std.heap.page_allocator;

    var buffer: [1024]u8 = undefined;
    var tty = try vaxis.Tty.init(io, &buffer);
    defer tty.deinit();

    const env = std.process.Environ{ .block = .{ .slice = std.mem.span(std.c.environ) } };
    var map: std.process.Environ.Map = std.process.Environ.createMap(env, gpa) catch undefined;
    var vx = try vaxis.init(io, gpa, &map, .{});
    defer vx.deinit(gpa, tty.writer());

    var loop: vaxis.Loop(Event) = .init(io, &tty, &vx);
    try loop.start();
    defer loop.stop();

    try vx.enterAltScreen(tty.writer());
    try vx.queryTerminal(tty.writer(), .fromSeconds(1));

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

    while (running) {
        const event = try loop.nextEvent();
        switch (event) {
            .key_press => |key| {
                if (key.matches('q', .{ .ctrl = true })) {
                    running = false;
                    continue;
                }
                if (paused) {
                    if (key.matches('p', .{})) {
                        paused = false;
                    }
                    continue;
                }
                if (key.matches('p', .{})) {
                    paused = true;
                    continue;
                }
                if (key.matches('c', .{ .ctrl = true })) {
                    running = false;
                    continue;
                }
                handleKeyPress(key, &state, &score);
            },
            .winsize => |ws| {
                try vx.resize(gpa, tty.writer(), ws);
            },
        }

        if (paused) {
            pacman.tui.renderFrame(&vx, vx.window(), &state, &anim, pacman.tui.default_palette);
            try vx.render(tty.writer());
            continue;
        }

        g = 0;
        while (g < 4) : (g += 1) {
            if (state.frightened_timer > 0) {
                ghosts_ai[g].frightened = true;
            } else {
                ghosts_ai[g].frightened = false;
            }
            try ghosts_ai[g].decideDirection(&state, g, tick);
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
                pacman.tui.renderGameOver(&vx, score, pacman.tui.default_palette);
                try vx.render(tty.writer());
                _ = try loop.nextEvent();
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
        pacman.tui.renderFrame(&vx, vx.window(), &state, &anim, pacman.tui.default_palette);
        try vx.render(tty.writer());

        if (state.dots_remaining == 0) {
            pacman.tui.renderWin(&vx, score, pacman.tui.default_palette);
            try vx.render(tty.writer());
            _ = try loop.nextEvent();
            running = false;
            continue;
        }

        tick += 1;
    }
}

fn handleKeyPress(key: vaxis.Key, state: *pacman.game.GameState, score: *u32) void {
    if (key.matches('q', .{}) or key.matches('Q', .{})) {
        std.process.exit(0);
    }

    var dx: i32 = 0;
    var dy: i32 = 0;
    if (key.matches('C', .{ .shift = true }) or key.matches(vaxis.Key.right, .{})) dx = 1;
    if (key.matches('D', .{ .shift = true }) or key.matches(vaxis.Key.left, .{})) dx = -1;
    if (key.matches('A', .{ .shift = true }) or key.matches(vaxis.Key.up, .{})) dy = -1;
    if (key.matches('B', .{ .shift = true }) or key.matches(vaxis.Key.down, .{})) dy = 1;

    if (dx == 0 and dy == 0) return;

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
                score.* += 10;
                state.score = score.*;
                state.dots_remaining -= 1;
            } else if (state.tiles[new_iy][new_ix].entity == .power_pellet) {
                state.tiles[new_iy][new_ix].entity = .empty;
                score.* += 50;
                state.score = score.*;
                state.frightened_timer = 300;
            }
        }
    }
}
