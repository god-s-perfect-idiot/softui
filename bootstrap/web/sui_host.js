/** Host-side suigui bridge — paints .sui into SoftUI's RGBA framebuffer. */

import { parseSafe } from "./sdk/lang/parser.js";
import {
  createAppRuntime,
  layoutTree,
  paintTree,
  hitTest,
  clearHover,
} from "./sdk/runtime/widgets.js";

let runtime = null;
let sourceKey = "";
let canvas = null;
let ctx = null;

export function suiPaint(memory, srcPtr, srcLen, fbPtr, w, h, stride, ev, x, y) {
  const bytes = new Uint8Array(memory.buffer, srcPtr, srcLen);
  const src = new TextDecoder().decode(bytes);
  if (src !== sourceKey || !runtime) {
    const parsed = parseSafe(src);
    if (!parsed.ok) return -2;
    runtime = createAppRuntime(parsed.ast);
    sourceKey = src;
    canvas = new OffscreenCanvas(w, h);
    ctx = canvas.getContext("2d", { alpha: false });
  }

  if (canvas.width !== w || canvas.height !== h) {
    canvas = new OffscreenCanvas(w, h);
    ctx = canvas.getContext("2d", { alpha: false });
  }

  layoutTree(runtime.roots, w, h);

  if (ev === 1) {
    clearHover(runtime.roots);
    const hit = hitTest(runtime.roots, x, y);
    if (hit) hit.hover = true;
  } else if (ev === 2) {
    const hit = hitTest(runtime.roots, x, y);
    if (hit) {
      try {
        runtime.fire(hit, "click");
      } catch (_) {
        /* ignore handler errors in host bridge */
      }
    }
  }

  paintTree(ctx, runtime.roots, w, h);
  const img = ctx.getImageData(0, 0, w, h);
  const dst = new Uint8Array(memory.buffer, fbPtr, stride * h);
  // ImageData is tightly packed RGBA; SoftUI stride may equal w*4.
  if (stride === w * 4) {
    dst.set(img.data);
  } else {
    for (let row = 0; row < h; row++) {
      dst.set(
        img.data.subarray(row * w * 4, (row + 1) * w * 4),
        row * stride,
      );
    }
  }
  return 0;
}

export function suiReset() {
  runtime = null;
  sourceKey = "";
  canvas = null;
  ctx = null;
}
