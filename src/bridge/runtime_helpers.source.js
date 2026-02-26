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
  const body = await res.json();
  if (body && typeof body === "object" && Number.isFinite(Number(body.job_id))) {
    const jobId = Math.trunc(Number(body.job_id));
    const pollMin = Number.isFinite(Number(body.poll_min_ms)) ? Math.max(50, Math.trunc(Number(body.poll_min_ms))) : 200;
    const pollMax = Number.isFinite(Number(body.poll_max_ms)) ? Math.max(pollMin, Math.trunc(Number(body.poll_max_ms))) : 1000;
    return await __webuiAwaitRpcJob(endpoint, jobId, pollMin, pollMax);
  }
  return body;
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

const __webuiRpcJobWaiters = new Map();

function __webuiHasActivePushSocket() {
  if (typeof globalThis === "undefined" || typeof globalThis.WebSocket !== "function") return false;
  if (__webuiSocketStopped) return false;
  if (__webuiSocketOpen) return true;
  if (__webuiSocket && __webuiSocket.readyState === globalThis.WebSocket.CONNECTING) return true;
  return false;
}

async function __webuiFetchRpcJobStatus(endpoint, jobId) {
  const url = new URL("/rpc/job", globalThis.location ? globalThis.location.href : endpoint);
  url.searchParams.set("id", String(jobId));
  return await __webuiJson(url.toString(), { method: "GET" });
}

async function __webuiAwaitRpcJob(endpoint, jobId, pollMinMs, pollMaxMs) {
  let stopped = false;
  let timer = null;
  let currentDelay = pollMinMs;
  let pollingStarted = false;

  return await new Promise((resolve, reject) => {
    const cleanup = () => {
      stopped = true;
      if (timer) clearTimeout(timer);
      timer = null;
      __webuiRpcJobWaiters.delete(jobId);
    };

    const failWithState = (status, fallbackMessage) => {
      const message = status && typeof status.error_message === "string" && status.error_message.length > 0
        ? status.error_message
        : fallbackMessage;
      reject(new Error(message));
    };

    const startPolling = () => {
      if (stopped || pollingStarted) return;
      pollingStarted = true;
      currentDelay = pollMinMs;
      void poll();
    };

    const schedulePoll = () => {
      if (stopped || !pollingStarted) return;
      timer = setTimeout(() => {
        void poll();
      }, currentDelay);
      currentDelay = Math.min(pollMaxMs, Math.max(pollMinMs, Math.floor(currentDelay * 1.6)));
    };

    const poll = async () => {
      if (stopped) return;
      try {
        const status = await __webuiFetchRpcJobStatus(endpoint, jobId);
        const state = status && typeof status.state === "string" ? status.state : "queued";
        if (state === "completed") {
          cleanup();
          resolve({ value: "value" in status ? status.value : null });
          return;
        }
        if (state === "failed") {
          cleanup();
          failWithState(status, `RPC job ${jobId} failed`);
          return;
        }
        if (state === "canceled") {
          cleanup();
          failWithState(status, `RPC job ${jobId} canceled`);
          return;
        }
        if (state === "timed_out") {
          cleanup();
          failWithState(status, `RPC job ${jobId} timed out`);
          return;
        }
      } catch (_) {
        // Keep bounded fallback polling on transient transport errors.
      }
      schedulePoll();
    };

    __webuiRpcJobWaiters.set(jobId, {
      trigger() {
        if (stopped) return;
        if (!pollingStarted) {
          startPolling();
          return;
        }
        currentDelay = pollMinMs;
        if (timer) clearTimeout(timer);
        timer = null;
        void poll();
      },
    });

    // Push-first: when the WS channel is live/connecting, allow push to drive completion
    // and only activate polling as a delayed fallback.
    if (__webuiHasActivePushSocket()) {
      const delayedFallbackMs = Math.max(400, Math.min(4000, pollMinMs * 8));
      timer = setTimeout(() => {
        timer = null;
        startPolling();
      }, delayedFallbackMs);
    } else {
      startPolling();
    }
  });
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
let __webuiSocketQueue = [];
let __webuiSocketEverOpened = false;
let __webuiSocketFailedAttempts = 0;
const __webuiSocketMaxFailedAttemptsBeforeStop = 8;

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

  if (__webuiSocketQueue.length < 256) {
    __webuiSocketQueue.push(payload);
  }
  return false;
}

