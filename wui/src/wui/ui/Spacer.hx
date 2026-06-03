package wui.ui;

import wui.View;

#if macro
import haxe.macro.Type;
import wui.macros.UIBuilder.ViewNode;
import wui.macros.PrimitiveCtx;
#end

/**
 * A flexible spacer that expands to fill available space.
 * In a VStack/HStack, it pushes siblings apart.
 */
@:wuiPrimitive
class Spacer extends View {
    public function new(?minSize:Float) {
        super("Spacer");
        if (minSize != null) properties.set("minSize", minSize);
    }

    #if macro
    public static function wuiAnalyze(args:Array<TypedExpr>, ctx:AnalyzeCtx):ViewNode {
        var props:Map<String, Dynamic> = new Map();
        if (args.length > 0) {
            var minSize = ctx.extractFloat(args[0]);
            if (minSize != null) props.set("minSize", minSize);
        }
        return { viewType: "Spacer", children: [], modifiers: [], properties: props };
    }

    /** Implemented as a Border stretched in both directions — that's
        what makes it absorb leftover space inside a StackPanel.
        Note: deliberately skips `applyModifiers` (legacy behaviour) —
        a Spacer with `.padding()` or `.width()` would defeat its
        elasticity, so we don't pretend to honour those. */
    public static function wuiEmit(node:ViewNode, ctx:EmitCtx):String {
        var varName = ctx.nextVar("spacer");
        ctx.lines.push('winrt_controls::Border $varName;');
        ctx.lines.push('$varName.HorizontalAlignment(winrt_xaml::HorizontalAlignment::Stretch);');
        ctx.lines.push('$varName.VerticalAlignment(winrt_xaml::VerticalAlignment::Stretch);');
        var minSize = node.properties.get("minSize");
        if (minSize != null) {
            ctx.lines.push('$varName.MinWidth($minSize);');
            ctx.lines.push('$varName.MinHeight($minSize);');
        }
        return varName;
    }
    #end
}
