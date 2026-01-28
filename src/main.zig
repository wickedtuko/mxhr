pub const UNICODE = true;
const win32 = @import("win32").everything;
const L = win32.L;
const HWND = win32.HWND;

const WM_TRAYICON = win32.WM_USER + 1;
const ID_TRAY_EXIT = 1001;

const CrosshairSettings = struct {
    color: u32 = 0x00FFFF, // Bright yellow (BGR format)
    border_color: u32 = 0xFFFFFF, // White
    thickness: i32 = 3,
    radius: i32 = 20, // Center gap
    opacity: u8 = 255, // 100% opacity (0-255)
    border_size: i32 = 1,
};

var g_hCrosshairWindow: ?HWND = null;
var g_crosshairSettings = CrosshairSettings{};
var g_cursorPos: win32.POINT = .{ .x = 0, .y = 0 };
var g_mouseHook: ?win32.HHOOK = null;

pub export fn wWinMain(
    hInstance: win32.HINSTANCE,
    _: ?win32.HINSTANCE,
    pCmdLine: [*:0]u16,
    nCmdShow: u32,
) callconv(.winapi) c_int {
    _ = pCmdLine;
    _ = nCmdShow;

    const CLASS_NAME = L("Sample Window Class");
    const wc = win32.WNDCLASSW{
        .style = .{},
        .lpfnWndProc = WindowProc,
        .cbClsExtra = 0,
        .cbWndExtra = 0,
        .hInstance = hInstance,
        .hIcon = null,
        .hCursor = win32.LoadCursorW(null, win32.IDC_ARROW),
        .hbrBackground = @ptrFromInt(@intFromEnum(win32.COLOR_WINDOW) + 1),
        .lpszMenuName = L("Some Menu Name"),
        .lpszClassName = CLASS_NAME,
    };

    if (0 == win32.RegisterClassW(&wc))
        win32.panicWin32("RegisterClass", win32.GetLastError());

    const hwnd = win32.CreateWindowExW(
        .{ .TOOLWINDOW = 1 },
        CLASS_NAME,
        L("mxhr"),
        win32.WS_OVERLAPPEDWINDOW,
        win32.CW_USEDEFAULT,
        win32.CW_USEDEFAULT, // Position
        400,
        200, // Size
        null, // Parent window
        null, // Menu
        hInstance, // Instance handle
        null, // Additional application data
    ) orelse win32.panicWin32("CreateWindow", win32.GetLastError());

    // Add system tray icon
    var nid: win32.NOTIFYICONDATAW = undefined;
    nid.cbSize = @sizeOf(win32.NOTIFYICONDATAW);
    nid.hWnd = hwnd;
    nid.uID = 1;
    nid.uFlags = .{ .MESSAGE = 1, .ICON = 1, .TIP = 1 };
    nid.uCallbackMessage = WM_TRAYICON;
    nid.hIcon = win32.LoadIconW(null, win32.IDI_APPLICATION);
    const tooltip = L("mxhr Application");
    @memcpy(nid.szTip[0..tooltip.len], tooltip);
    nid.szTip[tooltip.len] = 0;

    if (win32.Shell_NotifyIconW(.ADD, &nid) == 0) {
        win32.panicWin32("Shell_NotifyIcon", win32.GetLastError());
    }

    // Create the crosshair overlay window
    g_hCrosshairWindow = CreateCrosshairWindow(hInstance) catch null;

    // Install mouse hook for cursor tracking
    g_mouseHook = win32.SetWindowsHookExW(
        win32.WH_MOUSE_LL,
        MouseHookProc,
        hInstance,
        0,
    );

    // Initial crosshair display
    if (g_hCrosshairWindow) |ch_hwnd| {
        _ = win32.ShowWindow(ch_hwnd, win32.SW_SHOWNOACTIVATE);
        UpdateCrosshairDisplay();
    }

    _ = win32.ShowWindow(hwnd, win32.SW_HIDE);

    var msg: win32.MSG = undefined;
    while (win32.GetMessageW(&msg, null, 0, 0) != 0) {
        _ = win32.TranslateMessage(&msg);
        _ = win32.DispatchMessageW(&msg);
    }
    return @intCast(msg.wParam);
}

