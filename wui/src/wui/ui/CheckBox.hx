package wui.ui;

import wui.View;

#if macro
import haxe.macro.Type;
import wui.macros.UIBuilder.ViewNode;
import wui.macros.PrimitiveCtx;
#end

/**
 * A checkbox control. Maps to WinUI CheckBox.
 *
 * Usage:
 *   new CheckBox("Accept terms", acceptedState)
 */
@:wuiPrimitive
class CheckBox extends View {
    public function new(?label:String, ?binding:Dynamic) {
        super("CheckBox");
        if (label != null) properties.set("label", label);
        if (binding != null) properties.set("binding", binding);
    }

    #if macro
    public static function wuiAnalyze(args:Array<TypedExpr>, ctx:AnalyzeCtx):ViewNode {
        var props:Map<String, Dynamic> = new Map();
        if (args.length > 0) {
            var label = ctx.extractString(args[0]);
            if (label != null) props.set("label", label);
        }
        if (args.length > 1) {
            var stateRef = ctx.extractStateRef(args[1]);
            if (stateRef != null) props.set("boundState", stateRef);
        }
        return { viewType: "CheckBox", children: [], modifiers: [], properties: props };
    }

    /** Two-way binding via Checked / Unchecked event pair — WinUI's
        CheckBox doesn't expose a single `Toggled` event the way
        ToggleSwitch does. Both handlers update the same C++ static. */
    public static function wuiEmit(node:ViewNode, ctx:EmitCtx):String {
        var varName = ctx.nextVar("cb");
        ctx.lines.push('winrt_controls::CheckBox $varName;');

        var label = node.properties.get("label");
        if (label != null) {
            var escaped = ctx.escapeWideString(Std.string(label));
            ctx.lines.push('$varName.Content(winrt::box_value(L"$escaped"));');
        }

        var boundState = node.properties.get("boundState");
        if (boundState != null) {
            var stateName = Std.string(boundState);
            var id = ctx.cppId(stateName);
            ctx.lines.push('$varName.IsChecked(s_$id);');
            ctx.lines.push('$varName.Checked([](winrt::Windows::Foundation::IInspectable const&, winrt_xaml::RoutedEventArgs const&) {');
            ctx.lines.push('    s_$id = true; notify_$id();');
            ctx.lines.push('});');
            ctx.lines.push('$varName.Unchecked([](winrt::Windows::Foundation::IInspectable const&, winrt_xaml::RoutedEventArgs const&) {');
            ctx.lines.push('    s_$id = false; notify_$id();');
            ctx.lines.push('});');
            ctx.pushStateBinding({
                stateName: stateName,
                controlVar: varName,
                format: '$varName.IsChecked(s_$id);'
            });
        }

        ctx.applyModifiers(varName, "CheckBox", node.modifiers);
        return varName;
    }
    #end
}
