# NIP-XX: Game Score Events

## Purpose
General-purpose Nostr events for publishing game scores, enabling decentralized scoreboards across any game.

## Event Kind

Kind: `30000` (replace with assigned NIP number)

This kind is addressable. The `d` tag identifies the game.

## Content Format

JSON object:

```json
{
  "game": "pacman",
  "version": "1",
  "score": 12400,
  "level": 3,
  "duration_ms": 184000,
  "result": "win",
  "metadata": {
    "dots_eaten": 234,
    "power_pellets_eaten": 2,
    "ghosts_eaten": 5,
    "lives_remaining": 1
  }
}
```

## Tags

- `d` - Game identifier (e.g., `pacman`, `chess`, "doom")
- `game` - Alias for `d`
- `player` - Nostr pubkey of the player (npub)
- `session` - Unique session ID for this playthrough
- `mode` - Game mode: `single`, `local-multi`, "remote-multi"
- `created_at` - When the game started

## Validation

Relays MAY validate:
- `score` is a non-negative integer
- `game` is a non-empty string
- `duration_ms` is a positive integer if present

## Querying

Clients query with:

```
REQ <subid> <since> <until> {":game", "pacman"}
```

Or filter by player:

```
REQ <subid> <since> <until> {":player", "<npub>"}
```

## Compatibility

Clients that do not recognize this kind SHOULD display the event as application-specific data per NIP-78.
