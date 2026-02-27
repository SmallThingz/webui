const __webuiClientId = (() => {
  try {
    if (typeof globalThis !== "undefined" && globalThis.crypto && typeof globalThis.crypto.randomUUID === "function") {
      return globalThis.crypto.randomUUID();
    }
  } catch (_) {}
  return `webui-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 10)}`;
})();

function __webuiRequestHeaders(extraHeaders) {
  const headers = Object.assign({}, extraHeaders || {});
  headers["x-webui-client-id"] = __webuiClientId;
  return headers;
}

async function __webuiInvoke(endpoint, name, args) {
  const payload = JSON.stringify({ name, args });
  const res = await fetch(endpoint, {
    method: "POST",
    headers: __webuiRequestHeaders({ "content-type": "application/json" }),
    body: payload,
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`RPC ${name} failed: ${res.status} ${text}`);
  }
  return await res.json();
}

async function __webuiJson(endpoint, options) {
  const reqOptions = Object.assign({}, options || {});
  reqOptions.headers = __webuiRequestHeaders(reqOptions.headers || {});
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
    return { value: text };
  }
}

function __webuiNormalizeResult(result) {
  if (result && typeof result === "object" && "value" in result) {
    return result.value;
  }
  return result;
}

const __webuiSocketConnectTimeoutMs = 10000;

function __webuiSleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function __webuiWaitForSocketReady(timeoutMs) {
  const deadline = Date.now() + Math.max(50, timeoutMs || __webuiSocketConnectTimeoutMs);
  while (Date.now() < deadline) {
    if (__webuiSocketOpen && __webuiSocket && __webuiSocket.readyState === globalThis.WebSocket.OPEN) return;
    if (__webuiSocketStopped) break;
    __webuiConnectPushSocket();
    await __webuiSleep(40);
  }
  throw new Error("WebSocket unavailable");
}

async function __webuiSendObjectWithBackoff(message, timeoutMs, label) {
  const totalTimeout = Math.max(200, timeoutMs || __webuiSocketConnectTimeoutMs);
  const deadline = Date.now() + totalTimeout;
  let delayMs = 40;

  while (Date.now() < deadline) {
    if (__webuiSocketOpen && __webuiSocketSendObject(message)) return;
    const remaining = deadline - Date.now();
    if (remaining <= 0) break;
    try {
      await __webuiWaitForSocketReady(Math.min(remaining, 1200));
    } catch (_) {}
    if (__webuiSocketOpen && __webuiSocketSendObject(message)) return;
    await __webuiSleep(Math.min(delayMs, Math.max(10, deadline - Date.now())));
    delayMs = Math.min(500, Math.floor(delayMs * 1.7));
  }

  throw new Error(`${label || "socket send"} timed out`);
}

let __webuiWindowRuntimeEmulationEnabled = true;
let __webuiWindowRuntimeLoaded = false;

function __webuiApplyStyleEmulation(style) {
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

async function __webuiRunControlEmulation(mode) {
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
    await __webuiNotifyLifecycle("window_closing");
  }
}

