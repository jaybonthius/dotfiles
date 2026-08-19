import { afterEach, expect, test } from "bun:test";
import { createHash } from "node:crypto";
import * as fs from "node:fs";
import * as net from "node:net";
import * as os from "node:os";
import * as path from "node:path";
import {
  DEFAULT_MAX_PAYLOAD_BYTES,
  PINNED_EXTENSION_ID,
  startRelay,
  type Relay,
} from "./relay.ts";

const EXTENSION_ORIGIN = `chrome-extension://${PINNED_EXTENSION_ID}`;
const relays: Relay[] = [];
const tempDirs: string[] = [];

function makeRelay(maxPayloadBytes?: number) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "pi-annotate-relay-test-"));
  tempDirs.push(dir);
  const relay = startRelay({
    port: 0,
    socketPath: path.join(dir, "pi-annotate.sock"),
    tokenPath: path.join(dir, "pi-annotate.token"),
    maxPayloadBytes,
  });
  relays.push(relay);
  return relay;
}

function waitFor(predicate: () => boolean, message: string, timeoutMs = 2000): Promise<void> {
  const started = Date.now();
  return new Promise((resolve, reject) => {
    const check = () => {
      if (predicate()) return resolve();
      if (Date.now() - started >= timeoutMs) return reject(new Error(message));
      setTimeout(check, 10);
    };
    check();
  });
}

function openBrowser(relay: Relay, origin = EXTENSION_ORIGIN): Promise<WebSocket> {
  const ws = new WebSocket(`ws://${relay.host}:${relay.port}`, { headers: { Origin: origin } });
  return new Promise((resolve, reject) => {
    ws.addEventListener("open", () => resolve(ws), { once: true });
    ws.addEventListener("error", () => reject(new Error("WebSocket connection failed")), { once: true });
  });
}

function nextWebSocketMessage(ws: WebSocket): Promise<Record<string, unknown>> {
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error("Timed out waiting for WebSocket message")), 2000);
    ws.addEventListener("message", (event) => {
      clearTimeout(timeout);
      resolve(JSON.parse(String(event.data)));
    }, { once: true });
  });
}

function exactJsonPayload(byteLength: number, type: string) {
  const empty = JSON.stringify({ type, data: "" });
  const payload = JSON.stringify({ type, data: "x".repeat(byteLength - Buffer.byteLength(empty)) });
  expect(Buffer.byteLength(payload)).toBe(byteLength);
  return payload;
}

function connectPi(relay: Relay, token?: string): Promise<net.Socket> {
  const authToken = token ?? fs.readFileSync(relay.tokenPath, "utf8").trim();
  return new Promise((resolve, reject) => {
    const socket = net.createConnection(relay.socketPath);
    socket.once("connect", () => {
      socket.write(JSON.stringify({ type: "AUTH", token: authToken }) + "\n");
      resolve(socket);
    });
    socket.once("error", reject);
  });
}

function nextPiMessage(socket: net.Socket): Promise<Record<string, unknown>> {
  return new Promise((resolve, reject) => {
    let buffer = "";
    const timeout = setTimeout(() => {
      socket.off("data", onData);
      reject(new Error("Timed out waiting for Pi message"));
    }, 2000);
    const onData = (chunk: Buffer) => {
      buffer += chunk.toString("utf8");
      const newline = buffer.indexOf("\n");
      if (newline === -1) return;
      clearTimeout(timeout);
      socket.off("data", onData);
      resolve(JSON.parse(buffer.slice(0, newline)));
    };
    socket.on("data", onData);
  });
}

afterEach(async () => {
  await Promise.all(relays.splice(0).map((relay) => relay.stop()));
  for (const dir of tempDirs.splice(0)) fs.rmSync(dir, { recursive: true, force: true });
});

test("relays messages bidirectionally between browser and authenticated Pi", async () => {
  const relay = makeRelay();
  const browser = await openBrowser(relay);
  await waitFor(() => fs.existsSync(relay.tokenPath) && fs.existsSync(relay.socketPath), "Pi interface was not created");
  expect(fs.statSync(relay.socketPath).mode & 0o777).toBe(0o600);
  expect(fs.statSync(relay.tokenPath).mode & 0o777).toBe(0o600);
  const pi = await connectPi(relay);

  const browserMessage = nextWebSocketMessage(browser);
  pi.write(JSON.stringify({ type: "START_ANNOTATION", requestId: 1 }) + "\n");
  expect(await browserMessage).toEqual({ type: "START_ANNOTATION", requestId: 1 });

  const piMessage = nextPiMessage(pi);
  browser.send(JSON.stringify({ type: "CANCEL", requestId: 1, reason: "user" }));
  expect(await piMessage).toEqual({ type: "CANCEL", requestId: 1, reason: "user" });
});

