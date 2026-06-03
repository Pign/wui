package wui.ui;

import wui.View;

#if macro
import haxe.macro.Type;
import wui.macros.UIBuilder.ViewNode;
import wui.macros.PrimitiveCtx;
#end

/**
 * Horizontal stack layout. Maps to WinUI StackPanel with Horizontal orientation.
 *
 * Usage:
 *   new HStack([
 *       new Text("Left"),
 *       new Spacer(),
 *       new Text("Right")
 *   ])
 */
@:wuiPrimitive
class HStack extends View {
    public function new(children:Array<View>, ?spacing:Float) {
        super("StackPanel", children);
        properties.set("orientation", "Horizontal");
        if (spacing != null) properties.set("spacing", spacing);
    }

    #if macro
    /** Same ViewNode shape as VStack, just `orientation = Horizontal`.
        Emit is shared via the "StackPanel" entry in the emit registry —
        VStack owns the implementation, HStack only contributes analyze. */
    public static function wuiAnalyze(args:Array<TypedExpr>, ctx:AnalyzeCtx):ViewNode {
        var children = args.length > 0 ? ctx.recurseChildren(args[0]) : [];
        var spacing = args.length > 1 ? ctx.extractFloat(args[1]) : null;
        var props:Map<String, Dynamic> = new Map();
        props.set("orientation", "Horizontal");
        if (spacing != null) props.set("spacing", spacing);
        return { viewType: "StackPanel", children: children, modifiers: [], properties: props };
    }
    #end
}
