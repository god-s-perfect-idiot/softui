const canvas = document.getElementById("fb");
const ctx = canvas.getContext("2d", { alpha: false });

const MAX_WIDTH = 1920;
const MAX_HEIGHT = 1080;
const STORAGE_KEY = "softui.sofs";
/** Bump when factory init.sofs gains/renames demo assets so stale localStorage is replaced. */
const FACTORY_REV = "2026-11-09-wallpaper-jpg";
const FACTORY_REV_KEY = "softui.sofs.rev";

function nowNs() {
  return BigInt(Math.floor(performance.now() * 1e6));
}

/** @type {AudioContext | null} */
let audioCtx = null;
/** @type {Map<string, any>} */
const imageCache = new Map();

function decodeUtf8(memory, ptr, len) {
  const bytes = new Uint8Array(memory.buffer, ptr, len);
  return new TextDecoder().decode(bytes);
}

/** Best-effort MIME so host decode accepts SVG/PNG/JPEG. */
function sniffImageMime(bytes) {
  if (bytes.length >= 8 && bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4e && bytes[3] === 0x47) {
    return "image/png";
  }
  if (bytes.length >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) {
    return "image/jpeg";
  }
  let i = 0;
  while (i < bytes.length && (bytes[i] === 0x20 || bytes[i] === 0x09 || bytes[i] === 0x0a || bytes[i] === 0x0d)) i++;
  if (i + 4 <= bytes.length && bytes[i] === 0x3c) {
    // '<' — XML/SVG
    const head = new TextDecoder().decode(bytes.subarray(i, Math.min(bytes.length, i + 256))).toLowerCase();
    if (head.includes("<svg") || head.startsWith("<?xml")) return "image/svg+xml";
  }
  return "application/octet-stream";
}

function bytesToBase64(bytes) {
  let bin = "";
  const chunk = 0x8000;
  for (let i = 0; i < bytes.length; i += chunk) {
    bin += String.fromCharCode(...bytes.subarray(i, i + chunk));
  }
  return btoa(bin);
}

