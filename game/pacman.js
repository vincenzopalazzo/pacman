// PACMAN — browser canvas port of the TUI prototype.
// Fixed 120 Hz game loop. Native maze dimensions (31 rows x 28 cols),
// responsive page layout. Arrow keys / WASD steer, space toggles start/pause.

const MAZE = [
  "############################",
  "#o........................o#",
  "#.#####.####.##.####.#####.#",
  "#.#   #.#  #.##.#  #.#   #.#",
  "#.#####.####.##.####.#####.#",
  "#..........................#",
  "#.####.##.########.##.####.#",
  "#.####.##.########.##.####.#",
  "#......##..........##......#",
  "#.####.##.########.##.####.#",
  "#.#  #....#      #....#  #.#",
  "#.####....########....####.#",
  "#..........................#",
  "#.########.##--##.########.#",
  "#.########.#HHHH#.########.#",
  " ..........#HHHH#.......... ",
  "#.########.#HHHH#.########.#",
  "#.########.######.########.#",
  "#..........................#",
  "#.####....########....####.#",
  "#.#  #....#      #....#  #.#",
  "#.####.##.########.##.####.#",
  "#......##..........##......#",
  "#.####.##.########.##.####.#",
  "#.####.##.########.##.####.#",
  "#..........................#",
  "#.#####.####.##.####.#####.#",
  "#.#   #.#  #.##.#  #.#   #.#",
  "#.#####.####.##.####.#####.#",
  "#o........................o#",
  "############################",
];

const ROWS = 31, COLS = 28;
const CELL = 18; // fixed native cell size in canvas pixels
const WALL = "#3B4CFF", GATE = "#FFB8FF", DOT = "#FFB8AE", PAC = "#FFFF00";
const BLINKY = "#FF0000", PINKY = "#FFB8FF", INKY = "#00FFFF", CLYDE = "#FFB852";
const AFRAID = "#3B4CFF", FLASH = "#FFFFFF", DIM = "#9EA4B8", ALERT = "#FF0000";
const DIRS = { up: [-1, 0], down: [1, 0], left: [0, -1], right: [0, 1] };
const OPP = { up: "down", down: "up", left: "right", right: "left" };
const MODE_PLAN = [[7, "scatter"], [20, "chase"], [7, "scatter"], [20, "chase"], [5, "scatter"], [20, "chase"], [5, "scatter"]];

function isWall(r, c) {
  if (r < 0 || r >= ROWS || c < 0 || c >= COLS) return false;
  return MAZE[r][c] === "#";
}
function resolveWalls() {
  const g = [];
  for (let r = 0; r < ROWS; r++) {
    const row = [];
    for (let c = 0; c < COLS; c++) {
      if (MAZE[r][c] !== "#") { row.push(" "); continue; }
      const N = !isWall(r - 1, c), S = !isWall(r + 1, c), E = !isWall(r, c + 1), W = !isWall(r, c - 1);
      row.push(N && W ? "╭" : N && E ? "╮" : S && W ? "╰" : S && E ? "╯" : (N || S) ? "─" : (E || W) ? "│" : " ");
    }
    g.push(row);
  }
  return g;
}
const WALLG = resolveWalls();
function pad(n, w) { return String(n).padStart(w, "0"); }

class Game {
  constructor() {
    this.food = null; this.g = null;
    this.reset();
  }

  reset() {
    const food = MAZE.map((r) => r.split(""));
    let dots = 0;
    for (const row of food) for (const ch of row) if (ch === "." || ch === "o") dots++;
    this.g = {
      t: 0, food, dots, total: dots, score: 0, high: 42995, lives: 2, level: 1,
      pac: { r: 22, c: 14, dir: "left", prog: 0 },
      ghosts: [
        { n: "BLINKY", col: BLINKY, r: 12, c: 13, dir: "left", prog: 0, state: "out", home: [1, 26] },
        { n: "PINKY", col: PINKY, r: 15, c: 12, dir: "up", prog: 0, state: "house", home: [1, 1] },
        { n: "INKY", col: INKY, r: 15, c: 14, dir: "up", prog: 0, state: "house", home: [29, 26] },
        { n: "CLYDE", col: CLYDE, r: 15, c: 15, dir: "up", prog: 0, state: "house", home: [29, 1] },
      ],
      mode: "scatter", modeIdx: 0, modeT: 0, fright: 0, chain: 0,
      phase: "ready", phaseT: 4.5, want: null, wantAt: 0, deathT: 0, flashT: 0,
    };
  }

