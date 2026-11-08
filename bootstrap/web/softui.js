const canvas = document.getElementById("fb");
const ctx = canvas.getContext("2d", { alpha: false });

const WIDTH = canvas.width;
const HEIGHT = canvas.height;

function nowNs() {
  return BigInt(Math.floor(performance.now() * 1e6));
}

function decodeUtf8(memory, ptr, len) {
  const bytes = new Uint8Array(memory.buffer, ptr, len);
  return new TextDecoder().decode(bytes);
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

async function boot() {
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
    },
  };

  let instance;
  const wasmResp = await fetch("./softui.wasm");
  if (!wasmResp.ok) throw new Error(`failed to fetch softui.wasm (${wasmResp.status})`);
  const result = await WebAssembly.instantiateStreaming(wasmResp, imports);
  instance = result.instance;

  const {
    softui_start,
    softui_tick,
    softui_fb_ptr,
    softui_fb_width,
    softui_fb_height,
    softui_fb_stride,
    softui_alloc,
    softui_mount_disk,
    softui_push_key,
    softui_set_boot_mode,
    memory,
  } = instance.exports;

  if (typeof softui_start !== "function") {
    throw new Error("softui_start export missing");
  }

  // Default CLI boot (0). Pass ?boot=gui later when implemented.
  const params = new URLSearchParams(location.search);
  if (typeof softui_set_boot_mode === "function") {
    softui_set_boot_mode(params.get("boot") === "gui" ? 1 : 0);
  }

  const diskResp = await fetch("./init.sofs");
  if (!diskResp.ok) throw new Error(`failed to fetch init.sofs (${diskResp.status})`);
  const diskBuf = new Uint8Array(await diskResp.arrayBuffer());

  const diskPtr = softui_alloc(diskBuf.byteLength);
  if (!diskPtr) throw new Error("softui_alloc failed for disk");
  new Uint8Array(memory.buffer, diskPtr, diskBuf.byteLength).set(diskBuf);

  const mountRc = softui_mount_disk(diskPtr, diskBuf.byteLength);
  if (mountRc !== 0) throw new Error(`softui_mount_disk failed: ${mountRc}`);

  const rc = softui_start(WIDTH, HEIGHT);
  if (rc !== 0) throw new Error(`softui_start failed: ${rc}`);

  const width = softui_fb_width();
  const height = softui_fb_height();
  const stride = softui_fb_stride();
  if (width !== WIDTH || height !== HEIGHT) {
    throw new Error(`unexpected fb size ${width}x${height}`);
  }

  canvas.width = width;
  canvas.height = height;
  canvas.tabIndex = 0;
  canvas.focus();
  const image = ctx.createImageData(width, height);

  window.addEventListener("keydown", (e) => {
    const key = mapKey(e);
    if (!key) return;
    e.preventDefault();
    softui_push_key(key, modsOf(e));
  });

  canvas.addEventListener("pointerdown", () => canvas.focus());

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
