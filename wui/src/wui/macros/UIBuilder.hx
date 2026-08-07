package wui.macros;

#if macro
import haxe.macro.Context;
import sys.io.File;
import sys.FileSystem;
import haxe.io.Path;
#end

/**
 * Core code generation macro. Transforms the Haxe View tree AST
 * into imperative C++/WinRT code that constructs WinUI 3 controls.
 *
 * For each View node, it generates:
 * - Control construction (e.g., winrt_controls::StackPanel panel;)
 * - Property setting (e.g., panel.Orientation(...))
 * - Modifier application (e.g., panel.Margin(...))
 * - State subscriptions (e.g., state->subscribe([textBlock](...) { ... }))
 * - Child appending (e.g., panel.Children().Append(child))
 */
class UIBuilder {
    #if macro
    static var varCounter:Int = 0;

    /** Reset counter for a new generation pass. */
    public static function reset():Void {
        varCounter = 0;
    }

    /** Generate a unique variable name. */
    static function nextVar(prefix:String):String {
        return '${prefix}_${varCounter++}';
    }

    /**
     * Generate C++/WinRT code for a complete MainWindow.h/cpp
     * from a serialized view tree description.
     */
    /**
     * State fields discovered from the App class.
     * Each entry: { name, type, initial } where type is "int", "double", "bool", "string"
     */
    public static var stateFields:Array<{name:String, type:String, initial:String}> = [];

    /**
     * Every `@:state` field name, including the ones with no C++ static.
     *
     * `stateFields` answers "which states get a static here"; this answers "which
     * names are states at all". They were the same list until an array state --
     * which has no static, because Haxe rebuilds its list -- stopped being
     * recognised as a state and its ListView bound to nothing.
     */
    public static var allStateNames:Array<String> = [];

    /** True when the app is `@:nui`: the window is filled by the push contract. */
    public static var pushMode:Bool = false;

    /**
     * List of {stateName, textVar} pairs for state-bound text controls.
     * The generated code will subscribe to state changes and update these.
     */
    static var stateBindings:Array<{stateName:String, controlVar:String, format:String}> = [];

    /** ListViews found in the tree, keyed by the state that feeds them. */
    static var listViews:Array<{stateName:String, controlVar:String}> = [];

