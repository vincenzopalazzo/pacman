const std = @import("std");

pub const Direction = enum(u2) {
    none = 0,
    up = 1,
    down = 2,
    left = 3,
    right = 4,
};

pub const EntityType = enum(u3) {
    none = 0,
    pacman = 1,
    ghost = 2,
    dot = 3,
    power_pellet = 4,
    wall = 5,
};

pub const Tile = struct {
    x: u8,
    y: u8,
    entity: EntityType,
};

pub const Position = struct {
    x: f32,
    y: f32,
};

pub const GameState = struct {
    tiles: [][]Tile,
    pacman: Position,
    ghosts: [4]Position,
    score: u32,
    lives: u8,
    level: u8,
    frightened_timer: u32,
    dots_remaining: u32,
    running: bool,
};

pub fn createTile(x: u8, y: u8, entity: EntityType) Tile {
    return Tile{
        .x = x,
        .y = y,
        .entity = entity,
    };
}

pub fn createGameState(allocator: std.mem.Allocator, width: usize, height: usize) !GameState {
    const tiles = try allocator.alloc([]Tile, height);
    for (tiles) |*row| {
        row.* = try allocator.alloc(Tile, width);
    }

    const state = GameState{
        .tiles = tiles,
        .pacman = Position{ .x = 14.0, .y = 23.0 },
        .ghosts = [4]Position{
            Position{ .x = 14.0, .y = 11.0 },
            Position{ .x = 12.0, .y = 14.0 },
            Position{ .x = 14.0, .y = 14.0 },
            Position{ .x = 16.0, .y = 14.0 },
        },
        .score = 0,
        .lives = 3,
        .level = 1,
        .frightened_timer = 0,
        .dots_remaining = 0,
        .running = true,
    };

    return state;
}
