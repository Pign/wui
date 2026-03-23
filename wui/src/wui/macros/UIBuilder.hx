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
     * List of {stateName, textVar} pairs for state-bound text controls.
     * The generated code will subscribe to state changes and update these.
     */
    static var stateBindings:Array<{stateName:String, controlVar:String, format:String}> = [];

    public static function generateMainWindow(viewTree:ViewNode, outputDir:String):Void {
        reset();
        stateBindings = [];

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

        var sourceContent = '#include "pch.h"
#include "MainWindow.h"
#include <vector>

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
winrt_xaml::UIElement BuildUI(winrt_xaml::Window const& window)
{
    // Store dispatcher for thread-safe UI updates
    wui::runtime::dispatcherQueue = window.DispatcherQueue();

$bodyStr
    // ---- State bindings ----
$subscriptionLines
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
        applyModifiers(varName, "StackPanel", node.modifiers, lines);

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

        applyModifiers(varName, "Grid", node.modifiers, lines);

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

        applyModifiers(varName, "TextBlock", node.modifiers, lines);

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

        // Click handler — from onClick property, StateAction, or auto-detected state action
        var onClick = node.properties.get("onClick");
        if (onClick != null) {
            var code = Std.string(onClick);
            lines.push('$varName.Click([](winrt::Windows::Foundation::IInspectable const&, winrt_xaml::RoutedEventArgs const&) {');
            lines.push('    $code');
            lines.push('});');
        }

        var action = node.properties.get("action");
        if (action != null) {
            var actionCode = generateStateActionCode(action);
            lines.push('$varName.Click([](winrt::Windows::Foundation::IInspectable const&, winrt_xaml::RoutedEventArgs const&) {');
            lines.push('    $actionCode');
            lines.push('});');
        }

        // Auto-wire: if there are state fields and no explicit handler, detect by label
        if (onClick == null && action == null && stateFields.length > 0) {
            var sf = stateFields[0]; // use first state field
            var labelStr = label != null ? Std.string(label) : "";
            var clickCode:String = null;

            if (labelStr == "+" || labelStr == "Increment" || labelStr == "+ Increment") {
                clickCode = 's_${sf.name}++; notify_${sf.name}();';
            } else if (labelStr == "-" || labelStr == "Decrement" || labelStr == "- Decrement") {
                clickCode = 's_${sf.name}--; notify_${sf.name}();';
            } else if (labelStr == "Reset") {
                clickCode = 's_${sf.name} = ${sf.initial}; notify_${sf.name}();';
            }

            if (clickCode != null) {
                lines.push('$varName.Click([](winrt::Windows::Foundation::IInspectable const&, winrt_xaml::RoutedEventArgs const&) {');
                lines.push('    $clickCode');
                lines.push('});');
            }
        }

        applyModifiers(varName, "Button", node.modifiers, lines);

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

        applyModifiers(varName, "TextBox", node.modifiers, lines);
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

        applyModifiers(varName, "ToggleSwitch", node.modifiers, lines);
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

        applyModifiers(varName, "Slider", node.modifiers, lines);
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

        applyModifiers(varName, "Image", node.modifiers, lines);
        return varName;
    }

    static function generateScrollViewer(node:ViewNode, lines:Array<String>, depth:Int):String {
        var varName = nextVar("scroll");
        lines.push('winrt_controls::ScrollViewer $varName;');

        if (node.children.length > 0) {
            var contentVar = generateNode(node.children[0], lines, depth + 1);
            lines.push('$varName.Content($contentVar);');
        }

        applyModifiers(varName, "ScrollViewer", node.modifiers, lines);
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

        applyModifiers(varName, "CheckBox", node.modifiers, lines);
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

        applyModifiers(varName, "ProgressRing", node.modifiers, lines);
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

    static function applyModifiers(varName:String, controlType:String, modifiers:Array<ModifierData>, lines:Array<String>):Void {
        for (mod in modifiers) {
            switch (mod.type) {
                case "Padding":
                    lines.push('$varName.Padding(wui::runtime::uniformThickness(${mod.values[0]}));');
                case "Margin":
                    lines.push('$varName.Margin(wui::runtime::uniformThickness(${mod.values[0]}));');
                case "Width":
                    lines.push('$varName.Width(${mod.values[0]});');
                case "Height":
                    lines.push('$varName.Height(${mod.values[0]});');
                case "Opacity":
                    lines.push('$varName.Opacity(${mod.values[0]});');
                case "CornerRadius":
                    lines.push('$varName.CornerRadius(wui::runtime::uniformCornerRadius(${mod.values[0]}));');
                case "HorizontalAlignment":
                    var align = mod.values[0];
                    lines.push('$varName.HorizontalAlignment(winrt_xaml::HorizontalAlignment::$align);');
                case "VerticalAlignment":
                    var align = mod.values[0];
                    lines.push('$varName.VerticalAlignment(winrt_xaml::VerticalAlignment::$align);');
                case "Background":
                    var colorCode = generateColorBrush(mod.values[0]);
                    lines.push('$varName.Background($colorCode);');
                case "ForegroundColor":
                    if (controlType == "TextBlock") {
                        var colorCode = generateColorBrush(mod.values[0]);
                        lines.push('$varName.Foreground($colorCode);');
                    }
                case "Font":
                    if (controlType == "TextBlock") {
                        applyFontStyle(varName, mod.values[0], lines);
                    }
                case "FontSize":
                    if (controlType == "TextBlock") {
                        lines.push('$varName.FontSize(${mod.values[0]});');
                    }
                case "Bold":
                    if (controlType == "TextBlock") {
                        lines.push('$varName.FontWeight(winrt::Windows::UI::Text::FontWeight{ 700 });');
                    }
                case "Italic":
                    if (controlType == "TextBlock") {
                        lines.push('$varName.FontStyle(winrt::Windows::UI::Text::FontStyle::Italic);');
                    }
                case "Disabled":
                    var isDisabled = mod.values[0];
                    lines.push('$varName.IsEnabled(!$isDisabled);');
                case "Visible":
                    var isVisible = mod.values[0];
                    if (Std.string(isVisible) == "false") {
                        lines.push('$varName.Visibility(winrt_xaml::Visibility::Collapsed);');
                    }
                case "ToolTip":
                    var escaped = escapeWideString(Std.string(mod.values[0]));
                    lines.push('winrt_controls::ToolTipService::SetToolTip($varName, winrt::box_value(L"$escaped"));');
                case "BorderBrush":
                    var colorCode = generateColorBrush(mod.values[0]);
                    lines.push('$varName.BorderBrush($colorCode);');
                case "BorderThickness":
                    lines.push('$varName.BorderThickness(wui::runtime::uniformThickness(${mod.values[0]}));');
                case "Spacing":
                    if (controlType == "StackPanel") {
                        lines.push('$varName.Spacing(${mod.values[0]});');
                    }
                case "Frame":
                    // Frame(width, height, minWidth, maxWidth, minHeight, maxHeight)
                    if (mod.values[0] != null) lines.push('$varName.Width(${mod.values[0]});');
                    if (mod.values[1] != null) lines.push('$varName.Height(${mod.values[1]});');
                    if (mod.values[2] != null) lines.push('$varName.MinWidth(${mod.values[2]});');
                    if (mod.values[3] != null) lines.push('$varName.MaxWidth(${mod.values[3]});');
                    if (mod.values[4] != null) lines.push('$varName.MinHeight(${mod.values[4]});');
                    if (mod.values[5] != null) lines.push('$varName.MaxHeight(${mod.values[5]});');
                default:
                    lines.push('// TODO: modifier ${mod.type}');
            }
        }
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

    static function generateStateActionCode(action:Dynamic):String {
        // Generates C++ code for a StateAction
        // This will be expanded as the state system matures
        return "// StateAction: TODO";
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
    modifiers:Array<ModifierData>,
    properties:Map<String, Dynamic>
};

typedef ModifierData = {
    type:String,
    values:Array<Dynamic>
};
