/**
 * Pi Annotate - Background Service Worker
 *
 * Connects to the Linux relay through an SSH-forwarded WebSocket and
 * forwards messages between Pi and content scripts.
 */

const RELAY_URL = "ws://127.0.0.1:43173";
const HEARTBEAT_INTERVAL_MS = 20000;
const RECONNECT_DELAY_MS = 2000;

let relaySocket = null;
let reconnectTimer = null;
let heartbeatTimer = null;
let pendingPing = null;
let lastRelayDisconnectError = "";
const requestTabs = new Map();

function getRequestId(msg) {
  return typeof msg.requestId === "number" ? msg.requestId : (typeof msg.id === "number" ? msg.id : null);
}

function isRestrictedUrl(url) {
  if (!url) return true;
  return /^(chrome|chrome-extension|edge|about|devtools|view-source):/.test(url);
}

function resolvePendingPing(result) {
  if (!pendingPing) return;
  clearTimeout(pendingPing.timeoutId);
  pendingPing.resolve(result);
  pendingPing = null;
}

function sendPendingPing(socket) {
  if (!pendingPing || pendingPing.socket !== socket || pendingPing.sent) return;
  if (relaySocket !== socket || socket.readyState !== WebSocket.OPEN) return;
  pendingPing.sent = true;
  try {
    socket.send(JSON.stringify({ type: "PING" }));
  } catch (err) {
    resolvePendingPing({
      connected: false,
      error: err instanceof Error ? err.message : String(err),
    });
  }
}

function pingRelay() {
  if (pendingPing) return pendingPing.promise;

  const socket = relaySocket;
  if (!socket || ![WebSocket.CONNECTING, WebSocket.OPEN].includes(socket.readyState)) {
    return Promise.resolve({
      connected: false,
      error: lastRelayDisconnectError || "Relay not connected",
    });
  }

  let resolvePing;
  const promise = new Promise((resolve) => {
    resolvePing = resolve;
  });

  const timeoutId = setTimeout(() => {
    if (!pendingPing || pendingPing.promise !== promise) return;
    pendingPing = null;
    resolvePing({ connected: false, error: "Timeout - relay not responding" });
  }, 3000);

  pendingPing = { promise, resolve: resolvePing, timeoutId, socket, sent: false };
  sendPendingPing(socket);
  return promise;
}

function sendToNative(msg) {
  if (!relaySocket || relaySocket.readyState !== WebSocket.OPEN) {
    console.error("[pi-annotate] Cannot send to relay - not connected");
    return;
  }
  try {
    relaySocket.send(JSON.stringify(msg));
  } catch (err) {
    console.error("[pi-annotate] Failed to send to relay:", err);
  }
}

// Send message to content script, injecting it first if needed
async function sendToContentScript(tabId, msg) {
  try {
    await chrome.tabs.sendMessage(tabId, msg);
  } catch (err) {
    console.log("[pi-annotate] Content script not found, injecting...");
    try {
      await chrome.scripting.executeScript({
        target: { tabId },
        files: ["content.js"],
      });
      await new Promise(r => setTimeout(r, 100));
      await chrome.tabs.sendMessage(tabId, msg);
    } catch (injectErr) {
      console.error("[pi-annotate] Failed to inject:", injectErr.message);
      const requestId = getRequestId(msg);
      if (requestId) {
        requestTabs.delete(requestId);
        sendToNative({ type: "CANCEL", requestId, reason: `Cannot inject into tab: ${injectErr.message}` });
      }
    }
  }
}

// Wait for a tab to finish loading, then inject content script
function injectAfterLoad(tabId, msg, requestId) {
  let timeoutId = null;
  const listener = (updatedTabId, info) => {
    if (updatedTabId === tabId && info.status === "complete") {
      if (timeoutId) clearTimeout(timeoutId);
      chrome.tabs.onUpdated.removeListener(listener);
      setTimeout(() => {
        if (requestId) requestTabs.set(requestId, tabId);
        sendToContentScript(tabId, msg);
      }, 150);
    }
  };
  chrome.tabs.onUpdated.addListener(listener);

  timeoutId = setTimeout(() => {
    chrome.tabs.onUpdated.removeListener(listener);
    console.log("[pi-annotate] Navigation timeout - listener removed");
    if (requestId) {
      requestTabs.delete(requestId);
      sendToNative({ type: "CANCEL", requestId, reason: "navigation_timeout" });
    }
  }, 30000);
}

// Toggle annotation picker on active tab (used by popup + keyboard shortcut)
async function togglePicker() {
  try {
    const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
    if (!tab?.id || isRestrictedUrl(tab.url)) {
      console.log("[pi-annotate] Cannot toggle picker: no valid tab");
      return;
    }
    await sendToContentScript(tab.id, { type: "TOGGLE_PICKER" });
  } catch (err) {
    console.error("[pi-annotate] Toggle picker failed:", err);
  }
}

function scheduleReconnect() {
  if (reconnectTimer) return;
  reconnectTimer = setTimeout(() => {
    reconnectTimer = null;
    connectRelay();
  }, RECONNECT_DELAY_MS);
}

