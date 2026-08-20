# PAC·ZIG — TUI implementation brief

Hand this file **plus `Pacman TUI Prototype.dc.html`** to the implementing agent.
The prototype is a working reference implementation of everything below (JavaScript, meant to be read and ported — not shipped). `Pacman TUI Spec.dc.html` is the visual spec.

Target: **Zig 0.16.0** (Homebrew ships 0.15.2 — use the 0.16.0 Cellar binary), **libvaxis 0.6.0**, low-level API (`vaxis.Vaxis` + `vaxis.Loop`, not `vxfw`).

---

## 1. Acceptance criteria

1. Runs at any terminal size ≥ 30 × 36; below that it shows a live "too small" notice, never a clipped maze.
2. Three layout modes selected purely by size: `standard`, `wide`, `wide + rail`. Switching happens on `winsize` events only.
3. The maze never scales, stretches, or reflows. Only cells-per-tile, rail presence and centering offsets change.
4. Walls are **line art** resolved from neighbours, not filled blocks.
5. No emoji anywhere. Every game glyph measures width 1 via `win.gwidth()` at startup; if any doesn't, the ASCII fallback set is used for the whole run.
6. 120 Hz fixed simulation step, render capped at 30 fps and skipped when no state changed.
7. Truecolor palette with a 256-index fallback chosen once at startup from `vx.caps.rgb`.

---

## 2. Maze data

31 rows × 28 columns. Copy byte-for-byte into `const MAZE: [31][]const u8`.

```
############################
#o........................o#
#.#####.####.##.####.#####.#
#.#   #.#  #.##.#  #.#   #.#
#.#####.####.##.####.#####.#
#..........................#
#.####.##.########.##.####.#
#.####.##.########.##.####.#
#......##..........##......#
#.####.##.########.##.####.#
#.#  #....#      #....#  #.#
#.####....########....####.#
#..........................#
#.########.##--##.########.#
#.########.#HHHH#.########.#
 ..........#HHHH#..........
#.########.#HHHH#.########.#
#.########.######.########.#
#..........................#
#.####....########....####.#
#.#  #....#      #....#  #.#
#.####.##.########.##.####.#
#......##..........##......#
#.####.##.########.##.####.#
#.####.##.########.##.####.#
#..........................#
#.#####.####.##.####.#####.#
#.#   #.#  #.##.#  #.#   #.#
#.#####.####.##.####.#####.#
#o........................o#
############################
```

| Char | Meaning | Pac passable | Ghost passable |
|---|---|---|---|
| `#` | wall | no | no |
| `.` | dot (10 pts) | yes | yes |
| `o` | power pellet (50 pts) | yes | yes |
| `-` | ghost-house door | no | yes |
| `H` | ghost house interior | no | yes |
| space | void / enclosed interior | yes (unreachable) | yes |

Row 15 columns 0 and 27 are open: **tunnel**. Wrap `col` modulo 28; entities move at half speed inside it.

Fixed positions: Pac start `(22, 14)`. Blinky start `(12, 13)`. House slots `(15, 12) (15, 14) (15, 15)`. House re-entry target `(14, 13)`.
Scatter corners: Blinky `(1, 26)`, Pinky `(1, 1)`, Inky `(29, 26)`, Clyde `(29, 1)`.

---

## 3. Wall glyph resolution — run ONCE at level load

For each `#` tile compute which sides face a non-wall. **Out of bounds counts as open** — that is what gives the outer border its corners.

```
N and W -> ╭        N only, or N and S -> ─
N and E -> ╮        S only               -> ─
S and W -> ╰        E, W, or E and W     -> │
S and E -> ╯        none                 -> space
```

Checked in exactly that order. Store in `[31][28][]const u8` (slices of string literals — they outlive `render()`). Never recompute per frame.

Door tiles (`-`) draw `╌` in pink with `dim = true`. House interior draws nothing.

---

## 4. Layout — pure function of terminal size

```zig
const Mode = enum { too_small, standard, wide, wide_rail };

const Layout = struct { mode: Mode, cpt: u16, rail: u16, w: u16, h: u16, x: u16, y: u16 };

fn layout(cols: u16, rows: u16) Layout {
    if (cols < 30 or rows < 36) return .{ .mode = .too_small, ... };
    const wide  = cols >= 60 and rows >= 38;
    const cpt: u16 = if (wide) 2 else 1;          // cells per tile, horizontal
    const maze_w = 28 * cpt;
    const rail: u16 = if (cols >= maze_w + 24 and rows >= 40) 20 else 0;
    const w = maze_w + if (rail != 0) rail + 2 else 0;
    return .{
        .mode = if (rail != 0) .wide_rail else if (wide) .wide else .standard,
        .cpt = cpt, .rail = rail, .w = w, .h = 36,
        .x = (cols -| w) / 2,                      // saturating! u16 underflow otherwise
        .y = (rows -| 36) / 2,
    };
}
```