  passable(r, c, ghost) {
    if (r < 0 || r >= ROWS) return false;
    const ch = MAZE[r][(c + COLS) % COLS];
    if (ch === "#") return false;
    if (!ghost && (ch === "-" || ch === "H")) return false;
    return true;
  }
  ahead(r, c, dir) { const d = DIRS[dir]; return [r + d[0], (c + d[1] + COLS) % COLS]; }

  movePac(dt) {
    const g = this.g, p = g.pac;
    p.prog += dt * 8;
    if (p.prog < 1) return;
    p.prog -= 1;
    if (g.want && g.t - g.wantAt < 0.25) { const [r, c] = this.ahead(p.r, p.c, g.want); if (this.passable(r, c, false)) { p.dir = g.want; g.want = null; } }
    const [nr, nc] = this.ahead(p.r, p.c, p.dir);
    if (!this.passable(nr, nc, false)) { p.prog = 0; return; }
    p.r = nr; p.c = nc;
    const ch = g.food[p.r][p.c];
    if (ch === "." ) { g.food[p.r][p.c] = " "; g.dots--; g.score += 10; }
    else if (ch === "o") { g.food[p.r][p.c] = " "; g.dots--; g.score += 50; g.fright = Math.max(1, 7 - g.level); g.chain = 0; for (const gh of g.ghosts) if (gh.state === "out") gh.dir = OPP[gh.dir]; }
  }

  target(gh) {
    const g = this.g, p = g.pac;
    if (gh.state === "eyes") return [14, 13];
    if (gh.state === "house") return [12, 13];
    if (g.fright > 0) return [Math.floor(Math.random() * ROWS), Math.floor(Math.random() * COLS)];
    if (g.mode === "scatter") return gh.home;
    if (gh.n === "BLINKY") return [p.r, p.c];
    if (gh.n === "PINKY") { const d = DIRS[p.dir]; return [p.r + d[0] * 4, p.c + d[1] * 4]; }
    if (gh.n === "INKY") { const b = g.ghosts[0]; const d = DIRS[p.dir]; return [2 * (p.r + d[0] * 2) - b.r, 2 * (p.c + d[1] * 2) - b.c]; }
    const dist = Math.hypot(p.r - gh.r, p.c - gh.c);
    return dist > 8 ? [p.r, p.c] : gh.home;
  }

  moveGhost(gh, dt) {
    const g = this.g;
    const speed = gh.state === "eyes" ? 14 : g.fright > 0 ? 5 : 7.5;
    gh.prog += dt * speed;
    if (gh.prog < 1) return;
    gh.prog -= 1;
    if (gh.state === "house" && g.t > 2 + g.ghosts.indexOf(gh) * 2.5) gh.state = "leaving";
    if (gh.state === "leaving") { if (gh.r > 12) { gh.r -= gh.c === 13 ? 1 : 0; gh.c += gh.c < 13 ? 1 : gh.c > 13 ? -1 : 0; } else gh.state = "out"; return; }
    if (gh.state === "eyes" && gh.r === 14 && gh.c === 13) { gh.state = "out"; return; }
    const [tr, tc] = this.target(gh);
    let best = null, bestD = Infinity;
    for (const d of ["up", "left", "down", "right"]) {
      if (d === OPP[gh.dir] && gh.state !== "eyes") continue;
      const [nr, nc] = this.ahead(gh.r, gh.c, d);
      if (!this.passable(nr, nc, true)) continue;
      const dd = (nr - tr) ** 2 + (nc - tc) ** 2;
      if (dd < bestD) { bestD = dd; best = [d, nr, nc]; }
    }
    if (!best) { gh.dir = OPP[gh.dir]; return; }
    gh.dir = best[0]; gh.r = best[1]; gh.c = best[2];
  }

  collide() {
    const g = this.g, p = g.pac;
    for (const gh of g.ghosts) {
      if (gh.state === "eyes" || gh.r !== p.r || gh.c !== p.c) continue;
      if (g.fright > 0) { g.chain++; g.score += 200 * 2 ** (g.chain - 1); gh.state = "eyes"; }
      else { g.phase = "death"; g.phaseT = 2.4; g.deathT = 0; return; }
    }
  }