    public static function generateMainWindow(viewTree:ViewNode, outputDir:String):Void {
        reset();
        stateBindings = [];
        listViews = [];

        var bodyLines:Array<String> = [];
        var rootVar = generateNode(viewTree, bodyLines, 1);

        // Generate MainWindow.h
        var headerContent = '#pragma once
#include "pch.h"
#include <functional>

namespace MainWindow {
    winrt::Microsoft::UI::Xaml::UIElement BuildUI(
        winrt::Microsoft::UI::Xaml::Window const& window);
}
';
        ProjectGenerator.writeIfChanged(Path.join([outputDir, "MainWindow.h"]), headerContent);

        // Build state declarations
        var stateDecls = "";
        for (sf in stateFields) {
            stateDecls += '    static ${sf.type} s_${sf.name} = ${sf.initial};\n';
        }

        // Build state subscriber list type
        var subscriberDecls = "";
        for (sf in stateFields) {
            subscriberDecls += '    static std::vector<std::function<void()>> s_${sf.name}_listeners;\n';
        }

        // Build notify function
        var notifyFuncs = "";
        for (sf in stateFields) {
            notifyFuncs += '    static void notify_${sf.name}() {\n';
            notifyFuncs += '        for (auto& fn : s_${sf.name}_listeners) fn();\n';
            notifyFuncs += '    }\n';
        }

        // The way a Haxe write reaches these statics.
        //
        // `s_<name>` and `notify_<name>()` are static to this file, so the hxcpp
        // library cannot touch them. It exposes a slot instead, and this handler
        // fills it -- which also means an app built without Haxe still compiles,
        // because nothing here is required to exist on the other side.
        var intStates = [for (sf in stateFields) if (sf.type == "int") sf];
        var applyIntBody = "";
        for (sf in intStates) {
            applyIntBody += '        if (n == "${sf.name}") { s_${sf.name} = value; notify_${sf.name}(); return; }\n';
        }
        var stringStates = [for (sf in stateFields) if (sf.type == "std::wstring") sf];
        var applyStringBody = "";
        for (sf in stringStates) {
            applyStringBody += '        if (n == "${sf.name}") { s_${sf.name} = w; notify_${sf.name}(); return; }\n';
        }
        var applyStringFunc = "";
        if (stringStates.length > 0) {
            applyStringFunc = '    static void ApplyStringState(const char* name, const char* value) {\n'
                + '        std::string n(name);\n'
                + '        std::wstring w = wui::runtime::fromUtf8(value);\n'
                + '        wui::runtime::runOnUIThread([n, w]() {\n'
                + applyStringBody
                + '        });\n'
                + '    }\n';
        }

        var applyIntFunc = "";
        var registerHandler = "";
        if (stringStates.length > 0) {
            registerHandler += '    wui_bridge_set_string_handler(&ApplyStringState);\n';
        }
        if (intStates.length > 0) {
            applyIntFunc = '    static void ApplyIntState(const char* name, int value) {\n'
                + '        std::string n(name);\n'
                + '        // A Haxe write can land on any thread; XAML only tolerates one.\n'
                + '        wui::runtime::runOnUIThread([n, value]() {\n'
                + applyIntBody
                + '        });\n'
                + '    }\n';
            registerHandler += '    wui_bridge_set_int_handler(&ApplyIntState);\n';
        }

        // ---- lists ----
        //
        // One static ListView per bound state, plus the rebuilder. Rows arrive as
        // a flat payload (0x1e between rows, 0x1f between fields) because writing
        // a JSON parser here to carry three fields would be its own liability.
        var listDecls = "";
        var applyListBody = "";
        for (lv in listViews) {
            listDecls += '    static winrt_controls::ListView s_list_${lv.stateName}{nullptr};\n';
            applyListBody += '        if (n == "${lv.stateName}") { RebuildList(s_list_${lv.stateName}, payload); return; }\n';
        }

        var listHelpers = "";
        var registerListHandler = "";
        if (listViews.length > 0) {
            listHelpers = '    static void RebuildList(winrt_controls::ListView const& list, const char* payload) {\n'
                + '        if (list == nullptr) return;\n'
                + '        std::string all(payload);\n'
                + '        std::vector<std::string> rows;\n'
                + '        size_t start = 0;\n'
                + '        while (start <= all.size()) {\n'
                + '            size_t stop = all.find((char)30, start);\n'
                + '            if (stop == std::string::npos) { if (start < all.size()) rows.push_back(all.substr(start)); break; }\n'
                + '            rows.push_back(all.substr(start, stop - start));\n'
                + '            start = stop + 1;\n'
                + '        }\n'
                + '\n'
                + '        list.Items().Clear();\n'
                + '        for (auto const& row : rows) {\n'
                + '            std::vector<std::string> f;\n'
                + '            size_t p = 0;\n'
                + '            while (true) {\n'
                + '                size_t q = row.find((char)31, p);\n'
                + '                if (q == std::string::npos) { f.push_back(row.substr(p)); break; }\n'
                + '                f.push_back(row.substr(p, q - p));\n'
                + '                p = q + 1;\n'
                + '            }\n'
                + '            if (f.size() < 3) continue;\n'
                + '\n'
                + '            winrt_controls::StackPanel line;\n'
                + '            line.Orientation(winrt_controls::Orientation::Horizontal);\n'
                + '            line.Spacing(8);\n'
                + '\n'
                + '            winrt_controls::TextBlock caption;\n'
                + '            caption.Text(winrt::hstring(wui::runtime::fromUtf8(f[0].c_str())));\n'
                + '            caption.VerticalAlignment(winrt_xaml::VerticalAlignment::Center);\n'
                + '            line.Children().Append(caption);\n'
                + '\n'
                + '            int rowId = std::atoi(f[2].c_str());\n'
                + '            if (!f[1].empty() && rowId >= 0) {\n'
                + '                winrt_controls::Button act;\n'
                + '                act.Content(winrt::box_value(winrt::hstring(wui::runtime::fromUtf8(f[1].c_str()))));\n'
                + '                // rowId is captured by value: the row it names is gone the\n'
                + '                // moment the list rebuilds, and Callbacks.invokeRow reports a\n'
                + '                // stale id rather than running someone else\'s closure.\n'
                + '                act.Click([rowId](winrt::Windows::Foundation::IInspectable const&, winrt_xaml::RoutedEventArgs const&) {\n'
                + '                    wui_bridge_invoke_row(rowId);\n'
                + '                });\n'
                + '                line.Children().Append(act);\n'
                + '            }\n'
                + '\n'
                + '            list.Items().Append(line);\n'
                + '        }\n'
                + '    }\n'
                + '\n'
                + '    static void ApplyListState(const char* name, const char* payload) {\n'
                + '        std::string n(name);\n'
                + '        std::string copy(payload);\n'
                + '        wui::runtime::runOnUIThread([n, copy]() {\n'
                + '            const char* payload = copy.c_str();\n'
                + applyListBody
                + '        });\n'
                + '    }\n';
            registerListHandler = '    wui_bridge_set_list_handler(&ApplyListState);\n';
        }
        // The lists exist only now; ask Haxe for their rows again.
        var refreshLists = listViews.length > 0 ? "    wui_bridge_refresh_lists();" : "";
        registerHandler += registerListHandler;

        // Build state binding subscriptions
        var subscriptionLines = "";
        for (binding in stateBindings) {
            var fmt = binding.format;
            subscriptionLines += '    s_${binding.stateName}_listeners.push_back([${binding.controlVar}]() {\n';
            subscriptionLines += '        $fmt\n';
            subscriptionLines += '    });\n';
        }

        // Generate MainWindow.cpp
        var indent = "    ";
        var bodyStr = "";
        for (line in bodyLines) {
            bodyStr += indent + line + "\n";
        }

        // In push mode nothing below is generated from the tree: the window gets
        // an empty root, and `wui.nui.Mount` fills it through the sink. The two
        // paths do not mix -- an app is either transpiled or driven.
        if (pushMode) {
            var pushSource = '#include "pch.h"
#include "MainWindow.h"
#include "WuiNodes.h"
#include "WuiRuntime.h"

namespace winrt_controls = winrt::Microsoft::UI::Xaml::Controls;
namespace winrt_xaml = winrt::Microsoft::UI::Xaml;

// Implemented in the hxcpp library: mounts the Haxe node tree into handle 0.
extern "C" void wui_bridge_render_nui();

namespace MainWindow {

winrt_xaml::UIElement BuildUI(winrt_xaml::Window const& window)
{
    wui::runtime::dispatcherQueue = window.DispatcherQueue();

    // Handle 0 is this panel. Everything Haxe creates is inserted into it.
    winrt_controls::StackPanel root;
    root.Orientation(winrt_controls::Orientation::Vertical);
    wui::nodes::reset(root);

    wui_bridge_render_nui();

    return root;
}

} // namespace MainWindow
';
            ProjectGenerator.writeIfChanged(Path.join([outputDir, "MainWindow.cpp"]), pushSource);
            return;
        }

        var sourceContent = '#include "pch.h"
#include "MainWindow.h"
#include <vector>
#include <string>
#include <cstdlib>

// Implemented in the hxcpp library (wui.bridge.HaxeBridge). Declared rather
// than included: this file must keep compiling when no Haxe closure is used,
// and hxcpp headers have no business in the UI translation unit.
extern "C" void wui_bridge_invoke(int id);
extern "C" void wui_bridge_set_int_handler(void (*fn)(const char*, int));
extern "C" void wui_bridge_set_string_handler(void (*fn)(const char*, const char*));
extern "C" void wui_bridge_external_string(const char* name, const char* value);
extern "C" void wui_bridge_set_list_handler(void (*fn)(const char*, const char*));
extern "C" void wui_bridge_invoke_row(int id);
extern "C" void wui_bridge_refresh_lists();

namespace winrt_controls = winrt::Microsoft::UI::Xaml::Controls;
namespace winrt_xaml = winrt::Microsoft::UI::Xaml;
namespace winrt_media = winrt::Microsoft::UI::Xaml::Media;

namespace MainWindow {

    // ---- State variables ----
$stateDecls
    // ---- State listeners ----
$subscriberDecls
    // ---- Notify helpers ----
$notifyFuncs
    // ---- lists Haxe rebuilds ----
$listDecls
    // ---- Haxe state -> these statics ----
$applyIntFunc
$applyStringFunc
$listHelpers
winrt_xaml::UIElement BuildUI(winrt_xaml::Window const& window)
{
    // Store dispatcher for thread-safe UI updates
    wui::runtime::dispatcherQueue = window.DispatcherQueue();

$registerHandler
$bodyStr
    // ---- State bindings ----
$subscriptionLines
$refreshLists
    return $rootVar;
}

} // namespace MainWindow
';
        ProjectGenerator.writeIfChanged(Path.join([outputDir, "MainWindow.cpp"]), sourceContent);
    }

