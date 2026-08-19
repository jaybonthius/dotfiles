import { expect, test } from "bun:test";

test("popup ping waits for a connecting relay socket and reuses one pending ping", async () => {
  type Listener = (event: any) => void;

  class MockWebSocket {
    static readonly CONNECTING = 0;
    static readonly OPEN = 1;
    static readonly CLOSING = 2;
    static readonly CLOSED = 3;

    readyState = MockWebSocket.CONNECTING;
    sent: string[] = [];
    private listeners = new Map<string, Listener[]>();

    constructor(readonly url: string) {
      sockets.push(this);
    }

    addEventListener(type: string, listener: Listener) {
      const listeners = this.listeners.get(type) ?? [];
      listeners.push(listener);
      this.listeners.set(type, listeners);
    }

    send(payload: string) {
      this.sent.push(payload);
    }

    emit(type: string, event: any = {}) {
      for (const listener of this.listeners.get(type) ?? []) listener(event);
    }
  }

  const sockets: MockWebSocket[] = [];
  let runtimeListener: ((message: any, sender: any, sendResponse: (response: any) => void) => boolean | void) | null = null;
  const originalWebSocket = globalThis.WebSocket;
  const originalChrome = (globalThis as any).chrome;
  const originalSetInterval = globalThis.setInterval;
  const originalClearInterval = globalThis.clearInterval;

  (globalThis as any).WebSocket = MockWebSocket;
  (globalThis as any).chrome = {
    runtime: {
      onMessage: {
        addListener(listener: typeof runtimeListener) {
          runtimeListener = listener;
        },
      },
    },
    commands: { onCommand: { addListener() {} } },
  };
  (globalThis as any).setInterval = () => 1;
  (globalThis as any).clearInterval = () => {};

  try {
    await import(`./background.js?cold-popup-test=${Date.now()}`);
    expect(sockets).toHaveLength(1);
    expect(sockets[0].readyState).toBe(MockWebSocket.CONNECTING);
    expect(runtimeListener).not.toBeNull();

    let firstResponse: any = null;
    let secondResponse: any = null;
    expect(runtimeListener!({ type: "CHECK_CONNECTION" }, {}, (response) => {
      firstResponse = response;
    })).toBe(true);
    expect(runtimeListener!({ type: "CHECK_CONNECTION" }, {}, (response) => {
      secondResponse = response;
    })).toBe(true);
    await Promise.resolve();
    expect(firstResponse).toBeNull();
    expect(secondResponse).toBeNull();
    expect(sockets[0].sent).toHaveLength(0);

    sockets[0].readyState = MockWebSocket.OPEN;
    sockets[0].emit("open");
    expect(sockets[0].sent.map((payload) => JSON.parse(payload))).toEqual([{ type: "PING" }]);
    sockets[0].emit("message", {
      data: JSON.stringify({ type: "PONG", ready: true, error: null }),
    });
    await Promise.resolve();
    expect(firstResponse).toEqual({ connected: true });
    expect(secondResponse).toEqual({ connected: true });
  } finally {
    globalThis.WebSocket = originalWebSocket;
    (globalThis as any).chrome = originalChrome;
    globalThis.setInterval = originalSetInterval;
    globalThis.clearInterval = originalClearInterval;
  }
});