test("rejects Pi clients with an invalid AUTH token", async () => {
  const relay = makeRelay();
  await openBrowser(relay);
  await waitFor(() => fs.existsSync(relay.tokenPath), "Token was not created");
  const pi = await connectPi(relay, "wrong-token");
  await new Promise<void>((resolve) => pi.once("close", () => resolve()));
  expect(pi.destroyed).toBe(true);
});

test("accepts only the pinned extension origin", async () => {
  const acceptedRelay = makeRelay();
  const browser = await openBrowser(acceptedRelay);
  expect(browser.readyState).toBe(WebSocket.OPEN);

  const rejectedRelay = makeRelay();
  await expect(
    openBrowser(rejectedRelay, "chrome-extension://abcdefghijklmnopabcdefghijklmnop"),
  ).rejects.toThrow("WebSocket connection failed");
  expect(fs.existsSync(rejectedRelay.socketPath)).toBe(false);
  expect(fs.existsSync(rejectedRelay.tokenPath)).toBe(false);
});

test("manifest public key derives to the pinned extension ID", () => {
  const manifestPath = path.join(import.meta.dir, "chrome-extension", "manifest.json");
  const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8")) as { key: string };
  const digest = createHash("sha256").update(Buffer.from(manifest.key, "base64")).digest();
  const derivedId = [...digest.subarray(0, 16)]
    .flatMap((byte) => [byte >> 4, byte & 0x0f])
    .map((nibble) => String.fromCharCode("a".charCodeAt(0) + nibble))
    .join("");
  expect(derivedId).toBe(PINNED_EXTENSION_ID);
});

test("answers browser PING with WebSocket and Pi interface readiness", async () => {
  const relay = makeRelay();
  const browser = await openBrowser(relay);
  await waitFor(() => fs.existsSync(relay.tokenPath), "Token was not created");
  const pong = nextWebSocketMessage(browser);
  browser.send(JSON.stringify({ type: "PING" }));
  expect(await pong).toMatchObject({ type: "PONG", ready: true, error: null });
});

test("closes the browser when a conflicting path prevents Pi interface setup", async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "pi-annotate-relay-test-"));
  tempDirs.push(dir);
  const socketPath = path.join(dir, "pi-annotate.sock");
  const tokenPath = path.join(dir, "pi-annotate.token");
  fs.writeFileSync(socketPath, "not a socket");
  const relay = startRelay({ port: 0, socketPath, tokenPath });
  relays.push(relay);

  const browser = await openBrowser(relay);
  const closed = new Promise<CloseEvent>((resolve) => {
    browser.addEventListener("close", (event) => resolve(event), { once: true });
  });
  expect((await closed).code).toBe(1011);
  expect(fs.readFileSync(socketPath, "utf8")).toBe("not a socket");
  expect(fs.existsSync(tokenPath)).toBe(false);
});

test("a newly authenticated Pi replaces the previous Pi and blocks its messages", async () => {
  const relay = makeRelay();
  const browser = await openBrowser(relay);
  await waitFor(() => fs.existsSync(relay.tokenPath), "Token was not created");
  const first = await connectPi(relay);
  first.on("error", () => {});
  const replacement = nextPiMessage(first);
  const second = await connectPi(relay);

  expect(await replacement).toEqual({
    type: "SESSION_REPLACED",
    reason: "Another terminal started annotation",
  });
  const received: Record<string, unknown>[] = [];
  browser.addEventListener("message", (event) => received.push(JSON.parse(String(event.data))));
  first.write(JSON.stringify({ type: "OLD_PI_MESSAGE" }) + "\n");
  second.write(JSON.stringify({ type: "NEW_PI_MESSAGE" }) + "\n");
  await waitFor(() => received.length > 0, "Replacement Pi message was not forwarded");
  expect(received).toEqual([{ type: "NEW_PI_MESSAGE" }]);
  expect(second.destroyed).toBe(false);
});