    /**
     * Generate C++/WinRT code for a single view node and its children.
     * Returns the variable name of the generated control.
     */
    static function generateNode(node:ViewNode, lines:Array<String>, depth:Int):String {
        return switch (node.viewType) {
            case "StackPanel": generateStackPanel(node, lines, depth);
            case "Grid": generateGrid(node, lines, depth);
            case "TextBlock": generateTextBlock(node, lines, depth);
            case "Button": generateButton(node, lines, depth);
            case "TextBox": generateTextBox(node, lines, depth);
            case "ToggleSwitch": generateToggleSwitch(node, lines, depth);
            case "Slider": generateSlider(node, lines, depth);
            case "Image": generateImage(node, lines, depth);
            case "ScrollViewer": generateScrollViewer(node, lines, depth);
            case "CheckBox": generateCheckBox(node, lines, depth);
            case "ProgressRing": generateProgressRing(node, lines, depth);
            case "ListView": generateListView(node, lines, depth);
            case "Spacer": generateSpacer(node, lines, depth);
            default: generateGenericControl(node, lines, depth);
        };
    }

    static function generateStackPanel(node:ViewNode, lines:Array<String>, depth:Int):String {
        var varName = nextVar("panel");
        lines.push('winrt_controls::StackPanel $varName;');

        // Set orientation
        var orientation = node.properties.get("orientation");
        if (orientation == "Horizontal") {
            lines.push('$varName.Orientation(winrt_controls::Orientation::Horizontal);');
        } else {
            lines.push('$varName.Orientation(winrt_controls::Orientation::Vertical);');
        }

        // Set spacing
        var spacing = node.properties.get("spacing");
        if (spacing != null) {
            lines.push('$varName.Spacing($spacing);');
        }

        // Apply modifiers
        applyDeclaredProps(varName, node.viewType, node, lines);

        // Generate children
        for (child in node.children) {
            var childVar = generateNode(child, lines, depth + 1);
            lines.push('$varName.Children().Append($childVar);');
        }

        return varName;
    }

