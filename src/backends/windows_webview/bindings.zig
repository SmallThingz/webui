const std = @import("std");
const win = std.os.windows;

pub const HRESULT = i32;
pub const ULONG = u32;

pub const EventRegistrationToken = extern struct {
    value: i64,
};

pub const IUnknown = extern struct {
    lpVtbl: *const IUnknownVtbl,
};

pub const IUnknownVtbl = extern struct {
    QueryInterface: *const fn (*IUnknown, *const win.GUID, *?*anyopaque) callconv(.winapi) HRESULT,
    AddRef: *const fn (*IUnknown) callconv(.winapi) ULONG,
    Release: *const fn (*IUnknown) callconv(.winapi) ULONG,
};

pub const ICoreWebView2 = extern struct {
    lpVtbl: *const ICoreWebView2Vtbl,
};

pub const ICoreWebView2Settings = extern struct {
    lpVtbl: *const ICoreWebView2SettingsVtbl,
};

pub const ICoreWebView2Controller = extern struct {
    lpVtbl: *const ICoreWebView2ControllerVtbl,
};

pub const ICoreWebView2Environment = extern struct {
    lpVtbl: *const ICoreWebView2EnvironmentVtbl,
};

pub const ICoreWebView2CreateCoreWebView2ControllerCompletedHandler = extern struct {
    lpVtbl: *const ICoreWebView2CreateCoreWebView2ControllerCompletedHandlerVtbl,
};

pub const ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler = extern struct {
    lpVtbl: *const ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandlerVtbl,
};

pub const ICoreWebView2DocumentTitleChangedEventHandler = extern struct {
    lpVtbl: *const ICoreWebView2DocumentTitleChangedEventHandlerVtbl,
};

pub const ICoreWebView2CreateCoreWebView2ControllerCompletedHandlerVtbl = extern struct {
    QueryInterface: *const fn (*ICoreWebView2CreateCoreWebView2ControllerCompletedHandler, *const win.GUID, *?*anyopaque) callconv(.winapi) HRESULT,
    AddRef: *const fn (*ICoreWebView2CreateCoreWebView2ControllerCompletedHandler) callconv(.winapi) ULONG,
    Release: *const fn (*ICoreWebView2CreateCoreWebView2ControllerCompletedHandler) callconv(.winapi) ULONG,
    Invoke: *const fn (*ICoreWebView2CreateCoreWebView2ControllerCompletedHandler, HRESULT, ?*ICoreWebView2Controller) callconv(.winapi) HRESULT,
};

pub const ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandlerVtbl = extern struct {
    QueryInterface: *const fn (*ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler, *const win.GUID, *?*anyopaque) callconv(.winapi) HRESULT,
    AddRef: *const fn (*ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler) callconv(.winapi) ULONG,
    Release: *const fn (*ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler) callconv(.winapi) ULONG,
    Invoke: *const fn (*ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler, HRESULT, ?*ICoreWebView2Environment) callconv(.winapi) HRESULT,
};

pub const ICoreWebView2DocumentTitleChangedEventHandlerVtbl = extern struct {
    QueryInterface: *const fn (*ICoreWebView2DocumentTitleChangedEventHandler, *const win.GUID, *?*anyopaque) callconv(.winapi) HRESULT,
    AddRef: *const fn (*ICoreWebView2DocumentTitleChangedEventHandler) callconv(.winapi) ULONG,
    Release: *const fn (*ICoreWebView2DocumentTitleChangedEventHandler) callconv(.winapi) ULONG,
    Invoke: *const fn (*ICoreWebView2DocumentTitleChangedEventHandler, ?*ICoreWebView2, ?*IUnknown) callconv(.winapi) HRESULT,
};

pub const ICoreWebView2EnvironmentVtbl = extern struct {
    QueryInterface: *const fn (*ICoreWebView2Environment, *const win.GUID, *?*anyopaque) callconv(.winapi) HRESULT,
    AddRef: *const fn (*ICoreWebView2Environment) callconv(.winapi) ULONG,
    Release: *const fn (*ICoreWebView2Environment) callconv(.winapi) ULONG,
    CreateCoreWebView2Controller: *const fn (*ICoreWebView2Environment, win.HWND, *ICoreWebView2CreateCoreWebView2ControllerCompletedHandler) callconv(.winapi) HRESULT,
    CreateWebResourceResponse: *const anyopaque,
    get_BrowserVersionString: *const anyopaque,
    add_NewBrowserVersionAvailable: *const anyopaque,
    remove_NewBrowserVersionAvailable: *const anyopaque,
};

