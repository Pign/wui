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
    /**
        Emit the node runtime: a handle table and the six operations of
        `nui.NodeSink`, implemented against WinUI.

        **The switch is generated, not written.** It used to be a hand-kept list
        of `if (t == "Text")` branches under a comment asking whoever touched it
        to keep it in step with `Vocabulary` -- the fourth copy of one truth, and
        the last. It is built from the controls now: a class carrying
        `@:winuiType` is a node type, its `@:winrt` vars are its properties, and
        their declared defaults are applied at creation.

        **The handle is an integer, not an object.** `qui` holds a `ui.Item` in
        Haxe because Silica items are visible to it; a WinRT control is not
        visible to hxcpp at all. So the tree lives here and Haxe holds indices,
        the same way callbacks already cross.
    **/
    static function generateNodeRuntime(outputDir:String):Void {
        var header = new StringBuf();
        header.add("#pragma once\n#include \"pch.h\"\n\n");
        header.add("// The six operations of nui.NodeSink, over integer handles.\n");
        header.add("extern \"C\" int  wui_node_create(const char* type, int parent);\n");
        header.add("extern \"C\" void wui_node_prop_string(int h, const char* type, const char* key, const char* value);\n");
        header.add("extern \"C\" void wui_node_prop_int(int h, const char* type, const char* key, int value);\n");
        header.add("extern \"C\" void wui_node_prop_float(int h, const char* type, const char* key, double value);\n");
        header.add("extern \"C\" void wui_node_prop_bool(int h, const char* type, const char* key, bool value);\n");
        header.add("extern \"C\" void wui_node_prop_callback(int h, const char* type, const char* key, int callbackId);\n");
        header.add("extern \"C\" void wui_node_modifier(int h, const char* type, const char* modType, double f0, const char* s0);\n");
        header.add("extern \"C\" void wui_node_insert(int parent, int child, int index);\n");
        header.add("extern \"C\" void wui_node_remove(int parent, int child);\n");
        header.add("extern \"C\" void wui_node_destroy(int h);\n\n");
        header.add("namespace wui { namespace nodes {\n");
        header.add("    // Handle 0 is the root the window mounts; Haxe inserts into it.\n");
        header.add("    void reset(winrt::Microsoft::UI::Xaml::UIElement const& root);\n");
        header.add("    winrt::Microsoft::UI::Xaml::UIElement rootElement();\n}}\n");
        ProjectGenerator.writeIfChanged(Path.join([outputDir, "WuiNodes.h"]), header.toString());

        var src = new StringBuf();
        src.add("#include \"pch.h\"\n#include \"WuiNodes.h\"\n#include \"WuiRuntime.h\"\n");
        src.add("#include <vector>\n#include <string>\n\n");
        src.add("namespace winrt_controls = winrt::Microsoft::UI::Xaml::Controls;\n");
        src.add("namespace winrt_xaml = winrt::Microsoft::UI::Xaml;\n\n");
        src.add("// Implemented in the hxcpp library: a node property that is a handler crosses\n");
        src.add("// as an id, never as a pointer -- the same rule as every other callback here.\n");
        src.add("extern \"C\" void wui_bridge_invoke_node(int id);\n\n");

        src.add("namespace {\n");
        src.add("    // Index -> control. Handles are never reused: a stale one then names a hole\n");
        src.add("    // rather than someone elses control, so a use-after-destroy is a reported\n");
        src.add("    // no-op instead of a wrong widget being poked.\n");
        src.add("    std::vector<winrt_xaml::UIElement> g_nodes;\n\n");
        src.add("    // One Click subscription per node, so applying onClick again REPLACES it.\n");
        src.add("    // WinUI events accumulate, and a re-render hands fresh closures that can\n");
        src.add("    // never compare equal, so without revoking first one click fires n+1 times.\n");
        src.add("    std::vector<winrt::event_token> g_clickTokens;\n\n");
        src.add("    winrt_xaml::UIElement at(int h) {\n");
        src.add("        if (h < 0 || h >= (int)g_nodes.size()) return nullptr;\n");
        src.add("        return g_nodes[h];\n    }\n\n");
        src.add("    int put(winrt_xaml::UIElement const& e) {\n");
        src.add("        g_nodes.push_back(e);\n        g_clickTokens.push_back(winrt::event_token{});\n");
        src.add("        return (int)g_nodes.size() - 1;\n    }\n}\n\n");

        src.add("namespace wui { namespace nodes {\n");
        src.add("    void reset(winrt_xaml::UIElement const& root) {\n");
        src.add("        g_nodes.clear();\n        g_clickTokens.clear();\n");
        src.add("        g_nodes.push_back(root);\n        g_clickTokens.push_back(winrt::event_token{});\n    }\n\n");
        src.add("    winrt_xaml::UIElement rootElement() {\n");
        src.add("        return g_nodes.empty() ? nullptr : g_nodes[0];\n    }\n}}\n\n");

        // ---- create, from the declarations ----
        src.add("extern \"C\" int wui_node_create(const char* type, int parent) {\n");
        src.add("    std::string t(type);\n\n");
        src.add("    // Materialise, and nothing else -- no children, no mounting. WinUI can\n");
        src.add("    // honour that: a control exists before it has a parent, which is why\n");
        src.add("    // insert is a real operation here and not the no-op Silica forces.\n");
        for (type in wui.nui.Vocabulary.types()) {
            var winui = wui.nui.Vocabulary.winuiFor(type);
            if (winui == null) continue;

            src.add("    if (t == \"" + type + "\") {\n");
            src.add("        winrt_controls::" + winui + " c;\n");
            for (entry in wui.nui.Vocabulary.defaultsFor(type)) {
                // Escaped like every other splice: a declared default is still
                // a string landing inside a C++ literal.
                var literal = entry.kind == "KString"
                    ? "\"" + UIBuilder.escapeWideString(entry.value) + "\"" : entry.value;
                var call = nodeSetter(entry.winrt, entry.kind, literal, literal);
                if (call == null) continue;

                src.add("        c." + call + ";\n");
            }
            src.add("        return put(c);\n    }\n");
        }
        src.add("\n    // An unknown type is shown, not swallowed: a tree that cannot render\n");
        src.add("    // should say so rather than leave a hole nobody can explain.\n");
        src.add("    winrt_controls::TextBlock unknown;\n");
        src.add("    unknown.Text(winrt::hstring(L\"?\" + wui::runtime::fromUtf8(type)));\n");
        src.add("    return put(unknown);\n}\n\n");

        // ---- one setter function per kind, branches from the declarations ----
        for (kind in ["KString", "KInt", "KFloat", "KBool"]) {
            var fn = switch (kind) {
                case "KString": "string"; case "KInt": "int";
                case "KFloat": "float"; case _: "bool";
            };
            var cty = switch (kind) {
                case "KString": "const char*"; case "KInt": "int";
                case "KFloat": "double"; case _: "bool";
            };
            src.add("extern \"C\" void wui_node_prop_" + fn + "(int h, const char* type, const char* key, " + cty + " value) {\n");
            src.add("    auto e = at(h);\n    if (e == nullptr) return;\n");
            src.add("    std::string t(type);\n    std::string k(key);\n");
            if (kind == "KString") src.add("    auto text = winrt::hstring(wui::runtime::fromUtf8(value));\n");
            src.add("\n");

            for (type in wui.nui.Vocabulary.types()) {
                var winui = wui.nui.Vocabulary.winuiFor(type);
                if (winui == null) continue;

                for (entry in wui.nui.Vocabulary.propsFor(type)) {
                    if (entry.kind != kind) continue;
                    var call = nodeSetter(entry.winrt, kind, "text", "value");
                    if (call == null) continue;

                    // Emit against the concrete control and let MSVC check it has
                    // the member. That is what replaced the owner table: a
                    // hand-kept list of which WinRT type declares what, already
                    // wrong about Panel, and failing in silence when it was.
                    src.add("    if (t == \"" + type + "\" && k == \"" + entry.name + "\") {\n");
                    src.add("        if (auto c = e.try_as<winrt_controls::" + winui + ">()) { c." + call + "; }\n");
                    src.add("        return;\n    }\n");
                }
            }
            src.add("}\n\n");
        }

        // ---- the rest: unchanged, and not derivable ----
        src.add("extern \"C\" void wui_node_prop_callback(int h, const char* type, const char* key, int callbackId) {\n");
        src.add("    auto e = at(h);\n    if (e == nullptr) return;\n");
        src.add("    if (std::string(key) != \"onClick\") return;\n");
        src.add("    if (auto b = e.try_as<winrt_controls::Button>()) {\n");
        src.add("        if (g_clickTokens[h].value != 0) { b.Click(g_clickTokens[h]); }\n");
        src.add("        g_clickTokens[h] = b.Click([callbackId](winrt::Windows::Foundation::IInspectable const&,\n");
        src.add("                                               winrt_xaml::RoutedEventArgs const&) {\n");
        src.add("            wui_bridge_invoke_node(callbackId);\n        });\n    }\n}\n\n");

        src.add("extern \"C\" void wui_node_modifier(int h, const char* type, const char* modType, double f0, const char* s0) {\n");
        src.add("    // nui keeps an ordered modifier chain; wui has no such concept any more --\n");
        src.add("    // everything it used to carry is a declared property. Kept so the contract\n");
        src.add("    // is implemented, and reported rather than silently ignored.\n");
        src.add("    (void)h; (void)type; (void)f0; (void)s0;\n");
        src.add("    OutputDebugStringA(\"[wui] modifier ignored: wui has properties, not modifiers\\n\");\n}\n\n");

        // A parent holds its children in whichever place its own WinRT type
        // provides, and there are four such places -- not one. Handling only
        // `Panel` and returning silently for the rest is what drew the kitchen
        // sink as a lone "+": a TabView keeps its pages in `TabItems`, so every
        // tab was dropped, and WinUI renders a TabView with no items as nothing
        // but its add-tab button. A ScrollViewer and a Border lost their content
        // the same way, one level further down.
        src.add("extern \"C\" void wui_node_insert(int parent, int child, int index) {\n");
        src.add("    auto p = at(parent);\n    auto c = at(child);\n");
        src.add("    if (p == nullptr || c == nullptr) return;\n\n");
        src.add("    // A panel is the only shape with an ordered list, so it is the only\n");
        src.add("    // one that can honour `index`. WinUI can place a child at a chosen\n");
        src.add("    // position; Silica cannot -- its positioners append -- which is why\n");
        src.add("    // the contract keeps this parameter rather than dropping it for its\n");
        src.add("    // first adopter.\n");
        src.add("    if (auto panel = p.try_as<winrt_controls::Panel>()) {\n");
        src.add("        uint32_t n = panel.Children().Size();\n");
        src.add("        uint32_t i = index < 0 ? n : (uint32_t)index;\n");
        src.add("        if (i > n) i = n;\n");
        src.add("        panel.Children().InsertAt(i, c);\n        return;\n    }\n\n");
        src.add("    if (auto tabs = p.try_as<winrt_controls::TabView>()) {\n");
        src.add("        uint32_t n = tabs.TabItems().Size();\n");
        src.add("        uint32_t i = index < 0 ? n : (uint32_t)index;\n");
        src.add("        if (i > n) i = n;\n");
        src.add("        tabs.TabItems().InsertAt(i, c);\n        return;\n    }\n\n");
        src.add("    // Single-content containers: there is nothing for `index` to order,\n");
        src.add("    // and a second child replaces the first rather than joining it.\n");
        src.add("    if (auto border = p.try_as<winrt_controls::Border>()) { border.Child(c); return; }\n");
        src.add("    if (auto holder = p.try_as<winrt_controls::ContentControl>()) { holder.Content(c); return; }\n\n");
        src.add("    OutputDebugStringA(\"[wui] insert: this parent has nowhere to put a child\\n\");\n}\n\n");

        src.add("extern \"C\" void wui_node_remove(int parent, int child) {\n");
        src.add("    auto p = at(parent);\n    auto c = at(child);\n");
        src.add("    if (p == nullptr || c == nullptr) return;\n\n");
        src.add("    if (auto panel = p.try_as<winrt_controls::Panel>()) {\n");
        src.add("        uint32_t index = 0;\n");
        src.add("        if (panel.Children().IndexOf(c, index)) panel.Children().RemoveAt(index);\n");
        src.add("        return;\n    }\n\n");
        src.add("    if (auto tabs = p.try_as<winrt_controls::TabView>()) {\n");
        src.add("        uint32_t index = 0;\n");
        src.add("        if (tabs.TabItems().IndexOf(c, index)) tabs.TabItems().RemoveAt(index);\n");
        src.add("        return;\n    }\n\n");
        src.add("    // Emptied rather than searched: a single-content container holds this\n");
        src.add("    // child or it holds nothing, and clearing one it does not hold would\n");
        src.add("    // throw away a sibling that is still on screen.\n");
        src.add("    if (auto border = p.try_as<winrt_controls::Border>()) {\n");
        src.add("        if (border.Child() == c) border.Child(nullptr);\n        return;\n    }\n\n");
        src.add("    if (auto holder = p.try_as<winrt_controls::ContentControl>()) {\n");
        src.add("        if (holder.Content() == c) holder.Content(nullptr);\n        return;\n    }\n}\n\n");

        src.add("extern \"C\" void wui_node_destroy(int h) {\n");
        src.add("    if (h <= 0 || h >= (int)g_nodes.size()) return;\n");
        src.add("    // A real release, not a hide. Dropping the last reference frees a WinRT\n");
        src.add("    // control -- unlike Silica, where destroy can only set visible = false.\n");
        src.add("    g_clickTokens[h] = winrt::event_token{};\n");
        src.add("    g_nodes[h] = nullptr;\n}\n");

        ProjectGenerator.writeIfChanged(Path.join([outputDir, "WuiNodes.cpp"]), src.toString());
    }

    /**
        A named typographic step, as a size. The table is the one the previous
        hand-written translation used, kept rather than reinvented.
    **/
    static function fontScale(valueExpr:String):String {
        return "(" + valueExpr + " == std::string(\"Display\") ? 68 :"
            + " " + valueExpr + " == std::string(\"TitleLarge\") ? 40 :"
            + " " + valueExpr + " == std::string(\"Title\") ? 28 :"
            + " " + valueExpr + " == std::string(\"Subtitle\") ? 20 :"
            + " " + valueExpr + " == std::string(\"Caption\") ? 12 : 14)";
    }

    /**
        A name to its alignment enum.

        The two enums do not share their values: horizontal is Left/Center/Right,
        vertical is Top/Center/Bottom. One conversion for both compiled here and
        was rejected by MSVC, which is the sort of thing only the real compiler
        knows.
    **/
    static function alignmentExpr(member:String, valueExpr:String):String {
        var e = "winrt_xaml::" + member;
        var near = member == "VerticalAlignment" ? "Top" : "Left";
        var far = member == "VerticalAlignment" ? "Bottom" : "Right";

        return "(" + valueExpr + " == std::string(\"Center\") ? " + e + "::Center :"
            + " " + valueExpr + " == std::string(\"" + far + "\") ? " + e + "::" + far + " :"
            + " " + valueExpr + " == std::string(\"" + near + "\") ? " + e + "::" + near
            + " : " + e + "::Stretch)";
    }

    /**
        The WinRT call for one property, or `null` when the node path cannot make
        it yet -- reported by its absence rather than emitted wrong.
    **/
    public static function nodeSetter(member:String, kind:String, textExpr:String, valueExpr:String):Null<String> {
        return switch (member) {
            case "Foreground" | "Background" | "BorderBrush":
                member + "(wui::runtime::brushFromName(" + valueExpr + "))";
            case "Orientation":
                member + "(std::string(" + valueExpr + ") == \"Horizontal\" ? winrt_controls::Orientation::Horizontal : winrt_controls::Orientation::Vertical)";
            // Both take an IInspectable, not a string: WinUI lets a header or a
            // content be any element, and a string has to be boxed to become
            // one. Passing the hstring compiled to "no overloaded function
            // could convert all the argument types", which names the symptom.
            case "Content" | "Header":
                member + "(winrt::box_value(" + textExpr + "))";
            case "Visibility":
                member + "(" + valueExpr + " ? winrt_xaml::Visibility::Visible : winrt_xaml::Visibility::Collapsed)";

            // These take a struct, not a number -- one value, four sides.
            case "Padding" | "Margin" | "BorderThickness":
                member + "(wui::runtime::uniformThickness(" + valueExpr + "))";
            case "CornerRadius":
                member + "(wui::runtime::uniformCornerRadius(" + valueExpr + "))";
            // The typographic scale the old hand-written translation carried.
            // Emitting nothing for it is what lost the design.
            case "FontScale":
                "FontSize(" + fontScale(valueExpr) + ")";
            case "FontWeight":
                // A struct literal, not FontWeights::SemiBold(): that is a
                // function returning auto and MSVC refuses it here.
                member + "(" + valueExpr + " ? winrt::Windows::UI::Text::FontWeight{ 600 } : winrt::Windows::UI::Text::FontWeight{ 400 })";
            case "HorizontalAlignment" | "VerticalAlignment":
                member + "(" + alignmentExpr(member, valueExpr) + ")";
            case _:
                kind == "KString" ? member + "(" + textExpr + ")" : member + "(" + valueExpr + ")";
        };
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
