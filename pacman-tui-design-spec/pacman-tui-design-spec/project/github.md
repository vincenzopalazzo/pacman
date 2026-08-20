repo: rockorager/libvaxis
branch: main
path: src

## Last sync
date: 2026-08-20T15:31:01Z

### Updated in this project
- Read `src/Window.zig` and `src/Cell.zig` to ground the vaxis 0.6.0 rendering notes (print/printSegment semantics, `child()` border behaviour, custom border glyph order, `i17`/`u16` offsets).
- Verified `Cell.Color` is `union(enum){ default, index: u8, rgb: [3]u8 }` plus `rgbFromUint` — used in the palette spec.

## Screen map
| Screen / section | Built from |
| --- | --- |
| Pacman TUI Spec.dc.html — 07 vaxis 0.6.0 API notes | src/Window.zig, src/Cell.zig |
| Pacman TUI Spec.dc.html — 03 Palette (Color union, rgbFromUint) | src/Cell.zig |