Canvas is **28·cpt (+rail) × 36 cells**, rows relative to `y`:

| Row | Content |
|---|---|
| 0 | `1UP` · `HIGH SCORE` · `LVL` labels (dim) |
| 1 | score · high score · level values (white, zero-padded 6 / 2) |
| 2 | blank |
| 3–33 | maze, 31 rows |
| 34 | blank |
| 35 | lives (`ᗧ` × n, left) · fruit history (`◆`, right) |

Wide mode draws each tile in 2 cells. Second cell per glyph: `─ ╭ ╰` → `─`; `╮ ╯ │` → space; `╌` → `╌`; dots, pellets and entities → space.

Rail (when present) starts at `x + 28·cpt + 2`, 20 cols: ghost roster with live mode, dots-remaining meter (`█░` + count), current mode, key hints.

`too_small`: centered three lines — `TERMINAL TOO SMALL`, `NEED 30 × 36`, `GOT <cols> × <rows>` — updating on every `winsize`.

---

## 5. Palette

Truecolor is the source of truth; the index column is the `vx.caps.rgb == false` fallback. Contrast ratios are against `#000000`.

| Role | Hex | 256 | CR |
|---|---|---|---|
| background | `#000000` | 16 | — |
| wall | `#3B4CFF` | 63 | 4.6:1 |
| wall (`--theme=arcade`, opt-in) | `#2121DE` | 20 | 2.5:1 |
| ghost door | `#FFB8FF` | 219 | 12.6:1 |
| dot / power pellet | `#FFB8AE` | 224 | 11.5:1 |
| pac-man, lives, READY! | `#FFFF00` | 226 | 19.6:1 |
| blinky | `#FF0000` | 196 | 5.3:1 |
| pinky | `#FFB8FF` | 219 | 12.6:1 |
| inky | `#00FFFF` | 51 | 16.7:1 |
| clyde | `#FFB852` | 215 | 11.0:1 |
| frightened | `#3B4CFF` | 63 | 4.6:1 |
| fright flash / eyes / HUD value | `#FFFFFF` | 231 | 21:1 |
| HUD label, key hints | `#9EA4B8` | 248 | 7.4:1 |
| alert (GAME OVER) | `#FF0000` | 196 | 5.3:1 |
| success (level clear, meter) | `#4CFF4C` | 82 | 15.9:1 |

Rules: never set `bg` on maze cells (inherit the terminal background); only HUD inversion and overlay cards paint `bg`. Nothing is signalled by hue alone.

---

## 6. Glyphs

| Element | Glyph | ASCII fallback |
|---|---|---|
| wall | `╭ ─ ╮ │ ╰ ╯` (`├ ┤ ┬ ┴ ┼` unused by this map) | `+ - \|` |
| ghost door | `╌` | `-` |
| dot / pellet | `·` / `●` | `.` / `o` |
| pac right/left | `ᗧ` U+15E7 / `ᗤ` U+15E4 | `>` `<` |
| pac up/down | `◓` U+25D3 / `◒` U+25D2 | `^` `v` |
| pac closed (all dirs) | `●` | `O` |
| ghost | `ᗣ` U+15E3 | `M` |
| ghost eaten (eyes) | `"` | `"` |
| fruit / life | `◆` / `ᗧ` | `*` / `>` |
| overlay frame | `╔ ═ ╗ ║ ╚ ╝` | `= \|` |
| meter | `█ ░` | `# -` |

HUD copy is uppercase, single-spaced, zero-padded, no thousands separators.

---

## 7. Simulation

Fixed step `1/120 s`. Speeds in tiles/second; a tile move happens when accumulated progress ≥ 1.

| Thing | Value |
|---|---|
| pac | 8 tiles/s |
| ghost normal | 7.5 tiles/s |
| ghost frightened | 5 tiles/s |
| ghost eyes (returning) | 14 tiles/s |
| tunnel | half speed |
| input buffer | last direction key held 250 ms, retried each tick |
| mouth animation | 7.5 Hz, freezes closed when blocked |
| pellet blink | 5 Hz (own tick — never SGR `blink`) |
| frightened | `max(1, 7 - level)` seconds |
| fright flash | final 2 s, 4 Hz, `#3B4CFF` ↔ `#FFFFFF` |
| ghost eaten | 200/400/800/1600 per chain, 1 s freeze |
| death | 11 frames over 1.4 s, ghosts hidden from frame 0, last frame red, then 1 s black |
| READY | 4.5 s on level 1, 2 s after |
| level clear | 4 wall flashes at 3 Hz, then 1 s black |