function connectRelay() {
  if (relaySocket && [WebSocket.CONNECTING, WebSocket.OPEN].includes(relaySocket.readyState)) return;

  console.log("[pi-annotate] Connecting to relay...");
  const socket = new WebSocket(RELAY_URL);
  relaySocket = socket;

  socket.addEventListener("open", () => {
    if (relaySocket !== socket) return;
    lastRelayDisconnectError = "";
    sendPendingPing(socket);
    clearInterval(heartbeatTimer);
    heartbeatTimer = setInterval(() => {
      if (relaySocket === socket && socket.readyState === WebSocket.OPEN) {
        socket.send(JSON.stringify({ type: "PING" }));
      }
    }, HEARTBEAT_INTERVAL_MS);
  });

  socket.addEventListener("message", (event) => {
    let msg;
    try {
      msg = JSON.parse(event.data);
    } catch (err) {
      console.error("[pi-annotate] Invalid relay message:", err);
      return;
    }

    if (msg?.type === "PONG") {
      const error = typeof msg.error === "string" && msg.error ? msg.error : "Pi interface not ready";
      lastRelayDisconnectError = msg.ready === true ? "" : error;
      resolvePendingPing(msg.ready === true ? { connected: true } : { connected: false, error });
      return;
    }

    console.log("[pi-annotate] From relay:", msg);
    
    chrome.tabs.query({ active: true, currentWindow: true }, (tabs) => {
      if (!tabs[0]?.id) {
        console.log("[pi-annotate] No active tab found");
        const requestId = getRequestId(msg);
        if (requestId) {
          sendToNative({ type: "CANCEL", requestId, reason: "No active browser tab found" });
        }
        return;
      }
      
      const requestId = getRequestId(msg);
      const tabId = requestId && requestTabs.has(requestId) ? requestTabs.get(requestId) : tabs[0].id;
      const currentUrl = tabs[0].url;
      
      if (msg.type === "START_ANNOTATION") {
        const restricted = isRestrictedUrl(currentUrl);

        if (msg.url && (restricted || currentUrl !== msg.url)) {
          if (restricted) {
            console.log("[pi-annotate] Opening new tab:", msg.url);
            chrome.tabs.create({ url: msg.url }, (tab) => {
              if (chrome.runtime.lastError) {
                console.error("[pi-annotate] Failed to create tab:", chrome.runtime.lastError.message);
                sendToNative({ type: "CANCEL", requestId, reason: chrome.runtime.lastError.message });
                return;
              }
              injectAfterLoad(tab.id, msg, requestId);
            });
          } else {
            console.log("[pi-annotate] Navigating to:", msg.url);
            chrome.tabs.update(tabId, { url: msg.url }, (tab) => {
              if (chrome.runtime.lastError) {
                console.error("[pi-annotate] Failed to navigate:", chrome.runtime.lastError.message);
                sendToNative({ type: "CANCEL", requestId, reason: chrome.runtime.lastError.message });
                return;
              }
              injectAfterLoad(tab.id, msg, requestId);
            });
          }
        } else if (restricted) {
          console.log("[pi-annotate] Cannot annotate restricted tab:", currentUrl);
          if (requestId) {
            sendToNative({ type: "CANCEL", requestId, reason: "Current tab cannot be annotated (restricted URL). Provide a URL." });
          }
        } else {
          console.log("[pi-annotate] Activating on current tab:", currentUrl);
          if (requestId) requestTabs.set(requestId, tabId);
          sendToContentScript(tabId, msg);
        }
      } else {
        sendToContentScript(tabId, msg);
      }
    });
  });

  socket.addEventListener("error", () => {
    if (relaySocket === socket) lastRelayDisconnectError = `Cannot reach ${RELAY_URL}`;
  });

  socket.addEventListener("close", (event) => {
    if (relaySocket !== socket) return;
    const error = event.reason || lastRelayDisconnectError || "Relay disconnected unexpectedly";
    console.log("[pi-annotate] Relay disconnected", error);
    lastRelayDisconnectError = error;
    resolvePendingPing({ connected: false, error });
    relaySocket = null;
    clearInterval(heartbeatTimer);
    heartbeatTimer = null;
    scheduleReconnect();
  });
}

// Handle messages from content script and popup
chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  console.log("[pi-annotate] Message:", msg.type);
  
  if (msg.type === "CHECK_CONNECTION") {
    pingRelay().then(sendResponse);
    return true;
  }

  if (msg.type === "TOGGLE_PICKER") {
    togglePicker();
    return;
  }
  
  const requestId = getRequestId(msg);
  
  if (msg.type === "CAPTURE_SCREENSHOT") {
    if (!sender.tab?.windowId) {
      console.log("[pi-annotate] Screenshot failed: No window ID");
      sendResponse({ error: "No window ID" });
      return true;
    }
    chrome.tabs.captureVisibleTab(sender.tab.windowId, { format: "png" }, (dataUrl) => {
      if (chrome.runtime.lastError) {
        console.log("[pi-annotate] Screenshot error:", chrome.runtime.lastError.message);
        sendResponse({ error: chrome.runtime.lastError.message });
      } else {
        console.log("[pi-annotate] Screenshot captured, size:", dataUrl?.length || 0);
        sendResponse({ dataUrl });
      }
    });
    return true;
  }
  
  if (["ANNOTATIONS_COMPLETE", "CANCEL"].includes(msg.type)) {
    if (requestId) requestTabs.delete(requestId);
    console.log("[pi-annotate] Forwarding to relay:", msg.type);
    sendToNative(msg);
  }
});

// Handle keyboard shortcut
chrome.commands.onCommand.addListener((command) => {
  if (command === "toggle-picker") {
    togglePicker();
  }
});

// Connect on startup
connectRelay();
console.log("[pi-annotate] Background script loaded");