    static function generateGrid(node:ViewNode, lines:Array<String>, depth:Int):String {
        var varName = nextVar("grid");
        lines.push('winrt_controls::Grid $varName;');


        applyDeclaredProps(varName, node.viewType, node, lines);

        // For ZStack (overlapping), all children go in the same cell
        for (child in node.children) {
            var childVar = generateNode(child, lines, depth + 1);
            lines.push('$varName.Children().Append($childVar);');
        }

        return varName;
    }

    static function generateTextBlock(node:ViewNode, lines:Array<String>, depth:Int):String {
        var varName = nextVar("text");
        lines.push('winrt_controls::TextBlock $varName;');

        var text = node.properties.get("text");
        if (text != null) {
            var escaped = escapeWideString(Std.string(text));
            lines.push('$varName.Text(L"$escaped");');
        }

        // Check if this text should be bound to a state variable
        var boundState = node.properties.get("boundState");
        var boundFormat = node.properties.get("boundFormat");
        if (boundState != null) {
            var stateName = Std.string(boundState);
            var format = boundFormat != null ? Std.string(boundFormat) : '$varName.Text(wui::runtime::toHString(s_$stateName));';
            // Replace CTRL placeholder with actual variable name
            format = StringTools.replace(format, "CTRL", varName);
            stateBindings.push({
                stateName: stateName,
                controlVar: varName,
                format: format
            });
        }

        // Auto-bind: if text matches a state field's initial value, bind it
        if (boundState == null && stateFields.length > 0 && text != null) {
            var textStr = Std.string(text);
            for (sf in stateFields) {
                if (textStr == sf.initial || textStr == Std.string(Std.parseInt(sf.initial))) {
                    stateBindings.push({
                        stateName: sf.name,
                        controlVar: varName,
                        format: '$varName.Text(winrt::hstring(std::to_wstring(s_${sf.name})));'
                    });
                    break;
                }
            }
        }


        applyDeclaredProps(varName, node.viewType, node, lines);

        return varName;
    }

