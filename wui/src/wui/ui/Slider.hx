package wui.ui;

import wui.View;

#if macro
import haxe.macro.Type;
import wui.macros.UIBuilder.ViewNode;
import wui.macros.PrimitiveCtx;
#end

/**
 * A slider control for numeric ranges. Maps to WinUI Slider.
 *
 * Usage:
 *   new Slider(0, 100, volumeState)
 */
@:wuiPrimitive
class Slider extends View {
    public function new(min:Float, max:Float, ?binding:Dynamic, ?step:Float) {
        super("Slider");
        properties.set("min", min);
        properties.set("max", max);
        if (binding != null) properties.set("binding", binding);
        if (step != null) properties.set("step", step);
    }

    #if macro
    public static function wuiAnalyze(args:Array<TypedExpr>, ctx:AnalyzeCtx):ViewNode {
        var props:Map<String, Dynamic> = new Map();
        if (args.length > 0) props.set("min", ctx.extractFloat(args[0]));
        if (args.length > 1) props.set("max", ctx.extractFloat(args[1]));
        if (args.length > 2) {
            var stateRef = ctx.extractStateRef(args[2]);
            if (stateRef != null) props.set("boundState", stateRef);
        }
        if (args.length > 3) props.set("step", ctx.extractFloat(args[3]));
        return { viewType: "Slider", children: [], modifiers: [], properties: props };
    }

    /** Two-way binding casts to/from `int` — the @:state primitive
        for the slider value is Int by convention; if you wanted Float
        accuracy you'd bind a different field. Listener guards against
        the round-trip the ValueChanged handler itself would otherwise
        cause when the C++ side pushes a new value. */
    public static function wuiEmit(node:ViewNode, ctx:EmitCtx):String {
        var varName = ctx.nextVar("slider");
        ctx.lines.push('winrt_controls::Slider $varName;');

        var min = node.properties.get("min");
        var max = node.properties.get("max");
        if (min != null) ctx.lines.push('$varName.Minimum($min);');
        if (max != null) ctx.lines.push('$varName.Maximum($max);');

        var step = node.properties.get("step");
        if (step != null) ctx.lines.push('$varName.StepFrequency($step);');

        var boundState = node.properties.get("boundState");
        if (boundState != null) {
            var stateName = Std.string(boundState);
            var id = ctx.cppId(stateName);
            ctx.lines.push('$varName.Value(static_cast<double>(s_$id));');
            ctx.lines.push('$varName.ValueChanged([](winrt::Windows::Foundation::IInspectable const&, winrt_controls::Primitives::RangeBaseValueChangedEventArgs const& e) {');
            ctx.lines.push('    s_$id = static_cast<int>(e.NewValue());');
            ctx.lines.push('    notify_$id();');
            ctx.lines.push('});');
            ctx.pushStateBinding({
                stateName: stateName,
                controlVar: varName,
                format: '$varName.Value(static_cast<double>(s_$id));'
            });
        }

        ctx.applyModifiers(varName, "Slider", node.modifiers);
        return varName;
    }
    #end
}
