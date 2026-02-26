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
    if (typeof globalThis.close === "function") {
      try {
        globalThis.close();
      } catch (_) {}
    }
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
      if (typeof globalThis.close === "function") {
        try {
          globalThis.close();
        } catch (_) {}
      }
      return {
        success: true,
        emulation: "close_window",
        closed: true,
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

  if (result && result.closed === true) {
    if (typeof globalThis.close === "function") {
      try {
        globalThis.close();
      } catch (_) {}
    }
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

async function __webuiNotifyLifecycle(eventName) {
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

(function __webuiInstallScriptLoop() {
  if (typeof globalThis === "undefined") return;
  if (globalThis.__webuiScriptLoopInstalled) return;
  globalThis.__webuiScriptLoopInstalled = true;

  let stopped = false;
  if (typeof globalThis.addEventListener === "function") {
    globalThis.addEventListener("beforeunload", () => {
      stopped = true;
    });
  }

  async function loop() {
    while (!stopped) {
      try {
        const res = await fetch("/webui/script/pull", {
          method: "GET",
          headers: __webuiRequestHeaders({}),
          cache: "no-store",
        });
        if (res.status === 204) {
          await new Promise((resolve) => setTimeout(resolve, 90));
          continue;
        }
        if (!res.ok) {
          await new Promise((resolve) => setTimeout(resolve, 180));
          continue;
        }
        const task = await res.json();
        if (task && typeof task === "object" && typeof task.script === "string") {
          await __webuiExecuteScriptTask(task);
          continue;
        }
      } catch (_) {}
      await new Promise((resolve) => setTimeout(resolve, 90));
    }
  }

  void loop();
})();

(function __webuiInstallLifecycleHooks() {
  if (typeof globalThis === "undefined" || typeof globalThis.addEventListener !== "function") return;

  const DEFAULT_LIFECYCLE_CONFIG = Object.freeze({
    enable_heartbeat: true,
    heartbeat_interval_ms: 6000,
    heartbeat_hidden_interval_ms: 30000,
    heartbeat_timeout_ms: 1200,
    heartbeat_failures_before_close: 3,
    heartbeat_initial_delay_ms: 1000,
  });

  async function __webuiFetchLifecycleConfig() {
    try {
      const result = await __webuiJson("/webui/lifecycle/config");
      if (!result || typeof result !== "object") return DEFAULT_LIFECYCLE_CONFIG;
      return Object.assign({}, DEFAULT_LIFECYCLE_CONFIG, result);
    } catch (_) {
      return DEFAULT_LIFECYCLE_CONFIG;
    }
  }

  async function __webuiStartLifecycle() {
    let lifecycleConfig = await __webuiFetchLifecycleConfig();
    let lifecycleFailures = 0;
    let heartbeatTimer = null;
    let heartbeatActive = false;

    function heartbeatIntervalMs() {
      if (typeof document !== "undefined" && document.hidden) {
        return Math.max(1000, Number(lifecycleConfig.heartbeat_hidden_interval_ms) || 0);
      }
      return Math.max(1000, Number(lifecycleConfig.heartbeat_interval_ms) || 0);
    }

    function scheduleHeartbeat(delayMs) {
      if (!lifecycleConfig.enable_heartbeat) return;
      if (heartbeatTimer) clearTimeout(heartbeatTimer);
      heartbeatTimer = setTimeout(() => { void heartbeat(); }, delayMs);
    }

    async function heartbeat() {
      if (!lifecycleConfig.enable_heartbeat) return;
      if (heartbeatActive) return;
      heartbeatActive = true;

      const timeoutMs = Math.max(250, Number(lifecycleConfig.heartbeat_timeout_ms) || 0);
      const controller = typeof AbortController !== "undefined" ? new AbortController() : null;
      let timeoutHandle = null;
      if (controller) {
        timeoutHandle = setTimeout(() => {
          try { controller.abort(); } catch (_) {}
        }, timeoutMs);
      }

      try {
        await fetch("/webui/lifecycle", {
          method: "POST",
          headers: { "content-type": "application/json" },
          body: "{\"event\":\"heartbeat\"}",
          keepalive: false,
          signal: controller ? controller.signal : undefined,
        });
        lifecycleFailures = 0;
      } catch (_) {
        lifecycleFailures += 1;
        const maxFailures = Math.max(1, Number(lifecycleConfig.heartbeat_failures_before_close) || 0);
        if (lifecycleFailures >= maxFailures && typeof globalThis.close === "function") {
          try { globalThis.close(); } catch (_) {}
        }
      } finally {
        heartbeatActive = false;
        if (timeoutHandle) clearTimeout(timeoutHandle);
        scheduleHeartbeat(heartbeatIntervalMs());
      }
    }

    globalThis.addEventListener("beforeunload", () => {
      // beforeunload also fires on reload/navigation, so do not signal hard-close here.
      __webuiNotifyLifecycle("window_unloading");
    });

    if (typeof document !== "undefined" && typeof document.addEventListener === "function") {
      document.addEventListener("visibilitychange", () => {
        if (!lifecycleConfig.enable_heartbeat) return;
        scheduleHeartbeat(heartbeatIntervalMs());
      });
    }

    if (lifecycleConfig.enable_heartbeat) {
      const initialDelay = Math.max(0, Number(lifecycleConfig.heartbeat_initial_delay_ms) || 0);
      scheduleHeartbeat(initialDelay);
    }
  }

  if (typeof globalThis !== "undefined") {
    globalThis.__webuiNotifyLifecycle = __webuiNotifyLifecycle;
    globalThis.__webuiWindowControl = __webuiWindowControl;
    globalThis.__webuiWindowStyle = __webuiWindowStyle;
    globalThis.__webuiGetWindowStyle = __webuiGetWindowStyle;
    globalThis.__webuiGetWindowCapabilities = __webuiGetWindowCapabilities;
    setTimeout(() => { __webuiGetWindowStyle().catch(() => {}); }, 0);
  }

  void __webuiStartLifecycle();
})();