async function __webuiWindowControl(cmd) {
  const body = JSON.stringify({ cmd });
  let result;
  try {
    result = await __webuiJson("/webui/window/control", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body,
      keepalive: cmd === "close",
    });
  } catch (err) {
    if (cmd === "close") {
      try {
        await __webuiNotifyLifecycle("window_closing");
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
    await __webuiRunControlEmulation(result.emulation);
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

async function __webuiWindowStyle(stylePatch) {
  if (!__webuiWindowRuntimeLoaded) {
    await __webuiGetWindowCapabilities().catch(() => {});
  }
  const base = await __webuiGetWindowStyle().catch(() => ({}));
  const merged = Object.assign({}, base || {}, stylePatch || {});
  const body = JSON.stringify(merged);
  const style = await __webuiJson("/webui/window/style", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body,
  });
  if (__webuiWindowRuntimeEmulationEnabled) {
    __webuiApplyStyleEmulation(style);
  }
  return style;
}

async function __webuiGetWindowStyle() {
  if (!__webuiWindowRuntimeLoaded) {
    await __webuiGetWindowCapabilities().catch(() => {});
  }
  const style = await __webuiJson("/webui/window/style");
  if (__webuiWindowRuntimeEmulationEnabled) {
    __webuiApplyStyleEmulation(style);
  }
  return style;
}

async function __webuiGetWindowCapabilities() {
  const payload = await __webuiJson("/webui/window/control");
  if (payload && typeof payload === "object") {
    if ("emulation_enabled" in payload) {
      __webuiWindowRuntimeEmulationEnabled = !!payload.emulation_enabled;
    }
  }
  __webuiWindowRuntimeLoaded = true;
  return payload;
}

let __webuiSocket = null;
let __webuiSocketOpen = false;
let __webuiSocketStopped = false;
let __webuiSocketReconnectDelayMs = 120;

function __webuiSocketUrl() {
  try {
    if (typeof globalThis === "undefined" || !globalThis.location) return null;
    const url = new URL(globalThis.location.href);
    url.protocol = url.protocol === "https:" ? "wss:" : "ws:";
    url.pathname = "/webui/ws";
    url.search = `client_id=${encodeURIComponent(__webuiClientId)}`;
    return url.toString();
  } catch (_) {
    return null;
  }
}

function __webuiSocketSendObject(value) {
  let payload;
  try {
    payload = JSON.stringify(value);
  } catch (_) {
    return false;
  }

  if (__webuiSocketOpen && __webuiSocket && typeof __webuiSocket.send === "function") {
    try {
      __webuiSocket.send(payload);
      return true;
    } catch (_) {
      return false;
    }
  }
  return false;
}

function __webuiSendCloseAck(closeSignalId) {
  const id = Number(closeSignalId);
  if (!Number.isFinite(id) || id <= 0) return false;
  return __webuiSocketSendObject({
    type: "close_ack",
    id: Math.trunc(id),
    client_id: __webuiClientId,
  });
}

function __webuiHandleBackendClose(message) {
  __webuiSendCloseAck(message && message.id);
  __webuiSocketStopped = true;
  setTimeout(() => {
    if (typeof globalThis.close === "function") {
      try {
        globalThis.close();
      } catch (_) {}
    }
  }, 0);
}

function __webuiHandleSocketMessage(raw) {
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
    __webuiHandleBackendClose(message);
    return;
  }
  if (message.type !== "script_task") return;
  if (typeof message.script !== "string") return;
  void __webuiExecuteScriptTask(message);
}

function __webuiConnectPushSocket() {
  if (typeof globalThis === "undefined") return;
  if (__webuiSocketStopped) return;
  if (typeof globalThis.WebSocket !== "function") return;
  if (__webuiSocket && (__webuiSocket.readyState === globalThis.WebSocket.CONNECTING || __webuiSocket.readyState === globalThis.WebSocket.OPEN)) return;

  const url = __webuiSocketUrl();
  if (!url) return;

  let socket;
  try {
    socket = new globalThis.WebSocket(url);
  } catch (_) {
    setTimeout(__webuiConnectPushSocket, Math.min(2000, __webuiSocketReconnectDelayMs * 2));
    return;
  }

  __webuiSocket = socket;
  socket.onopen = () => {
    __webuiSocketOpen = true;
    __webuiSocketReconnectDelayMs = 120;
  };
  socket.onmessage = (event) => {
    __webuiHandleSocketMessage(event);
  };
  socket.onerror = () => {};
  socket.onclose = () => {
    __webuiSocketOpen = false;
    __webuiSocket = null;
    if (__webuiSocketStopped) return;
    const delay = Math.min(1500, __webuiSocketReconnectDelayMs);
    __webuiSocketReconnectDelayMs = Math.min(2500, __webuiSocketReconnectDelayMs * 2);
    setTimeout(__webuiConnectPushSocket, delay);
  };
}

async function __webuiNotifyLifecycle(eventName) {
  // WS-only lifecycle signaling: no fetch/sendBeacon fallback.
  await __webuiSendObjectWithBackoff({
    type: "lifecycle",
    event: eventName,
    client_id: __webuiClientId,
  }, __webuiSocketConnectTimeoutMs, "lifecycle send");
}

async function __webuiExecuteScriptTask(task) {
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
    client_id: __webuiClientId,
    connection_id: task.connection_id,
  };
  try {
    // WS-only script response path. Backend dispatches tasks over WS and expects
    // completion over WS using the same request id.
    await __webuiSendObjectWithBackoff(responsePayload, __webuiSocketConnectTimeoutMs, `script response ${task.id}`);
  } catch (_) {}
}

(function __webuiInstallPushChannel() {
  if (typeof globalThis === "undefined") return;
  if (globalThis.__webuiPushInstalled) return;
  globalThis.__webuiPushInstalled = true;

  if (typeof globalThis.addEventListener === "function") {
    globalThis.addEventListener("beforeunload", () => {
      __webuiSocketStopped = true;
      __webuiSocketOpen = false;
      if (__webuiSocket && typeof __webuiSocket.close === "function") {
        try {
          __webuiSocket.close();
        } catch (_) {}
      }
      __webuiSocket = null;
    });
  }
  __webuiConnectPushSocket();
})();

(function __webuiInstallLifecycleHooks() {
  if (typeof globalThis === "undefined") return;
  globalThis.__webuiNotifyLifecycle = __webuiNotifyLifecycle;
  globalThis.__webuiWindowControl = __webuiWindowControl;
  globalThis.__webuiWindowStyle = __webuiWindowStyle;
  globalThis.__webuiGetWindowStyle = __webuiGetWindowStyle;
  globalThis.__webuiGetWindowCapabilities = __webuiGetWindowCapabilities;
})();

