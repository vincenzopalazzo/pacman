(function () {
  "use strict";

  // ---- Source of truth: copied byte-for-byte from the prototype ----
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

  const PAL = {
    bg: "#000000", wall: "#3B4CFF", gate: "#FFB8FF", dot: "#FFB8AE", pac: "#FFFF00",
    blinky: "#FF0000", pinky: "#FFB8FF", inky: "#00FFFF", clyde: "#FFB852",
    afraid: "#3B4CFF", flash: "#FFFFFF", hud: "#FFFFFF", dim: "#9EA4B8",
    alert: "#FF0000", ok: "#4CFF4C", faint: "#4A5068",
  };

  const GHOSTS = [
    { n: "BLINKY", col: PAL.blinky, r: 12, c: 13 },
    { n: "PINKY", col: PAL.pinky, r: 15, c: 12 },
    { n: "INKY", col: PAL.inky, r: 15, c: 14 },
    { n: "CLYDE", col: PAL.clyde, r: 15, c: 15 },
  ];

  // ---- wall glyph resolution (run once) ----
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
        const N = !isWall(r - 1, c), S = !isWall(r + 1, c),
              E = !isWall(r, c + 1), W = !isWall(r, c - 1);
        row.push(N && W ? "╭" : N && E ? "╮" : S && W ? "╰" : S && E ? "╯"
          : (N || S) ? "─" : (E || W) ? "│" : " ");
      }
      g.push(row);
    }
    return g;
  }
  const WALLG = resolveWalls();

  // ---- element references ----
  const canvas = document.getElementById("maze");
  const dotsOut = document.getElementById("dots");
  const totalOut = document.getElementById("total");
  const livesOut = document.getElementById("lives");
  const scoreOut = document.getElementById("score");
  const levelOut = document.getElementById("level");
  const highOut = document.getElementById("high");
  const modeOut = document.getElementById("mode");
  const statusOut = document.getElementById("status");

  const pacStart = document.getElementById("pacStart");
  const ghostStart = document.getElementById("ghostStart");
  const readyStart = document.getElementById("readyStart");

  // ---- state ----
  let cell = 12;
  let mode = "standard";
  let speed = "normal";
  let running = true;
  let pelletOn = false;
  let frame = 0;
  let score = 0, lives = 2, level = 1, high = 42995;

  const food = MAZE.map(r => r.split(""));
  let totalDots = 0;
  let dotsFilled = 0;
  for (const row of food) for (const ch of row) if (ch === "." || ch === "o") totalDots++;

  const pac = { r: 22, c: 14, dir: "left", prog: 0 };

  const ghosts = GHOSTS.map(g => ({ ...g, prog: 0, state: "out", fright: 0 }));

  const keymap = {
    arrowup: "up", w: "up", arrowdown: "down", s: "down",
    arrowleft: "left", a: "left", arrowright: "right", d: "right",
  };

  // ---- layout / cell sizing ----
  function calcCell() {
    const vw = window.innerWidth - 64;
    const vh = window.innerHeight - 360;
    const byCol = Math.floor(vw / (COLS * 2));
    const byRow = Math.floor(vh / (ROWS + 4));
    cell = Math.max(8, Math.min(byCol, byRow, 16));
    if (mode === "wide") cell = Math.min(cell, 10);
    canvas.width = COLS * cell;
    canvas.height = ROWS * cell;
  }

  // ---- drawing ----
  function draw() {
    const ctx = canvas.getContext("2d");
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    ctx.fillStyle = PAL.bg;
    ctx.fillRect(0, 0, canvas.width, canvas.height);

    // maze tiles
    for (let r = 0; r < ROWS; r++) {
      for (let c = 0; c < COLS; c++) {
        const x = c * cell, y = r * cell;
        const t = MAZE[r][c];
        if (t === "#") {
          ctx.fillStyle = PAL.wall;
          ctx.font = (cell - 2) + "px monospace";
          ctx.textAlign = "center";
          ctx.textBaseline = "middle";
          ctx.fillText(WALLG[r][c], x + cell / 2, y + cell / 2 + 1);
        } else if (t === "-") {
          ctx.fillStyle = PAL.gate;
          ctx.fillRect(x + 1, y + cell * 0.5 - 1, cell - 2, 2);
        } else if (t === "h" || t === "H") {
          if (cell > 11) { ctx.fillStyle = "#0A0A1A"; ctx.fillRect(x, y, cell, cell); }
        } else {
          const f = food[r][c];
          if (f === ".") {
            ctx.fillStyle = PAL.dot;
            ctx.beginPath();
            ctx.arc(x + cell / 2, y + cell / 2, Math.max(1, cell * 0.09), 0, Math.PI * 2);
            ctx.fill();
          } else if (f === "o" && pelletOn) {
            ctx.fillStyle = PAL.dot;
            ctx.beginPath();
            ctx.arc(x + cell / 2, y + cell / 2, Math.max(1, cell * 0.22), 0, Math.PI * 2);
            ctx.fill();
          }
        }
      }
    }

    // ghosts
    for (const g of ghosts) drawGhost(ctx, g);

    // Pac-Man
    drawPac(ctx);
  }

  function drawGhost(ctx, g) {
    const x = g.c * cell, y = g.r * cell;
    const col = (g.fright > 0)
      ? (g.fright < 2 && Math.floor(frame * 8) % 2 === 0) ? PAL.flash : PAL.afraid
      : g.col;
    ctx.fillStyle = (g.fright === 0 && g.state === "eyes") ? PAL.flash : col;
    ctx.beginPath();
    ctx.arc(x + cell / 2, y + cell * 0.4, cell * 0.4, Math.PI, 0);
    ctx.lineTo(x + cell * 0.9, y + cell * 0.85);
    ctx.lineTo(x + cell * 0.5, y + cell);
    ctx.lineTo(x + cell * 0.1, y + cell * 0.85);
    ctx.closePath();
    ctx.fill();

    ctx.fillStyle = "#FFFFFF";
    const ex = x + cell / 2, ey = y + cell * 0.42;
    ctx.beginPath(); ctx.arc(ex - cell * 0.14, ey, cell * 0.09, 0, Math.PI * 2); ctx.fill();
    ctx.beginPath(); ctx.arc(ex + cell * 0.14, ey, cell * 0.09, 0, Math.PI * 2); ctx.fill();
    ctx.fillStyle = "#1A1A4D";
    ctx.beginPath(); ctx.arc(ex - cell * 0.14 + 0.5, ey, cell * 0.04, 0, Math.PI * 2); ctx.fill();
    ctx.beginPath(); ctx.arc(ex + cell * 0.14 + 0.5, ey, cell * 0.04, 0, Math.PI * 2); ctx.fill();
  }

  function drawPac(ctx) {
    const x = pac.c * cell, y = pac.r * cell;
    const cx = x + cell / 2, cy = y + cell / 2, rad = cell * 0.42;
    ctx.fillStyle = PAL.pac;
    ctx.beginPath();
    const open = 0.22 + Math.sin(frame * 0.5) * 0.12;
    let base = 0;
    if (pac.dir === "right") base = 0;
    else if (pac.dir === "left") base = Math.PI;
    else if (pac.dir === "up") base = -Math.PI / 2;
    else if (pac.dir === "down") base = Math.PI / 2;
    ctx.arc(cx, cy, rad, base + open, base + Math.PI - open);
    ctx.lineTo(cx, cy);
    ctx.closePath();
    ctx.fill();
  }

  // ---- HUD ----
  function pad(n, w) { return String(n).padStart(w, "0"); }

  function renderHUD() {
    scoreOut.textContent = pad(score, 6);
    highOut.textContent = pad(high, 6);
    levelOut.textContent = pad(level, 2);
    dotsOut.textContent = dotsFilled;
    totalOut.textContent = totalDots;
    modeOut.textContent = mode.toUpperCase();
    livesOut.textContent = "ᗧ".repeat(Math.max(0, lives));
    statusOut.textContent = running ? "RUNNING" : "PAUSED";
  }

  // ---- movement ----
  function atCenter(p) { return p.prog >= 1; }

  function tryMove(p, dir) {
    const d = { up: [-1, 0], down: [1, 0], left: [0, -1], right: [0, 1] };
    const [dr, dc] = d[dir];
    const nr = p.r + dr, nc = p.c + dc;
    if (nr < 0 || nr >= ROWS || nc < 0 || nc >= COLS) return false;
    const t = MAZE[nr][nc];
    if (t === "#" || t === "-" || t === "h" || t === "H") return false;
    p.r = nr; p.c = nc; p.dir = dir; p.prog = 0;
    return true;
  }

  let want = null;
  window.addEventListener("keydown", (e) => {
    const k = e.key.toLowerCase();
    if (keymap[k]) {
      if (atCenter(pac) && tryMove(pac, keymap[k])) want = null;
      else want = keymap[k];
      e.preventDefault();
    } else if (k === "p") { running = !running; }
    else if (k === "r") resetGame();
  });

  function speedMult() {
    return speed === "slow" ? 0.6 : speed === "fast" ? 1.5 : 1;
  }

  function resetGhosts() {
    ghosts[0].r = 12; ghosts[0].c = 13;
    ghosts[1].r = 15; ghosts[1].c = 12;
    ghosts[2].r = 15; ghosts[2].c = 14;
    ghosts[3].r = 15; ghosts[3].c = 15;
  }

  function resetGame() {
    for (const row of food) for (const ch of row) if (ch === "." || ch === "o") { /* keep */ }
    score = 0; lives = 2; level = 1; dotsFilled = 0;
    pac.r = 22; pac.c = 14; pac.dir = "left"; pac.prog = 0;
    resetGhosts();
  }

  function step() {
    if (want) {
      if (atCenter(pac)) {
        if (!tryMove(pac, want)) want = null;
      }
    }
    if (!atCenter(pac)) {
      pac.prog += 0.08 * speedMult();
      if (pac.prog >= 1) { pac.prog = 0; }
    }

    const f = food[pac.r][pac.c];
    if (f === ".") { food[pac.r][pac.c] = " "; score += 10; dotsFilled++; }
    else if (f === "o") { food[pac.r][pac.c] = " "; score += 50; dotsFilled++; }

    if (dotsFilled >= totalDots) { level++; score += 1000; }
    if (score > high) high = score;

    for (const g of ghosts) {
      if (!atCenter(g)) {
        g.prog += 0.04 * speedMult();
      } else {
        g.prog = 0;
        const dirs = ["up", "down", "left", "right"];
        let best = null, bestD = 1e9;
        for (const d of dirs) {
          const dd = { up: [-1,0], down:[1,0], left:[0,-1], right:[0,1] }[d];
          const nr = g.r + dd[0], nc = g.c + dd[1];
          if (nr < 0 || nr >= ROWS || nc < 0 || nc >= COLS) continue;
          const t = MAZE[nr][nc];
          if (t === "#" || t === "-" || t === "h" || t === "H") continue;
          const dist = Math.abs(nr - pac.r) + Math.abs(nc - pac.c);
          if (dist < bestD) { bestD = dist; best = d; }
        }
        if (best === "up") g.r -= 1;
        else if (best === "down") g.r += 1;
        else if (best === "left") g.c -= 1;
        else if (best === "right") g.c += 1;
      }
    }

    for (const g of ghosts) {
      if (Math.abs(g.r - pac.r) + Math.abs(g.c - pac.c) === 0) {
        lives--;
        if (lives < 0) { }
        else { pac.r = 22; pac.c = 14; pac.dir = "left"; resetGhosts(); }
      }
    }
  }

  // ---- palette swatches ----
  function buildPalette() {
    const grid = document.getElementById("paletteGrid");
    if (!grid) return;
    Object.entries(PAL).forEach(([name, hex]) => {
      const sw = document.createElement("div");
      sw.className = "palette-item";
      sw.innerHTML =
        '<div class="palette-swatch" style="background:' + hex + '"></div>' +
        '<div class="palette-name">' + name + '</div>' +
        '<div class="palette-hex">' + hex.toUpperCase() + '</div>';
      grid.appendChild(sw);
    });
  }

  // ---- control toggles ----
  function bindToggles() {
    document.querySelectorAll('[data-layout]').forEach(btn => {
      btn.addEventListener("click", () => {
        mode = btn.dataset.layout;
        document.querySelectorAll('[data-layout]').forEach(b => b.classList.toggle("active", b === btn));
        calcCell();
      });
    });
    document.querySelectorAll('[data-speed]').forEach(btn => {
      btn.addEventListener("click", () => {
        speed = btn.dataset.speed;
        document.querySelectorAll('[data-speed]').forEach(b => b.classList.toggle("active", b === btn));
      });
    });
    const pauseBtn = document.getElementById("pauseBtn");
    if (pauseBtn) pauseBtn.addEventListener("click", () => { running = !running; });
    const restartBtn = document.getElementById("restartBtn");
    if (restartBtn) restartBtn.addEventListener("click", () => { resetGame(); });
  }

  // ---- init ----
  function init() {
    calcCell();
    window.addEventListener("resize", calcCell);
    buildPalette();
    bindToggles();

    pacStart.textContent = "← → ↑ ↓  move   P  pause   R  restart";
    ghostStart.textContent = "Eat all dots. Avoid the ghosts.";
    readyStart.textContent = "READY!";

    loop();
  }

  function loop() {
    frame++;
    pelletOn = Math.floor(frame / 15) % 2 === 0;
    if (running) step();
    draw();
    renderHUD();
    requestAnimationFrame(loop);
  }

  init();
})();