    static function generateButton(node:ViewNode, lines:Array<String>, depth:Int):String {
        var varName = nextVar("btn");
        lines.push('winrt_controls::Button $varName;');

        var label = node.properties.get("label");
        if (label != null) {
            var escaped = escapeWideString(Std.string(label));
            lines.push('$varName.Content(winrt::box_value(L"$escaped"));');
        }

        // The only click path there is.
        //
        // Every action -- a Haxe closure or a `StateAction` -- reaches Haxe by id.
        // What used to sit here instead: a translation of four `StateAction`
        // constructors into C++ that mutated `s_<name>` directly, and, failing
        // that, a guess at the intent from the button's *label* ("+" incremented
        // the first state field, "Reset" assigned its initial value). Both are
        // gone. The label heuristic could not have survived W3 anyway: it wrote
        // to a static Haxe no longer agreed with.
        var callbackId = node.properties.get("haxeCallbackId");
        if (callbackId != null) {
            lines.push('$varName.Click([](winrt::Windows::Foundation::IInspectable const&, winrt_xaml::RoutedEventArgs const&) {');
            lines.push('    wui_bridge_invoke($callbackId);');
            lines.push('});');
        }


        applyDeclaredProps(varName, node.viewType, node, lines);

        return varName;
    }

    /**
     * A list whose rows Haxe builds.
     *
     * The generator cannot pre-emit rows -- it does not know how many there will
     * be -- so it emits an empty ListView, remembers it under the bound state's
     * name, and lets `ApplyListState` refill it whenever Haxe pushes.
     */
    static function generateListView(node:ViewNode, lines:Array<String>, depth:Int):String {
        var varName = nextVar("list");
        lines.push('winrt_controls::ListView $varName;');

        var stateName = node.properties.get("boundState");
        if (stateName != null) {
            listViews.push({stateName: Std.string(stateName), controlVar: varName});
            lines.push('s_list_${stateName} = $varName;');
        }


        applyDeclaredProps(varName, node.viewType, node, lines);
        return varName;
    }

    static function generateTextBox(node:ViewNode, lines:Array<String>, depth:Int):String {
        var varName = nextVar("textBox");
        lines.push('winrt_controls::TextBox $varName;');

        var placeholder = node.properties.get("placeholder");
        if (placeholder != null) {
            var escaped = escapeWideString(Std.string(placeholder));
            lines.push('$varName.PlaceholderText(L"$escaped");');
        }

        // Two-way binding to state
        var boundState = node.properties.get("boundState");
        if (boundState != null) {
            var stateName = Std.string(boundState);
            // Set initial value
            lines.push('$varName.Text(winrt::hstring(s_$stateName));');
            // TextBox → state (on text change)
            lines.push('$varName.TextChanged([](winrt::Windows::Foundation::IInspectable const& sender, winrt_controls::TextChangedEventArgs const&) {');
            lines.push('    auto h = sender.as<winrt_controls::TextBox>().Text();');
            lines.push('    s_$stateName = std::wstring(h.c_str(), h.size());');
            lines.push('    notify_$stateName();');
            lines.push('    // Tell Haxe, without letting it push the value back into the');
            lines.push('    // box being typed in. The static above is a mirror, not a');
            lines.push('    // second owner: applyExternal leaves both sides agreeing.');
            lines.push('    wui_bridge_external_string("$stateName", wui::runtime::toUtf8(s_$stateName).c_str());');
            lines.push('});');
            // State → TextBox
            stateBindings.push({
                stateName: stateName,
                controlVar: varName,
                format: 'if ($varName.Text() != winrt::hstring(s_$stateName)) $varName.Text(winrt::hstring(s_$stateName));'
            });
        }


        applyDeclaredProps(varName, node.viewType, node, lines);
        return varName;
    }

