package wui.ui;

import wui.View;

#if macro
import haxe.macro.Type;
import wui.macros.UIBuilder.ViewNode;
import wui.macros.PrimitiveCtx;
#end

/**
 * Visibility gate keyed on a `@:state` Bool field.
 *
 *   new Show(isConnected, mailClientView)
 *   new Show(isLoginShown, loginForm)
 *
 * The child view is always built (it's part of the static tree) but
 * its `Visibility` flips between `Visible` and `Collapsed` whenever
 * the bound state changes — no re-render, no allocation, just a XAML
 * property write. That's enough to swap screens for the common
 * "login → main app" transition without bringing in a real
 * `ConditionalView` (which would need rebuild semantics).
 *
 * MVP shape: first arg is a `@:state` Bool reference, second arg is
 * the child View. Negation (show when *false*) isn't supported here
 * yet — declare a companion `@:state` and flip both, or wait for
 * `.hiddenWhen(...)` to land.
 */
@:wuiPrimitive
class Show extends View {
    public function new(when:Dynamic, child:View) {
        super("Show", [child]);
        properties.set("when", when);
    }

    #if macro
    public static function wuiAnalyze(args:Array<TypedExpr>, ctx:AnalyzeCtx):ViewNode {
        var stateRef = args.length > 0 ? ctx.extractStateRef(args[0]) : null;
        var children = args.length > 1 ? [ctx.recurseChild(args[1])] : [];
        var props:Map<String, Dynamic> = new Map();
        if (stateRef != null) props.set("boundState", stateRef);
        return { viewType: "Show", children: children, modifiers: [], properties: props };
    }

    /** Wraps the child in a `ContentControl` (the WinUI generic
        "holds any UIElement" container) and binds its Visibility
        to the @:state Bool. The change listener defers via
        `DispatcherQueue.TryEnqueue` for the same reason every state
        binding does — synchronous Visibility flips from inside a Haxe
        worker would fight the XAML compositor. */
    public static function wuiEmit(node:ViewNode, ctx:EmitCtx):String {
        var varName = ctx.nextVar("show");
        ctx.lines.push('winrt_controls::ContentControl $varName;');
        // ContentControl defaults to Left/Top alignment for its
        // content — that leaves a flex-layout child sitting in the
        // corner of an otherwise empty pane. We want the child to
        // fill the slot Show occupies.
        ctx.lines.push('$varName.HorizontalAlignment(winrt_xaml::HorizontalAlignment::Stretch);');
        ctx.lines.push('$varName.VerticalAlignment(winrt_xaml::VerticalAlignment::Stretch);');
        ctx.lines.push('$varName.HorizontalContentAlignment(winrt_xaml::HorizontalAlignment::Stretch);');
        ctx.lines.push('$varName.VerticalContentAlignment(winrt_xaml::VerticalAlignment::Stretch);');
        if (node.children.length > 0) {
            var childVar = ctx.emitChild(node.children[0]);
            ctx.lines.push('$varName.Content($childVar);');
        }
        var boundState = node.properties.get("boundState");
        if (boundState != null) {
            var name = Std.string(boundState);
            var id = ctx.cppId(name);
            var setVis = '$varName.Visibility(s_$id ? winrt_xaml::Visibility::Visible : winrt_xaml::Visibility::Collapsed);';
            ctx.lines.push(setVis);
            ctx.lines.push('s_${id}_listeners.push_back([$varName]() {');
            ctx.lines.push('    if (wui::runtime::dispatcherQueue) {');
            ctx.lines.push('        wui::runtime::dispatcherQueue.TryEnqueue([$varName]() {');
            ctx.lines.push('            $setVis');
            ctx.lines.push('        });');
            ctx.lines.push('    }');
            ctx.lines.push('});');
        }
        ctx.applyModifiers(varName, "ContentControl", node.modifiers);
        return varName;
    }
    #end
}
