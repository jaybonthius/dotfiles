// pi-herdr-tab-sync: sync pi session name → herdr tab label
// Only activates inside herdr-managed panes (HERDR_ENV=1).
// Triggers on: session_start (resume), session_info_changed (/name), agent_start (fallback).
// Does nothing if the session has no name.

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { createConnection } from "node:net";

const HERDR_ENV = process.env.HERDR_ENV;
const socketPath = process.env.HERDR_SOCKET_PATH;
const paneId = process.env.HERDR_PANE_ID;

function enabled() {
  return HERDR_ENV === "1" && !!socketPath && !!paneId;
}

function herdrRequest(method: string, params: Record<string, unknown>): Promise<Record<string, unknown> | null> {
  return new Promise((resolve) => {
    let done = false;
    let buf = "";
    const finish = (result: Record<string, unknown> | null = null) => {
      if (done) return;
      done = true;
      clearTimeout(timer);
      socket.destroy();
      resolve(result);
    };

    const socket = createConnection(socketPath!);
    socket.on("error", () => finish());
    socket.on("connect", () => {
      const id = `pi-herdr-tab:${Date.now()}`;
      socket.write(`${JSON.stringify({ id, method, params })}\n`);
    });
    socket.on("data", (chunk) => {
      buf += chunk.toString();
      if (buf.includes("\n")) {
        try {
          const resp = JSON.parse(buf.split("\n")[0]);
          finish(resp.result ?? null);
        } catch {
          finish();
        }
      }
    });
    socket.on("end", () => finish());
    const timer = setTimeout(() => finish(), 1000);
    timer.unref?.();
  });
}

async function renameTab(label: string): Promise<boolean> {
  const result = await herdrRequest("pane.get", { pane_id: paneId! });
  const tabId = (result as { pane?: { tab_id?: string } })?.pane?.tab_id;
  if (!tabId) return false;
  return (await herdrRequest("tab.rename", { tab_id: tabId, label })) !== null;
}

export default function (pi: ExtensionAPI) {
  // pi.registerCommand("herdr-debug", {
  //   description: "Debug herdr-tab-sync: show env vars, session name, and test socket",
  //   handler: async (_args, ctx) => {
  //     const lines: string[] = [
  //       `HERDR_ENV        = ${HERDR_ENV ?? "(unset)"}`,
  //       `HERDR_SOCKET_PATH= ${socketPath ?? "(unset)"}`,
  //       `HERDR_PANE_ID    = ${paneId ?? "(unset)"}`,
  //       `enabled()        = ${enabled()}`,
  //       `sessionName      = ${pi.getSessionName() ?? "(none)"}`,
  //     ];
  //
  //     if (enabled()) {
  //       const result = await herdrRequest("pane.get", { pane_id: paneId! });
  //       lines.push(`pane.get result  = ${JSON.stringify(result)}`);
  //       const tabId = (result as { pane?: { tab_id?: string } })?.pane?.tab_id;
  //       lines.push(`tab_id           = ${tabId ?? "(not found)"}`);
  //     }
  //
  //     ctx.ui.notify(lines.join("\n"), "info");
  //   },
  // });

  if (!enabled()) return;

  let lastSynced: string | undefined;
  let pending: string | undefined;
  let syncing = false;

  async function flush() {
    syncing = true;
    try {
      while (pending && pending !== lastSynced) {
        const name = pending;
        const renamed = await renameTab(name);
        if (renamed) lastSynced = name;
        // Retry failures on the next event, but process a newer name now.
        if (!renamed && pending === name) break;
      }
    } finally {
      syncing = false;
    }
  }

  function sync() {
    pending = pi.getSessionName();
    if (pending && !syncing && pending !== lastSynced) void flush();
  }

  pi.on("session_start", () => sync());
  pi.on("session_info_changed", () => sync());
  pi.on("agent_start", () => sync());
}
