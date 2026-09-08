import { spawn } from "node:child_process";
import { constants } from "node:os";
import { join } from "node:path";
import { ensureAgentBrowser, getBrowserPackage, readTargetVersion } from "./runtime.mjs";

try {
  const version = await readTargetVersion(getBrowserPackage());
  const bin = await ensureAgentBrowser(version);
  const child = spawn(join(bin, "agent-browser"), process.argv.slice(2), { stdio: "inherit" });
  for (const signal of ["SIGINT", "SIGTERM", "SIGHUP"]) {
    process.on(signal, () => child.kill(signal));
  }
  child.on("error", (error) => {
    console.error(error.message);
    process.exit(1);
  });
  child.on("exit", (code, signal) => process.exit(code ?? 128 + (constants.signals[signal] || 1)));
} catch (error) {
  console.error(`agent-browser setup: ${error.message}`);
  process.exitCode = 1;
}
