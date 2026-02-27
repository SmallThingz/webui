const webuiClientId = (() => {
  try {
    if (typeof globalThis !== "undefined" && globalThis.crypto && typeof globalThis.crypto.randomUUID === "function") {
      return globalThis.crypto.randomUUID();
    }
  } catch (_) {}
  return `webui-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 10)}`;
})();

function webuiRequestHeaders(extraHeaders) {
  const headers = Object.assign({}, extraHeaders || {});
  headers["x-webui-client-id"] = webuiClientId;
  return headers;
}

async function webuiInvoke(endpoint, name, args) {
  const payload = JSON.stringify({ name, args });
  const res = await fetch(endpoint, {
    method: "POST",
    headers: webuiRequestHeaders({ "content-type": "application/json" }),
    body: payload,
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`RPC ${name} failed: ${res.status} ${text}`);
  }
  const contentType = res.headers.get("content-type") || "";
  if (contentType.includes("application/json")) {
    return await res.json();
  }

  const text = await res.text();
  if (!text || !text.trim()) return null;
  try {
    return JSON.parse(text);
  } catch (_) {
    return text;
  }
}

async function webuiJson(endpoint, options) {
  const reqOptions = Object.assign({}, options || {});
  reqOptions.headers = webuiRequestHeaders(reqOptions.headers || {});
  const res = await fetch(endpoint, reqOptions);
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`HTTP ${res.status} ${endpoint}: ${text}`);
  }

  const contentType = res.headers.get("content-type") || "";
  if (contentType.includes("application/json")) {
    return await res.json();
  }

  const text = await res.text();
  if (!text || !text.trim()) return {};
  try {
    return JSON.parse(text);
  } catch (_) {
    return text;
  }
}

const webuiSocketConnectTimeoutMs = 10000;

function webuiSleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function webuiWaitForSocketReady(timeoutMs) {
  const deadline = Date.now() + Math.max(50, timeoutMs || webuiSocketConnectTimeoutMs);
  while (Date.now() < deadline) {
    if (webuiSocketOpen && webuiSocket && webuiSocket.readyState === globalThis.WebSocket.OPEN) return;
    if (webuiSocketStopped) break;
    webuiConnectPushSocket();
    await webuiSleep(40);
  }
  throw new Error("WebSocket unavailable");
}

async function webuiSendObjectWithBackoff(message, timeoutMs, label) {
  const totalTimeout = Math.max(200, timeoutMs || webuiSocketConnectTimeoutMs);
  const deadline = Date.now() + totalTimeout;
  let delayMs = 40;

  while (Date.now() < deadline) {
    if (webuiSocketOpen && webuiSocketSendObject(message)) return;
    const remaining = deadline - Date.now();
    if (remaining <= 0) break;
    try {
      await webuiWaitForSocketReady(Math.min(remaining, 1200));
    } catch (_) {}
    if (webuiSocketOpen && webuiSocketSendObject(message)) return;
    await webuiSleep(Math.min(delayMs, Math.max(10, deadline - Date.now())));
    delayMs = Math.min(500, Math.floor(delayMs * 1.7));
  }

  throw new Error(`${label || "socket send"} timed out`);
}

let webuiWindowRuntimeEmulationEnabled = true;
let webuiWindowRuntimeLoaded = false;

function webuiApplyStyleEmulation(style) {
  if (!style || typeof document === "undefined") return;
  const root = document.documentElement;
  const body = document.body;
  if (!root) return;

  root.classList.toggle("webui-frameless", !!style.frameless);
  root.classList.toggle("webui-high-contrast", style.high_contrast === true);
  root.classList.toggle("webui-transparent", style.transparent === true);

  if (style.transparent === true) {
    root.style.background = "transparent";
    if (body) {
      body.style.background = "transparent";
      body.classList.add("webui-window-shadowed");
    }
  }

  if (style.transparent === false) {
    root.style.removeProperty("background");
    if (body) {
      body.style.removeProperty("background");
      body.classList.remove("webui-window-shadowed");
    }
  }

  if (typeof style.hidden === "boolean" && body) {
    body.style.visibility = style.hidden ? "hidden" : "visible";
  }
}

