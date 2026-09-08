import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { existsSync } from "node:fs";
import { readFile } from "node:fs/promises";
import { join, resolve, sep } from "node:path";
import { ensureAgentBrowser, getBrowserPackage, prependPath, readTargetVersion } from "./runtime.mjs";

type LoadedBrowser = { factory: (pi: ExtensionAPI) => unknown; version: string };
const cacheKey = Symbol.for("dotfiles.pi-browser-runtime.factories");
const processState = globalThis as typeof globalThis & { [cacheKey]?: Map<string, Promise<LoadedBrowser>> };

async function loadBrowser(packageRoot: string): Promise<LoadedBrowser> {
  const pkg = JSON.parse(await readFile(join(packageRoot, "package.json"), "utf8"));
  const entries = pkg.pi?.extensions;
  if (!Array.isArray(entries) || entries.length !== 1 || typeof entries[0] !== "string") {
    throw new Error("pi-agent-browser-native must declare one extension entrypoint");
  }
  const entry = resolve(packageRoot, entries[0]);
  if (!entry.startsWith(resolve(packageRoot) + sep)) throw new Error("Invalid browser extension entrypoint");

  // Keep this dynamic import in the Pi-loaded TypeScript module: Pi's jiti
  // loader supplies the host's virtual Pi/typebox imports to the upstream JS.
  const upstream = await import(entry);
  const runtimeVersion = join(packageRoot, "dist/extensions/agent-browser/lib/upstream-version.js");
  const version = existsSync(runtimeVersion)
    ? (await import(runtimeVersion)).TARGET_AGENT_BROWSER_VERSION
    : await readTargetVersion(packageRoot);
  if (typeof upstream.default !== "function") throw new Error("Missing browser extension factory");
  return { factory: upstream.default, version };
}

export default async function (pi: ExtensionAPI) {
  const packageRoot = getBrowserPackage();
  const factories = processState[cacheKey] ??= new Map();
  let loaded = factories.get(packageRoot);
  if (!loaded) {
    loaded = loadBrowser(packageRoot);
    factories.set(packageRoot, loaded);
    loaded.catch(() => factories.delete(packageRoot));
  }
  // Compiled upstream modules are process-cached. Preserve BOTH the factory and
  // its target through /reload; a new Pi process picks up extension upgrades.
  const { factory, version } = await loaded;
  const bin = await ensureAgentBrowser(version, { offline: process.argv.includes("--offline") });
  prependPath(bin);
  await factory(pi);
}
