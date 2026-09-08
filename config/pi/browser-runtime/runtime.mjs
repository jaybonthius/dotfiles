import { execFile } from "node:child_process";
import { mkdir, mkdtemp, readFile, rename, rm, writeFile } from "node:fs/promises";
import { arch, homedir, platform } from "node:os";
import { delimiter, join, resolve } from "node:path";
import { promisify } from "node:util";

const exec = promisify(execFile);
const exactVersion = /^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$/;

export function getBrowserPackage(env = process.env) {
  const home = env.HOME || homedir();
  const configured = env.PI_CODING_AGENT_DIR || join(home, ".pi", "agent");
  const agentDir = configured.startsWith("~/") ? join(home, configured.slice(2)) : resolve(configured);
  return join(agentDir, "npm", "node_modules", "pi-agent-browser-native");
}

export async function readTargetVersion(packageRoot) {
  // dist is what Pi executes. Older releases (including the Discord install)
  // only publish the capability baseline. Never scrape prose or guess latest.
  const candidates = [
    ["dist/scripts/agent-browser-target.mjs", /\bTARGET_AGENT_BROWSER_VERSION\s*=\s*["']([^"']+)["']/],
    ["scripts/agent-browser-target.mjs", /\bTARGET_AGENT_BROWSER_VERSION\s*=\s*["']([^"']+)["']/],
    ["scripts/agent-browser-capability-baseline.mjs", /\btargetVersion\s*:\s*["']([^"']+)["']/],
  ];
  for (const [file, pattern] of candidates) {
    let text;
    try {
      text = await readFile(join(packageRoot, file), "utf8");
    } catch (error) {
      if (error.code === "ENOENT") continue;
      throw error;
    }
    const version = text.match(pattern)?.[1];
    if (!version || !exactVersion.test(version)) {
      throw new Error(`Cannot read an exact agent-browser target version from ${join(packageRoot, file)}`);
    }
    return version;
  }
  throw new Error(`No agent-browser target version metadata in ${packageRoot}. Install pi-agent-browser-native in this Pi home first.`);
}

export function prependPath(bin, env = process.env) {
  env.PATH = [bin, ...(env.PATH || "").split(delimiter).filter((part) => part && part !== bin)].join(delimiter);
}

async function verifyInstallation(directory, version, env) {
  const pkg = JSON.parse(await readFile(join(directory, "node_modules", "agent-browser", "package.json"), "utf8"));
  const bin = join(directory, "node_modules", ".bin");
  if (pkg.version !== version) throw new Error(`Expected agent-browser ${version}, found package ${pkg.version}`);
  const { stdout } = await exec(join(bin, "agent-browser"), ["--version"], { env, timeout: 15_000, maxBuffer: 64 * 1024 });
  if (stdout.trim() !== `agent-browser ${version}`) {
    throw new Error(`Expected agent-browser ${version}, found ${JSON.stringify(stdout.trim())}`);
  }
  return bin;
}

export async function ensureAgentBrowser(version, options = {}) {
  if (!exactVersion.test(version)) throw new Error(`Invalid exact agent-browser version: ${version}`);
  const env = options.env || process.env;
  const cacheRoot = options.cacheRoot || join(env.XDG_CACHE_HOME || join(env.HOME || homedir(), ".cache"), "pi-agent-browser", `${platform()}-${arch()}`);
  const destination = join(cacheRoot, version);
  try {
    return await verifyInstallation(destination, version, env);
  } catch (error) {
    // Only a missing install can be built. Never overwrite an existing version
    // that another Pi process may still be using.
    if (error.code !== "ENOENT") throw error;
  }
  if (options.offline || /^(1|true|yes)$/i.test(env.PI_OFFLINE || "")) {
    throw new Error(`agent-browser ${version} is not cached and Pi is offline. Start Pi online once to install its matching CLI.`);
  }

  await mkdir(cacheRoot, { recursive: true, mode: 0o700 });
  const staging = await mkdtemp(join(cacheRoot, `.install-${version}-`));
  try {
    await writeFile(join(staging, "package.json"), JSON.stringify({ private: true }));
    const [npm, ...prefix] = options.npmCommand || ["npm"];
    // Upstream postinstall can rewrite a global agent-browser symlink even on
    // local installs. Its published JS launcher already selects/chmods the
    // packaged native binary, so lifecycle scripts are unnecessary here.
    try {
      await exec(npm, [...prefix, "install", "--prefix", staging, "--global=false", "--ignore-scripts", "--no-audit", "--no-fund", "--save-exact", "--package-lock=true", `agent-browser@${version}`], {
        cwd: staging, env, timeout: 180_000, maxBuffer: 1024 * 1024,
      });
    } catch (error) {
      throw new Error(`Failed to install agent-browser ${version}: ${String(error.stderr || error.message).slice(-4000)}`, { cause: error });
    }
    await verifyInstallation(staging, version, env);
    try {
      // Atomic publication: concurrent starts may duplicate preparation, but
      // never observe a partial install or replace an already published CLI.
      await rename(staging, destination);
    } catch (error) {
      if (error.code !== "EEXIST" && error.code !== "ENOTEMPTY") throw error;
    }
    return await verifyInstallation(destination, version, env);
  } finally {
    await rm(staging, { recursive: true, force: true });
  }
}