async function webuiRunControlEmulation(mode) {
  if (mode === "minimize_blur") {
    if (typeof globalThis.blur === "function") globalThis.blur();
    return;
  }

  if (mode === "maximize_fullscreen") {
    if (typeof document !== "undefined" && !document.fullscreenElement && document.documentElement && document.documentElement.requestFullscreen) {
      await document.documentElement.requestFullscreen();
    }
    return;
  }

  if (mode === "restore_fullscreen") {
    if (typeof document !== "undefined" && document.fullscreenElement && document.exitFullscreen) {
      await document.exitFullscreen();
    }
    return;
  }

  if (mode === "hide_page") {
    if (typeof document !== "undefined" && document.body) {
      document.body.style.visibility = "hidden";
    }
    return;
  }

  if (mode === "show_page") {
    if (typeof document !== "undefined" && document.body) {
      document.body.style.visibility = "visible";
    }
    return;
  }

  if (mode === "close_window") {
    await webuiNotifyLifecycle("window_closing");
  }
}

async function webuiWindowControl(cmd) {
  const body = JSON.stringify({ cmd });
  let result;
  try {
    result = await webuiJson("/webui/window/control", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body,
      keepalive: cmd === "close",
    });
  } catch (err) {
    if (cmd === "close") {
      try {
        await webuiNotifyLifecycle("window_closing");
      } catch (_) {}
      return {
        success: false,
        emulation: null,
        closed: false,
        warning: "close control fallback: backend unreachable",
      };
    }
    throw err;
  }

  if (result && typeof result === "object" && typeof result.emulation === "string") {
    await webuiRunControlEmulation(result.emulation);
  }

  if (result && typeof result === "object" && typeof result.warning === "string" && result.warning.length > 0) {
    try {
      if (typeof console !== "undefined" && typeof console.warn === "function") {
        console.warn("[webui.warning]", result.warning);
      }
    } catch (_) {}
  }

  return result;
}

async function webuiWindowStyle(stylePatch) {
  if (!webuiWindowRuntimeLoaded) {
    await webuiGetWindowCapabilities().catch(() => {});
  }
  const base = await webuiGetWindowStyle().catch(() => ({}));
  const merged = Object.assign({}, base || {}, stylePatch || {});
  const body = JSON.stringify(merged);
  const style = await webuiJson("/webui/window/style", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body,
  });
  if (webuiWindowRuntimeEmulationEnabled) {
    webuiApplyStyleEmulation(style);
  }
  return style;
}

async function webuiGetWindowStyle() {
  if (!webuiWindowRuntimeLoaded) {
    await webuiGetWindowCapabilities().catch(() => {});
  }
  const style = await webuiJson("/webui/window/style");
  if (webuiWindowRuntimeEmulationEnabled) {
    webuiApplyStyleEmulation(style);
  }
  return style;
}

async function webuiGetWindowCapabilities() {
  const payload = await webuiJson("/webui/window/control");
  if (payload && typeof payload === "object") {
    if ("emulation_enabled" in payload) {
      webuiWindowRuntimeEmulationEnabled = !!payload.emulation_enabled;
    }
  }
  webuiWindowRuntimeLoaded = true;
  return payload;
}

let webuiSocket = null;
let webuiSocketOpen = false;
let webuiSocketStopped = false;
let webuiSocketReconnectDelayMs = 120;

function webuiSocketUrl() {
  try {
    if (typeof globalThis === "undefined" || !globalThis.location) return null;
    const url = new URL(globalThis.location.href);
    url.protocol = url.protocol === "https:" ? "wss:" : "ws:";
    url.pathname = "/webui/ws";
    url.search = `client_id=${encodeURIComponent(webuiClientId)}`;
    return url.toString();
  } catch (_) {
    return null;
  }
}

function webuiSocketSendObject(value) {
  let payload;
  try {
    payload = JSON.stringify(value);
  } catch (_) {
    return false;
  }

  if (webuiSocketOpen && webuiSocket && typeof webuiSocket.send === "function") {
    try {
      webuiSocket.send(payload);
      return true;
    } catch (_) {
      return false;
    }
  }
  return false;
}

function webuiSendCloseAck(closeSignalId) {
  const id = Number(closeSignalId);
  if (!Number.isFinite(id) || id <= 0) return false;
  return webuiSocketSendObject({
    type: "close_ack",
    id: Math.trunc(id),
    client_id: webuiClientId,
  });
}

function webuiHandleBackendClose(message) {
  webuiSendCloseAck(message && message.id);
  webuiSocketStopped = true;
  setTimeout(() => {
    if (typeof globalThis.close === "function") {
      try {
        globalThis.close();
      } catch (_) {}
    }
  }, 0);
}

