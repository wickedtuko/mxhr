pub const UNICODE = true;
const win32 = @import("win32").everything;
const L = win32.L;
const HWND = win32.HWND;

const WM_TRAYICON = win32.WM_USER + 1;
const ID_TRAY_EXIT = 1001;

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

    _ = win32.ShowWindow(hwnd, win32.SW_HIDE);

    var msg: win32.MSG = undefined;
    while (win32.GetMessageW(&msg, null, 0, 0) != 0) {
        _ = win32.TranslateMessage(&msg);
        _ = win32.DispatchMessageW(&msg);
    }
    return @intCast(msg.wParam);
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
