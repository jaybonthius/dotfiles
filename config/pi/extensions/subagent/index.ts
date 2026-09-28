import { getAgentDir, getPackageDir, type ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { readFile } from "node:fs/promises";
import { join, resolve, sep } from "node:path";

export default async function (pi: ExtensionAPI) {
  // SDK hosts such as Pi Web do not launch through Pi's CLI entrypoint, and
  // their SDK need not be installed inside the extensions' npm tree.
  // Supply the actual host, not a second SDK or whichever CLI is on PATH.
  const override = "PI_SUBAGENTS_PI_CODING_AGENT_PACKAGE_ROOT";
  if (!process.env[override]?.trim() && !process.versions.bun) {
    const root = getPackageDir();
    const host = JSON.parse(await readFile(join(root, "package.json"), "utf8"));
    if (host.name !== "@earendil-works/pi-coding-agent") {
      throw new Error(`Unexpected Pi host package at ${root}`);
    }
    process.env[override] = root;
  }

  const root = join(getAgentDir(), "npm", "node_modules", "pi-subagents");
  const pkg = JSON.parse(await readFile(join(root, "package.json"), "utf8"));
  const entries = pkg.pi?.extensions;
  if (!Array.isArray(entries) || entries.length !== 1 || typeof entries[0] !== "string") {
    throw new Error("pi-subagents must declare one extension entrypoint");
  }
  const entry = resolve(root, entries[0]);
  if (!entry.startsWith(resolve(root) + sep)) throw new Error("Invalid subagent extension entrypoint");
  // Import through Pi's loader, after setting the supported host override.
  const upstream = await import(entry);
  if (typeof upstream.default !== "function") throw new Error("Missing subagent extension factory");
  await upstream.default(pi);
}
