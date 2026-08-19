import { randomBytes } from "node:crypto";
import * as fs from "node:fs";
import * as net from "node:net";

const DEFAULT_HOST = "127.0.0.1";
const DEFAULT_PORT = 43173;
const DEFAULT_SOCKET_PATH = "/tmp/pi-annotate.sock";
const DEFAULT_TOKEN_PATH = "/tmp/pi-annotate.token";
export const DEFAULT_MAX_PAYLOAD_BYTES = 32 * 1024 * 1024 - 1;
export const PINNED_EXTENSION_ID = "kkkknbhejplcekiaipnmmghfegjnlelf";

export type RelayOptions = {
  host?: string;
  port?: number;
  socketPath?: string;
  tokenPath?: string;
  maxPayloadBytes?: number;
};

type BrowserSocket = ServerWebSocket<undefined>;

export type Relay = {
  host: string;
  port: number;
  socketPath: string;
  tokenPath: string;
  stop: () => Promise<void>;
};

function unlinkIfExists(filePath: string) {
  try {
    fs.unlinkSync(filePath);
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error;
  }
}

function socketIsLive(socketPath: string): Promise<boolean> {
  return new Promise((resolve) => {
    const socket = net.createConnection(socketPath);
    socket.once("connect", () => {
      socket.destroy();
      resolve(true);
    });
    socket.once("error", () => resolve(false));
  });
}

async function removeStaleSocket(socketPath: string) {
  let stat: fs.Stats;
  try {
    stat = fs.lstatSync(socketPath);
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") return;
    throw error;
  }
  if (!stat.isSocket()) throw new Error(`Refusing to replace non-socket path ${socketPath}`);
  if (await socketIsLive(socketPath)) throw new Error(`Socket ${socketPath} is already in use`);
  fs.unlinkSync(socketPath);
}

function isExtensionOrigin(origin: string | null) {
  return origin === `chrome-extension://${PINNED_EXTENSION_ID}`;
}

