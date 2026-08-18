const std = @import("std");
const pacman = @import("pacman");

pub fn main() !void {
    const io = std.Io.Threaded.global_single_threaded.io();
    const gpa = std.heap.page_allocator;
    var stdout_buf: [1024]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(io, &stdout_buf);
    const stdout_writer = &stdout.interface;

    const state = try pacman.game.createGameState(gpa, 28, 31);
    defer {
        for (state.tiles) |row| {
            gpa.free(row);
        }
        gpa.free(state.tiles);
    }

    try stdout_writer.print("Pac-Man (Zig)\n", .{});
    try stdout_writer.print("Score: 0\n", .{});
    try stdout_writer.print("Lives: 3\n", .{});
    try stdout_writer.print("Level: 1\n", .{});
    try stdout.flush();

    const score_event = pacman.nostr.ScoreEvent{
        .game = "pacman",
        .version = "1",
        .score = state.score,
        .level = state.level,
        .duration_ms = 0,
        .result = "in_progress",
        .player = undefined,
        .session = undefined,
        .mode = "single",
    };

    const event = try pacman.nostr.createScoreEvent(io, gpa, score_event);
    _ = event;
    try stdout_writer.writeAll("Game initialized.\n");
    try stdout.flush();
}
