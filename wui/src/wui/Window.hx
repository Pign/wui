package wui;

/**
 * Imperative API for OS-level Window properties — title, backdrop, and
 * (future) icon / progress / jump list. Calls into extern "C" bridges
 * defined alongside the dispatcher in App.cpp.
 *
 * Compose with [[Effect]] for reactivity:
 *
 *   Effect.run(() -> Window.setTitle('Inbox (${StateBridge.getInt("unreadCount")})'),
 *              ["unreadCount"]);
 *
 * Every call is marshalled onto the UI thread (`runOnUIThread`) so it's
 * safe to invoke from a worker thread (e.g. an OIDC poll loop).
 */
#if cpp
@:cppFileCode('
extern "C" void clw_window_set_title(const wchar_t* val, int val_len);
extern "C" void clw_window_set_backdrop(int kind);
extern "C" void clw_window_open_url(const wchar_t* val, int val_len);
')
@:keep
class Window {
    /** Update the OS window title. Shows in the taskbar, Alt+Tab,
        accessibility tree, and (when `titleBar()` returns null) the
        system caption bar. */
    public static function setTitle(value:String):Void {
        untyped __cpp__('clw_window_set_title(reinterpret_cast<const wchar_t*>(({0}).wc_str()), ({0}).length)', value);
    }

    /** Swap the Window's translucent material at runtime. Matches the
        same `Backdrop` enum as the `App.backdrop()` override; passing
        `None` reverts to an opaque system page background. */
    public static function setBackdrop(value:Backdrop):Void {
        var kind:Int = switch (value) {
            case None: 0;
            case Mica: 1;
            case MicaAlt: 2;
            case Acrylic: 3;
        };
        untyped __cpp__('clw_window_set_backdrop({0})', kind);
    }

    /** Open a URL in the user's default browser via the Windows shell
        (`ShellExecuteW("open", …)`). Safe to call from any thread —
        the call is marshalled to the UI thread by the C++ bridge, so
        the caller doesn't need its own COM apartment.

        Typical use is the OAuth Device Flow handoff : after the
        verification URI comes back from `/oidc/device_authorization`,
        the app pops the user's browser straight to the consent page
        instead of asking them to copy the URL by hand. */
    public static function openUrl(value:String):Void {
        untyped __cpp__('clw_window_open_url(reinterpret_cast<const wchar_t*>(({0}).wc_str()), ({0}).length)', value);
    }
}
#else
class Window {
    public static function setTitle(value:String):Void throw "wui.Window: cpp target only";
    public static function setBackdrop(value:Backdrop):Void throw "wui.Window: cpp target only";
    public static function openUrl(value:String):Void throw "wui.Window: cpp target only";
}
#end
