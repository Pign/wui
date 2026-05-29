package wui.macros;

#if macro
import haxe.macro.Context;
import sys.io.File;
import sys.FileSystem;
import haxe.io.Path;
import haxe.Json;
#end

/**
 * Generates the C++/WinRT application boilerplate:
 * - App.h / App.cpp (wWinMain entry point, window creation)
 * - WuiRuntime.h (string conversion, UI thread dispatch, state notification)
 */
class BridgeGenerator {
    #if macro
    public static function generate(appName:String, displayName:String, outputDir:String, windowWidth:Int, windowHeight:Int, backdrop:String, hasTitleBar:Bool):Void {
        if (!FileSystem.exists(outputDir)) {
            FileSystem.createDirectory(outputDir);
        }

        generateAppHeader(appName, outputDir);
        generateAppSource(appName, displayName, outputDir, windowWidth, windowHeight, backdrop, hasTitleBar);
        generateRuntime(outputDir);
    }

    static function generateAppHeader(appName:String, outputDir:String):Void {
        // No XAML, no IDL — pure C++/WinRT Application with IXamlMetadataProvider
        var content = '#pragma once
#include "pch.h"
#include <winrt/Microsoft.UI.Xaml.Markup.h>
#include <winrt/Microsoft.UI.Xaml.XamlTypeInfo.h>

// Forward declare the UI builder
namespace MainWindow {
    winrt::Microsoft::UI::Xaml::UIElement BuildUI(
        winrt::Microsoft::UI::Xaml::Window const& window);
}

// Application class with IXamlMetadataProvider for programmatic resource loading.
// No XAML, no IDL, no XBF needed.
struct App : winrt::Microsoft::UI::Xaml::ApplicationT<App, winrt::Microsoft::UI::Xaml::Markup::IXamlMetadataProvider>
{
    void OnLaunched(winrt::Microsoft::UI::Xaml::LaunchActivatedEventArgs const&);

    // IXamlMetadataProvider — delegates to XamlControlsXamlMetaDataProvider
    winrt::Microsoft::UI::Xaml::Markup::IXamlType GetXamlType(winrt::Windows::UI::Xaml::Interop::TypeName const& type) {
        return m_provider.GetXamlType(type);
    }
    winrt::Microsoft::UI::Xaml::Markup::IXamlType GetXamlType(winrt::hstring const& fullName) {
        return m_provider.GetXamlType(fullName);
    }
    winrt::com_array<winrt::Microsoft::UI::Xaml::Markup::XmlnsDefinition> GetXmlnsDefinitions() {
        return m_provider.GetXmlnsDefinitions();
    }

private:
    winrt::Microsoft::UI::Xaml::XamlTypeInfo::XamlControlsXamlMetaDataProvider m_provider;
    winrt::Microsoft::UI::Xaml::Window m_window{ nullptr };
};
';
        ProjectGenerator.writeIfChanged(Path.join([outputDir, "App.h"]), content);
    }

    /** Optional debug console — opt-in via `"debugConsole": true` in
        wui.json. When set, wWinMain allocates a Win32 console at boot
        and redirects stdout/stderr/stdin to it so `Sys.println`,
        `printf`, etc. become visible. */
    static function readDebugConsole():Bool {
        var p = Path.join([Sys.getCwd(), "wui.json"]);
        if (!FileSystem.exists(p)) return false;
        try {
            var cfg:Dynamic = Json.parse(File.getContent(p));
            return cfg.debugConsole == true;
        } catch (e:Dynamic) {
            return false;
        }
    }

    /** Emit the C++ that sets `Window.SystemBackdrop`. Driven by the
        bare enum constructor name (`Mica`, `MicaAlt`, `Acrylic`, `None`)
        coming from the user's `backdrop():Backdrop` override; defaults
        upstream. Returns "" for `None` so the window keeps its system
        opaque page background. */
    // titleBar wiring is no longer a tail-end step — when present it has
    // to wrap BuildUI's output in a 2-row Grid so the title-bar element
    // is part of the window's visual tree (SetTitleBar only marks the
    // drag region; it does NOT add the element). See `contentSetupCode`.
    static function titleBarSetupCode(_:Bool):String { return ""; }

