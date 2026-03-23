package wui.macros;

#if macro
import haxe.macro.Context;
import sys.io.File;
import sys.FileSystem;
import haxe.io.Path;
#end

/**
 * Generates the C++/WinRT application boilerplate:
 * - App.h / App.cpp (wWinMain entry point, window creation)
 * - WuiRuntime.h (string conversion, UI thread dispatch, state notification)
 */
class BridgeGenerator {
    #if macro
    public static function generate(appName:String, outputDir:String, windowWidth:Int, windowHeight:Int):Void {
        if (!FileSystem.exists(outputDir)) {
            FileSystem.createDirectory(outputDir);
        }

        generateAppHeader(appName, outputDir);
        generateAppSource(appName, outputDir, windowWidth, windowHeight);
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

    static function generateAppSource(appName:String, outputDir:String, windowWidth:Int, windowHeight:Int):Void {
        var content = '#include "pch.h"
#include "App.h"
#include "MainWindow.h"

namespace winrt_xaml = winrt::Microsoft::UI::Xaml;

void App::OnLaunched(winrt_xaml::LaunchActivatedEventArgs const&)
{
    // Load WinUI control styles (enables TextBox, Slider, ToggleSwitch, etc.)
    Resources().MergedDictionaries().Append(
        winrt::Microsoft::UI::Xaml::Controls::XamlControlsResources());

    m_window = winrt_xaml::Window();
    m_window.Title(L"$appName");

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
    winrt::init_apartment(winrt::apartment_type::single_threaded);

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