fn CrosshairWindowProc(
    hwnd: HWND,
    uMsg: u32,
    wParam: win32.WPARAM,
    lParam: win32.LPARAM,
) callconv(.winapi) win32.LRESULT {
    switch (uMsg) {
        win32.WM_PAINT => {
            var ps: win32.PAINTSTRUCT = undefined;
            const hdc = win32.BeginPaint(hwnd, &ps);
            if (hdc) |dc| {
                // Get window dimensions
                var rect: win32.RECT = undefined;
                _ = win32.GetClientRect(hwnd, &rect);
                const width = rect.right - rect.left;
                const height = rect.bottom - rect.top;

                // Clear with magenta (this will be made transparent)
                const hBrush = win32.CreateSolidBrush(0xFF00FF); // Magenta
                _ = win32.FillRect(dc, &rect, hBrush);
                _ = win32.DeleteObject(hBrush);

                // Get virtual screen offset
                const x = win32.GetSystemMetrics(win32.SM_XVIRTUALSCREEN);
                const y = win32.GetSystemMetrics(win32.SM_YVIRTUALSCREEN);

                // Convert cursor to window coordinates
                const cursorX = g_cursorPos.x - x;
                const cursorY = g_cursorPos.y - y;

                // Draw crosshairs
                DrawCrosshairs(dc, width, height, cursorX, cursorY, g_crosshairSettings);
            }
            _ = win32.EndPaint(hwnd, &ps);
            return 0;
        },
        win32.WM_NCHITTEST => {
            // Make window click-through
            return win32.HTTRANSPARENT;
        },
        win32.WM_DESTROY => {
            return 0;
        },
        else => {},
    }
    return win32.DefWindowProcW(hwnd, uMsg, wParam, lParam);
}

fn MouseHookProc(
    nCode: i32,
    wParam: win32.WPARAM,
    lParam: win32.LPARAM,
) callconv(.winapi) win32.LRESULT {
    if (nCode >= 0 and wParam == win32.WM_MOUSEMOVE) {
        UpdateCrosshairDisplay();
    }
    return win32.CallNextHookEx(null, nCode, wParam, lParam);
}

fn CreateCrosshairWindow(hInstance: win32.HINSTANCE) !HWND {
    const CROSSHAIR_CLASS_NAME = L("CrosshairOverlay");

    // Register window class for crosshair overlay
    const wc = win32.WNDCLASSW{
        .style = .{},
        .lpfnWndProc = CrosshairWindowProc,
        .cbClsExtra = 0,
        .cbWndExtra = 0,
        .hInstance = hInstance,
        .hIcon = null,
        .hCursor = null,
        .hbrBackground = null,
        .lpszMenuName = null,
        .lpszClassName = CROSSHAIR_CLASS_NAME,
    };

    if (0 == win32.RegisterClassW(&wc)) {
        return error.RegisterClassFailed;
    }

    // Get virtual screen dimensions for multi-monitor support
    const x = win32.GetSystemMetrics(win32.SM_XVIRTUALSCREEN);
    const y = win32.GetSystemMetrics(win32.SM_YVIRTUALSCREEN);
    const width = win32.GetSystemMetrics(win32.SM_CXVIRTUALSCREEN);
    const height = win32.GetSystemMetrics(win32.SM_CYVIRTUALSCREEN);

    // Create fullscreen transparent overlay window
    const hwnd = win32.CreateWindowExW(
        .{ .LAYERED = 1, .TOOLWINDOW = 1, .TOPMOST = 1 },
        CROSSHAIR_CLASS_NAME,
        L("Crosshair Overlay"),
        win32.WS_POPUP,
        x,
        y,
        width,
        height,
        null, // No parent
        null, // No menu
        hInstance,
        null,
    ) orelse return error.CreateWindowFailed;

    // Make magenta color transparent (so only crosshairs are visible)
    _ = win32.SetLayeredWindowAttributes(hwnd, 0xFF00FF, 0, win32.LWA_COLORKEY);

    return hwnd;
}