    /** Emit the body-or-title-bar+body wiring. Without a title bar
        override this is the original two-liner that builds the UI and
        hands it to `Content()`. With one, we wrap title bar + body in
        a Grid:
            row 0 (Auto)  = BuildTitleBar() output, also passed to
                            `SetTitleBar()` so the system treats it as
                            the drag region.
            row 1 (Star)  = BuildUI() output, gets the rest of the window.

        `ExtendsContentIntoTitleBar(true)` removes the system caption row,
        which is why the wrapper Grid takes over the whole client area —
        and why row 0 has to leave ~138px on its right (the codegen
        already applies that as a min Margin in BuildTitleBar). */
    static function contentSetupCode(hasTitleBar:Bool):String {
        if (!hasTitleBar) {
            return '    auto content = MainWindow::BuildUI(m_window);
    m_window.Content(content);
';
        }
        return '    // Custom title bar — wrap title bar + body in a Grid so the
    // title bar element is actually rendered (SetTitleBar only flags
    // the drag region; it does not insert the element into the tree).
    {
        m_window.ExtendsContentIntoTitleBar(true);
        auto _tb = MainWindow::BuildTitleBar(m_window);
        auto _body = MainWindow::BuildUI(m_window);

        winrt::Microsoft::UI::Xaml::Controls::Grid _wrap;
        {
            winrt::Microsoft::UI::Xaml::Controls::RowDefinition _r0;
            _r0.Height(winrt::Microsoft::UI::Xaml::GridLength{ 0, winrt::Microsoft::UI::Xaml::GridUnitType::Auto });
            _wrap.RowDefinitions().Append(_r0);
            winrt::Microsoft::UI::Xaml::Controls::RowDefinition _r1;
            _r1.Height(winrt::Microsoft::UI::Xaml::GridLength{ 1, winrt::Microsoft::UI::Xaml::GridUnitType::Star });
            _wrap.RowDefinitions().Append(_r1);
        }
        if (auto _tbFe = _tb.try_as<winrt::Microsoft::UI::Xaml::FrameworkElement>()) {
            winrt::Microsoft::UI::Xaml::Controls::Grid::SetRow(_tbFe, 0);
        }
        if (auto _bodyFe = _body.try_as<winrt::Microsoft::UI::Xaml::FrameworkElement>()) {
            winrt::Microsoft::UI::Xaml::Controls::Grid::SetRow(_bodyFe, 1);
        }
        _wrap.Children().Append(_tb);
        _wrap.Children().Append(_body);

        m_window.Content(_wrap);
        m_window.SetTitleBar(_tb);
    }
';
    }

    static function backdropSetupCode(kind:String):String {
        return switch (kind) {
            case "None": "";
            case "Acrylic":
                '    // Win11 desktop acrylic backdrop — translucent blur with noise.
    m_window.SystemBackdrop(winrt::Microsoft::UI::Xaml::Media::DesktopAcrylicBackdrop());

';
            case "MicaAlt":
                '    // Win11 Mica backdrop (BaseAlt variant — higher contrast).
    {
        auto _mica = winrt::Microsoft::UI::Xaml::Media::MicaBackdrop();
        _mica.Kind(winrt::Microsoft::UI::Composition::SystemBackdrops::MicaKind::BaseAlt);
        m_window.SystemBackdrop(_mica);
    }

';
            default: // "Mica" — also the safe fallback for an unrecognised value
                '    // Win11 Mica backdrop — translucent surface tinted by wallpaper.
    m_window.SystemBackdrop(winrt::Microsoft::UI::Xaml::Media::MicaBackdrop());

';
        };
    }

