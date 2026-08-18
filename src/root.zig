//! Pacman game root module
//! Exports game state and Nostr scoreboard functionality.

pub const game = @import("game/state.zig");
pub const ai = @import("game/ai.zig");
pub const tui = @import("tui.zig");
pub const nostr = @import("nostr/events.zig");
