package wui.ui;

import wui.View;

#if macro
import haxe.macro.Type;
import wui.macros.UIBuilder.ViewNode;
import wui.macros.PrimitiveCtx;
#end

/**
 * Vertical stack layout. Maps to WinUI StackPanel with Vertical orientation.
 *
 * Usage:
 *   new VStack([
 *       new Text("Top"),
 *       new Text("Bottom")
 *   ]).spacing(8)
 */
@:wuiPrimitive
class VStack extends View {
    public function new(children:Array<View>, ?spacing:Float) {
        super("StackPanel", children);
        properties.set("orientation", "Vertical");
        if (spacing != null) properties.set("spacing", spacing);
    }

    #if macro
    /**
     * Build a `StackPanel`-flavoured ViewNode from the constructor
     * args. `spacing` is optional; absent → no Spacing() call emitted.
     */
    public static function wuiAnalyze(args:Array<TypedExpr>, ctx:AnalyzeCtx):ViewNode {
        var children = args.length > 0 ? ctx.recurseChildren(args[0]) : [];
        var spacing = args.length > 1 ? ctx.extractFloat(args[1]) : null;
        var props:Map<String, Dynamic> = new Map();
        props.set("orientation", "Vertical");
        if (spacing != null) props.set("spacing", spacing);
        return { viewType: "StackPanel", children: children, modifiers: [], properties: props };
    }

    /**
     * Shared StackPanel emit — also installed for HStack (orientation
     * differs in the ViewNode only). Reads `orientation` and optional
     * `spacing` off properties, runs the modifier chain, then walks
     * children via `ctx.emitChild`. The caller (`UIBuilder.generateNode`)
     * appends our return varName to its parent if any.
     */
    public static function wuiEmit(node:ViewNode, ctx:EmitCtx):String {
        var varName = ctx.nextVar("panel");
        ctx.lines.push('winrt_controls::StackPanel $varName;');

        var orientation = node.properties.get("orientation");
        if (orientation == "Horizontal") {
            ctx.lines.push('$varName.Orientation(winrt_controls::Orientation::Horizontal);');
        } else {
            ctx.lines.push('$varName.Orientation(winrt_controls::Orientation::Vertical);');
        }

        var spacing = node.properties.get("spacing");
        if (spacing != null) {
            ctx.lines.push('$varName.Spacing($spacing);');
        }

        ctx.applyModifiers(varName, "StackPanel", node.modifiers);

        for (child in node.children) {
            var childVar = ctx.emitChild(child);
            ctx.lines.push('$varName.Children().Append($childVar);');
        }

        return varName;
    }
    #end
}