  respawn() {
    const g = this.g;
    g.pac = { r: 22, c: 14, dir: "left", prog: 0 };
    g.ghosts.forEach((gh, i) => { gh.r = i === 0 ? 12 : 15; gh.c = [13, 12, 14, 15][i]; gh.dir = i === 0 ? "left" : "up"; gh.state = i === 0 ? "out" : "house"; gh.prog = 0; });
    g.fright = 0; g.mode = "scatter"; g.modeIdx = 0; g.modeT = 0; g.t = 0;
    g.phase = "ready"; g.phaseT = 2;
  }
  nextLevel() { const keep = { score: this.g.score, lives: this.g.lives, level: this.g.level, high: this.g.high }; this.reset(); Object.assign(this.g, keep); this.g.phaseT = 2; }

  step(dt) {
    const g = this.g;
    g.t += dt;
    if (g.phase !== "play") {
      g.phaseT -= dt;
      if (g.phase === "death") g.deathT += dt;
      if (g.phase === "cleared") g.flashT += dt;
      if (g.phaseT <= 0) {
        if (g.phase === "ready") g.phase = "play";
        else if (g.phase === "death") { g.lives -= 1; if (g.lives < 0) { g.phase = "over"; g.phaseT = 1e9; } else this.respawn(); }
        else if (g.phase === "cleared") { g.level += 1; this.nextLevel(); }
      }
      return;
    }
    if (g.fright > 0) { g.fright -= dt; if (g.fright <= 0) g.chain = 0; }
    else { g.modeT += dt; const plan = MODE_PLAN[Math.min(g.modeIdx, MODE_PLAN.length - 1)]; if (g.modeT >= plan[0]) { g.modeT = 0; g.modeIdx++; g.mode = MODE_PLAN[Math.min(g.modeIdx, MODE_PLAN.length - 1)][1]; for (const gh of g.ghosts) if (gh.state === "out") gh.dir = OPP[gh.dir]; } }

    this.movePac(dt);
    for (const gh of g.ghosts) this.moveGhost(gh, dt);
    this.collide();
    if (g.dots === 0) { g.phase = "cleared"; g.phaseT = 2.4; g.flashT = 0; }
  }

  // ---------- canvas rendering ----------
  draw(ctx) {
    const g = this.g, W = COLS * CELL, H = ROWS * CELL;
    ctx.fillStyle = "#000000";
    ctx.fillRect(0, 0, W, H);
    const tick = g.t;

    // HUD top
    ctx.font = "500 11px 'JetBrains Mono', monospace";
    ctx.textBaseline = "top";
    ctx.fillStyle = DIM; ctx.textAlign = "left";
    ctx.fillText("1UP", 6, 6);
    ctx.fillText("HIGH SCORE", 6, 22);
    ctx.fillStyle = FLASH;
    ctx.fillText(pad(g.score, 6), 6, 20);
    ctx.fillStyle = DIM; ctx.fillText(pad(g.high, 6), 6, 36);
    ctx.fillStyle = FLASH;
    ctx.fillText(pad(g.level, 2), 6, 52);

    // maze
    const mazeFlash = g.phase === "cleared" && Math.floor(g.flashT * 6) % 2 === 1;
    const wallCol = mazeFlash ? FLASH : WALL;
    ctx.fillStyle = wallCol;
    for (let r = 0; r < ROWS; r++) {
      for (let c = 0; c < COLS; c++) {
        const t = MAZE[r][c], f = g.food[r][c];
        if (t === "#") {
          const gl = WALLG[r][c];
          if (gl === " " || gl === "─" || gl === "│") this.fillRectRect(ctx, c * CELL, r * CELL, CELL, CELL, wallCol);
          else drawCorner(ctx, gl, c * CELL, r * CELL, CELL, wallCol);
        } else if (t === "-") { this.fillRectRect(ctx, c * CELL, r * CELL, CELL, CELL, GATE); }
        else if (f === ".") { this.drawPellet(ctx, c * CELL + CELL / 2, r * CELL + CELL / 2, DOT, 2); }
        else if (f === "o" && Math.floor(tick * 5) % 2 === 0) { this.drawPellet(ctx, c * CELL + CELL / 2, r * CELL + CELL / 2, DOT, 4); }
      }
    }

    // ghosts
    if (g.phase !== "death") {
      for (const gh of g.ghosts) {
        if (gh.state === "eyes") { ctx.fillStyle = FLASH; this.drawGhostBody(ctx, gh.c * CELL, gh.r * CELL, CELL, FLASH, true); }
        else {
          let col = gh.col;
          if (g.fright > 0) col = (g.fright < 2 && Math.floor(tick * 8) % 2 === 0) ? FLASH : AFRAID;
          this.drawGhostBody(ctx, gh.c * CELL, gh.r * CELL, CELL, col, false);
        }
      }
    }

    // pac-man
    const p = g.pac;
    if (g.phase === "death") {
      const idx = Math.min(DEATH.length - 1, Math.floor(g.deathT / 0.13));
      ctx.fillStyle = g.deathT > 1.2 ? ALERT : PAC;
      this.drawDeathPac(ctx, p.c * CELL, p.r * CELL, CELL, idx);
    } else {
      this.drawPac(ctx, p.c * CELL, p.r * CELL, CELL, p.dir, Math.floor(tick * 15) % 2);
    }
  }

