/**
 * Compile the React Email templates into a single plain-CJS renderer module
 * (emails/dist/render.cjs) that index.js can require() at runtime.
 *
 * Run via `npm run build:emails` (wired into firebase.json predeploy so every
 * deploy rebuilds automatically).
 */
import { build } from "esbuild";
import path from "node:path";
import { fileURLToPath } from "node:url";

const dir = path.dirname(fileURLToPath(import.meta.url));

await build({
  entryPoints: [path.join(dir, "render.jsx")],
  outfile: path.join(dir, "dist", "render.cjs"),
  bundle: true,
  platform: "node",
  target: "node24",
  format: "cjs",
  jsx: "automatic",
  minify: true,
  logLevel: "info",
});

console.log("✓ built emails/dist/render.cjs");