fn DrawCrosshairs(hdc: win32.HDC, width: i32, height: i32, cursorX: i32, cursorY: i32, settings: CrosshairSettings) void {
    // Create pen for border
    const hBorderPen = win32.CreatePen(win32.PS_SOLID, settings.border_size, settings.border_color);
    const hOldBorderPen = win32.SelectObject(hdc, hBorderPen);

    // Draw border lines (if border size > 0)
    if (settings.border_size > 0) {
        const border_offset = @divTrunc(settings.thickness, 2) + @divTrunc(settings.border_size, 2);

        // Left horizontal line border
        _ = win32.MoveToEx(hdc, 0, cursorY, null);
        _ = win32.LineTo(hdc, cursorX - settings.radius - border_offset, cursorY);

        // Right horizontal line border
        _ = win32.MoveToEx(hdc, cursorX + settings.radius + border_offset, cursorY, null);
        _ = win32.LineTo(hdc, width, cursorY);

        // Top vertical line border
        _ = win32.MoveToEx(hdc, cursorX, 0, null);
        _ = win32.LineTo(hdc, cursorX, cursorY - settings.radius - border_offset);

        // Bottom vertical line border
        _ = win32.MoveToEx(hdc, cursorX, cursorY + settings.radius + border_offset, null);
        _ = win32.LineTo(hdc, cursorX, height);
    }

    _ = win32.SelectObject(hdc, hOldBorderPen);
    _ = win32.DeleteObject(hBorderPen);

    // Create pen for main crosshair
    const hPen = win32.CreatePen(win32.PS_SOLID, settings.thickness, settings.color);
    const hOldPen = win32.SelectObject(hdc, hPen);

    // Draw horizontal line (with gap in center)
    _ = win32.MoveToEx(hdc, 0, cursorY, null);
    _ = win32.LineTo(hdc, cursorX - settings.radius, cursorY);
    _ = win32.MoveToEx(hdc, cursorX + settings.radius, cursorY, null);
    _ = win32.LineTo(hdc, width, cursorY);

    // Draw vertical line (with gap in center)
    _ = win32.MoveToEx(hdc, cursorX, 0, null);
    _ = win32.LineTo(hdc, cursorX, cursorY - settings.radius);
    _ = win32.MoveToEx(hdc, cursorX, cursorY + settings.radius, null);
    _ = win32.LineTo(hdc, cursorX, height);

    _ = win32.SelectObject(hdc, hOldPen);
    _ = win32.DeleteObject(hPen);
}

fn UpdateCrosshairDisplay() void {
    const hwnd = g_hCrosshairWindow orelse return;

    // Get cursor position
    _ = win32.GetCursorPos(&g_cursorPos);

    // Invalidate window to trigger repaint
    _ = win32.InvalidateRect(hwnd, null, 1);
}

fn WindowProc(
    hwnd: HWND,
    uMsg: u32,
    wParam: win32.WPARAM,
    lParam: win32.LPARAM,
) callconv(.winapi) win32.LRESULT {
    switch (uMsg) {
        WM_TRAYICON => {
            if (lParam == win32.WM_LBUTTONDOWN) {
                // Left click on tray icon - show/hide window
                if (win32.IsWindowVisible(hwnd) != 0) {
                    _ = win32.ShowWindow(hwnd, win32.SW_HIDE);
                } else {
                    _ = win32.ShowWindow(hwnd, win32.SW_SHOW);
                    _ = win32.SetForegroundWindow(hwnd);
                }
            } else if (lParam == win32.WM_RBUTTONDOWN) {
                // Right click on tray icon - show context menu
                const hMenu = win32.CreatePopupMenu();
                if (hMenu) |menu| {
                    _ = win32.AppendMenuW(menu, .{}, ID_TRAY_EXIT, L("Exit"));

                    // Get cursor position for menu
                    var pt: win32.POINT = undefined;
                    _ = win32.GetCursorPos(&pt);

                    // Required to make menu disappear when clicking outside
                    _ = win32.SetForegroundWindow(hwnd);

                    // Show menu and get selection
                    _ = win32.TrackPopupMenu(
                        menu,
                        .{},
                        pt.x,
                        pt.y,
                        0,
                        hwnd,
                        null,
                    );

                    _ = win32.DestroyMenu(menu);
                }
            }
            return 0;
        },
        win32.WM_COMMAND => {
            const cmd = @as(u16, @truncate(wParam & 0xFFFF));
            if (cmd == ID_TRAY_EXIT) {
                _ = win32.DestroyWindow(hwnd);
            }
            return 0;
        },
        win32.WM_DESTROY => {
            // Remove mouse hook
            if (g_mouseHook) |hook| {
                _ = win32.UnhookWindowsHookEx(hook);
                g_mouseHook = null;
            }

            // Destroy crosshair window if it exists
            if (g_hCrosshairWindow) |ch_hwnd| {
                _ = win32.DestroyWindow(ch_hwnd);
                g_hCrosshairWindow = null;
            }

            // Remove system tray icon
            var nid: win32.NOTIFYICONDATAW = undefined;
            nid.cbSize = @sizeOf(win32.NOTIFYICONDATAW);
            nid.hWnd = hwnd;
            nid.uID = 1;
            _ = win32.Shell_NotifyIconW(.DELETE, &nid);

            win32.PostQuitMessage(0);
            return 0;
        },
        else => {},
    }
    return win32.DefWindowProcW(hwnd, uMsg, wParam, lParam);
}

pub export fn WinMain(
    hInstance: win32.HINSTANCE,
    hPrevInstance: ?win32.HINSTANCE,
    pCmdLine: [*:0]u8,
    nShowCmd: u32,
) callconv(.winapi) c_int {
    _ = pCmdLine;

    return wWinMain(
        hInstance,
        hPrevInstance,
        win32.GetCommandLineW().?,
        nShowCmd,
    );
}