test("a new browser replaces the old browser without dropping Pi readiness", async () => {
  const relay = makeRelay();
  const first = await openBrowser(relay);
  await waitFor(() => fs.existsSync(relay.tokenPath), "Token was not created");
  const pi = await connectPi(relay);
  const firstClosed = new Promise<void>((resolve) => first.addEventListener("close", () => resolve(), { once: true }));
  const second = await openBrowser(relay);
  await firstClosed;

  const message = nextWebSocketMessage(second);
  pi.write(JSON.stringify({ type: "START_ANNOTATION", requestId: 2 }) + "\n");
  expect(await message).toEqual({ type: "START_ANNOTATION", requestId: 2 });
  expect(fs.existsSync(relay.socketPath)).toBe(true);
  expect(fs.existsSync(relay.tokenPath)).toBe(true);
});

test("browser disconnect removes Pi readiness and disconnects Pi", async () => {
  const relay = makeRelay();
  const browser = await openBrowser(relay);
  await waitFor(() => fs.existsSync(relay.tokenPath), "Token was not created");
  const pi = await connectPi(relay);
  const piClosed = new Promise<void>((resolve) => pi.once("close", () => resolve()));
  browser.close();

  await piClosed;
  await waitFor(
    () => !fs.existsSync(relay.socketPath) && !fs.existsSync(relay.tokenPath),
    "Pi interface remained after browser disconnect",
  );
});

test("stop cleans up the socket, token, browser, and Pi connection", async () => {
  const relay = makeRelay();
  const browser = await openBrowser(relay);
  await waitFor(() => fs.existsSync(relay.tokenPath), "Token was not created");
  const pi = await connectPi(relay);
  const browserClosed = new Promise<void>((resolve) => browser.addEventListener("close", () => resolve(), { once: true }));
  const piClosed = new Promise<void>((resolve) => pi.once("close", () => resolve()));

  await relay.stop();
  await Promise.all([browserClosed, piClosed]);
  expect(fs.existsSync(relay.socketPath)).toBe(false);
  expect(fs.existsSync(relay.tokenPath)).toBe(false);
  await relay.stop();
});

test("uses a default payload bound whose newline fits index.ts socket buffer", () => {
  expect(DEFAULT_MAX_PAYLOAD_BYTES + 1).toBe(32 * 1024 * 1024);
});

test("accepts an exact-bound Pi line before checking the incomplete remainder", async () => {
  const maxPayloadBytes = 128;
  const relay = makeRelay(maxPayloadBytes);
  const browser = await openBrowser(relay);
  await waitFor(() => fs.existsSync(relay.tokenPath), "Token was not created");
  const pi = await connectPi(relay);
  const payload = exactJsonPayload(maxPayloadBytes, "PI_BOUNDARY");
  const message = nextWebSocketMessage(browser);
  pi.write(payload + "\n" + " ");
  expect(await message).toEqual(JSON.parse(payload));
  expect(pi.destroyed).toBe(false);
});

test("rejects a Pi line one byte over the payload bound", async () => {
  const maxPayloadBytes = 128;
  const relay = makeRelay(maxPayloadBytes);
  await openBrowser(relay);
  await waitFor(() => fs.existsSync(relay.tokenPath), "Token was not created");
  const pi = await connectPi(relay);
  const closed = new Promise<void>((resolve) => pi.once("close", () => resolve()));
  pi.write(exactJsonPayload(maxPayloadBytes + 1, "PI_TOO_LARGE") + "\n");
  await closed;
  expect(pi.destroyed).toBe(true);
});

test("accepts an exact-bound browser payload with its newline", async () => {
  const maxPayloadBytes = 128;
  const relay = makeRelay(maxPayloadBytes);
  const browser = await openBrowser(relay);
  await waitFor(() => fs.existsSync(relay.tokenPath), "Token was not created");
  const pi = await connectPi(relay);
  const payload = exactJsonPayload(maxPayloadBytes, "BROWSER_BOUNDARY");
  const message = nextPiMessage(pi);
  browser.send(payload);
  expect(await message).toEqual(JSON.parse(payload));
  expect(Buffer.byteLength(payload + "\n")).toBe(maxPayloadBytes + 1);
});

test("closes a browser whose payload is one byte over the bound", async () => {
  const maxPayloadBytes = 128;
  const relay = makeRelay(maxPayloadBytes);
  const browser = await openBrowser(relay);
  const closed = new Promise<void>((resolve) => {
    browser.addEventListener("close", () => resolve(), { once: true });
  });
  browser.send(exactJsonPayload(maxPayloadBytes + 1, "BROWSER_TOO_LARGE"));
  await closed;
  expect(browser.readyState).toBe(WebSocket.CLOSED);
  await waitFor(
    () => !fs.existsSync(relay.socketPath) && !fs.existsSync(relay.tokenPath),
    "Pi interface remained after oversized browser payload",
  );
});
