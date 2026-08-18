## Clarified Problem Statement

**Goal:** Build a classic Pac-Man game in Zig (single-player, extensible to local/remote multiplayer) with a general Nostr-based scoreboard system, using openspec.dev for specification and a personal code-style dataset for formatting alignment. The game must feature a modern, super cool TUI (Text User Interface) inspired by OpenCode's TUI — not a simple CLI — with rich visuals, animations, and polished terminal UX.

**Constraints:**
- Zig (latest stable version)
- Real-time multiplayer (same machine and remote)
- Classic Pac-Man 1:1 (maze, dots, power pellets, 4 ghost AI)
- Scoreboard backed by Nostr relays
- Code style aligned to `vincenzopalazzo/code-style-dataset`
- Private repo: `git@github.com:vincenzopalazzo/pacman.git`
- TUI must be super cool and modern (OpenCode TUI-inspired)

**Non-goals:**
- Online matchmaking / lobby system (initial focus: local play)
- Monetization or competitive ranking (just score tracking)
- Cross-platform mobile support (desktop-first)
- GUI/ graphical desktop app (terminal-only)

**Success criteria:**
- Playable Pac-Man with correct ghost AI
- Local 2-player real-time mode working
- Remote multiplayer via Nostr relay (pub/sub)
- Score events published as Nostr events with a new general NIP for game scoreboards
- Relay board that indexes scores by game + user
- Openspec specs/decisions/tasks/ scaffolded and used
- Code formatted per personal style dataset
- Super cool TUI with modern terminal UX (inspired by OpenCode)

## Approaches Considered

### Approach A: Custom Zig + raw WebSocket + new Nostr NIP + Custom TUI
- Sketch: Build game loop in Zig with a custom super cool TUI (OpenCode-inspired) using ANSI escape codes and Unicode. Multiplayer via raw WebSocket (local) and Nostr WebSocket relays (remote). Define a new NIP (e.g., kind `30064` or similar) for general game scoreboard events, inspired by NIP-64 (chess PGN).
- Affected files: `src/main.zig`, `src/tui.zig` (new), `src/game.zig`, `src/network.zig`, `src/nostr.zig`, `specs/`, `nips/`
- Tradeoffs: Full control, no framework lock-in. Requires writing Nostr crypto from scratch or porting a small library. New NIP needs community adoption but is simple. Custom TUI gives maximum visual control and retro arcade feel.
- Effort: Large

### Approach B: Zig + ECS framework + extend NIP-78 + Custom TUI
- Sketch: Use a Zig ECS library for game state. Multiplayer via existing networking lib. Use NIP-78 (kind `30078`, Application-specific Data) for score storage, avoiding a new NIP. Custom TUI layer for rendering.
- Affected files: Same as A, plus ECS layer and `src/tui.zig`
- Tradeoffs: Faster to ship, no NIP proposal overhead. NIP-78 is very generic — scoreboard queries are less standardized. Less "canonical" for game-specific metadata. Custom TUI adds visual polish.
- Effort: Medium

### Approach C: Zig + Godot/Unity-style engine + NIP-64 extension
- Sketch: Build a minimal engine in Zig. Extend NIP-64 (currently chess-only) with a `game` tag to support arbitrary games, or propose a sibling NIP (e.g., NIP-XX) for arcade game scores.
- Affected files: Same as A
- Tradeoffs: Leverages existing NIP-64 recognition. Extension approach is controversial (NIP-64 is chess-specific). New NIP is cleaner. No specific TUI plan.
- Effort: Large

## Recommendation

**Approach A** — Custom Zig + raw WebSocket + new Nostr NIP + Custom TUI.

Reasoning: NIP-64 proves the pattern (kind-based game events) works. A new, general "game scoreboard" NIP (e.g., `NIP-XX: Game Score Events`) is the right long-term move — it's general, simple, and follows the NIP-64 precedent. Zig gives you performance and control. Raw WebSocket is sufficient for local/remote real-time play without pulling in heavy networking frameworks. A custom TUI layer gives full control over the retro arcade aesthetic and OpenCode-inspired modern terminal UX, keeping the project pure Zig without external TUI dependencies.

## Open questions