pub const ICoreWebView2ControllerVtbl = extern struct {
    QueryInterface: *const fn (*ICoreWebView2Controller, *const win.GUID, *?*anyopaque) callconv(.winapi) HRESULT,
    AddRef: *const fn (*ICoreWebView2Controller) callconv(.winapi) ULONG,
    Release: *const fn (*ICoreWebView2Controller) callconv(.winapi) ULONG,
    get_IsVisible: *const anyopaque,
    put_IsVisible: *const fn (*ICoreWebView2Controller, win.BOOL) callconv(.winapi) HRESULT,
    get_Bounds: *const anyopaque,
    put_Bounds: *const fn (*ICoreWebView2Controller, win.RECT) callconv(.winapi) HRESULT,
    get_ZoomFactor: *const anyopaque,
    put_ZoomFactor: *const anyopaque,
    add_ZoomFactorChanged: *const anyopaque,
    remove_ZoomFactorChanged: *const anyopaque,
    SetBoundsAndZoomFactor: *const anyopaque,
    MoveFocus: *const anyopaque,
    add_MoveFocusRequested: *const anyopaque,
    remove_MoveFocusRequested: *const anyopaque,
    add_GotFocus: *const anyopaque,
    remove_GotFocus: *const anyopaque,
    add_LostFocus: *const anyopaque,
    remove_LostFocus: *const anyopaque,
    add_AcceleratorKeyPressed: *const anyopaque,
    remove_AcceleratorKeyPressed: *const anyopaque,
    get_ParentWindow: *const anyopaque,
    put_ParentWindow: *const anyopaque,
    NotifyParentWindowPositionChanged: *const anyopaque,
    Close: *const fn (*ICoreWebView2Controller) callconv(.winapi) HRESULT,
    get_CoreWebView2: *const fn (*ICoreWebView2Controller, *?*ICoreWebView2) callconv(.winapi) HRESULT,
};

pub const ICoreWebView2SettingsVtbl = extern struct {
    QueryInterface: *const fn (*ICoreWebView2Settings, *const win.GUID, *?*anyopaque) callconv(.winapi) HRESULT,
    AddRef: *const fn (*ICoreWebView2Settings) callconv(.winapi) ULONG,
    Release: *const fn (*ICoreWebView2Settings) callconv(.winapi) ULONG,
    get_IsScriptEnabled: *const anyopaque,
    put_IsScriptEnabled: *const fn (*ICoreWebView2Settings, win.BOOL) callconv(.winapi) HRESULT,
    get_IsWebMessageEnabled: *const anyopaque,
    put_IsWebMessageEnabled: *const fn (*ICoreWebView2Settings, win.BOOL) callconv(.winapi) HRESULT,
    get_AreDefaultScriptDialogsEnabled: *const anyopaque,
    put_AreDefaultScriptDialogsEnabled: *const fn (*ICoreWebView2Settings, win.BOOL) callconv(.winapi) HRESULT,
    get_IsStatusBarEnabled: *const anyopaque,
    put_IsStatusBarEnabled: *const anyopaque,
    get_AreDevToolsEnabled: *const anyopaque,
    put_AreDevToolsEnabled: *const fn (*ICoreWebView2Settings, win.BOOL) callconv(.winapi) HRESULT,
    get_AreDefaultContextMenusEnabled: *const anyopaque,
    put_AreDefaultContextMenusEnabled: *const anyopaque,
    get_AreHostObjectsAllowed: *const anyopaque,
    put_AreHostObjectsAllowed: *const anyopaque,
    get_IsZoomControlEnabled: *const anyopaque,
    put_IsZoomControlEnabled: *const anyopaque,
    get_IsBuiltInErrorPageEnabled: *const anyopaque,
    put_IsBuiltInErrorPageEnabled: *const anyopaque,
};