    static function generateAppSource(appName:String, displayName:String, outputDir:String, windowWidth:Int, windowHeight:Int, backdrop:String, hasTitleBar:Bool):Void {
        var backdropInit = backdropSetupCode(backdrop);
        var contentInit = contentSetupCode(hasTitleBar);
        var consoleInit = readDebugConsole()
            ? '    // Debug console (opt-in via wui.json "debugConsole": true).
    // Sys.println, printf, std::cout become visible in the attached console.
    AllocConsole();
    FILE* _dummy = nullptr;
    freopen_s(&_dummy, "CONOUT$$", "w", stdout);
    freopen_s(&_dummy, "CONOUT$$", "w", stderr);
    freopen_s(&_dummy, "CONIN$$", "r", stdin);
    SetConsoleTitleW(L"$displayName — Debug Console");
    printf("[wui] Debug console attached\\n");

'
            : '';

        var content = '#include "pch.h"
#include "App.h"
#include "MainWindow.h"
#include <cstdio>
#include <string>
#include <winrt/Microsoft.UI.Composition.SystemBackdrops.h>

namespace winrt_xaml = winrt::Microsoft::UI::Xaml;
namespace winrt_media = winrt::Microsoft::UI::Xaml::Media;

// Boot the Haxe runtime (linked from libHelloworld.lib produced by hxcpp).
// Defined in build/cpp/src/__lib__.cpp when -D static_link is set.
extern "C" void __hxcpp_lib_main();

// ---- wui.Window bridges --------------------------------------------------
// Imperative Haxe → Win32 surface for runtime-mutable Window properties.
// `wui::runtime::window` is set below in OnLaunched; every call is
// marshalled onto the UI thread so it stays safe from worker threads
// (e.g. an OIDC poll loop calling `Window.setTitle(...)`).

extern "C" void clw_window_set_title(const wchar_t* val, int val_len) {
    if (!wui::runtime::window) return;
    std::wstring s(val, val_len);
    wui::runtime::runOnUIThread([s]() {
        if (wui::runtime::window) wui::runtime::window.Title(winrt::hstring(s));
    });
}

extern "C" void clw_window_set_backdrop(int kind) {
    if (!wui::runtime::window) return;
    wui::runtime::runOnUIThread([kind]() {
        if (!wui::runtime::window) return;
        switch (kind) {
            case 0: // None
                wui::runtime::window.SystemBackdrop(nullptr);
                break;
            case 1: // Mica
                wui::runtime::window.SystemBackdrop(winrt_media::MicaBackdrop());
                break;
            case 2: { // MicaAlt
                auto _m = winrt_media::MicaBackdrop();
                _m.Kind(winrt::Microsoft::UI::Composition::SystemBackdrops::MicaKind::BaseAlt);
                wui::runtime::window.SystemBackdrop(_m);
                break;
            }
            case 3: // Acrylic
                wui::runtime::window.SystemBackdrop(winrt_media::DesktopAcrylicBackdrop());
                break;
        }
    });
}

void App::OnLaunched(winrt_xaml::LaunchActivatedEventArgs const&)
{
    // Load WinUI control styles (enables TextBox, Slider, ToggleSwitch, etc.)
    Resources().MergedDictionaries().Append(
        winrt::Microsoft::UI::Xaml::Controls::XamlControlsResources());

    m_window = winrt_xaml::Window();
    m_window.Title(L"$displayName");

    // Store the dispatcher queue + window handle for marshaling and
    // imperative C++ calls from Haxe (wui.Window).
    wui::runtime::dispatcherQueue = m_window.DispatcherQueue();
    wui::runtime::window = m_window;

    // Resize window
    if (auto appWindow = m_window.AppWindow()) {
        appWindow.Resize(winrt::Windows::Graphics::SizeInt32{ $windowWidth, $windowHeight });
    }

    // Build the UI from Haxe-generated code (Content + optional title bar)
$contentInit
$backdropInit    m_window.Activate();
}

// Application entry point
int __stdcall wWinMain(HINSTANCE, HINSTANCE, PWSTR, int)
{
$consoleInit    winrt::init_apartment(winrt::apartment_type::single_threaded);

    // Bootstrap the Haxe runtime: hx::Boot(), __boot_all(), then call
    // the App subclass static main(). Required for @:state fields and
    // any Haxe class to function at runtime.
    __hxcpp_lib_main();

    winrt_xaml::Application::Start(
        [](auto&&) {
            ::winrt::make<App>();
        });

    return 0;
}
';
        ProjectGenerator.writeIfChanged(Path.join([outputDir, "App.cpp"]), content);
    }