  fillRectRect(ctx, x, y, w, h, color) { ctx.fillStyle = color; ctx.fillRect(x, y, w, h); }
  drawPellet(ctx, cx, cy, color, r) { ctx.fillStyle = color; ctx.beginPath(); ctx.arc(cx, cy, r, 0, Math.PI * 2); ctx.fill(); }

  drawPac(ctx, x, y, cell, dir, frame) {
    const cx = x + cell / 2, cy = y + cell / 2, rad = cell * 0.42;
    const angles = { right: 0, down: Math.PI / 2, left: Math.PI, up: -Math.PI / 2 }[dir];
    const open = frame === 0 ? 0.35 : 0.08; // radians half-width of mouth
    ctx.save();
    ctx.translate(cx, cy);
    ctx.rotate(angles);
    ctx.fillStyle = PAC;
    ctx.beginPath();
    ctx.moveTo(0, 0);
    ctx.arc(0, 0, rad, Math.PI * open, Math.PI * (2 - open));
    ctx.closePath();
    ctx.fill();
    ctx.restore();
  }

  drawDeathPac(ctx, x, y, cell, idx) {
    const cx = x + cell / 2, cy = y + cell / 2, rad = cell * 0.42 * (1 - idx / DEATH.length * 0.5);
    if (idx >= 8) { // star burst
      ctx.fillStyle = idx >= 9 ? "#000000" : "#FF0000";
      ctx.beginPath();
      for (let i = 0; i < 8; i++) {
        const a = (i / 8) * Math.PI * 2;
        ctx.moveTo(cx, cy);
        ctx.lineTo(cx + Math.cos(a) * rad, cy + Math.sin(a) * rad);
      }
      ctx.fill();
      return;
    }
    ctx.fillStyle = PAC;
    ctx.beginPath();
    ctx.moveTo(cx, cy);
    ctx.arc(cx, cy, rad, 0, Math.PI * (1 - idx / 8) * 2);
    ctx.arc(cx, cy, rad * (1 - idx / 8), (Math.PI * (1 - idx / 8) * 2) % (Math.PI * 2), Math.PI * 2);
    ctx.fill();
  }

  drawGhostBody(ctx, x, y, cell, color, eyesOnly) {
    const cx = x + cell / 2, cy = y + cell / 2, rad = cell * 0.44;
    ctx.fillStyle = eyesOnly ? color : color;
    if (eyesOnly) {
      ctx.fillStyle = FLASH;
      ctx.beginPath(); ctx.arc(cx - rad * 0.4, cy - rad * 0.1, rad * 0.35, 0, Math.PI * 2); ctx.fill();
      ctx.beginPath(); ctx.arc(cx + rad * 0.4, cy - rad * 0.1, rad * 0.35, 0, Math.PI * 2); ctx.fill();
      return;
    }
    ctx.beginPath();
    ctx.moveTo(x, y + cell);
    ctx.lineTo(x, cy + rad * 0.3);
    ctx.quadraticCurveTo(cx, cy - rad, cx + rad, cy + rad * 0.3);
    ctx.lineTo(x + cell, y + cell);
    // wavy bottom
    const feet = 4, fw = cell / feet;
    for (let i = feet; i >= 1; i--) {
      const fx = x + i * fw;
      const fy = y + cell - (i % 2 === 0 ? rad * 0.25 : 0);
      ctx.lineTo(fx, fy);
    }
    ctx.closePath();
    ctx.fill();
    // eyes
    const eyeCol = eyesOnly ? FLASH : FLASH;
    ctx.fillStyle = eyeCol;
    ctx.beginPath(); ctx.arc(cx - rad * 0.4, cy - rad * 0.1, rad * 0.28, 0, Math.PI * 2); ctx.fill();
    ctx.beginPath(); ctx.arc(cx + rad * 0.4, cy - rad * 0.1, rad * 0.28, 0, Math.PI * 2); ctx.fill();
    ctx.fillStyle = "#000044";
    ctx.beginPath(); ctx.arc(cx - rad * 0.35, cy - rad * 0.05, rad * 0.14, 0, Math.PI * 2); ctx.fill();
    ctx.beginPath(); ctx.arc(cx + rad * 0.45, cy - rad * 0.05, rad * 0.14, 0, Math.PI * 2); ctx.fill();
  }

