package wui.ui;

import wui.View;
import wui.state.StateAction;

#if macro
import haxe.macro.Type;
import wui.macros.UIBuilder.ViewNode;
import wui.macros.PrimitiveCtx;
#end

/**
 * A clickable button. Maps to WinUI `Button`.
 *
 * The third constructor arg is a `StateAction` — now just a typedef
 * over `() -> Void`. Pass a closure or a static function reference :
 *
 *   new Button("Click me",     null, () -> count.value++);
 *   new Button("Save changes", null, MyApp.save);
 */
@:wuiPrimitive
class Button extends View {
    public function new(label:String, ?icon:Dynamic, ?action:StateAction) {
        super("Button");
        properties.set("label", label);
        if (icon != null) properties.set("icon", icon);
        if (action != null) properties.set("action", action);
    }

    /** Modifier-chain alias for the constructor's `action` arg —
        chain it after construction when the action isn't known at
        ctor time, or for the modifier-style fluency. */
    public function onClick(callback:() -> Void):Button {
        properties.set("onClick", callback);
        return cast this;
    }

    #if macro
    /** Args: (label, ?icon, ?action). The action is converted by
        `extractStateAction` into a C++ snippet (static-fn wrapper
        call, lambda-lift call, or — in a ForEach row context —
        a builder-backed `regHandler/runHandler` pair). The runtime
        `action` field on the View is never read (the macro analyses
        the typed AST ; the View instance isn't constructed). */
    public static function wuiAnalyze(args:Array<TypedExpr>, ctx:AnalyzeCtx):ViewNode {
        var label = args.length > 0 ? ctx.extractString(args[0]) : "Button";
        var props:Map<String, Dynamic> = new Map();
        props.set("label", label);
        if (args.length > 2) {
            var actionCode = ctx.extractStateAction(args[2]);
            if (actionCode != null) {
                props.set("onClick", actionCode);
            }
        }
        return { viewType: "Button", children: [], modifiers: [], properties: props };
    }

    public static function wuiEmit(node:ViewNode, ctx:EmitCtx):String {
        var varName = ctx.nextVar("btn");
        ctx.lines.push('winrt_controls::Button $varName;');

        var label = node.properties.get("label");
        if (label != null) {
            var escaped = ctx.escapeWideString(Std.string(label));
            ctx.lines.push('$varName.Content(winrt::box_value(L"$escaped"));');
        }

        var onClick = node.properties.get("onClick");
        if (onClick != null) {
            var code = Std.string(onClick);
            ctx.lines.push('$varName.Click([](winrt::Windows::Foundation::IInspectable const&, winrt_xaml::RoutedEventArgs const&) {');
            ctx.lines.push('    $code');
            ctx.lines.push('});');
        }

        ctx.applyModifiers(varName, "Button", node.modifiers);
        return varName;
    }
    #end
}