    static function generateRuntime(outputDir:String):Void {
        var content = '#pragma once
#include <functional>
#include <string>
#include <vector>
#include <unordered_map>
#include <winrt/Microsoft.UI.Dispatching.h>
#include <winrt/Microsoft.UI.Xaml.h>
#include <winrt/Microsoft.UI.Xaml.Controls.h>
#include <winrt/Microsoft.UI.Xaml.Media.h>

namespace wui { namespace runtime {

    // ---- UI Thread Dispatch ----

    inline winrt::Microsoft::UI::Dispatching::DispatcherQueue dispatcherQueue{ nullptr };

    // ---- Main window handle ----
    //
    // Set in App::OnLaunched. Used by the extern "C" `clw_window_*`
    // bridges (see App.cpp) so `wui.Window.setTitle` / `setBackdrop`
    // from Haxe land safely on a real WinRT object even when called
    // from a worker thread.
    inline winrt::Microsoft::UI::Xaml::Window window{ nullptr };

    inline void runOnUIThread(std::function<void()> fn) {
        if (dispatcherQueue && !dispatcherQueue.HasThreadAccess()) {
            dispatcherQueue.TryEnqueue(
                winrt::Microsoft::UI::Dispatching::DispatcherQueueHandler(fn));
        } else {
            fn();
        }
    }

    // ---- String Conversion ----

    inline winrt::hstring toHString(const std::wstring& s) { return winrt::hstring(s); }
    inline winrt::hstring toHString(const wchar_t* s) { return winrt::hstring(s); }
    inline winrt::hstring toHString(int value) { return winrt::hstring(std::to_wstring(value)); }
    inline winrt::hstring toHString(double value) { return winrt::hstring(std::to_wstring(value)); }
    inline winrt::hstring toHString(bool value) { return winrt::hstring(value ? L"true" : L"false"); }

    // ---- State Change Notification (placeholder for debugging) ----

    inline void onStateChanged(const char* name, const char* value) {}

    // ---- Color Helpers ----

    inline winrt::Microsoft::UI::Xaml::Media::SolidColorBrush
    colorBrush(uint8_t r, uint8_t g, uint8_t b, uint8_t a = 255) {
        winrt::Windows::UI::Color color{ a, r, g, b };
        return winrt::Microsoft::UI::Xaml::Media::SolidColorBrush(color);
    }

    inline auto blackBrush()       { return colorBrush(0, 0, 0); }
    inline auto whiteBrush()       { return colorBrush(255, 255, 255); }
    inline auto redBrush()         { return colorBrush(255, 0, 0); }
    inline auto greenBrush()       { return colorBrush(0, 128, 0); }
    inline auto blueBrush()        { return colorBrush(0, 0, 255); }
    inline auto yellowBrush()      { return colorBrush(255, 255, 0); }
    inline auto orangeBrush()      { return colorBrush(255, 165, 0); }
    inline auto purpleBrush()      { return colorBrush(128, 0, 128); }
    inline auto grayBrush()        { return colorBrush(128, 128, 128); }
    inline auto transparentBrush() { return colorBrush(0, 0, 0, 0); }
    inline auto accentBrush()      { return colorBrush(0, 120, 212); }

    // ---- Thickness / CornerRadius ----

    inline winrt::Microsoft::UI::Xaml::Thickness uniformThickness(double value) {
        return { value, value, value, value };
    }

    inline winrt::Microsoft::UI::Xaml::CornerRadius uniformCornerRadius(double value) {
        return { value, value, value, value };
    }

}} // namespace wui::runtime
';
        ProjectGenerator.writeIfChanged(Path.join([outputDir, "WuiRuntime.h"]), content);
    }
    #end
}