  drawCorner(ctx, gl, x, y, cell, color) {
    // approximate unicode wall corners with filled quarter/edge segments
    ctx.fillStyle = color;
    const half = cell / 2, th = cell * 0.18;
    if (gl === "╭") { // top-left corner: fill top and left edges
      ctx.fillRect(x, y + th - cell * 0.02, cell, th);
      ctx.fillRect(x + th - cell * 0.02, y, th, cell);
    } else if (gl === "╮") {
      ctx.fillRect(x, y + th - cell * 0.02, cell, th);
      ctx.fillRect(x + cell - th + cell * 0.02, y, th, cell);
    } else if (gl === "╰") {
      ctx.fillRect(x, y + cell - th + cell * 0.02, cell, th);
      ctx.fillRect(x + th - cell * 0.02, y, th, cell);
    } else if (gl === "╯") {
      ctx.fillRect(x, y + cell - th + cell * 0.02, cell, th);
      ctx.fillRect(x + cell - th + cell * 0.02, y, th, cell);
    }
  }
}

const DEATH = ["ᗧ", "●", "◓", "◒", "○", "○", "◌", "◌", "✳", "·", " "];

// ---------- app glue ----------
const game = new Game();
const canvas = document.getElementById("game");
const ctx = canvas.getContext("2d");
const hud = document.getElementById("hud");
const overlay = document.getElementById("overlay");

let running = false;
let last = performance.now();

function setCanvasSize() {
  const W = COLS * CELL, H = ROWS * CELL;
  const maxW = window.innerWidth - 40, maxH = window.innerHeight - 140;
  const scale = Math.min(1, maxW / W, maxH / H);
  canvas.width = W; canvas.height = H;
  canvas.style.width = Math.floor(W * scale) + "px";
  canvas.style.height = Math.floor(H * scale) + "px";
}

function tickLoop() {
  const now = performance.now();
  const dt = Math.min((now - last) / 1000, 0.1);
  last = now;
  if (running) {
    const step = 1 / 120;
    for (let acc = dt; acc > 0; acc -= step) game.step(Math.min(step, acc));
  }
  game.draw(ctx);
  updateHUD();
  requestAnimationFrame(tickLoop);
}

function updateHUD() {
  const g = game.g;
  hud.innerHTML =
    '<div class="stat"><span class="lbl">1UP</span> ' + g.score + '</div>' +
    '<div class="stat"><span class="lbl">HIGH</span> ' + g.high + '</div>' +
    '<div class="stat"><span class="lbl">LVL</span> ' + pad(g.level, 2) + '</div>' +
    '<div class="stat"><span class="lbl">SCORE</span> ' + g.score + '</div>' +
    '<div class="stat"><span class="lbl">LIVES</span> ' + Math.max(0, g.lives) + '</div>';
}

function showOverlay(title, sub) {
  overlay.innerHTML = '<h1 class="title">' + title + '</h1>' + (sub ? '<p class="sub">' + sub + '</p>' : '') + '<p class="start">Press SPACE to ' + (g_startText(title) || 'start') + '</p>';
}
function g_startText(title) {
  return title === "GAME OVER" ? "restart" : "start";
}

function startGame() {
  if (game.g.phase === "over") game.reset();
  running = true;
  overlay.classList.add("hidden");
}

function togglePause() {
  if (game.g.phase === "play" && running) {
    running = false;
    showOverlay("PAUSED", "");
  } else if (!running) {
    running = true;
    overlay.classList.add("hidden");
  }
}

document.addEventListener("keydown", (e) => {
  const k = e.key.toLowerCase();
  const map = { arrowup: "up", w: "up", arrowdown: "down", s: "down", arrowleft: "left", a: "left", arrowright: "right", d: "right" };
  if (map[k]) { const g = game.g; g.want = map[k]; g.wantAt = g.t; e.preventDefault(); }
  else if (k === " ") { if (running) togglePause(); else startGame(); e.preventDefault(); }
  else if (k === "p") togglePause();
  else if (k === "r") { game.reset(); running = true; overlay.classList.add("hidden"); }
});

setCanvasSize();
window.addEventListener("resize", setCanvasSize);
if (game.g.phase === "ready") showOverlay("PAC·ZIG", "native 31x28 maze, arrow keys / WASD");
requestAnimationFrame(tickLoop);
