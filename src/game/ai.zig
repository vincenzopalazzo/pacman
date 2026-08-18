const std = @import("std");
const game = @import("state.zig");

pub const GhostPersonality = struct {
    aggression: f32,
    target_bias: f32,
    randomness: f32,
    retreat_speed: f32,
};

pub const GhostAI = struct {
    personality: GhostPersonality,
    direction: game.Direction,
    frightened: bool,
    last_decision_tick: u32,
    target_x: f32,
    target_y: f32,

    pub fn init(personality: GhostPersonality) GhostAI {
        return GhostAI{
            .personality = personality,
            .direction = game.Direction.none,
            .frightened = false,
            .last_decision_tick = 0,
            .target_x = 0,
            .target_y = 0,
        };
    }

    pub fn decideDirection(
        self: *GhostAI,
        allocator: std.mem.Allocator,
        state: *const game.GameState,
        ghost_index: usize,
        tick: u32,
    ) !void {
        const gx = state.ghosts[ghost_index].x;
        const gy = state.ghosts[ghost_index].y;
        const px = state.pacman.x;
        const py = state.pacman.y;

        if (self.frightened) {
            self.target_x = @as(f32, @floatFromInt(@as(i32, @intFromFloat(gx)) -% @as(i32, @intFromFloat(px))));
            self.target_y = @as(f32, @floatFromInt(@as(i32, @intFromFloat(gy)) -% @as(i32, @intFromFloat(py))));
        } else {
            const bias = self.personality.target_bias;
            self.target_x = px + (gx - px) * bias;
            self.target_y = py + (gy - py) * bias;
        }

        const possible_dirs = try self.getPossibleDirections(allocator, state, ghost_index);
        defer allocator.free(possible_dirs);

        if (possible_dirs.len == 0) return;

        var best_dir = possible_dirs[0];
        var best_dist: f32 = std.math.inf(f32);

        for (possible_dirs) |dir| {
            const nx = gx + dxFor(dir);
            const ny = gy + dyFor(dir);
            const dist = (nx - self.target_x) * (nx - self.target_x) + (ny - self.target_y) * (ny - self.target_y);
            if (dist < best_dist) {
                best_dist = dist;
                best_dir = dir;
            }
        }

        self.direction = best_dir;
        self.last_decision_tick = tick;
    }

    pub fn moveGhost(
        self: *GhostAI,
        state: *game.GameState,
        ghost_index: usize,
        speed: f32,
    ) void {
        const gx = state.ghosts[ghost_index].x;
        const gy = state.ghosts[ghost_index].y;
        const dx = dxFor(self.direction);
        const dy = dyFor(self.direction);
        const new_x = gx + dx * speed;
        const new_y = gy + dy * speed;

        const ix: usize = @as(usize, @intFromFloat(new_x));
        const iy: usize = @as(usize, @intFromFloat(new_y));

        if (iy >= 0 and iy < state.tiles.len and ix >= 0 and ix < state.tiles[0].len) {
            if (state.tiles[iy][ix].entity != .wall) {
                state.ghosts[ghost_index].x = new_x;
                state.ghosts[ghost_index].y = new_y;
            }
        }
    }

    fn getPossibleDirections(
        _: *GhostAI,
        allocator: std.mem.Allocator,
        state: *const game.GameState,
        ghost_index: usize,
    ) ![]const game.Direction {
        const gx = state.ghosts[ghost_index].x;
        const gy = state.ghosts[ghost_index].y;
        var dirs = std.ArrayList(game.Direction).initCapacity(allocator, 4) catch return &[0]game.Direction{};
        errdefer dirs.deinit(allocator);

        const dirs_to_check = [_]game.Direction{
            game.Direction.up,
            game.Direction.down,
            game.Direction.left,
            game.Direction.right,
        };

        for (dirs_to_check) |dir| {
            const dx = dxFor(dir);
            const dy = dyFor(dir);
            const nx = gx + dx;
            const ny = gy + dy;
            const ix: usize = @as(usize, @intFromFloat(nx));
            const iy: usize = @as(usize, @intFromFloat(ny));

            if (iy > 0 and iy < state.tiles.len and ix > 0 and ix < state.tiles[0].len) {
                if (state.tiles[iy][ix].entity != .wall) {
                    dirs.append(allocator, dir) catch {};
                }
            }
        }

        return dirs.toOwnedSlice(allocator) catch &[0]game.Direction{};
    }
};

fn dxFor(dir: game.Direction) f32 {
    return switch (dir) {
        .left => -1.0,
        .right => 1.0,
        else => 0.0,
    };
}

fn dyFor(dir: game.Direction) f32 {
    return switch (dir) {
        .up => -1.0,
        .down => 1.0,
        else => 0.0,
    };
}

pub fn getDefaultPersonalities() [4]GhostPersonality {
    return [4]GhostPersonality{
        GhostPersonality{ .aggression = 0.9, .target_bias = 1.0, .randomness = 0.1, .retreat_speed = 1.0 },
        GhostPersonality{ .aggression = 0.7, .target_bias = 0.8, .randomness = 0.2, .retreat_speed = 1.2 },
        GhostPersonality{ .aggression = 0.5, .target_bias = 0.5, .randomness = 0.3, .retreat_speed = 1.5 },
        GhostPersonality{ .aggression = 0.3, .target_bias = 0.3, .randomness = 0.4, .retreat_speed = 1.8 },
    };
}
