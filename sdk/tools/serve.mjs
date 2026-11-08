#!/usr/bin/env node
/**
 * Tiny static server for the Sui SDK web preview.
 * Usage: node tools/serve.mjs
 * Then open http://127.0.0.1:8765/web/
 */
import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(__dirname, "..");
const port = Number(process.env.PORT || 8765);

const types = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".mjs": "text/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".sui": "text/plain; charset=utf-8",
  ".md": "text/markdown; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".svg": "image/svg+xml",
  ".png": "image/png",
};

function safeJoin(base, reqPath) {
  const decoded = decodeURIComponent(reqPath.split("?")[0]);
  const cleaned = path.normalize(decoded).replace(/^([/\\])+/, "");
  const full = path.resolve(base, cleaned);
  if (!full.startsWith(base)) return null;
  return full;
}

const server = http.createServer((req, res) => {
  let urlPath = req.url || "/";
  if (urlPath === "/") {
    res.writeHead(302, { Location: "/web/" });
    res.end();
    return;
  }
  if (urlPath.endsWith("/")) urlPath += "index.html";

  const file = safeJoin(root, urlPath);
  if (!file) {
    res.writeHead(403);
    res.end("Forbidden");
    return;
  }
  fs.readFile(file, (err, data) => {
    if (err) {
      res.writeHead(err.code === "ENOENT" ? 404 : 500);
      res.end(err.code === "ENOENT" ? "Not found" : "Error");
      return;
    }
    const ext = path.extname(file);
    res.writeHead(200, { "Content-Type": types[ext] || "application/octet-stream" });
    res.end(data);
  });
});

server.listen(port, "127.0.0.1", () => {
  console.log(`Sui SDK preview: http://127.0.0.1:${port}/web/`);
  console.log(`Serving ${root}`);
});
