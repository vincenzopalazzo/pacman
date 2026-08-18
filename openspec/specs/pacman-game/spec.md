# Pacman Game Specification

## Purpose
Classic Pac-Man arcade game with real-time multiplayer support and Nostr-based scoreboard.

## Requirements

### Requirement: Game Loop
The system SHALL run a deterministic game loop at 60 FPS with fixed timestep physics.

#### Scenario: Frame advancement
- GIVEN the game is running
- WHEN a frame is processed
- THEN all entities update position and state
- AND the renderer draws the current frame

### Requirement: Maze Rendering
The system SHALL render a 2D tile-based maze matching classic Pac-Man layout.

#### Scenario: Wall collision
- GIVEN Pac-Man is adjacent to a wall tile
- WHEN Pac-Man attempts to move into the wall
- THEN movement is blocked
- AND Pac-Man remains in the current tile

### Requirement: Ghost AI
The system SHALL implement 4 ghost personalities: Blinky (chase), Pinky (ambush), Inky (unpredictable), Clyde (random).

#### Scenario: Blinky targets Pac-Man
- GIVEN Blinky is in scatter mode
- WHEN mode timer expires
- THEN Blinky's target becomes Pac-Man's current tile

### Requirement: Score System
The system SHALL track score with dot (10pts), power pellet (50pts), and ghost (200-1600pts) values.

#### Scenario: Eating a ghost
- GIVEN a ghost is vulnerable (power pellet active)
- WHEN Pac-Man collides with the ghost
- THEN score increases by 200 * consecutive ghosts eaten
- AND the ghost returns to the ghost house

### Requirement: Local Multiplayer
The system SHALL support 2 players on the same machine with shared keyboard input.

#### Scenario: Second player joins
- GIVEN a game is running in single-player mode
- WHEN second player presses join key
- THEN second player spawns at start position
- AND both players share the same maze and dots

### Requirement: Remote Multiplayer
The system SHALL synchronize game state across network using WebSocket connections.

#### Scenario: Remote player connects
- GIVEN a host is waiting for players
- WHEN a remote client connects via WebSocket
- THEN host assigns player ID to client
- AND client receives current game state

### Requirement: Nostr Scoreboard
The system SHALL publish score events to Nostr relays using a general game scoreboard NIP.

#### Scenario: Game ends
- GIVEN a player completes a game (wins or loses)
- WHEN the score event is created
- THEN the event is signed with player's private key
- AND published to configured relays

### Requirement: Relay Board
The system SHALL query Nostr relays for game scores and display leaderboards.

#### Scenario: View leaderboard
- GIVEN the user requests a leaderboard
- WHEN querying relays for a specific game kind
- THEN scores are aggregated by user
- AND displayed sorted by highest score