function webuiHandleSocketMessage(raw) {
  let payload = raw;
  if (payload && typeof payload !== "string" && typeof payload.data === "string") {
    payload = payload.data;
  }
  if (typeof payload !== "string" || payload.length === 0) return;

  let message;
  try {
    message = JSON.parse(payload);
  } catch (_) {
    return;
  }

  if (!message || typeof message !== "object") return;
  if (message.type === "backend_close") {
    webuiHandleBackendClose(message);
    return;
  }
  if (message.type !== "script_task") return;
  if (typeof message.script !== "string") return;
  void webuiExecuteScriptTask(message);
}

function webuiConnectPushSocket() {
  if (typeof globalThis === "undefined") return;
  if (webuiSocketStopped) return;
  if (typeof globalThis.WebSocket !== "function") return;
  if (webuiSocket && (webuiSocket.readyState === globalThis.WebSocket.CONNECTING || webuiSocket.readyState === globalThis.WebSocket.OPEN)) return;

  const url = webuiSocketUrl();
  if (!url) return;

  let socket;
  try {
    socket = new globalThis.WebSocket(url);
  } catch (_) {
    setTimeout(webuiConnectPushSocket, Math.min(2000, webuiSocketReconnectDelayMs * 2));
    return;
  }

  webuiSocket = socket;
  socket.onopen = () => {
    webuiSocketOpen = true;
    webuiSocketReconnectDelayMs = 120;
  };
  socket.onmessage = (event) => {
    webuiHandleSocketMessage(event);
  };
  socket.onerror = () => {};
  socket.onclose = () => {
    webuiSocketOpen = false;
    webuiSocket = null;
    if (webuiSocketStopped) return;
    const delay = Math.min(1500, webuiSocketReconnectDelayMs);
    webuiSocketReconnectDelayMs = Math.min(2500, webuiSocketReconnectDelayMs * 2);
    setTimeout(webuiConnectPushSocket, delay);
  };
}

async function webuiNotifyLifecycle(eventName) {
  // WS-only lifecycle signaling: no fetch/sendBeacon fallback.
  await webuiSendObjectWithBackoff({
    type: "lifecycle",
    event: eventName,
    client_id: webuiClientId,
  }, webuiSocketConnectTimeoutMs, "lifecycle send");
}

async function webuiExecuteScriptTask(task) {
  let js_error = false;
  let value = null;
  let error_message = null;

  try {
    const runner = new Function(`return (async () => {\n${task.script}\n})();`);
    const result = await runner();
    value = typeof result === "undefined" ? null : result;
  } catch (err) {
    js_error = true;
    error_message = String(err);
  }

  if (!task.expect_result) return;
  const responsePayload = {
    type: "script_response",
    id: task.id,
    js_error,
    value,
    error_message,
    client_id: webuiClientId,
    connection_id: task.connection_id,
  };
  try {
    // WS-only script response path. Backend dispatches tasks over WS and expects
    // completion over WS using the same request id.
    await webuiSendObjectWithBackoff(responsePayload, webuiSocketConnectTimeoutMs, `script response ${task.id}`);
  } catch (_) {}
}

(function webuiInstallPushChannel() {
  if (typeof globalThis === "undefined") return;
  if (globalThis.webuiPushInstalled) return;
  globalThis.webuiPushInstalled = true;

  if (typeof globalThis.addEventListener === "function") {
    globalThis.addEventListener("beforeunload", () => {
      // Best-effort lifecycle close signal for browser-window mode.
      // Backend intentionally applies a grace timeout before honoring this
      // close so page refresh/reload can reconnect without killing runtime.
      webuiSocketSendObject({
        type: "lifecycle",
        event: "window_closing",
        client_id: webuiClientId,
      });
      webuiSocketStopped = true;
      webuiSocketOpen = false;
      // Let the browser own socket teardown during unload.
    });
  }
  webuiConnectPushSocket();
})();

(function webuiInstallLifecycleHooks() {
  if (typeof globalThis === "undefined") return;
  globalThis.webuiNotifyLifecycle = webuiNotifyLifecycle;
  globalThis.webuiWindowControl = webuiWindowControl;
  globalThis.webuiWindowStyle = webuiWindowStyle;
  globalThis.webuiGetWindowStyle = webuiGetWindowStyle;
  globalThis.webuiGetWindowCapabilities = webuiGetWindowCapabilities;
})();
