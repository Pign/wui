package wui.ui;

import wui.View;

#if macro
import haxe.macro.Type;
import wui.macros.UIBuilder.ViewNode;
import wui.macros.PrimitiveCtx;
#end

/**
 * A circular progress indicator. Maps to WinUI ProgressRing.
 *
 * Usage:
 *   new ProgressRing()           // indeterminate
 *   new ProgressRing(0.5)        // 50% progress
 */
@:wuiPrimitive
class ProgressRing extends View {
    public function new(?value:Float) {
        super("ProgressRing");
        if (value != null) {
            properties.set("value", value);
            properties.set("isIndeterminate", false);
        } else {
            properties.set("isIndeterminate", true);
        }
    }

    #if macro
    public static function wuiAnalyze(args:Array<TypedExpr>, ctx:AnalyzeCtx):ViewNode {
        var props:Map<String, Dynamic> = new Map();
        if (args.length > 0) {
            props.set("value", ctx.extractFloat(args[0]));
            props.set("isIndeterminate", "false");
        } else {
            props.set("isIndeterminate", "true");
        }
        return { viewType: "ProgressRing", children: [], modifiers: [], properties: props };
    }

    public static function wuiEmit(node:ViewNode, ctx:EmitCtx):String {
        var varName = ctx.nextVar("prog");
        ctx.lines.push('winrt_controls::ProgressRing $varName;');
        var isIndeterminate = node.properties.get("isIndeterminate");
        if (isIndeterminate == "true" || isIndeterminate == true) {
            ctx.lines.push('$varName.IsIndeterminate(true);');
        } else {
            ctx.lines.push('$varName.IsIndeterminate(false);');
            var value = node.properties.get("value");
            if (value != null) ctx.lines.push('$varName.Value($value);');
        }
        ctx.applyModifiers(varName, "ProgressRing", node.modifiers);
        return varName;
    }
    #end
}