export function startRelay(options: RelayOptions = {}): Relay {
  const host = options.host ?? DEFAULT_HOST;
  const requestedPort = options.port ?? DEFAULT_PORT;
  const socketPath = options.socketPath ?? DEFAULT_SOCKET_PATH;
  const tokenPath = options.tokenPath ?? DEFAULT_TOKEN_PATH;
  const maxPayloadBytes = options.maxPayloadBytes ?? DEFAULT_MAX_PAYLOAD_BYTES;

  if (host !== DEFAULT_HOST) throw new Error("Pi Annotate relay must bind to 127.0.0.1");

  let browser: BrowserSocket | null = null;
  let piServer: net.Server | null = null;
  let activePi: net.Socket | null = null;
  let authToken: string | null = null;
  let ownsPiInterface = false;
  let piInterfaceReady = false;
  let piInterfaceError = "Pi interface not ready";
  let stopped = false;
  let transition = Promise.resolve();
  const piSockets = new Set<net.Socket>();

  function closePiSockets() {
    for (const socket of piSockets) socket.destroy();
    piSockets.clear();
    activePi = null;
  }

  async function hidePiInterface() {
    closePiSockets();
    const server = piServer;
    piServer = null;
    authToken = null;
    piInterfaceReady = false;
    piInterfaceError = "Pi interface not ready";
    if (server) {
      await new Promise<void>((resolve) => server.close(() => resolve()));
    }
    if (ownsPiInterface) {
      ownsPiInterface = false;
      unlinkIfExists(socketPath);
      unlinkIfExists(tokenPath);
    }
  }

  async function showPiInterface() {
    if (piServer || stopped) return;
    piInterfaceReady = false;
    piInterfaceError = "Pi interface not ready";
    await removeStaleSocket(socketPath);
    unlinkIfExists(tokenPath);

    const token = randomBytes(32).toString("hex");
    const server = net.createServer((socket) => {
      piSockets.add(socket);
      let authenticated = false;
      let buffer = Buffer.alloc(0);

      socket.on("data", (chunk: Buffer) => {
        buffer = Buffer.concat([buffer, chunk]);

        let newline = buffer.indexOf(0x0a);
        while (newline !== -1) {
          const lineBuffer = buffer.subarray(0, newline);
          buffer = buffer.subarray(newline + 1);
          if (lineBuffer.byteLength > maxPayloadBytes) {
            buffer = Buffer.alloc(0);
            socket.destroy();
            return;
          }
          const line = lineBuffer.toString("utf8").trim();
          if (line) {
            try {
              const message = JSON.parse(line);
              if (!authenticated) {
                if (message?.type !== "AUTH" || message.token !== authToken) {
                  socket.destroy();
                  return;
                }
                authenticated = true;
                if (activePi && activePi !== socket && !activePi.destroyed) {
                  activePi.write(JSON.stringify({
                    type: "SESSION_REPLACED",
                    reason: "Another terminal started annotation",
                  }) + "\n");
                  activePi.end();
                }
                activePi = socket;
              } else if (activePi === socket && browser) {
                browser.send(line);
              }
            } catch {
              // Match the upstream native host: malformed Pi messages are dropped.
            }
          }
          newline = buffer.indexOf(0x0a);
        }

        if (buffer.byteLength > maxPayloadBytes) {
          buffer = Buffer.alloc(0);
          socket.destroy();
        }
      });

      socket.on("close", () => {
        piSockets.delete(socket);
        if (activePi === socket) activePi = null;
      });
      socket.on("error", () => {});
    });

    await new Promise<void>((resolve, reject) => {
      const onError = (error: Error) => reject(error);
      server.once("error", onError);
      server.listen(socketPath, () => {
        server.off("error", onError);
        resolve();
      });
    });

    ownsPiInterface = true;
    try {
      fs.chmodSync(socketPath, 0o600);
      fs.writeFileSync(tokenPath, token, { mode: 0o600 });
      fs.chmodSync(tokenPath, 0o600);
      authToken = token;
      piServer = server;
      piInterfaceReady = true;
      piInterfaceError = "";
    } catch (error) {
      server.close();
      ownsPiInterface = false;
      unlinkIfExists(socketPath);
      unlinkIfExists(tokenPath);
      throw error;
    }
  }

  function queueTransition(action: () => Promise<void>, reportError = true) {
    transition = transition.then(action, action).catch((error) => {
      if (reportError) {
        console.error(`[pi-annotate-relay] ${error instanceof Error ? error.message : String(error)}`);
      }
    });
  }

  queueTransition(async () => {
    await removeStaleSocket(socketPath);
    unlinkIfExists(tokenPath);
  }, false);

  const webServer = Bun.serve<undefined>({
    hostname: host,
    port: requestedPort,
    fetch(request, server) {
      if (!isExtensionOrigin(request.headers.get("origin"))) {
        return new Response("Forbidden", { status: 403 });
      }
      if (!server.upgrade(request)) return new Response("WebSocket upgrade required", { status: 426 });
    },
    websocket: {
      maxPayloadLength: maxPayloadBytes,
      open(ws) {
        const previous = browser;
        browser = ws;
        if (previous && previous !== ws) previous.close(1000, "Replaced by a newer browser connection");
        queueTransition(async () => {
          if (browser !== ws || stopped) return;
          try {
            await showPiInterface();
          } catch (error) {
            const message = error instanceof Error ? error.message : String(error);
            piInterfaceReady = false;
            piInterfaceError = message;
            console.error(`[pi-annotate-relay] ${message}`);
            if (browser === ws) ws.close(1011, "Pi interface unavailable");
          }
        });
      },
      message(ws, payload) {
        if (browser !== ws) return;
        const text = typeof payload === "string" ? payload : Buffer.from(payload).toString("utf8");
        if (Buffer.byteLength(text) > maxPayloadBytes) {
          ws.close(1009, "Message too large");
          return;
        }
        try {
          const message = JSON.parse(text);
          if (message?.type === "PING") {
            ws.send(JSON.stringify({
              type: "PONG",
              timestamp: Date.now(),
              ready: piInterfaceReady,
              error: piInterfaceReady ? null : piInterfaceError,
            }));
          } else if (activePi && !activePi.destroyed) {
            activePi.write(text + "\n");
          }
        } catch {
          // Match the upstream native host: malformed browser messages are dropped.
        }
      },
      close(ws) {
        if (browser !== ws) return;
        browser = null;
        queueTransition(async () => {
          if (!browser) await hidePiInterface();
        });
      },
    },
  });

  return {
    host,
    port: webServer.port,
    socketPath,
    tokenPath,
    async stop() {
      if (stopped) return;
      stopped = true;
      const currentBrowser = browser;
      browser = null;
      currentBrowser?.close(1001, "Relay shutting down");
      webServer.stop(true);
      await transition;
      await hidePiInterface();
    },
  };
}

if (import.meta.main) {
  process.umask(0o077);
  const relay = startRelay();
  console.log(`[pi-annotate-relay] listening on ws://${relay.host}:${relay.port}`);
  let shuttingDown = false;
  const shutdown = async () => {
    if (shuttingDown) return;
    shuttingDown = true;
    await relay.stop();
    process.exit(0);
  };
  process.on("SIGINT", shutdown);
  process.on("SIGTERM", shutdown);
}
