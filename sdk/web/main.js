import { parseSafe } from "../lang/parser.js";
import {
  createAppRuntime,
  layoutTree,
  paintTree,
  hitTest,
  clearHover,
} from "../runtime/widgets.js";

const sourceEl = document.getElementById("source");
const statusEl = document.getElementById("status");
const exampleEl = document.getElementById("example");
const reloadBtn = document.getElementById("reload");
const canvas = document.getElementById("view");
const ctx = canvas.getContext("2d", { alpha: false });

/** Layout / hit-test size in CSS pixels (backing store is × devicePixelRatio). */
let viewW = 360;
let viewH = 480;

let runtime = null;
let raf = 0;

function setStatus(msg, isError = false) {
  statusEl.textContent = msg;
  statusEl.classList.toggle("error", isError);
}

/**
 * Match canvas buffer to CSS box × scale.
 * Use at least 2× so rounded corners and glyphs get real AA even when DPR is 1
 * (browser then downscales the sharper buffer into the CSS box).
 */
function syncCanvas() {
  const rect = canvas.getBoundingClientRect();
  const dpr = Math.max(1, window.devicePixelRatio || 1);
  const scale = Math.max(2, dpr);
  const cssW = Math.max(1, Math.round(rect.width || canvas.clientWidth || 360));
  const cssH = Math.max(1, Math.round(rect.height || canvas.clientHeight || 480));
  const bw = Math.max(1, Math.round(cssW * scale));
  const bh = Math.max(1, Math.round(cssH * scale));
  if (canvas.width !== bw || canvas.height !== bh) {
    canvas.width = bw;
    canvas.height = bh;
  }
  ctx.setTransform(scale, 0, 0, scale, 0, 0);
  ctx.imageSmoothingEnabled = true;
  ctx.imageSmoothingQuality = "high";
  viewW = cssW;
  viewH = cssH;
  return { w: cssW, h: cssH };
}

async function loadExample(name) {
  const res = await fetch(`../examples/${name}`);
  if (!res.ok) throw new Error(`Failed to load ${name}`);
  sourceEl.value = await res.text();
}

function compileAndRun() {
  const src = sourceEl.value;
  const result = parseSafe(src);
  if (!result.ok) {
    runtime = null;
    setStatus(result.error, true);
    paintEmpty();
    return;
  }
  try {
    runtime = createAppRuntime(result.ast);
    document.title = `${runtime.appName} — suigui`;
    setStatus(`OK — ${runtime.appName} (${result.ast.roots.length} root node(s))`);
    frame();
  } catch (e) {
    runtime = null;
    setStatus(e.message || String(e), true);
    paintEmpty();
  }
}

function paintEmpty() {
  syncCanvas();
  ctx.fillStyle = "#0b0e12";
  ctx.fillRect(0, 0, viewW, viewH);
}

function frame() {
  if (!runtime) return;
  syncCanvas();
  layoutTree(runtime.roots, viewW, viewH);
  paintTree(ctx, runtime.roots, viewW, viewH);
}

function pointerPos(ev) {
  const rect = canvas.getBoundingClientRect();
  if (rect.width <= 0 || rect.height <= 0) return { x: 0, y: 0 };
  const x = ((ev.clientX - rect.left) / rect.width) * viewW;
  const y = ((ev.clientY - rect.top) / rect.height) * viewH;
  return { x, y };
}

canvas.addEventListener("pointermove", (ev) => {
  if (!runtime) return;
  const { x, y } = pointerPos(ev);
  clearHover(runtime.roots);
  const hit = hitTest(runtime.roots, x, y);
  if (hit) hit.hover = true;
  frame();
});

canvas.addEventListener("pointerleave", () => {
  if (!runtime) return;
  clearHover(runtime.roots);
  frame();
});

canvas.addEventListener("pointerdown", (ev) => {
  if (!runtime) return;
  const { x, y } = pointerPos(ev);
  const hit = hitTest(runtime.roots, x, y);
  if (!hit) return;
  try {
    if (runtime.fire(hit, "click")) {
      setStatus(`click → #${hit.attrs.id || hit.tag}`);
      frame();
    }
  } catch (e) {
    setStatus(e.message || String(e), true);
  }
});

reloadBtn.addEventListener("click", compileAndRun);
sourceEl.addEventListener("keydown", (ev) => {
  if ((ev.ctrlKey || ev.metaKey) && ev.key === "Enter") {
    ev.preventDefault();
    compileAndRun();
  }
});

exampleEl.addEventListener("change", async () => {
  try {
    await loadExample(exampleEl.value);
    compileAndRun();
  } catch (e) {
    setStatus(e.message || String(e), true);
  }
});

if (typeof ResizeObserver !== "undefined") {
  new ResizeObserver(() => {
    if (runtime) frame();
    else paintEmpty();
  }).observe(canvas);
} else {
  window.addEventListener("resize", () => {
    if (runtime) frame();
    else paintEmpty();
  });
}

(async function boot() {
  try {
    await loadExample(exampleEl.value);
    compileAndRun();
  } catch (e) {
    setStatus(e.message || String(e), true);
  }
  const loop = () => {
    if (runtime) frame();
    raf = requestAnimationFrame(loop);
  };
  raf = requestAnimationFrame(loop);
})();
