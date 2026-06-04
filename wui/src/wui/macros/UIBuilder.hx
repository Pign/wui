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

    /** Sanitize a state name into a legal C++ identifier suffix.
        Composite Observable keys carry dots ("settings.darkMode") which
        match the bridge dispatch wstring; the static variables, notify
        functions, and listener vectors that mirror them need underscores
        instead ("s_settings_darkMode"). Bridge comparisons still use
        the original dotted key. */
    public static inline function cppId(name:String):String {
        return StringTools.replace(name, ".", "_");
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
     * Auto-exposed Haxe callback wrapper names (see
     * `WinUIGenerator.emitCallbackModule`). MainWindow.cpp emits
     * one `extern "C" void <name>();` per entry so the generated
     * click handlers can call them.
     */
    public static var exposedCallbacks:Array<String> = [];

    /**
     * True when at least one `wui.ui.ForEach` widget was analysed and
     * its accessor module (`wui.generated.ForEachAccessor`) was emitted.
     * Triggers the `<wui/generated/ForEachAccessor.h>` include in
     * MainWindow.cpp so the rebuild lambdas can resolve
     * `::wui::generated::ForEachAccessor_obj::<name>_length()` etc.
     */
    public static var foreachAccessorPresent:Bool = false;

    /**
     * Per-viewType emit functions, registered by primitive widget
     * classes (see `wui.macros.PrimitiveCtx`). Consulted by
     * `generateNodeImpl` before falling through to the legacy
     * switch — that switch is being drained one widget at a time
     * as each primitive moves into self-emit form.
     *
     * Keyed by `viewType` (the string a widget's `wuiAnalyze` writes
     * into its ViewNode), not by Haxe class name, because multiple
     * widget classes can share an emit (HStack / VStack both produce
     * "StackPanel" nodes — one StackPanelEmitter handles both).
     */
    public static var emitRegistry:Map<String, ViewNode -> wui.macros.PrimitiveCtx.EmitCtx -> String> = new Map();

    /** Register a per-viewType emit function. Re-registration
        overwrites silently — last writer wins, deliberately, so a
        consumer can override a framework primitive locally without
        forking. */
    public static function registerEmitter(viewType:String, fn:ViewNode -> wui.macros.PrimitiveCtx.EmitCtx -> String):Void {
        emitRegistry.set(viewType, fn);
    }

    /**
     * `wui.Effect.run(fn, [deps])` registrations harvested by
     * `WinUIGenerator.collectEffects`. Each entry's `wrapperName` is
     * already in `exposedCallbacks` (registered via `registerLambda`);
     * `deps` are the @:state field names whose listener lists must call
     * the wrapper. Emitted in `BuildUI`, after view bindings.
     */
    public static var effects:Array<{wrapperName:String, deps:Array<String>}> = [];

    /**
     * Variable names of focusable / clickable controls created during
     * the current Build pass. Populated by `generateNode` whenever it
     * emits a TextBox, Button, ComboBox, Slider, ToggleSwitch, or
     * CheckBox.
     *
     * Used by `BuildTitleBar` only: WinUI 3 1.5 treats the entire
     * `SetTitleBar()` element as a drag region and does NOT reliably
     * passthrough pointer input to interactive children (especially
     * TextBox). `InputNonClientPointerSource.SetRegionRects(Passthrough)`
     * is the documented workaround — codegen registers each tracked
     * control's bounds on Loaded/SizeChanged so a click on a search
     * field actually focuses it.
     */
    public static var interactiveVars:Array<String> = [];

    /**
     * List of {stateName, textVar} pairs for state-bound text controls.
     * The generated code will subscribe to state changes and update these.
     */
    static var stateBindings:Array<{stateName:String, controlVar:String, format:String}> = [];

    public static function generateMainWindow(viewTree:ViewNode, titleBarTree:ViewNode, outputDir:String):Void {
        reset();
        stateBindings = [];

        // Generate body() tree first, snapshot its bindings so titleBar()'s
        // bindings can be split off into their own BuildTitleBar function.
        var bodyLines:Array<String> = [];
        var rootVar = generateNode(viewTree, bodyLines, 1);
        var bodyBindings = stateBindings.copy();

        // Body comes first; interactive controls tracked there are
        // discarded — passthrough region magic only matters for the
        // title bar element.
        interactiveVars = [];

        // titleBar() — optional, only emit if the user actually overrode it.
        // Variable counter keeps incrementing so widget names never collide
        // even though the two trees live in separate Build functions.
        var hasTitleBar = titleBarTree != null;
        var titleBarLines:Array<String> = [];
        var titleBarRootVar:String = null;
        var titleBarBindings:Array<{stateName:String, controlVar:String, format:String}> = [];
        var titleBarInteractive:Array<String> = [];
        if (hasTitleBar) {
            stateBindings = [];
            interactiveVars = [];
            titleBarRootVar = generateNode(titleBarTree, titleBarLines, 1);
            titleBarBindings = stateBindings.copy();
            titleBarInteractive = interactiveVars.copy();
            // Reserve ~138px on the right so the system caption buttons
            // (min/max/close) don't sit on top of user widgets. Preserved
            // user-set margin on left/top/bottom; right is enforced to a
            // minimum so a tall design can still grow it.
            titleBarLines.push('auto _tbm = $titleBarRootVar.Margin();');
            titleBarLines.push('if (_tbm.Right < 145.0) _tbm.Right = 145.0;');
            titleBarLines.push('$titleBarRootVar.Margin(_tbm);');
        }

        // Generate MainWindow.h
        var titleBarDecl = hasTitleBar
            ? '\n    winrt::Microsoft::UI::Xaml::UIElement BuildTitleBar(\n        winrt::Microsoft::UI::Xaml::Window const& window);\n'
            : '';
        var headerContent = '#pragma once
#include "pch.h"
#include <functional>

namespace MainWindow {
    winrt::Microsoft::UI::Xaml::UIElement BuildUI(
        winrt::Microsoft::UI::Xaml::Window const& window);
$titleBarDecl}
';
        ProjectGenerator.writeIfChanged(Path.join([outputDir, "MainWindow.h"]), headerContent);

        // Build state declarations
        var stateDecls = "";
        for (sf in stateFields) {
            stateDecls += '    static ${sf.type} s_${cppId(sf.name)} = ${sf.initial};\n';
        }

        // Build state subscriber list type
        var subscriberDecls = "";
        for (sf in stateFields) {
            subscriberDecls += '    static std::vector<std::function<void()>> s_${cppId(sf.name)}_listeners;\n';
        }

        // Build notify function
        var notifyFuncs = "";
        for (sf in stateFields) {
            notifyFuncs += '    static void notify_${cppId(sf.name)}() {\n';
            notifyFuncs += '        for (auto& fn : s_${cppId(sf.name)}_listeners) fn();\n';
            notifyFuncs += '    }\n';
        }

        // Per-type dispatch functions called by `wui.state.StateBridge`
        // from Haxe lambdas (CLW-21). Single signature regardless of
        // how many fields exist; the body looks up by wstring name.
        // Functions are defined OUTSIDE the MainWindow namespace so
        // they have C linkage and a stable symbol.
        function buildDispatch(typeName:String, cppType:String, retCppType:String, signature:String, setBody:String -> String, getBody:String -> String):String {
            // Always emit the dispatch functions — even when no fields of
            // this type exist — so wui.state.StateBridge always finds its
            // C symbols at link time. Branches list is empty when no fields.
            var typedFields = [for (sf in stateFields) if (sf.type == cppType) sf];
            var setBranches = '    (void)name; (void)name_len;\n';
            var getBranches = '    (void)name; (void)name_len;\n';
            if (typedFields.length > 0) {
                setBranches = '    std::wstring n(name, name_len);\n';
                getBranches = '    std::wstring n(name, name_len);\n';
                for (sf in typedFields) {
                    // The wstring key keeps its dots (it's the bridge key
                    // that StateBridge.X("foo.bar") sends from Haxe); the
                    // C++ symbols use `cppId` so identifiers stay legal.
                    //
                    // setBody is a statement list ending without `return`
                    // — the dispatch tacks on `return;` to exit the void
                    // setter. getBody must include its own `return X;`
                    // (the wstring case writes out-params + `return;`,
                    // the numeric/bool cases return a value directly);
                    // appending another `return;` here would be either
                    // dead code (string) or a void-return from a typed
                    // getter (int/bool/double), which fails to compile.
                    var id = cppId(sf.name);
                    setBranches += '    if (n == L"${sf.name}") { ${setBody(id)} return; }\n';
                    getBranches += '    if (n == L"${sf.name}") { ${getBody(id)} }\n';
                }
            }
            return signature
                .split("__SET_BRANCHES__").join(setBranches)
                .split("__GET_BRANCHES__").join(getBranches);
        }

        var dispatchCode = "} // close MainWindow ns to define extern \"C\" bridges\n";
        // String
        dispatchCode += buildDispatch(
            "string", "std::wstring", "void",
            'extern "C" void clw_state_set_string(const wchar_t* name, int name_len, const wchar_t* val, int val_len) {\n'
            + '__SET_BRANCHES__'
            + '}\n'
            + 'extern "C" void clw_state_get_string(const wchar_t* name, int name_len, const wchar_t** out_buf, int* out_len) {\n'
            + '__GET_BRANCHES__'
            + '    *out_buf = L""; *out_len = 0;\n'
            + '}\n',
            function(name) return 'MainWindow::s_$name.assign(val, val_len); MainWindow::notify_$name();',
            function(name) return '*out_buf = MainWindow::s_$name.c_str(); *out_len = (int)MainWindow::s_$name.length(); return;'
        );
        // Int
        dispatchCode += buildDispatch(
            "int", "int", "int",
            'extern "C" void clw_state_set_int(const wchar_t* name, int name_len, int val) {\n'
            + '__SET_BRANCHES__'
            + '}\n'
            + 'extern "C" int clw_state_get_int(const wchar_t* name, int name_len) {\n'
            + '__GET_BRANCHES__'
            + '    return 0;\n'
            + '}\n',
            function(name) return 'MainWindow::s_$name = val; MainWindow::notify_$name();',
            function(name) return 'return MainWindow::s_$name;'
        );
        // Float (double)
        dispatchCode += buildDispatch(
            "double", "double", "double",
            'extern "C" void clw_state_set_double(const wchar_t* name, int name_len, double val) {\n'
            + '__SET_BRANCHES__'
            + '}\n'
            + 'extern "C" double clw_state_get_double(const wchar_t* name, int name_len) {\n'
            + '__GET_BRANCHES__'
            + '    return 0.0;\n'
            + '}\n',
            function(name) return 'MainWindow::s_$name = val; MainWindow::notify_$name();',
            function(name) return 'return MainWindow::s_$name;'
        );
        // Bool
        dispatchCode += buildDispatch(
            "bool", "bool", "bool",
            'extern "C" void clw_state_set_bool(const wchar_t* name, int name_len, bool val) {\n'
            + '__SET_BRANCHES__'
            + '}\n'
            + 'extern "C" bool clw_state_get_bool(const wchar_t* name, int name_len) {\n'
            + '__GET_BRANCHES__'
            + '    return false;\n'
            + '}\n',
            function(name) return 'MainWindow::s_$name = val; MainWindow::notify_$name();',
            function(name) return 'return MainWindow::s_$name;'
        );
        dispatchCode += 'namespace MainWindow {\n';
        var accessorsCode = dispatchCode;

        // Build state binding subscriptions.
        // Each listener defers its UI update via DispatcherQueue.TryEnqueue —
        // running synchronously from inside a click handler is a known WinUI 3
        // re-entrance pattern that crashes the XAML compositor a frame later
        // with STOWED_EXCEPTION 0xc000027b in Microsoft.UI.Xaml.dll.
        function emitSubscriptions(bindings:Array<{stateName:String, controlVar:String, format:String}>):String {
            var s = "";
            for (binding in bindings) {
                var fmt = binding.format;
                s += '    s_${cppId(binding.stateName)}_listeners.push_back([${binding.controlVar}]() {\n';
                s += '        if (wui::runtime::dispatcherQueue) {\n';
                s += '            wui::runtime::dispatcherQueue.TryEnqueue([${binding.controlVar}]() {\n';
                s += '                $fmt\n';
                s += '            });\n';
                s += '        }\n';
                s += '    });\n';
            }
            return s;
        }
        var subscriptionLines = emitSubscriptions(bodyBindings);
        var titleBarSubscriptionLines = emitSubscriptions(titleBarBindings);

        // ---- wui.Effect.run wiring -----------------------------------
        // For each effect harvested by WinUIGenerator.collectEffects:
        //   1. invoke the lifted wrapper once at startup (matches React
        //      `useEffect(fn, [deps])` semantics)
        //   2. subscribe the SAME wrapper to each dep's listener list,
        //      dispatched through DispatcherQueue so we share the same
        //      re-entrance protection as view bindings.
        var effectsLines = "";
        if (effects.length > 0) {
            for (eff in effects) {
                effectsLines += '    ::wui::generated::Callbacks_obj::${eff.wrapperName}();\n';
                for (d in eff.deps) {
                    effectsLines += '    s_${cppId(d)}_listeners.push_back([]() {\n';
                    effectsLines += '        if (wui::runtime::dispatcherQueue) {\n';
                    effectsLines += '            wui::runtime::dispatcherQueue.TryEnqueue([]() {\n';
                    effectsLines += '                ::wui::generated::Callbacks_obj::${eff.wrapperName}();\n';
                    effectsLines += '            });\n';
                    effectsLines += '        }\n';
                    effectsLines += '    });\n';
                }
            }
        }

        // Generate MainWindow.cpp
        var indent = "    ";
        var bodyStr = "";
        for (line in bodyLines) {
            bodyStr += indent + line + "\n";
        }
        var titleBarStr = "";
        for (line in titleBarLines) {
            titleBarStr += indent + line + "\n";
        }

        // Auto-exposed Haxe callbacks (CLW-11). MainWindow.cpp pulls in
        // hxcpp.h + the generated wui.generated.Callbacks header so the
        // click handlers can call `::wui::generated::Callbacks_obj::name()`
        // directly. The include is only emitted when at least one
        // callback was registered, to keep simple Counter-style apps free
        // of the hxcpp framework dependency on the WinRT side.
        var callbacksInclude = exposedCallbacks.length > 0
            ? '#include <hxcpp.h>\n#include <wui/generated/Callbacks.h>\n'
            : '';
        // ForEach widgets reach into Haxe via wui.generated.ForEachAccessor.
        // Only pull in the header when the macro actually emitted that
        // module — otherwise we'd reference a non-existent type.
        if (foreachAccessorPresent) {
            if (exposedCallbacks.length == 0) {
                callbacksInclude = '#include <hxcpp.h>\n';
            }
            callbacksInclude += '#include <wui/generated/ForEachAccessor.h>\n';
        }

        // Title-bar passthrough needs `InputNonClientPointerSource` from
        // the Microsoft.UI.Input WinRT projection. Only emitted when the
        // user actually overrode `titleBar()` so simple-form apps stay
        // lean.
        var titleBarInputInclude = hasTitleBar
            ? '#include <winrt/Microsoft.UI.Input.h>\n#include <winrt/Windows.Graphics.h>\n'
            : '';

        var sourceContent = '#include "pch.h"
#include "MainWindow.h"
#include <vector>
$callbacksInclude$titleBarInputInclude
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
$accessorsCode
winrt_xaml::UIElement BuildUI(winrt_xaml::Window const& window)
{
    // Store dispatcher for thread-safe UI updates
    wui::runtime::dispatcherQueue = window.DispatcherQueue();

$bodyStr
    // ---- State bindings ----
$subscriptionLines
    // ---- Effects (wui.Effect.run) ----
$effectsLines
    return $rootVar;
}
${hasTitleBar ? '
winrt_xaml::UIElement BuildTitleBar(winrt_xaml::Window const& window)
{
$titleBarStr
    // ---- State bindings ----
$titleBarSubscriptionLines
    // ---- Title bar input passthrough ----
    // WinUI 3 1.5 marks the entire SetTitleBar element as drag and does
    // not reliably forward pointer input to interactive children
    // (especially TextBox — Tab still works, mouse click does not focus).
    // Register each interactive child as a passthrough region via
    // InputNonClientPointerSource, recomputed on Loaded/SizeChanged so
    // the rectangles track DPI changes and layout shifts.
${emitTitleBarPassthrough(titleBarRootVar, titleBarInteractive)}
    return $titleBarRootVar;
}
' : ''}
} // namespace MainWindow
';
        ProjectGenerator.writeIfChanged(Path.join([outputDir, "MainWindow.cpp"]), sourceContent);
    }

    /**
     * Generate C++/WinRT code for a single view node and its children.
     * Returns the variable name of the generated control.
     */
    /**
     * Emit the Loaded/SizeChanged wiring that registers every tracked
     * interactive child as a passthrough region with
     * `InputNonClientPointerSource`. Bounds are recomputed each time the
     * layout changes (resize, DPI shift) so a click on a moved widget
     * still focuses it.
     *
     * Coordinates: `TransformToVisual(nullptr)` returns DIPs relative to
     * the window; `SetRegionRects` wants physical pixels, so we multiply
     * by `XamlRoot.RasterizationScale`.
     */
    static function emitTitleBarPassthrough(rootVar:String, interactive:Array<String>):String {
        if (interactive.length == 0) return "";
        var buf = new StringBuf();
        var addRectLines = "";
        for (v in interactive) {
            addRectLines += '            addRect($v);\n';
        }
        var captures = '$rootVar, window';
        for (v in interactive) captures += ', $v';
        buf.add('    auto _refreshPassthrough = [$captures]() {\n');
        buf.add('        if (!window.AppWindow()) return;\n');
        buf.add('        auto _src = winrt::Microsoft::UI::Input::InputNonClientPointerSource::GetForWindowId(\n');
        buf.add('            window.AppWindow().Id());\n');
        buf.add('        double _scale = $rootVar.XamlRoot() ? $rootVar.XamlRoot().RasterizationScale() : 1.0;\n');
        buf.add('        std::vector<winrt::Windows::Graphics::RectInt32> _rects;\n');
        buf.add('        auto addRect = [&](winrt::Microsoft::UI::Xaml::FrameworkElement child) {\n');
        buf.add('            if (!child) return;\n');
        buf.add('            auto _tx = child.TransformToVisual(nullptr);\n');
        buf.add('            auto _r = _tx.TransformBounds({0, 0, (float)child.ActualWidth(), (float)child.ActualHeight()});\n');
        buf.add('            _rects.push_back(winrt::Windows::Graphics::RectInt32{\n');
        buf.add('                (int32_t)(_r.X * _scale), (int32_t)(_r.Y * _scale),\n');
        buf.add('                (int32_t)(_r.Width * _scale), (int32_t)(_r.Height * _scale)\n');
        buf.add('            });\n');
        buf.add('        };\n');
        buf.add(addRectLines);
        buf.add('        _src.SetRegionRects(\n');
        buf.add('            winrt::Microsoft::UI::Input::NonClientRegionKind::Passthrough,\n');
        buf.add('            _rects);\n');
        buf.add('    };\n');
        buf.add('    $rootVar.Loaded([_refreshPassthrough](winrt::Windows::Foundation::IInspectable const&, winrt_xaml::RoutedEventArgs const&) {\n');
        buf.add('        _refreshPassthrough();\n');
        buf.add('    });\n');
        buf.add('    $rootVar.SizeChanged([_refreshPassthrough](winrt::Windows::Foundation::IInspectable const&, winrt_xaml::SizeChangedEventArgs const&) {\n');
        buf.add('        _refreshPassthrough();\n');
        buf.add('    });\n');
        return buf.toString();
    }

    static function generateNode(node:ViewNode, lines:Array<String>, depth:Int):String {
        var varName = generateNodeImpl(node, lines, depth);
        // Track interactive controls for title-bar passthrough — see
        // `interactiveVars` doc. Filter is intentionally narrow: only
        // widgets where a mis-routed pointer click is a real UX bug.
        switch (node.viewType) {
            case "TextBox" | "Button" | "ComboBox" | "Slider"
               | "ToggleSwitch" | "CheckBox":
                interactiveVars.push(varName);
            default:
        }
        return varName;
    }

    static function generateNodeImpl(node:ViewNode, lines:Array<String>, depth:Int):String {
        // Every viewType the framework knows about lives in
        // `emitRegistry`. Unknown viewType → generic Border
        // placeholder (the same fallback the legacy switch had via
        // its `default`).
        var emit = emitRegistry.get(node.viewType);
        if (emit != null) {
            return emit(node, buildEmitCtx(lines, depth));
        }
        return generateGenericControl(node, lines, depth);
    }

    /** Wire UIBuilder's mutable globals + helpers into the immutable
        record a migrated widget's `wuiEmit` expects. Cheap to build
        per-node — these are all closures over file-scope state, not
        the state itself. */
    static function buildEmitCtx(lines:Array<String>, depth:Int):wui.macros.PrimitiveCtx.EmitCtx {
        return {
            lines: lines,
            depth: depth,
            nextVar: nextVar,
            emitChild: (child:ViewNode) -> generateNode(child, lines, depth + 1),
            // `applyModifiers` internally takes the lines array too; bind it
            // here so widgets see the 3-arg signature in the ctx contract.
            applyModifiers: (varName, type, mods) -> applyModifiers(varName, type, mods, lines),
            pushStateBinding: (b) -> stateBindings.push(b),
            cppId: cppId,
            escapeWideString: escapeWideString,
            stateFields: stateFields,
        };
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
                    var colorCode = generateColorBrush(mod.values);
                    lines.push('$varName.Background($colorCode);');
                case "ForegroundColor":
                    if (controlType == "TextBlock") {
                        var colorCode = generateColorBrush(mod.values);
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
                case "OnTap":
                    // The compiled action snippet was produced by
                    // `extractStateAction` at analyze time. Wrap it in
                    // a `Tapped` handler — works on every UIElement,
                    // so this modifier composes with any primitive
                    // (Button.Click + Tapped both fire on click ; the
                    // user can choose either route).
                    var snippet = Std.string(mod.values[0]);
                    lines.push('$varName.Tapped([](winrt::Windows::Foundation::IInspectable const&, winrt::Microsoft::UI::Xaml::Input::TappedRoutedEventArgs const&) {');
                    lines.push('    $snippet');
                    lines.push('});');
                case "BorderBrush":
                    var colorCode = generateColorBrush(mod.values);
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

    /**
     * Translate a ColorValue enum (extracted as a flat
     * [constructorName, ...args] array by WinUIGenerator) into the C++/WinRT
     * brush expression that goes into the generated MainWindow.cpp.
     *
     * Nullary constructors land on the named runtime helpers; parametric
     * Rgb/Argb/Hex unpack their components into a single colorBrush() call.
     * Anything we don't recognise falls back to grayBrush() with a comment
     * marking the offending spec so it's grep-able in the generated source.
     */
    static function generateColorBrush(values:Array<Dynamic>):String {
        if (values == null || values.length == 0) return "wui::runtime::grayBrush()";
        var name = Std.string(values[0]);
        switch (name) {
            case "Black": return "wui::runtime::blackBrush()";
            case "White": return "wui::runtime::whiteBrush()";
            case "Red": return "wui::runtime::redBrush()";
            case "Green": return "wui::runtime::greenBrush()";
            case "Blue": return "wui::runtime::blueBrush()";
            case "Yellow": return "wui::runtime::yellowBrush()";
            case "Orange": return "wui::runtime::orangeBrush()";
            case "Purple": return "wui::runtime::purpleBrush()";
            case "Gray": return "wui::runtime::grayBrush()";
            case "Transparent": return "wui::runtime::transparentBrush()";
            case "AccentColor" | "AccentColorLight1" | "AccentColorLight2"
               | "AccentColorDark1" | "AccentColorDark2":
                return "wui::runtime::accentBrush()";
            case "Rgb":
                if (values.length < 4) return 'wui::runtime::grayBrush() /* Rgb: missing args */';
                var r = clampByte(values[1]);
                var g = clampByte(values[2]);
                var b = clampByte(values[3]);
                return 'wui::runtime::colorBrush($r, $g, $b)';
            case "Argb":
                if (values.length < 5) return 'wui::runtime::grayBrush() /* Argb: missing args */';
                var a = clampByte(values[1]);
                var r = clampByte(values[2]);
                var g = clampByte(values[3]);
                var b = clampByte(values[4]);
                return 'wui::runtime::colorBrush($r, $g, $b, $a)';
            case "Hex":
                if (values.length < 2) return 'wui::runtime::grayBrush() /* Hex: missing arg */';
                var parsed = parseHexColor(Std.string(values[1]));
                if (parsed == null) return 'wui::runtime::grayBrush() /* Hex: bad string ${values[1]} */';
                return 'wui::runtime::colorBrush(${parsed.r}, ${parsed.g}, ${parsed.b}, ${parsed.a})';
            default:
                return 'wui::runtime::grayBrush() /* unknown: $name */';
        }
    }

    static function clampByte(v:Dynamic):Int {
        var n = Std.parseInt(Std.string(v));
        if (n == null) return 0;
        if (n < 0) return 0;
        if (n > 255) return 255;
        return n;
    }

    /** Accept `#RGB`, `#RRGGBB`, `#AARRGGBB` (`#` optional). */
    static function parseHexColor(s:String):{a:Int, r:Int, g:Int, b:Int} {
        if (s == null) return null;
        var hex = StringTools.startsWith(s, "#") ? s.substr(1) : s;
        hex = hex.toLowerCase();
        for (i in 0...hex.length) {
            var c = hex.charCodeAt(i);
            var ok = (c >= "0".code && c <= "9".code)
                  || (c >= "a".code && c <= "f".code);
            if (!ok) return null;
        }
        function nib2(off:Int):Int {
            var n = Std.parseInt("0x" + hex.substr(off, 2));
            return n == null ? 0 : n;
        }
        function nib1(off:Int):Int {
            var n = Std.parseInt("0x" + hex.charAt(off));
            return n == null ? 0 : n * 17;
        }
        switch (hex.length) {
            case 3:
                return { a: 255, r: nib1(0), g: nib1(1), b: nib1(2) };
            case 6:
                return { a: 255, r: nib2(0), g: nib2(2), b: nib2(4) };
            case 8:
                return { a: nib2(0), r: nib2(2), g: nib2(4), b: nib2(6) };
            default:
                return null;
        }
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