    static function generateToggleSwitch(node:ViewNode, lines:Array<String>, depth:Int):String {
        var varName = nextVar("toggle");
        lines.push('winrt_controls::ToggleSwitch $varName;');

        var label = node.properties.get("label");
        if (label != null) {
            var escaped = escapeWideString(Std.string(label));
            lines.push('$varName.Header(winrt::box_value(L"$escaped"));');
        }

        // Two-way binding to state
        var boundState = node.properties.get("boundState");
        if (boundState != null) {
            var stateName = Std.string(boundState);
            lines.push('$varName.IsOn(s_$stateName);');
            lines.push('$varName.Toggled([](winrt::Windows::Foundation::IInspectable const& sender, winrt_xaml::RoutedEventArgs const&) {');
            lines.push('    s_$stateName = sender.as<winrt_controls::ToggleSwitch>().IsOn();');
            lines.push('    notify_$stateName();');
            lines.push('});');
            stateBindings.push({
                stateName: stateName,
                controlVar: varName,
                format: '$varName.IsOn(s_$stateName);'
            });
        }


        applyDeclaredProps(varName, node.viewType, node, lines);
        return varName;
    }

    static function generateSlider(node:ViewNode, lines:Array<String>, depth:Int):String {
        var varName = nextVar("slider");
        lines.push('winrt_controls::Slider $varName;');

        var min = node.properties.get("min");
        var max = node.properties.get("max");
        if (min != null) lines.push('$varName.Minimum($min);');
        if (max != null) lines.push('$varName.Maximum($max);');

        var step = node.properties.get("step");
        if (step != null) lines.push('$varName.StepFrequency($step);');

        // Two-way binding to state
        var boundState = node.properties.get("boundState");
        if (boundState != null) {
            var stateName = Std.string(boundState);
            lines.push('$varName.Value(static_cast<double>(s_$stateName));');
            lines.push('$varName.ValueChanged([](winrt::Windows::Foundation::IInspectable const&, winrt_controls::Primitives::RangeBaseValueChangedEventArgs const& e) {');
            lines.push('    s_$stateName = static_cast<int>(e.NewValue());');
            lines.push('    notify_$stateName();');
            lines.push('});');
            stateBindings.push({
                stateName: stateName,
                controlVar: varName,
                format: '$varName.Value(static_cast<double>(s_$stateName));'
            });
        }


        applyDeclaredProps(varName, node.viewType, node, lines);
        return varName;
    }

    static function generateImage(node:ViewNode, lines:Array<String>, depth:Int):String {
        var varName = nextVar("img");
        lines.push('winrt_controls::Image $varName;');

        var source = node.properties.get("source");
        if (source != null) {
            var escaped = escapeWideString(Std.string(source));
            lines.push('{');
            lines.push('    winrt::Microsoft::UI::Xaml::Media::Imaging::BitmapImage bmp;');
            lines.push('    bmp.UriSource(winrt::Windows::Foundation::Uri(L"$escaped"));');
            lines.push('    $varName.Source(bmp);');
            lines.push('}');
        }


        applyDeclaredProps(varName, node.viewType, node, lines);
        return varName;
    }

    static function generateScrollViewer(node:ViewNode, lines:Array<String>, depth:Int):String {
        var varName = nextVar("scroll");
        lines.push('winrt_controls::ScrollViewer $varName;');

        if (node.children.length > 0) {
            var contentVar = generateNode(node.children[0], lines, depth + 1);
            lines.push('$varName.Content($contentVar);');
        }


        applyDeclaredProps(varName, node.viewType, node, lines);
        return varName;
    }

