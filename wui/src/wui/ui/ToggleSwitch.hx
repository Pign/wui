package wui.ui;

import wui.View;

#if macro
import haxe.macro.Type;
import wui.macros.UIBuilder.ViewNode;
import wui.macros.PrimitiveCtx;
#end

/**
 * A toggle switch control. Maps to WinUI ToggleSwitch.
 *
 * Usage:
 *   new ToggleSwitch("Dark Mode", darkModeState)
 */
@:wuiPrimitive
class ToggleSwitch extends View {
    public function new(?label:String, ?binding:Dynamic) {
        super("ToggleSwitch");
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
        return { viewType: "ToggleSwitch", children: [], modifiers: [], properties: props };
    }

    public static function wuiEmit(node:ViewNode, ctx:EmitCtx):String {
        var varName = ctx.nextVar("toggle");
        ctx.lines.push('winrt_controls::ToggleSwitch $varName;');

        var label = node.properties.get("label");
        if (label != null) {
            var escaped = ctx.escapeWideString(Std.string(label));
            ctx.lines.push('$varName.Header(winrt::box_value(L"$escaped"));');
        }

        var boundState = node.properties.get("boundState");
        if (boundState != null) {
            var stateName = Std.string(boundState);
            var id = ctx.cppId(stateName);
            ctx.lines.push('$varName.IsOn(s_$id);');
            ctx.lines.push('$varName.Toggled([](winrt::Windows::Foundation::IInspectable const& sender, winrt_xaml::RoutedEventArgs const&) {');
            ctx.lines.push('    s_$id = sender.as<winrt_controls::ToggleSwitch>().IsOn();');
            ctx.lines.push('    notify_$id();');
            ctx.lines.push('});');
            ctx.pushStateBinding({
                stateName: stateName,
                controlVar: varName,
                format: '$varName.IsOn(s_$id);'
            });
        }

        ctx.applyModifiers(varName, "ToggleSwitch", node.modifiers);
        return varName;
    }
    #end
}
