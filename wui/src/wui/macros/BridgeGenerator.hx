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
    public static function generate(appName:String, outputDir:String, windowWidth:Int, windowHeight:Int, appClassPath:String, callbackCount:Int):Void {
        if (!FileSystem.exists(outputDir)) {
            FileSystem.createDirectory(outputDir);
        }

        generateNodeRuntime(outputDir);
        generateAppHeader(appName, outputDir);
        generateAppSource(appName, outputDir, windowWidth, windowHeight, appClassPath, callbackCount);
        generateRuntime(outputDir);
    }


    /**
        Emit the node runtime: a handle table and the six operations of
        `nui.NodeSink`, implemented against WinUI.

        **The handle is an integer, not an object.** `qui` can hold a `ui.Item`
        in Haxe because Silica items are visible to it; a WinRT control is not
        visible to hxcpp at all. So the tree lives here, Haxe holds indices, and
        the contract crosses the same way callbacks already do.

        This file does not depend on the app, only on the vocabulary of node
        types it knows how to build.
    **/
    static function generateNodeRuntime(outputDir:String):Void {
        var header = '#pragma once
#include "pch.h"

// The six operations of nui.NodeSink, over integer handles.
extern "C" int  wui_node_create(const char* type, int parent);
extern "C" void wui_node_prop_string(int h, const char* type, const char* key, const char* value);
extern "C" void wui_node_prop_int(int h, const char* type, const char* key, int value);
extern "C" void wui_node_prop_float(int h, const char* type, const char* key, double value);
extern "C" void wui_node_prop_bool(int h, const char* type, const char* key, bool value);
extern "C" void wui_node_prop_callback(int h, const char* type, const char* key, int callbackId);
extern "C" void wui_node_modifier(int h, const char* type, const char* modType, double f0, const char* s0);
extern "C" void wui_node_insert(int parent, int child, int index);
extern "C" void wui_node_remove(int parent, int child);
extern "C" void wui_node_destroy(int h);

namespace wui { namespace nodes {
    // Handle 0 is the root the window mounts; Haxe inserts into it.
    void reset(winrt::Microsoft::UI::Xaml::UIElement const& root);
    winrt::Microsoft::UI::Xaml::UIElement rootElement();
}}
';
        ProjectGenerator.writeIfChanged(Path.join([outputDir, "WuiNodes.h"]), header);

        var source = '#include "pch.h"
#include "WuiNodes.h"
#include "WuiRuntime.h"
#include <vector>
#include <string>

namespace winrt_controls = winrt::Microsoft::UI::Xaml::Controls;
namespace winrt_xaml = winrt::Microsoft::UI::Xaml;

// Implemented in the hxcpp library: a node property that is a handler crosses as
// an id, never as a pointer -- the same rule as every other callback here.
extern "C" void wui_bridge_invoke_node(int id);

namespace {
    // Index -> control. Handles are never reused: a stale handle then names a
    // hole rather than someone elses control, which turns a use-after-destroy
    // into a reported no-op instead of a wrong widget being poked.
    std::vector<winrt_xaml::UIElement> g_nodes;

    // One Click subscription per node, so applying onClick again REPLACES it.
    //
    // WinUI events accumulate: Click(handler) adds a subscriber, it does not
    // set one. A re-render hands fresh closures every time -- comparing them by
    // reference can never call them equal -- so without revoking first, every
    // render leaves another live handler behind and one click fires n+1 times.
    // "Apply this property" has to mean apply, not append.
    std::vector<winrt::event_token> g_clickTokens;

    winrt_xaml::UIElement at(int h) {
        if (h < 0 || h >= (int)g_nodes.size()) return nullptr;
        return g_nodes[h];
    }

    int put(winrt_xaml::UIElement const& e) {
        g_nodes.push_back(e);
        g_clickTokens.push_back(winrt::event_token{});
        return (int)g_nodes.size() - 1;
    }
}

namespace wui { namespace nodes {
    void reset(winrt_xaml::UIElement const& root) {
        g_nodes.clear();
        g_clickTokens.clear();
        g_nodes.push_back(root);   // handle 0
        g_clickTokens.push_back(winrt::event_token{});
    }

    winrt_xaml::UIElement rootElement() {
        return g_nodes.empty() ? nullptr : g_nodes[0];
    }
}}

extern "C" int wui_node_create(const char* type, int parent) {
    std::string t(type);

    // Materialise, and nothing else -- no properties, no children, no mounting.
    // The contract is explicit about this, and WinUI can honour it: a control
    // exists perfectly well before it has a parent, which is why insert is a
    // real operation here and not the no-op it has to be on Silica.
    if (t == "VStack" || t == "HStack" || t == "Stack") {
        winrt_controls::StackPanel p;
        p.Orientation(t == "HStack" ? winrt_controls::Orientation::Horizontal
                                    : winrt_controls::Orientation::Vertical);
        return put(p);
    }
    if (t == "Text" || t == "TextBlock") {
        winrt_controls::TextBlock tb;
        tb.VerticalAlignment(winrt_xaml::VerticalAlignment::Center);
        return put(tb);
    }
    if (t == "Button") {
        return put(winrt_controls::Button());
    }
    if (t == "TextBox") {
        return put(winrt_controls::TextBox());
    }

    // An unknown type is shown, not swallowed: a tree that cannot render should
    // say so on screen rather than leave a hole nobody can explain.
    winrt_controls::TextBlock unknown;
    unknown.Text(winrt::hstring(L"?" + wui::runtime::fromUtf8(type)));
    return put(unknown);
}

extern "C" void wui_node_prop_string(int h, const char* type, const char* key, const char* value) {
    auto e = at(h);
    if (e == nullptr) return;
    std::string k(key);
    auto text = winrt::hstring(wui::runtime::fromUtf8(value));

    if (k == "text") {
        if (auto tb = e.try_as<winrt_controls::TextBlock>()) { tb.Text(text); return; }
        if (auto b = e.try_as<winrt_controls::Button>()) { b.Content(winrt::box_value(text)); return; }
        if (auto x = e.try_as<winrt_controls::TextBox>()) { x.Text(text); return; }
    }
    if (k == "label") {
        if (auto b = e.try_as<winrt_controls::Button>()) { b.Content(winrt::box_value(text)); return; }
    }
    if (k == "placeholder") {
        if (auto x = e.try_as<winrt_controls::TextBox>()) { x.PlaceholderText(text); return; }
    }
}

extern "C" void wui_node_prop_int(int h, const char* type, const char* key, int value) {
    wui_node_prop_float(h, type, key, (double)value);
}

extern "C" void wui_node_prop_float(int h, const char* type, const char* key, double value) {
    auto e = at(h);
    if (e == nullptr) return;
    std::string k(key);

    if (k == "spacing") {
        if (auto p = e.try_as<winrt_controls::StackPanel>()) { p.Spacing(value); return; }
    }
    if (k == "width") {
        if (auto f = e.try_as<winrt_xaml::FrameworkElement>()) { f.Width(value); return; }
    }
    if (k == "height") {
        if (auto f = e.try_as<winrt_xaml::FrameworkElement>()) { f.Height(value); return; }
    }
}

extern "C" void wui_node_prop_bool(int h, const char* type, const char* key, bool value) {
    auto e = at(h);
    if (e == nullptr) return;
    std::string k(key);

    if (k == "visible") {
        e.Visibility(value ? winrt_xaml::Visibility::Visible : winrt_xaml::Visibility::Collapsed);
        return;
    }
    if (k == "enabled") {
        if (auto c = e.try_as<winrt_controls::Control>()) { c.IsEnabled(value); return; }
    }
}

extern "C" void wui_node_prop_callback(int h, const char* type, const char* key, int callbackId) {
    auto e = at(h);
    if (e == nullptr) return;
    std::string k(key);

    if (k == "onClick") {
        if (auto b = e.try_as<winrt_controls::Button>()) {
            // Revoke the previous subscription before adding the new one.
            if (g_clickTokens[h].value != 0) {
                b.Click(g_clickTokens[h]);
                g_clickTokens[h] = winrt::event_token{};
            }
            g_clickTokens[h] = b.Click([callbackId](winrt::Windows::Foundation::IInspectable const&,
                                                   winrt_xaml::RoutedEventArgs const&) {
                wui_bridge_invoke_node(callbackId);
            });
            return;
        }
    }
}

extern "C" void wui_node_modifier(int h, const char* type, const char* modType, double f0, const char* s0) {
    auto e = at(h);
    if (e == nullptr) return;
    std::string m(modType);

    if (m == "padding") {
        if (auto c = e.try_as<winrt_controls::Control>()) { c.Padding(wui::runtime::uniformThickness(f0)); return; }
        if (auto p = e.try_as<winrt_controls::StackPanel>()) { p.Padding(wui::runtime::uniformThickness(f0)); return; }
    }
    if (m == "margin") {
        if (auto f = e.try_as<winrt_xaml::FrameworkElement>()) { f.Margin(wui::runtime::uniformThickness(f0)); return; }
    }
    if (m == "foregroundColor") {
        if (auto tb = e.try_as<winrt_controls::TextBlock>()) {
            tb.Foreground(wui::runtime::brushFromName(s0));
            return;
        }
    }
}

extern "C" void wui_node_insert(int parent, int child, int index) {
    auto p = at(parent);
    auto c = at(child);
    if (p == nullptr || c == nullptr) return;

    auto panel = p.try_as<winrt_controls::Panel>();
    if (panel == nullptr) return;

    // WinUI can place a child at a chosen index. Silica cannot -- its
    // positioners append -- which is why the contract keeps this parameter
    // rather than dropping it for its first adopter.
    uint32_t n = panel.Children().Size();
    uint32_t i = index < 0 ? n : (uint32_t)index;
    if (i > n) i = n;
    panel.Children().InsertAt(i, c);
}

extern "C" void wui_node_remove(int parent, int child) {
    auto p = at(parent);
    auto c = at(child);
    if (p == nullptr || c == nullptr) return;

    auto panel = p.try_as<winrt_controls::Panel>();
    if (panel == nullptr) return;

    uint32_t index = 0;
    if (panel.Children().IndexOf(c, index)) {
        panel.Children().RemoveAt(index);
    }
}

extern "C" void wui_node_destroy(int h) {
    if (h <= 0 || h >= (int)g_nodes.size()) return;
    g_clickTokens[h] = winrt::event_token{};
    // A real release, not a hide. Dropping the last reference is what frees a
    // WinRT control, so clearing the slot destroys it -- unlike Silica, where
    // destroy can only set visible = false and the item leaks.
    g_nodes[h] = nullptr;
}
';
        ProjectGenerator.writeIfChanged(Path.join([outputDir, "WuiNodes.cpp"]), source);
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

    static function generateAppSource(appName:String, outputDir:String, windowWidth:Int, windowHeight:Int, appClassPath:String, callbackCount:Int):Void {
        var content = '#include "pch.h"
#include "App.h"
#include "MainWindow.h"

namespace winrt_xaml = winrt::Microsoft::UI::Xaml;

// Starts the Haxe runtime. Defined in the hxcpp static library; see
// wui.bridge.HaxeBridge. WinUI owns the entry point, so Haxe cannot own main --
// it is booted here instead, before the window exists, the same way Qt boots it
// in qui and Swift in sui.
extern "C" void wui_bridge_init();
extern "C" int wui_bridge_install(const char* appClass);

void App::OnLaunched(winrt_xaml::LaunchActivatedEventArgs const&)
{
    // Boot Haxe first: everything built below may call into it.
    wui_bridge_init();

    // Then let Haxe build its own view tree once, purely to collect the closures
    // its buttons carry. The controls below are still built by this file; what
    // this call produces is the id -> closure table the Click handlers use.
    //
    // The count is compared because a silent zero is the failure that matters:
    // the app would look correct and every Haxe button would do nothing.
    {
        int installed = wui_bridge_install("$appClassPath");
        if (installed != $callbackCount) {
            OutputDebugStringA("[wui] callback count mismatch, generated vs registered\\n");
        }
    }

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

    // ---- UTF-8 <-> UTF-16, for text crossing the Haxe bridge ----
    //
    // Haxe strings are UTF-8 and WinUI wants UTF-16, so every string that crosses
    // is converted here rather than at each call site. Going through the Win32
    // functions rather than std::codecvt, which is deprecated and was never right
    // about surrogate pairs -- an emoji in a text box is enough to show it.

    inline std::wstring fromUtf8(const char* s) {
        if (s == nullptr || *s == 0) return std::wstring();
        int len = ::MultiByteToWideChar(CP_UTF8, 0, s, -1, nullptr, 0);
        if (len <= 1) return std::wstring();
        std::wstring out(static_cast<size_t>(len - 1), static_cast<wchar_t>(0));
        ::MultiByteToWideChar(CP_UTF8, 0, s, -1, &out[0], len);
        return out;
    }

    inline std::string toUtf8(const std::wstring& s) {
        if (s.empty()) return std::string();
        int len = ::WideCharToMultiByte(CP_UTF8, 0, s.c_str(), static_cast<int>(s.size()),
                                        nullptr, 0, nullptr, nullptr);
        if (len <= 0) return std::string();
        std::string out(static_cast<size_t>(len), 0);
        ::WideCharToMultiByte(CP_UTF8, 0, s.c_str(), static_cast<int>(s.size()),
                              &out[0], len, nullptr, nullptr);
        return out;
    }

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

    // Colours arrive from nui as names, because a node property is a string.
    // An unknown name yields no brush rather than a guessed one: leaving the
    // control its own colour beats inventing one, and cui made the same call
    // when it chose to skip a hex colour rather than approximate it.
    inline winrt::Microsoft::UI::Xaml::Media::SolidColorBrush brushFromName(const char* name) {
        std::string n(name == nullptr ? "" : name);
        if (n == "black")   return blackBrush();
        if (n == "white")   return whiteBrush();
        if (n == "red")     return redBrush();
        if (n == "green")   return greenBrush();
        if (n == "blue")    return blueBrush();
        if (n == "yellow")  return yellowBrush();
        if (n == "orange")  return orangeBrush();
        if (n == "purple")  return purpleBrush();
        if (n == "gray")    return grayBrush();
        if (n == "accent")  return accentBrush();
        return nullptr;
    }

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