- Nostr NIP number: Do you want to reserve a specific number, or just draft it locally as `NIP-XX` and submit later?
- Zig package manager: Use `zigmod`/`ziger` or manual `build.zig` dependencies?
- Asset pipeline: Do you want procedural assets (generated in code) or sprite sheets?
- Relay strategy: Use public relays (e.g., relay.damus.io) or run a local relay for development?
- Ghost AI: Start with behavior tree + personality weights, or explore local LLM integration later?
- TUI library: Build custom TUI layer in Zig, or use an existing Zig TUI library (e.g., `zitui`, `tigerbeetle/tui`)?
- TUI features: Should it include side panels (score, lives, minimap), animations (ghost movement, power-pellet flash), and color themes?

## TUI Design Plan

### Objective
Replace the basic terminal rendering with a super cool, modern TUI inspired by OpenCode's interface — featuring rich colors, smooth animations, side panels, and polished terminal UX.

### Approach
- **Phase 1: Enhanced Rendering Layer**
  - Add `src/tui.zig` for terminal UI abstraction
  - Use ANSI 256-color / true-color escape sequences for Pac-Man (yellow), ghosts (red/pink/cyan/orange), walls (blue), dots (white), power pellets (white flashing)
  - Implement double-buffered rendering with `\x1b[H\x1b[J` + redraw for smooth updates
  - Add Unicode box-drawing characters for UI panels (score, lives, level, timer)

- **Phase 2: Layout & Panels**
  - Main game area (maze) centered
  - Left panel: Score, High Score, Level, Lives (with heart icons ♥)
  - Right panel: Ghost status indicators (normal/frightened/eaten), frightened timer bar
  - Bottom bar: Controls hint (Arrow keys / WASD, Q to quit, P to pause)
  - Top bar: Game title with gradient/color effect

- **Phase 3: Animations & Effects**
  - Pac-Man mouth animation (open/close `()` vs `@`)
  - Ghost eyes direction tracking
  - Power-pellet flashing animation (blink every 10 ticks)
  - Frightened mode: ghost colors cycle through blue/white
  - Screen shake on death
  - Score popup (+10, +200) floating text animation

- **Phase 4: Polish**
  - Smooth color transitions
  - CRT/retro scanline effect (optional, toggleable)
  - Sound effects via terminal bell (`\x07`) or beep patterns
  - Responsive layout that adapts to terminal size

### TUI Library Options
- **Option A: Custom Zig TUI** — Full control, no dependencies. Use ANSI escape codes directly.
- **Option B: Zig TUI library** — Use an existing Zig TUI crate if available (e.g., `zitui` or similar).
- **Option C: Rust TUI bridge** — Overkill, not recommended.

**Recommendation:** Option A (custom Zig TUI) — keeps the project pure Zig, matches the code-style dataset, and gives full control over the retro arcade aesthetic.

### Files to create/modify
- `src/tui.zig` (new) — TUI renderer, color palette, layout, animations
- `src/main.zig` — integrate TUI renderer, replace raw ANSI output
- `src/game/state.zig` — add animation state fields (mouth_phase, flash_tick, etc.)
- `src/game/ai.zig` — expose ghost state for TUI color rendering

## Local AI Plan

### Objective
Make ghosts less stupid and more fun using local AI techniques, starting with deterministic behavior trees and personality systems.

### Approach
- **Phase 1: Behavior Tree + Personality Weights**
  - Create `src/game/ai.zig`
  - Add `GhostAI` struct with personality weights (aggression, ambush, unpredictability)
  - Implement `decideDirection(ghost, pacman, maze) -> Direction`
  - Personality presets: Blinky (chase 0.9), Pinky (ambush 0.7), Inky (unpredictable 0.5), Clyde (random 0.3)

- **Phase 2: FSM with States**
  - States: `chase`, `scatter`, `frightened`, `eaten`
  - State transitions based on timers and events (power pellet, proximity)

- **Phase 3: Local LLM (experimental)**
  - Evaluate `llama.cpp` or similar for ghost "personality" queries
  - High latency, fun but not arcade-appropriate

### Files to create/modify
- `src/game/ai.zig` (new)
- `src/game/state.zig` (add personality fields to Ghost)
- `src/main.zig` (call AI in game loop)
