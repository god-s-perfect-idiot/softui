/** System lib surface for suigui (preview bindings). */

export function createLibs(host) {
  return {
    ui: {
      /** @deprecated preview uses widget tree directly */
    },
    draw: {
      clear(color) {
        host.clear(color);
      },
      fill(x, y, w, h, color) {
        host.fill(x, y, w, h, color);
      },
      text(str, x, y, color) {
        host.text(str, x, y, color);
      },
    },
    app: {
      title(name) {
        host.setTitle(name);
      },
      quit() {
        host.quit();
      },
    },
    time: {
      now() {
        return Date.now();
      },
      clock() {
        const d = new Date();
        const hh = String(d.getHours()).padStart(2, "0");
        const mm = String(d.getMinutes()).padStart(2, "0");
        return `${hh}:${mm}`;
      },
    },
  };
}
