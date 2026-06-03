package wui.ui;

import wui.View;

#if macro
import haxe.macro.Type;
import wui.macros.UIBuilder.ViewNode;
import wui.macros.PrimitiveCtx;
#end

/**
 * Overlapping layout. Maps to WinUI Grid with all children in the same cell.
 *
 * Usage:
 *   new ZStack([
 *       new Image("background.png"),
 *       new Text("Overlay text")
 *   ])
 */
@:wuiPrimitive
class ZStack extends View {
    public function new(children:Array<View>) {
        super("Grid", children);
        properties.set("overlapping", true);
    }

    #if macro
    public static function wuiAnalyze(args:Array<TypedExpr>, ctx:AnalyzeCtx):ViewNode {
        var children = args.length > 0 ? ctx.recurseChildren(args[0]) : [];
        return { viewType: "Grid", children: children, modifiers: [], properties: new Map() };
    }

    /** ZStack semantics — every child lands in the same grid cell so
        they overlap visually. No row/column definitions; Grid's default
        behaviour stacks children at (0,0) with z-order matching insertion. */
    public static function wuiEmit(node:ViewNode, ctx:EmitCtx):String {
        var varName = ctx.nextVar("grid");
        ctx.lines.push('winrt_controls::Grid $varName;');
        ctx.applyModifiers(varName, "Grid", node.modifiers);
        for (child in node.children) {
            var childVar = ctx.emitChild(child);
            ctx.lines.push('$varName.Children().Append($childVar);');
        }
        return varName;
    }
    #end
}