Scatter/chase plan (seconds, level 1), repeating on the last entry; frightened **pauses** this clock, and every mode edge forces a reversal:
`7 scatter · 20 chase · 7 scatter · 20 chase · 5 scatter · 20 chase · 5 scatter · chase…`

Ghost targets: Blinky = Pac's tile. Pinky = 4 tiles ahead of Pac. Inky = mirror of Blinky through the point 2 tiles ahead of Pac. Clyde = Pac if further than 8 tiles, else his corner. Frightened = random. Direction choice each tile: all directions except the reverse, filtered to passable, minimum squared distance to target.

---

## 8. Component contract

| Component | Owns | Reads | Must not |
|---|---|---|---|
| `Game` | maze grid, food, score, lives, level, phase machine (`ready/play/death/cleared/over`), input buffer | key events, GhostAI decisions, AnimationState | know that vaxis exists — it draws nothing |
| `GhostAI` | per-ghost mode/target/state (`house/leaving/out/eyes`), mode clock, forced reversals | maze walls, Pac tile + dir | mutate maze or score |
| `AnimationState` | one monotonic `tick: u64`, all derived phases, cutscene locks | nothing | hold game rules or per-entity timers |
| `Screen` | root window, layout mode, offsets, child windows | terminal size | allocate per frame, cache windows across resize |
| `HUD` | HUD rows + **owned** score/level format buffers | score, lives, level, dots, fruit | format into a stack buffer |
| `MazeView` | pre-resolved wall glyph table, draw order (dots → pellets → fruit → ghosts → pac) | maze, entities, palette, phases | recompute glyphs per frame |
| `Overlay` | title/pause/game-over/level-clear cards, menu index | phase, AnimationState, high scores | run game logic — it returns an intent enum |

Draw layer is pure functions of `(state, window)`: no mutation, no allocation.

---

## 9. vaxis 0.6.0 API notes (from `src/Window.zig`, `src/Cell.zig`)

- `Cell.Color = union(enum) { default, index: u8, rgb: [3]u8 }`; build with `.{ .rgb = .{ r, g, b } }` or `Color.rgbFromUint(0xFFB8AE)`. Resolve truecolor-vs-index **once** at startup, not per cell.
- **`print`/`printSegment` store a slice, not a copy** (`.grapheme = grapheme.bytes(segment.text)`), and the frame flushes after `render()` returns. Every dynamic string must live in a buffer owned by `Game`/`HUD`; a stack buffer renders as garbage or U+FFFD, intermittently.
- `printSegment(seg, opts)` == `print(&.{seg}, opts)` and returns `PrintResult{ col, row, overflow }`. Call with `.commit = false` to measure, then print centered at `(win.width -| result.col) / 2`.
- `win.child(.{ .border = .{ .where = .all } })` returns the **inner** window (border eats one cell per side). The maze's own outer wall is the frame — no vaxis border on the canvas.
- Custom border glyph order is `.{ top_left, horizontal, top_right, vertical, bottom_right, bottom_left }` — last two reversed from reading order. Built-ins `.single_rounded`, `.single_square`.
- `writeCell` clips silently out of bounds — no error, no panic. Assert maze bounds in debug; draw the maze into a child window sized exactly `28·cpt × 31`.
- Set `Cell.Character.width = 1` explicitly for every glyph (verified once with `win.gwidth()`); `width = 0` re-measures every cell every frame.
- `x_off`/`y_off` are `i17`, `width`/`height` are `u16`. Centre with saturating `-|`.
- `clear()` on a full-width window is one memset, and `vx.render()` already diffs against the previous frame. Redraw everything, gate on "did state change", don't hand-roll dirty rects.
- Never use `Cell.Style.blink`.

---

## 10. Build order suggestion

1. `MAZE` + `resolveWalls()` + `layout()` + a static render of the READY screen. Verify against the prototype at 30×36, 60×38, 80×40.
2. Pac movement + input buffer + dot eating + HUD.
3. Ghost house exit, scatter/chase, collisions, lives, death animation.
4. Power pellets, frightened, chain scoring, eyes returning home.
5. Overlays (title, pause, game over, level clear) and the rail.
6. `gwidth` startup check with ASCII fallback, 256-color fallback, `--theme=arcade`.
