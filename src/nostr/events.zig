const std = @import("std");

pub const Event = struct {
    id: [64]u8,
    pubkey: [64]u8,
    created_at: u64,
    kind: u64,
    tags: []const []const [8]u8,
    content: []const u8,
    sig: [128]u8,
};

pub const ScoreEvent = struct {
    game: []const u8,
    version: []const u8,
    score: u64,
    level: u8,
    duration_ms: u64,
    result: []const u8,
    player: [64]u8,
    session: [64]u8,
    mode: []const u8,
};

pub fn createScoreEvent(
    io: std.Io,
    allocator: std.mem.Allocator,
    score: ScoreEvent,
) !Event {
    const kind: u64 = 30000;
    const timestamp = std.Io.Clock.Timestamp.now(io, .real);
    const created_at: u64 = @intCast(@divTrunc(timestamp.raw.nanoseconds, std.time.ns_per_s));

    var tags_buf = try std.ArrayList([]const [8]u8).initCapacity(allocator, 0);
    errdefer tags_buf.deinit(allocator);

    const game_tag: [8]u8 = .{ 'g', 'a', 'm', 'e', ' ', ' ', ' ', ' ' };
    const player_tag: [8]u8 = .{ 'p', 'l', 'a', 'y', 'e', 'r', ' ', ' ' };
    try tags_buf.append(allocator, &[_][8]u8{game_tag});
    try tags_buf.append(allocator, &[_][8]u8{player_tag});

    const tags = try allocator.alloc([]const [8]u8, tags_buf.items.len);
    errdefer allocator.free(tags);
    @memcpy(tags, tags_buf.items);

    const content = try std.fmt.allocPrint(allocator,
        \\{{"game":"{s}","version":"{s}","score":{d},"level":{d},"duration_ms":{d},"result":"{s}"}}
    , .{
        score.game,
        score.version,
        score.score,
        score.level,
        score.duration_ms,
        score.result,
    });
    errdefer allocator.free(content);

    const event = Event{
        .id = undefined,
        .pubkey = undefined,
        .created_at = created_at,
        .kind = kind,
        .tags = tags,
        .content = content,
        .sig = undefined,
    };

    return event;
}