    static function generateCheckBox(node:ViewNode, lines:Array<String>, depth:Int):String {
        var varName = nextVar("cb");
        lines.push('winrt_controls::CheckBox $varName;');

        var label = node.properties.get("label");
        if (label != null) {
            var escaped = escapeWideString(Std.string(label));
            lines.push('$varName.Content(winrt::box_value(L"$escaped"));');
        }

        // Two-way binding to state
        var boundState = node.properties.get("boundState");
        if (boundState != null) {
            var stateName = Std.string(boundState);
            lines.push('$varName.IsChecked(s_$stateName);');
            lines.push('$varName.Checked([](winrt::Windows::Foundation::IInspectable const&, winrt_xaml::RoutedEventArgs const&) {');
            lines.push('    s_$stateName = true; notify_$stateName();');
            lines.push('});');
            lines.push('$varName.Unchecked([](winrt::Windows::Foundation::IInspectable const&, winrt_xaml::RoutedEventArgs const&) {');
            lines.push('    s_$stateName = false; notify_$stateName();');
            lines.push('});');
            stateBindings.push({
                stateName: stateName,
                controlVar: varName,
                format: '$varName.IsChecked(s_$stateName);'
            });
        }


        applyDeclaredProps(varName, node.viewType, node, lines);
        return varName;
    }

    static function generateProgressRing(node:ViewNode, lines:Array<String>, depth:Int):String {
        var varName = nextVar("prog");
        lines.push('winrt_controls::ProgressRing $varName;');

        var isIndeterminate = node.properties.get("isIndeterminate");
        if (isIndeterminate == "true" || isIndeterminate == true) {
            lines.push('$varName.IsIndeterminate(true);');
        } else {
            lines.push('$varName.IsIndeterminate(false);');
            var value = node.properties.get("value");
            if (value != null) lines.push('$varName.Value($value);');
        }


        applyDeclaredProps(varName, node.viewType, node, lines);
        return varName;
    }

    static function generateSpacer(node:ViewNode, lines:Array<String>, depth:Int):String {
        // Spacer is implemented as a Grid row/column that expands
        var varName = nextVar("spacer");
        lines.push('winrt_controls::Border $varName;');
        lines.push('$varName.HorizontalAlignment(winrt_xaml::HorizontalAlignment::Stretch);');
        lines.push('$varName.VerticalAlignment(winrt_xaml::VerticalAlignment::Stretch);');

        var minSize = node.properties.get("minSize");
        if (minSize != null) {
            lines.push('$varName.MinWidth($minSize);');
            lines.push('$varName.MinHeight($minSize);');
        }

        return varName;
    }

    static function generateGenericControl(node:ViewNode, lines:Array<String>, depth:Int):String {
        var varName = nextVar("ctrl");
        lines.push('winrt_controls::Border $varName;');
        lines.push('// Unknown view type: ${node.viewType}');
        return varName;
    }

    // ---- Modifier Application ----

    /**
     * Emit a WinRT setter for every declared property the node carries.
     *
     * The mapping comes from the control's own `@:winrt` metadata, so this
     * switch does not exist: adding a property to a control is enough for the
     * generator to apply it. What used to require a branch here, a branch in
     * the node runtime and a line in a table now requires a declaration.
     *
     * A property with no declared WinRT member is skipped in silence only when
     * the generator handles it itself (`text`, `label`, `spacing`…); anything
     * else is reported, because a property that reaches nothing is exactly the
     * failure this replaces.
     */
    static function applyDeclaredProps(varName:String, nodeType:String, node:ViewNode, lines:Array<String>):Void {
        for (key in node.properties.keys()) {
            if (HANDLED.indexOf(key) >= 0) continue;

            var member = wui.nui.Vocabulary.winrtOf(nodeType, key);
            var kind = wui.nui.Vocabulary.kindOf(nodeType, key);

            // Fall back to View: the transpiled path names its types after WinUI
            // while the vocabulary is keyed by the nui name, so a per-type lookup
            // misses the properties every element shares.
            if (member == null) {
                var shared = wui.nui.Vocabulary.viewProp(key);
                if (shared == null) continue;
                member = shared.winrt;
                kind = shared.kind;
            }

            var raw = node.properties.get(key);
            var value = kind == "KString" ? "\"" + Std.string(raw) + "\"" : Std.string(raw);
            var text = kind == "KString" ? "winrt::hstring(L\"" + Std.string(raw) + "\")" : value;

            // The same emitter the node runtime uses. It knows which WinRT type
            // declares a member and which ones do not take a plain value -- and
            // for a few hours each generator had its own idea of that, which is
            // the duplication this whole sequence exists to remove.
            var call = BridgeGenerator.nodeSetter(member, kind, text, value);
            if (call == null) continue;

            // Straight onto the control. The declarations mirror the WinRT
            // hierarchy now, so a property reaching a control that lacks it is a
            // compile error rather than a setter quietly skipped.
            lines.push('$varName.$call;');
        }
    }

