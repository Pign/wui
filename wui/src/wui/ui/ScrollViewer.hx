package wui.ui;

import wui.View;

#if macro
import haxe.macro.Type;
import wui.macros.UIBuilder.ViewNode;
import wui.macros.PrimitiveCtx;
#end

/**
 * A scrollable container. Maps to WinUI ScrollViewer.
 *
 * Usage:
 *   new ScrollViewer(
 *       new VStack(longListOfItems)
 *   )
 */
@:wuiPrimitive
class ScrollViewer extends View {
    public function new(content:View) {
        super("ScrollViewer", [content]);
    }

    #if macro
    public static function wuiAnalyze(args:Array<TypedExpr>, ctx:AnalyzeCtx):ViewNode {
        var children = args.length > 0 ? [ctx.recurseChild(args[0])] : [];
        return { viewType: "ScrollViewer", children: children, modifiers: [], properties: new Map() };
    }

    public static function wuiEmit(node:ViewNode, ctx:EmitCtx):String {
        var varName = ctx.nextVar("scroll");
        ctx.lines.push('winrt_controls::ScrollViewer $varName;');
        if (node.children.length > 0) {
            var contentVar = ctx.emitChild(node.children[0]);
            ctx.lines.push('$varName.Content($contentVar);');
        }
        ctx.applyModifiers(varName, "ScrollViewer", node.modifiers);
        return varName;
    }
    #end
}