function base64ToBytes(b64) {
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

function loadPersistedDisk() {
  try {
    if (localStorage.getItem(FACTORY_REV_KEY) !== FACTORY_REV) {
      localStorage.removeItem(STORAGE_KEY);
      localStorage.setItem(FACTORY_REV_KEY, FACTORY_REV);
      return null;
    }
    const b64 = localStorage.getItem(STORAGE_KEY);
    if (!b64) return null;
    const bytes = base64ToBytes(b64);
    if (bytes.length < 8) return null;
    if (
      bytes[0] !== 0x53 ||
      bytes[1] !== 0x4f ||
      bytes[2] !== 0x46 ||
      bytes[3] !== 0x53
    ) {
      return null;
    }
    return bytes;
  } catch (err) {
    console.warn("[softui] persisted disk load failed", err);
    return null;
  }
}

function savePersistedDisk(memory, ptr, len) {
  try {
    const bytes = new Uint8Array(memory.buffer, ptr, len);
    localStorage.setItem(STORAGE_KEY, bytesToBase64(bytes));
  } catch (err) {
    console.warn("[softui] persisted disk save failed", err);
  }
}

function mapKey(e) {
  if (e.key.length === 1) return e.key.charCodeAt(0);
  switch (e.key) {
    case "Enter":
      return 13;
    case "Backspace":
      return 8;
    case "Tab":
      return 9;
    case "Escape":
      return 27;
    case "ArrowLeft":
      return 0x100;
    case "ArrowRight":
      return 0x101;
    case "ArrowUp":
      return 0x102;
    case "ArrowDown":
      return 0x103;
    case "Home":
      return 0x104;
    case "End":
      return 0x105;
    case "Delete":
      return 0x106;
    default:
      return 0;
  }
}

function modsOf(e) {
  let m = 0;
  if (e.shiftKey) m |= 1;
  if (e.ctrlKey) m |= 2;
  if (e.altKey) m |= 4;
  if (e.metaKey) m |= 8;
  return m;
}

/** SoftUI FB pixels from CSS viewport box × devicePixelRatio, clamped. */
function viewportPixels() {
  const dpr = window.devicePixelRatio || 1;
  const cw = canvas.clientWidth || window.innerWidth || 800;
  const ch = canvas.clientHeight || window.innerHeight || 500;
  // Cap DPR scale so Debug WASM stays interactive on HiDPI displays.
  const scale = Math.min(dpr, 1.5);
  const w = Math.max(1, Math.min(MAX_WIDTH, Math.floor(cw * scale)));
  const h = Math.max(1, Math.min(MAX_HEIGHT, Math.floor(ch * scale)));
  return { w, h };
}

function ensureAudio() {
  if (!audioCtx) {
    const AC = window.AudioContext || window.webkitAudioContext;
    if (!AC) return null;
    audioCtx = new AC();
  }
  if (audioCtx.state === "suspended") audioCtx.resume().catch(() => {});
  return audioCtx;
}

/** s16le view of guest memory. Copies when ptr is not 2-byte aligned. */
function pcmS16(buffer, ptr, sampleCount) {
  const byteLen = sampleCount * 2;
  if ((ptr & 1) === 0) return new Int16Array(buffer, ptr, sampleCount);
  const copy = new Uint8Array(byteLen);
  copy.set(new Uint8Array(buffer, ptr, byteLen));
  return new Int16Array(copy.buffer);
}

function imageCacheKey(bytes) {
  let h = bytes.length >>> 0;
  if (bytes.length) {
    h = (h * 33 + bytes[0]) >>> 0;
    h = (h * 33 + bytes[bytes.length >> 1]) >>> 0;
    h = (h * 33 + bytes[bytes.length - 1]) >>> 0;
  }
  return `${bytes.length}:${h}`;
}

async function boot() {
  let instance;
  const imports = {
    env: {
      host_log(ptr, len) {
        try {
          console.log("[softui]", decodeUtf8(instance.exports.memory, ptr, len));
        } catch (err) {
          console.log("[softui] log failed", err);
        }
      },
      host_present() {},
      host_storage_write(ptr, len) {
        savePersistedDisk(instance.exports.memory, ptr, len);
      },
      host_time_wall_ms() {
        return BigInt(Date.now());
      },
      host_time_tz_min() {
        return -new Date().getTimezoneOffset();
      },
      host_audio_queue(ptr, len, sampleRate, channels) {
        const ac = ensureAudio();
        if (!ac || len < 2 || channels < 1) return -1;
        const nSamples = Math.floor(len / 2);
        const frames = Math.floor(nSamples / channels);
        if (frames <= 0) return -1;
        const sampleCount = frames * channels;
        // ABI pointer is a byte address. Int16Array rejects an odd start offset.
        const samples = pcmS16(instance.exports.memory.buffer, ptr, sampleCount);
        const buf = ac.createBuffer(channels, frames, sampleRate || 22050);
        for (let ch = 0; ch < channels; ch++) {
          const data = buf.getChannelData(ch);
          for (let i = 0; i < frames; i++) {
            data[i] = samples[i * channels + ch] / 32768;
          }
        }
        const src = ac.createBufferSource();
        src.buffer = buf;
        src.connect(ac.destination);
        src.start();
        return 0;
      },
      host_audio_stop() {
        if (audioCtx) {
          audioCtx.close().catch(() => {});
          audioCtx = null;
        }
      },
      host_image_decode(srcPtr, srcLen, dstPtr, dstCap, outWPtr, outHPtr) {
        const mem = instance.exports.memory;
        const src = new Uint8Array(mem.buffer, srcPtr, srcLen);
        const key = imageCacheKey(src);
        const hit = imageCache.get(key);
        if (hit === "pending") return -2;
        if (hit && hit.rgba) {
          const need = hit.w * hit.h * 4;
          if (need > dstCap) return -3;
          new Uint8Array(mem.buffer, dstPtr, need).set(hit.rgba.subarray(0, need));
          const view = new DataView(mem.buffer);
          view.setUint32(outWPtr, hit.w, true);
          view.setUint32(outHPtr, hit.h, true);
          return need;
        }
        imageCache.set(key, "pending");
        const copy = src.slice();
        createImageBitmap(new Blob([copy], { type: sniffImageMime(copy) }))
          .then((bmp) => {
            const c = new OffscreenCanvas(bmp.width, bmp.height);
            const cctx = c.getContext("2d", { alpha: true });
            cctx.drawImage(bmp, 0, 0);
            const data = cctx.getImageData(0, 0, bmp.width, bmp.height);
            imageCache.set(key, { w: bmp.width, h: bmp.height, rgba: data.data });
          })
          .catch((err) => {
            console.warn("[softui] image decode failed", err);
            imageCache.delete(key);
          });
        return -2;
      },
    },
  };

  const wasmResp = await fetch("./softui.wasm");
  if (!wasmResp.ok) throw new Error(`failed to fetch softui.wasm (${wasmResp.status})`);
  const result = await WebAssembly.instantiateStreaming(wasmResp, imports);
  instance = result.instance;

  const {
    softui_start,
    softui_resize,
    softui_tick,
    softui_fb_ptr,
    softui_fb_width,
    softui_fb_height,
    softui_fb_stride,
    softui_alloc,
    softui_mount_disk,
    softui_push_key,
    softui_push_pointer,
    softui_persist,
    memory,
  } = instance.exports;

  if (typeof softui_start !== "function") {
    throw new Error("softui_start export missing");
  }

  // Session choice (GUI/CLI) is SoftUI-owned via the guest bootloader.
  // Hosts only provide Host ABI: storage, keyboard, pointer, present/blit.

  let diskBuf = loadPersistedDisk();
  let diskSource = "localStorage";
  if (!diskBuf) {
    const diskResp = await fetch("./init.sofs");
    if (!diskResp.ok) throw new Error(`failed to fetch init.sofs (${diskResp.status})`);
    diskBuf = new Uint8Array(await diskResp.arrayBuffer());
    diskSource = "init.sofs";
  }
  console.log(`[softui] mounting disk from ${diskSource} (${diskBuf.byteLength} bytes)`);

  const diskPtr = softui_alloc(diskBuf.byteLength);
  if (!diskPtr) throw new Error("softui_alloc failed for disk");
  new Uint8Array(memory.buffer, diskPtr, diskBuf.byteLength).set(diskBuf);

  const mountRc = softui_mount_disk(diskPtr, diskBuf.byteLength);
  if (mountRc !== 0) {
    if (diskSource === "localStorage") {
      console.warn("[softui] persisted disk mount failed; falling back to init.sofs");
      localStorage.removeItem(STORAGE_KEY);
      const diskResp = await fetch("./init.sofs");
      if (!diskResp.ok) throw new Error(`failed to fetch init.sofs (${diskResp.status})`);
      diskBuf = new Uint8Array(await diskResp.arrayBuffer());
      const retryPtr = softui_alloc(diskBuf.byteLength);
      if (!retryPtr) throw new Error("softui_alloc failed for fallback disk");
      new Uint8Array(memory.buffer, retryPtr, diskBuf.byteLength).set(diskBuf);
      const retryRc = softui_mount_disk(retryPtr, diskBuf.byteLength);
      if (retryRc !== 0) throw new Error(`softui_mount_disk failed: ${retryRc}`);
    } else {
      throw new Error(`softui_mount_disk failed: ${mountRc}`);
    }
  }

  let width = 0;
  let height = 0;
  let stride = 0;
  let image = null;

  function syncCanvasFromGuest() {
    width = softui_fb_width();
    height = softui_fb_height();
    stride = softui_fb_stride();
    canvas.width = width;
    canvas.height = height;
    image = ctx.createImageData(width, height);
  }

  function applyViewportSize(start) {
    const { w, h } = viewportPixels();
    if (start) {
      const rc = softui_start(w, h);
      if (rc !== 0) throw new Error(`softui_start failed: ${rc}`);
    } else if (typeof softui_resize === "function") {
      if (w === width && h === height) return;
      const rc = softui_resize(w, h);
      if (rc !== 0) {
        console.warn(`[softui] softui_resize failed: ${rc}`);
        return;
      }
    } else {
      return;
    }
    syncCanvasFromGuest();
    console.log(`[softui] framebuffer ${width}x${height} (dpr=${window.devicePixelRatio || 1})`);
  }

  applyViewportSize(true);

  canvas.tabIndex = 0;
  canvas.style.touchAction = "none";
  canvas.focus();

  window.addEventListener("keydown", (e) => {
    const key = mapKey(e);
    if (!key) return;
    e.preventDefault();
    softui_push_key(key, modsOf(e));
  });

  function fbCoords(e) {
    const rect = canvas.getBoundingClientRect();
    if (rect.width <= 0 || rect.height <= 0 || width <= 0 || height <= 0) {
      return { x: 0, y: 0 };
    }
    const x = Math.floor(((e.clientX - rect.left) / rect.width) * width);
    const y = Math.floor(((e.clientY - rect.top) / rect.height) * height);
    return {
      x: Math.max(0, Math.min(width - 1, x)),
      y: Math.max(0, Math.min(height - 1, y)),
    };
  }

  function pushPointer(e, kind) {
    if (typeof softui_push_pointer !== "function") return;
    const { x, y } = fbCoords(e);
    const buttons = e.buttons & 1;
    softui_push_pointer(x, y, buttons, kind);
  }

  canvas.addEventListener("pointermove", (e) => {
    pushPointer(e, 0);
  });
  canvas.addEventListener("pointerdown", (e) => {
    canvas.focus();
    canvas.setPointerCapture?.(e.pointerId);
    e.preventDefault();
    pushPointer(e, 1);
  });
  canvas.addEventListener("pointerup", (e) => {
    e.preventDefault();
    pushPointer(e, 2);
  });
  canvas.addEventListener("pointercancel", (e) => {
    pushPointer(e, 2);
  });

  if (typeof ResizeObserver !== "undefined") {
    const ro = new ResizeObserver(() => applyViewportSize(false));
    ro.observe(canvas);
  } else {
    window.addEventListener("resize", () => applyViewportSize(false));
  }
  window.addEventListener("orientationchange", () => {
    setTimeout(() => applyViewportSize(false), 100);
  });

  if (typeof softui_persist === "function") {
    window.addEventListener("beforeunload", () => {
      softui_persist();
    });
  }

  function frame() {
    softui_tick(nowNs());

    const ptr = softui_fb_ptr();
    const src = new Uint8Array(memory.buffer, ptr, stride * height);
    image.data.set(src.subarray(0, width * height * 4));
    ctx.putImageData(image, 0, 0);

    requestAnimationFrame(frame);
  }

  requestAnimationFrame(frame);
}

boot().catch((err) => {
  console.error(err);
});
