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
const ctx = canvas.getContext("2d");

let runtime = null;
let raf = 0;

function setStatus(msg, isError = false) {
  statusEl.textContent = msg;
  statusEl.classList.toggle("error", isError);
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
  ctx.fillStyle = "#0b0e12";
  ctx.fillRect(0, 0, canvas.width, canvas.height);
}

function frame() {
  if (!runtime) return;
  layoutTree(runtime.roots, canvas.width, canvas.height);
  paintTree(ctx, runtime.roots, canvas.width, canvas.height);
}

function pointerPos(ev) {
  const rect = canvas.getBoundingClientRect();
  const x = ((ev.clientX - rect.left) / rect.width) * canvas.width;
  const y = ((ev.clientY - rect.top) / rect.height) * canvas.height;
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
