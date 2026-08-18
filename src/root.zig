//! Pacman game root module
//! Exports game state and Nostr scoreboard functionality.

pub const game = @import("game/state.zig");
pub const nostr = @import("nostr/events.zig");
