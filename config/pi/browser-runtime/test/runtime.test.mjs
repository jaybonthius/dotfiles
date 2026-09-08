import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { mkdir, mkdtemp, readFile, readdir, rm, writeFile } from "node:fs/promises";
import { arch, platform, tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { promisify } from "node:util";
import { test } from "node:test";
import { ensureAgentBrowser, getBrowserPackage, readTargetVersion, prependPath } from "../runtime.mjs";
import loadBrowserExtension from "../index.ts";

const exec = promisify(execFile);

async function fixture(t) {
  const root = await mkdtemp(join(tmpdir(), "pi-browser-runtime-test-"));
  t.after(() => rm(root, { recursive: true, force: true }));
  const npm = join(root, "npm.mjs");
  await writeFile(npm, `
import { mkdir, writeFile, appendFile } from 'node:fs/promises';
import { join } from 'node:path';
const args = process.argv.slice(2);
const dest = args[args.indexOf('--prefix') + 1];
const version = args.at(-1).slice('agent-browser@'.length);
await appendFile(process.env.INSTALL_LOG, JSON.stringify(args) + '\\n');
if (process.env.FAIL_INSTALL) process.exit(17);
const bin = join(dest, 'node_modules', '.bin');
const pkg = join(dest, 'node_modules', 'agent-browser');
await mkdir(bin, {recursive:true});
await mkdir(pkg, {recursive:true});
await writeFile(join(pkg, 'package.json'), JSON.stringify({version}));
await writeFile(join(bin, 'agent-browser'), '#!' + process.execPath + '\\nconsole.log("agent-browser ' + (process.env.WRONG_VERSION || version) + '");\\n', {mode:0o755});
`);
  return {
    root,
    options: {
      cacheRoot: join(root, "cache"),
      npmCommand: [process.execPath, npm],
      env: { ...process.env, PI_OFFLINE: "0", INSTALL_LOG: join(root, "installs.log") },
    },
  };
}

async function target(root, file, text) {
  const path = join(root, file);
  await mkdir(dirname(path), { recursive: true });
  await writeFile(path, text);
}

test("use the compiled runtime target, not stale source metadata", async (t) => {
  const { root } = await fixture(t);
  await target(root, "dist/scripts/agent-browser-target.mjs", 'export const TARGET_AGENT_BROWSER_VERSION = "0.34.0";');
  await target(root, "scripts/agent-browser-target.mjs", 'export const TARGET_AGENT_BROWSER_VERSION = "0.33.2";');
  assert.equal(await readTargetVersion(root), "0.34.0");
});

test("support the older Discord extension's canonical baseline", async (t) => {
  const { root } = await fixture(t);
  await target(root, "scripts/agent-browser-capability-baseline.mjs", 'export const CAPABILITY_BASELINE = { targetVersion: "0.30.1" };');
  assert.equal(await readTargetVersion(root), "0.30.1");
});

test("unknown metadata fails closed rather than using a global or latest version", async (t) => {
  const { root } = await fixture(t);
  await target(root, "dist/scripts/agent-browser-target.mjs", 'export const TARGET_AGENT_BROWSER_VERSION = "../../bad";');
  await target(root, "scripts/agent-browser-target.mjs", 'export const TARGET_AGENT_BROWSER_VERSION = "0.33.2";');
  await assert.rejects(readTargetVersion(root), /target version/i);
});

test("select the active Pi home, including Discord, without cwd package lookup", () => {
  assert.equal(getBrowserPackage({ HOME: "/home/test" }), "/home/test/.pi/agent/npm/node_modules/pi-agent-browser-native");
  assert.equal(getBrowserPackage({ HOME: "/home/test", PI_CODING_AGENT_DIR: "/home/test/.pi/discord-agent" }), "/home/test/.pi/discord-agent/npm/node_modules/pi-agent-browser-native");
  assert.equal(getBrowserPackage({ HOME: "/home/test", PI_CODING_AGENT_DIR: "~/custom-pi" }), "/home/test/custom-pi/npm/node_modules/pi-agent-browser-native");
});

test("install the exact version once; cache hits work offline", async (t) => {
  const { options } = await fixture(t);
  const bin = await ensureAgentBrowser("0.34.0", options);
  assert.equal((await exec(join(bin, "agent-browser"), ["--version"])).stdout.trim(), "agent-browser 0.34.0");
  assert.equal(await ensureAgentBrowser("0.34.0", { ...options, env: { ...options.env, PI_OFFLINE: "1" } }), bin);
  const installs = (await readFile(options.env.INSTALL_LOG, "utf8")).trim().split("\n").map(JSON.parse);
  assert.equal(installs.length, 1);
  assert.equal(installs[0].at(-1), "agent-browser@0.34.0");
  assert.ok(installs[0].includes("--ignore-scripts"), "upstream postinstall must not rewrite global binaries");
  assert.ok(installs[0].includes("--global=false"));
});

test("two extension versions coexist without changing the older CLI", async (t) => {
  const { options } = await fixture(t);
  const oldBin = await ensureAgentBrowser("0.30.1", options);
  const newBin = await ensureAgentBrowser("0.34.0", options);
  assert.notEqual(oldBin, newBin);
  assert.equal((await exec(join(oldBin, "agent-browser"), ["--version"])).stdout.trim(), "agent-browser 0.30.1");
  assert.equal((await exec(join(newBin, "agent-browser"), ["--version"])).stdout.trim(), "agent-browser 0.34.0");
});

test("concurrent first starts publish only a complete verified installation", async (t) => {
  const { options } = await fixture(t);
  const bins = await Promise.all(Array.from({ length: 4 }, () => ensureAgentBrowser("0.34.0", options)));
  assert.equal(new Set(bins).size, 1);
  assert.equal((await exec(join(bins[0], "agent-browser"), ["--version"])).stdout.trim(), "agent-browser 0.34.0");
  assert.deepEqual(await readdir(options.cacheRoot), ["0.34.0"]);
});

test("failed or wrong-version installs never replace a working cache", async (t) => {
  const { options } = await fixture(t);
  const oldBin = await ensureAgentBrowser("0.30.1", options);
  await assert.rejects(ensureAgentBrowser("0.34.0", { ...options, env: { ...options.env, FAIL_INSTALL: "1" } }), /install/i);
  await assert.rejects(ensureAgentBrowser("0.34.0", { ...options, env: { ...options.env, WRONG_VERSION: "0.33.2" } }), /0\.34\.0/);
  assert.deepEqual(await readdir(options.cacheRoot), ["0.30.1"]);
  assert.equal((await exec(join(oldBin, "agent-browser"), ["--version"])).stdout.trim(), "agent-browser 0.30.1");
});

test("offline cache miss and invalid versions never invoke npm", async (t) => {
  const { options } = await fixture(t);
  await assert.rejects(ensureAgentBrowser("0.34.0", { ...options, env: { ...options.env, PI_OFFLINE: "1" } }), /offline/i);
  await assert.rejects(ensureAgentBrowser("latest", options), /version/i);
  await assert.rejects(ensureAgentBrowser("../../evil", options), /version/i);
  await assert.rejects(readFile(options.env.INSTALL_LOG), { code: "ENOENT" });
});

test("the selected CLI wins over inherited parent and global CLI paths", () => {
  const env = { PATH: "/old/bin:/usr/bin", HOME: "/home/test" };
  prependPath("/new/bin", env);
  prependPath("/new/bin", env);
  assert.equal(env.PATH, "/new/bin:/old/bin:/usr/bin");
  assert.equal(env.HOME, "/home/test");
});

test("loader preserves the loaded factory/CLI pair through an on-disk upgrade and reload", async (t) => {
  const { root, options } = await fixture(t);
  const packageRoot = getBrowserPackage({ HOME: root });
  const metadata = "dist/scripts/agent-browser-target.mjs";
  await target(packageRoot, "package.json", JSON.stringify({ type: "module", pi: { extensions: ["./dist/extensions/agent-browser/index.js"] } }));
  await target(packageRoot, metadata, 'export const TARGET_AGENT_BROWSER_VERSION = "0.34.0";');
  await target(packageRoot, "dist/extensions/agent-browser/lib/upstream-version.js", 'export { TARGET_AGENT_BROWSER_VERSION } from "../../../scripts/agent-browser-target.mjs";');
  await target(packageRoot, "dist/extensions/agent-browser/index.js", 'import { TARGET_AGENT_BROWSER_VERSION } from "./lib/upstream-version.js"; export default function (pi) { pi.registerTool({ name: "agent_browser", version: TARGET_AGENT_BROWSER_VERSION }); }');
  const cacheRoot = join(root, ".cache", "pi-agent-browser", `${platform()}-${arch()}`);
  const bin = await ensureAgentBrowser("0.34.0", { ...options, cacheRoot });
  const saved = { ...process.env };
  t.after(() => {
    for (const key of Object.keys(process.env)) if (!(key in saved)) delete process.env[key];
    Object.assign(process.env, saved);
  });
  process.env.HOME = root;
  delete process.env.PI_CODING_AGENT_DIR;
  delete process.env.XDG_CACHE_HOME;
  process.env.PI_OFFLINE = "1";
  const registered = [];
  const pi = { registerTool: (tool) => registered.push(tool) };
  await loadBrowserExtension(pi);
  await target(packageRoot, metadata, 'export const TARGET_AGENT_BROWSER_VERSION = "0.35.0";');
  await loadBrowserExtension(pi);
  assert.deepEqual(registered.map((tool) => tool.version), ["0.34.0", "0.34.0"]);
  assert.equal(process.env.PATH.split(":")[0], bin);
  assert.equal(await readTargetVersion(packageRoot), "0.35.0", "standalone/new processes see the upgraded metadata");
});

test("dotfiles keep upstream updates enabled but load the native tool only through the paired loader", async () => {
  const settings = JSON.parse(await readFile(new URL("../../settings.base.json", import.meta.url), "utf8"));
  const native = settings.packages.filter((entry) => (typeof entry === "string" ? entry : entry.source).startsWith("npm:pi-agent-browser-native"));
  assert.deepEqual(native, [{ source: "npm:pi-agent-browser-native", extensions: [] }]);
  assert.equal(settings.packages.filter((entry) => entry === "../browser-runtime").length, 1);
});
