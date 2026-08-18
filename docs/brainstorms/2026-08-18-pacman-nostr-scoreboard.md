## Clarified Problem Statement

**Goal:** Build a classic Pac-Man game in Zig (single-player, extensible to local/remote multiplayer) with a general Nostr-based scoreboard system, using openspec.dev for specification and a personal code-style dataset for formatting alignment.

**Constraints:**
- Zig (latest stable version)
- Real-time multiplayer (same machine and remote)
- Classic Pac-Man 1:1 (maze, dots, power pellets, 4 ghost AI)
- Scoreboard backed by Nostr relays
- Code style aligned to `vincenzopalazzo/code-style-dataset`
- Private repo: `git@github.com:vincenzopalazzo/pacman.git`

**Non-goals:**
- Online matchmaking / lobby system (initial focus: local play)
- Monetization or competitive ranking (just score tracking)
- Cross-platform mobile support (desktop-first)

**Success criteria:**
- Playable Pac-Man with correct ghost AI
- Local 2-player real-time mode working
- Remote multiplayer via Nostr relay (pub/sub)
- Score events published as Nostr events with a new general NIP for game scoreboards
- Relay board that indexes scores by game + user
- Openspec specs/decisions/tasks/ scaffolded and used
- Code formatted per personal style dataset

## Approaches Considered

### Approach A: Custom Zig + raw WebSocket + new Nostr NIP
- Sketch: Build game loop in Zig with Raylib/Zig-raylib for rendering. Multiplayer via raw WebSocket (local) and Nostr WebSocket relays (remote). Define a new NIP (e.g., kind `30064` or similar) for general game scoreboard events, inspired by NIP-64 (chess PGN).
- Affected files: `src/main.zig`, `src/game.zig`, `src/network.zig`, `src/nostr.zig`, `specs/`, `nips/`
- Tradeoffs: Full control, no framework lock-in. Requires writing Nostr crypto from scratch or porting a small library. New NIP needs community adoption but is simple.
- Effort: Large

### Approach B: Zig + ECS framework + extend NIP-78
- Sketch: Use a Zig ECS library for game state. Multiplayer via existing networking lib. Use NIP-78 (kind `30078`, Application-specific Data) for score storage, avoiding a new NIP.
- Affected files: Same as A, plus ECS layer
- Tradeoffs: Faster to ship, no NIP proposal overhead. NIP-78 is very generic — scoreboard queries are less standardized. Less "canonical" for game-specific metadata.
- Effort: Medium

### Approach C: Zig + Godot/Unity-style engine + NIP-64 extension
- Sketch: Build a minimal engine in Zig. Extend NIP-64 (currently chess-only) with a `game` tag to support arbitrary games, or propose a sibling NIP (e.g., NIP-XX) for arcade game scores.
- Affected files: Same as A
- Tradeoffs: Leverages existing NIP-64 recognition. Extension approach is controversial (NIP-64 is chess-specific). New NIP is cleaner.
- Effort: Large

## Recommendation

**Approach A** — Custom Zig + raw WebSocket + new Nostr NIP.

Reasoning: NIP-64 proves the pattern (kind-based game events) works. A new, general "game scoreboard" NIP (e.g., `NIP-XX: Game Score Events`) is the right long-term move — it's general, simple, and follows the NIP-64 precedent. Zig gives you performance and control. Raw WebSocket is sufficient for local/remote real-time play without pulling in heavy networking frameworks.

## Open questions

- Nostr NIP number: Do you want to reserve a specific number, or just draft it locally as `NIP-XX` and submit later?
- Zig package manager: Use `zigmod`/`ziger` or manual `build.zig` dependencies?
- Asset pipeline: Do you want procedural assets (generated in code) or sprite sheets?
- Relay strategy: Use public relays (e.g., relay.damus.io) or run a local relay for development?
- Ghost AI: Start with behavior tree + personality weights, or explore local LLM integration later?

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
