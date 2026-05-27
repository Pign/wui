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
    public static function generate(appName:String, displayName:String, outputDir:String, windowWidth:Int, windowHeight:Int):Void {
        if (!FileSystem.exists(outputDir)) {
            FileSystem.createDirectory(outputDir);
        }

        generateAppHeader(appName, outputDir);
        generateAppSource(appName, displayName, outputDir, windowWidth, windowHeight);
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

    static function generateAppSource(appName:String, displayName:String, outputDir:String, windowWidth:Int, windowHeight:Int):Void {
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

namespace winrt_xaml = winrt::Microsoft::UI::Xaml;

// Boot the Haxe runtime (linked from libHelloworld.lib produced by hxcpp).
// Defined in build/cpp/src/__lib__.cpp when -D static_link is set.
extern "C" void __hxcpp_lib_main();

void App::OnLaunched(winrt_xaml::LaunchActivatedEventArgs const&)
{
    // Load WinUI control styles (enables TextBox, Slider, ToggleSwitch, etc.)
    Resources().MergedDictionaries().Append(
        winrt::Microsoft::UI::Xaml::Controls::XamlControlsResources());

    m_window = winrt_xaml::Window();
    m_window.Title(L"$displayName");

    // Store the dispatcher queue for UI thread marshaling
    wui::runtime::dispatcherQueue = m_window.DispatcherQueue();

    // Resize window
    if (auto appWindow = m_window.AppWindow()) {
        appWindow.Resize(winrt::Windows::Graphics::SizeInt32{ $windowWidth, $windowHeight });
    }

    // Build the UI from Haxe-generated code
    auto content = MainWindow::BuildUI(m_window);
    m_window.Content(content);

    m_window.Activate();
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
