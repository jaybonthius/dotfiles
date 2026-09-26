import assert from "node:assert/strict";
import { mkdtemp, rm } from "node:fs/promises";
import net from "node:net";
import os from "node:os";
import path from "node:path";
import { test } from "node:test";

const directory = await mkdtemp(path.join(os.tmpdir(), "pi-herdr-tab-sync-"));
const socketPath = path.join(directory, "herdr.sock");
process.env.HERDR_ENV = "1";
process.env.HERDR_SOCKET_PATH = socketPath;
process.env.HERDR_PANE_ID = "pane-1";
const { default: tabSync } = await import("../index.ts");

function agent() {
  const handlers = new Map();
  let name;
  const pi = {
    getSessionName: () => name,
    on: (event, handler) => handlers.set(event, handler),
  };
  tabSync(pi);
  return {
    emit(event, nextName = name) {
      name = nextName;
      handlers.get(event)();
    },
  };
}

async function until(predicate) {
  for (let i = 0; i < 100; i++) {
    if (predicate()) return;
    await new Promise((resolve) => setTimeout(resolve, 10));
  }
  assert.fail("timed out waiting for tab sync");
}

test("retries failed renames and serializes rapid name changes", async () => {
  const labels = [];
  let failNextRename = true;
  let releaseRename;
  const server = net.createServer((socket) => {
    let buffer = "";
    socket.on("data", (chunk) => {
      buffer += chunk;
      if (!buffer.includes("\n")) return;
      const request = JSON.parse(buffer.split("\n")[0]);
      const reply = (payload) => socket.write(`${JSON.stringify({ id: request.id, ...payload })}\n`);
      if (request.method === "pane.get") {
        reply({ result: { pane: { tab_id: "tab-1" } } });
      } else {
        assert.equal(request.method, "tab.rename");
        assert.equal(request.params.tab_id, "tab-1");
        labels.push(request.params.label);
        if (failNextRename) {
          failNextRename = false;
          reply({ error: { message: "transient failure" } });
        } else if (request.params.label === "first") {
          releaseRename = () => reply({ result: { type: "tab_renamed" } });
        } else {
          reply({ result: { type: "tab_renamed" } });
        }
      }
    });
  });

  try {
    await new Promise((resolve) => server.listen(socketPath, resolve));
    const session = agent();
    session.emit("session_start"); // Unnamed sessions leave the tab alone.
    assert.deepEqual(labels, []);

    session.emit("session_info_changed", "retry-me");
    await until(() => labels.length === 1);
    // The failed response must be consumed before the retry event.
    await new Promise((resolve) => setTimeout(resolve, 20));
    session.emit("agent_start");
    await until(() => labels.length === 2);
    assert.deepEqual(labels, ["retry-me", "retry-me"]);

    session.emit("session_info_changed", "first");
    await until(() => releaseRename !== undefined);
    session.emit("session_info_changed", "skipped");
    session.emit("session_info_changed", "latest");
    assert.deepEqual(labels, ["retry-me", "retry-me", "first"]);
    releaseRename();
    await until(() => labels.length === 4);
    assert.deepEqual(labels, ["retry-me", "retry-me", "first", "latest"]);
  } finally {
    await new Promise((resolve) => server.close(resolve));
    await rm(directory, { recursive: true, force: true });
  }
});
