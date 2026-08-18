const std = @import("std");

pub const Direction = enum(u3) {
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
    empty = 6,
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

pub fn loadClassicMaze(allocator: std.mem.Allocator, width: usize, height: usize) !GameState {
    var state = try createGameState(allocator, width, height);

    const maze = [_][28]u8{
        .{ 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5 },
        .{ 5, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 5, 5, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 5 },
        .{ 5, 3, 5, 5, 5, 5, 3, 5, 5, 5, 5, 5, 3, 5, 5, 3, 5, 5, 5, 5, 5, 3, 5, 5, 5, 5, 3, 5 },
        .{ 5, 4, 5, 5, 5, 5, 3, 5, 5, 5, 5, 5, 3, 5, 5, 3, 5, 5, 5, 5, 5, 3, 5, 5, 5, 5, 4, 5 },
        .{ 5, 3, 5, 5, 5, 5, 3, 5, 5, 5, 5, 5, 3, 5, 5, 3, 5, 5, 5, 5, 5, 3, 5, 5, 5, 5, 3, 5 },
        .{ 5, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 5 },
        .{ 5, 3, 5, 5, 5, 5, 3, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 3, 5, 5, 5, 5, 3, 5 },
        .{ 5, 3, 5, 5, 5, 5, 3, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 3, 5, 5, 5, 5, 3, 5 },
        .{ 5, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 5, 5, 5, 5, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 5 },
        .{ 5, 5, 5, 5, 5, 5, 3, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 3, 5, 5, 5, 5, 5, 5 },
        .{ 0, 0, 0, 0, 0, 5, 3, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 3, 5, 0, 0, 0, 0, 0 },
        .{ 0, 0, 0, 0, 0, 5, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 5, 0, 0, 0, 0, 0 },
        .{ 0, 0, 0, 0, 0, 5, 3, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 3, 5, 0, 0, 0, 0, 0 },
        .{ 5, 5, 5, 5, 5, 5, 3, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 3, 5, 5, 5, 5, 5, 5 },
        .{ 0, 0, 0, 0, 0, 5, 3, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 3, 5, 0, 0, 0, 0, 0 },
        .{ 0, 0, 0, 0, 0, 5, 3, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 3, 5, 0, 0, 0, 0, 0 },
        .{ 0, 0, 0, 0, 0, 5, 3, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 3, 5, 0, 0, 0, 0, 0 },
        .{ 5, 5, 5, 5, 5, 5, 3, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 3, 5, 5, 5, 5, 5, 5 },
        .{ 5, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 5, 5, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 5 },
        .{ 5, 3, 5, 5, 5, 5, 3, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 3, 5, 5, 5, 5, 3, 5 },
        .{ 5, 3, 5, 5, 5, 5, 3, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 3, 5, 5, 5, 5, 3, 5 },
        .{ 5, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 5, 5, 5, 5, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 5 },
        .{ 5, 3, 5, 5, 5, 5, 3, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 3, 5, 5, 5, 5, 3, 5 },
        .{ 5, 3, 5, 5, 5, 5, 3, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 3, 5, 5, 5, 5, 3, 5 },
        .{ 5, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 5 },
        .{ 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5 },
        .{ 5, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 5, 5, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 5 },
        .{ 5, 3, 5, 5, 5, 5, 3, 5, 5, 5, 5, 5, 3, 5, 5, 3, 5, 5, 5, 5, 5, 3, 5, 5, 5, 5, 3, 5 },
        .{ 5, 3, 5, 5, 5, 5, 3, 5, 5, 5, 5, 5, 3, 5, 5, 3, 5, 5, 5, 5, 5, 3, 5, 5, 5, 5, 3, 5 },
        .{ 5, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 5 },
        .{ 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5 },
    };

    var dots: u32 = 0;
    var y: usize = 0;
    while (y < height) : (y += 1) {
        var x: usize = 0;
        while (x < width) : (x += 1) {
            const entity: EntityType = @enumFromInt(maze[y][x]);
            state.tiles[y][x] = Tile{ .x = @intCast(x), .y = @intCast(y), .entity = entity };
            if (entity == .dot) {
                dots += 1;
            }
        }
    }

    state.dots_remaining = dots;
    return state;
}