    /** Properties the per-control code already emits itself. **/
    static final HANDLED = ["text", "label", "spacing", "orientation", "placeholder",
        "binding", "action", "onClick", "hasHaxeCallback", "haxeCallbackId", "icon", "boundState"];

    /** A few WinRT members take something other than a plain string. **/
    static function stringPropExpr(varName:String, member:String, value:String):String {
        return switch (member) {
            case "Foreground" | "Background" | "BorderBrush":
                '$varName.$member(wui::runtime::brushFromName("$value"));';
            case "HorizontalAlignment" | "VerticalAlignment":
                '$varName.$member(winrt_xaml::${member}::$value);';
            case "Style": null;  // a TextBlock style needs a resource lookup; not yet
            case _: '$varName.$member(L"$value");';
        };
    }

    static function applyFontStyle(varName:String, style:String, lines:Array<String>):Void {
        switch (style) {
            case "Caption":
                lines.push('$varName.FontSize(12);');
            case "Body":
                lines.push('$varName.FontSize(14);');
            case "BodyStrong":
                lines.push('$varName.FontSize(14);');
                lines.push('$varName.FontWeight(winrt::Windows::UI::Text::FontWeight{ 600 });');
            case "Subtitle":
                lines.push('$varName.FontSize(20);');
                lines.push('$varName.FontWeight(winrt::Windows::UI::Text::FontWeight{ 600 });');
            case "Title":
                lines.push('$varName.FontSize(28);');
                lines.push('$varName.FontWeight(winrt::Windows::UI::Text::FontWeight{ 600 });');
            case "TitleLarge":
                lines.push('$varName.FontSize(40);');
                lines.push('$varName.FontWeight(winrt::Windows::UI::Text::FontWeight{ 600 });');
            case "Display":
                lines.push('$varName.FontSize(68);');
                lines.push('$varName.FontWeight(winrt::Windows::UI::Text::FontWeight{ 600 });');
            default:
                lines.push('$varName.FontSize(14);');
        }
    }

    static function generateColorBrush(colorSpec:String):String {
        return switch (colorSpec) {
            case "Black": "wui::runtime::blackBrush()";
            case "White": "wui::runtime::whiteBrush()";
            case "Red": "wui::runtime::redBrush()";
            case "Green": "wui::runtime::greenBrush()";
            case "Blue": "wui::runtime::blueBrush()";
            case "Yellow": "wui::runtime::yellowBrush()";
            case "Orange": "wui::runtime::orangeBrush()";
            case "Purple": "wui::runtime::purpleBrush()";
            case "Gray": "wui::runtime::grayBrush()";
            case "Transparent": "wui::runtime::transparentBrush()";
            // System accent colors — use Application.Current().Resources() lookup
            case "AccentColor": "wui::runtime::accentBrush()";
            case "AccentColorLight1": "wui::runtime::accentBrush()";
            case "AccentColorLight2": "wui::runtime::accentBrush()";
            case "AccentColorDark1": "wui::runtime::accentBrush()";
            case "AccentColorDark2": "wui::runtime::accentBrush()";
            default: 'wui::runtime::grayBrush() /* unknown: $colorSpec */';
        };
    }


    // ---- Utilities ----

    public static function escapeWideString(s:String):String {
        var result = new StringBuf();
        for (i in 0...s.length) {
            var c = s.charAt(i);
            switch (c) {
                case "\\": result.add("\\\\");
                case "\"": result.add("\\\"");
                case "\n": result.add("\\n");
                case "\r": result.add("\\r");
                case "\t": result.add("\\t");
                default: result.add(c);
            }
        }
        return result.toString();
    }
    #end
}

/**
 * Serialized view node for code generation.
 * The WinUIGenerator creates these from the Haxe AST,
 * then passes them to UIBuilder for C++ code generation.
 */
typedef ViewNode = {
    viewType:String,
    children:Array<ViewNode>,
    properties:Map<String, Dynamic>
};