pub const ICoreWebView2Vtbl = extern struct {
    QueryInterface: *const fn (*ICoreWebView2, *const win.GUID, *?*anyopaque) callconv(.winapi) HRESULT,
    AddRef: *const fn (*ICoreWebView2) callconv(.winapi) ULONG,
    Release: *const fn (*ICoreWebView2) callconv(.winapi) ULONG,
    get_Settings: *const fn (*ICoreWebView2, *?*ICoreWebView2Settings) callconv(.winapi) HRESULT,
    get_Source: *const anyopaque,
    Navigate: *const fn (*ICoreWebView2, [*:0]const u16) callconv(.winapi) HRESULT,
    NavigateToString: *const anyopaque,
    add_NavigationStarting: *const anyopaque,
    remove_NavigationStarting: *const anyopaque,
    add_ContentLoading: *const anyopaque,
    remove_ContentLoading: *const anyopaque,
    add_SourceChanged: *const anyopaque,
    remove_SourceChanged: *const anyopaque,
    add_HistoryChanged: *const anyopaque,
    remove_HistoryChanged: *const anyopaque,
    add_NavigationCompleted: *const anyopaque,
    remove_NavigationCompleted: *const anyopaque,
    add_FrameNavigationStarting: *const anyopaque,
    remove_FrameNavigationStarting: *const anyopaque,
    add_FrameNavigationCompleted: *const anyopaque,
    remove_FrameNavigationCompleted: *const anyopaque,
    add_ScriptDialogOpening: *const anyopaque,
    remove_ScriptDialogOpening: *const anyopaque,
    add_PermissionRequested: *const anyopaque,
    remove_PermissionRequested: *const anyopaque,
    add_ProcessFailed: *const anyopaque,
    remove_ProcessFailed: *const anyopaque,
    AddScriptToExecuteOnDocumentCreated: *const anyopaque,
    RemoveScriptToExecuteOnDocumentCreated: *const anyopaque,
    ExecuteScript: *const anyopaque,
    CapturePreview: *const anyopaque,
    Reload: *const anyopaque,
    PostWebMessageAsJson: *const anyopaque,
    PostWebMessageAsString: *const anyopaque,
    add_WebMessageReceived: *const anyopaque,
    remove_WebMessageReceived: *const anyopaque,
    CallDevToolsProtocolMethod: *const anyopaque,
    get_BrowserProcessId: *const anyopaque,
    get_CanGoBack: *const anyopaque,
    get_CanGoForward: *const anyopaque,
    GoBack: *const anyopaque,
    GoForward: *const anyopaque,
    GetDevToolsProtocolEventReceiver: *const anyopaque,
    Stop: *const anyopaque,
    add_NewWindowRequested: *const anyopaque,
    remove_NewWindowRequested: *const anyopaque,
    add_DocumentTitleChanged: *const fn (*ICoreWebView2, *ICoreWebView2DocumentTitleChangedEventHandler, *EventRegistrationToken) callconv(.winapi) HRESULT,
    remove_DocumentTitleChanged: *const anyopaque,
    get_DocumentTitle: *const fn (*ICoreWebView2, *?win.PWSTR) callconv(.winapi) HRESULT,
    AddHostObjectToScript: *const anyopaque,
    RemoveHostObjectFromScript: *const anyopaque,
    OpenDevToolsWindow: *const anyopaque,
    add_ContainsFullScreenElementChanged: *const anyopaque,
    remove_ContainsFullScreenElementChanged: *const anyopaque,
    get_ContainsFullScreenElement: *const anyopaque,
    add_WebResourceRequested: *const anyopaque,
    remove_WebResourceRequested: *const anyopaque,
    AddWebResourceRequestedFilter: *const anyopaque,
    RemoveWebResourceRequestedFilter: *const anyopaque,
    add_WindowCloseRequested: *const anyopaque,
    remove_WindowCloseRequested: *const anyopaque,
};

pub const CreateCoreWebView2EnvironmentWithOptionsFn = *const fn (
    ?[*:0]const u16,
    ?[*:0]const u16,
    ?*anyopaque,
    *ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler,
) callconv(.winapi) HRESULT;

pub const Symbols = struct {
    loader: std.DynLib,
    create_environment: CreateCoreWebView2EnvironmentWithOptionsFn,

    pub fn load() !Symbols {
        var loader = try std.DynLib.open("WebView2Loader.dll");
        errdefer loader.close();

        const create_environment = loader.lookup(CreateCoreWebView2EnvironmentWithOptionsFn, "CreateCoreWebView2EnvironmentWithOptions") orelse
            return error.MissingDynamicSymbol;

        return .{
            .loader = loader,
            .create_environment = create_environment,
        };
    }

    pub fn deinit(self: *Symbols) void {
        self.loader.close();
    }
};

pub inline fn succeeded(hr: HRESULT) bool {
    return hr >= 0;
}

pub inline fn releaseUnknown(ptr: anytype) void {
    const value = ptr orelse return;
    _ = value.lpVtbl.Release(value);
}

test "webview2 symbols can be referenced" {
    try std.testing.expect(@sizeOf(EventRegistrationToken) == @sizeOf(i64));
}