function __webuiSocketFlushQueue() {
  if (!__webuiSocketOpen || !__webuiSocket || typeof __webuiSocket.send !== "function") return;
  while (__webuiSocketQueue.length > 0) {
    const payload = __webuiSocketQueue.shift();
    if (!payload) continue;
    try {
      __webuiSocket.send(payload);
    } catch (_) {
      __webuiSocketQueue.unshift(payload);
      break;
    }
  }
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
  if (message.type === "rpc_job_update") {
    const id = Number(message.job_id);
    if (Number.isFinite(id)) {
      const waiter = __webuiRpcJobWaiters.get(Math.trunc(id));
      if (waiter && typeof waiter.trigger === "function") waiter.trigger();
    }
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
  if (!__webuiSocketEverOpened && __webuiSocketFailedAttempts >= __webuiSocketMaxFailedAttemptsBeforeStop) {
    __webuiSocketStopped = true;
    return;
  }
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
    __webuiSocketEverOpened = true;
    __webuiSocketFailedAttempts = 0;
    __webuiSocketReconnectDelayMs = 120;
    __webuiSocketFlushQueue();
  };
  socket.onmessage = (event) => {
    __webuiHandleSocketMessage(event);
  };
  socket.onerror = () => {};
  socket.onclose = () => {
    __webuiSocketOpen = false;
    __webuiSocket = null;
    if (__webuiSocketStopped) return;
    __webuiSocketFailedAttempts += 1;
    if (!__webuiSocketEverOpened && __webuiSocketFailedAttempts >= __webuiSocketMaxFailedAttemptsBeforeStop) {
      __webuiSocketStopped = true;
      __webuiSocketQueue = [];
      return;
    }
    const delay = Math.min(1500, __webuiSocketReconnectDelayMs);
    __webuiSocketReconnectDelayMs = Math.min(2500, __webuiSocketReconnectDelayMs * 2);
    setTimeout(__webuiConnectPushSocket, delay);
  };
}

async function __webuiNotifyLifecycle(eventName) {
  const message = {
    type: "lifecycle",
    event: eventName,
    client_id: __webuiClientId,
  };

  if (__webuiSocketSendObject(message)) return;

  const payload = JSON.stringify({ event: eventName, client_id: __webuiClientId });
  try {
    if (typeof navigator !== "undefined" && navigator.sendBeacon) {
      const blob = new Blob([payload], { type: "application/json" });
      navigator.sendBeacon("/webui/lifecycle", blob);
      return;
    }
  } catch (_) {}

  try {
    await fetch("/webui/lifecycle", {
      method: "POST",
      headers: __webuiRequestHeaders({ "content-type": "application/json" }),
      body: payload,
      keepalive: true,
    });
  } catch (_) {}
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
  if (__webuiSocketSendObject(responsePayload)) return;
  try {
    await __webuiJson("/webui/script/response", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        id: task.id,
        js_error,
        value,
        error_message,
      }),
      keepalive: false,
    });
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
  if (typeof globalThis === "undefined" || typeof globalThis.addEventListener !== "function") return;
  globalThis.addEventListener("beforeunload", () => {
    // beforeunload also fires on reload/navigation, so do not signal hard-close here.
    __webuiNotifyLifecycle("window_unloading");
  });

  if (typeof globalThis !== "undefined") {
    globalThis.__webuiNotifyLifecycle = __webuiNotifyLifecycle;
    globalThis.__webuiWindowControl = __webuiWindowControl;
    globalThis.__webuiWindowStyle = __webuiWindowStyle;
    globalThis.__webuiGetWindowStyle = __webuiGetWindowStyle;
    globalThis.__webuiGetWindowCapabilities = __webuiGetWindowCapabilities;
  }
})();
