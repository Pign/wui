package wui.ui;

import wui.View;
import wui.state.StateAction;

#if macro
import haxe.macro.Type;
import wui.macros.UIBuilder.ViewNode;
import wui.macros.PrimitiveCtx;
#end

/**
 * A clickable button. Maps to WinUI Button.
 *
 * Usage:
 *   new Button("Click me", null, count.inc(1))
 *   new Button("Submit", myIcon, submitAction)
 */
@:wuiPrimitive
class Button extends View {
    public function new(label:String, ?icon:Dynamic, ?action:StateAction) {
        super("Button");
        properties.set("label", label);
        if (icon != null) properties.set("icon", icon);
        if (action != null) properties.set("action", action);
    }

    /** Set a callback function instead of a StateAction. */
    public function onClick(callback:() -> Void):Button {
        properties.set("onClick", callback);
        return cast this;
    }

    #if macro
    /** Args: (label, ?icon, ?action). The action — `StateAction` enum
        ctor — is pre-compiled to a C++ snippet by `extractStateAction`
        and stashed under `onClick`. The runtime `action` field on the
        View is dead code (the macro analyses the typed AST before
        runtime, so the View instance is never constructed). */
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

    /** Three click sources, in priority order:
         1. `onClick` (pre-compiled snippet from `extractStateAction`)
         2. `action` (legacy path — still present from older callers)
         3. Auto-wire by label: `+ / - / Reset` against the first
            @:state field, for counter-style demos that don't bother
            with `StateAction.Custom`.
        Auto-wire is the only path that depends on `stateFields`. */
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

        var action = node.properties.get("action");
        if (action != null) {
            var actionCode = wui.macros.UIBuilder.generateStateActionCode(action);
            ctx.lines.push('$varName.Click([](winrt::Windows::Foundation::IInspectable const&, winrt_xaml::RoutedEventArgs const&) {');
            ctx.lines.push('    $actionCode');
            ctx.lines.push('});');
        }

        if (onClick == null && action == null && ctx.stateFields.length > 0) {
            var sf = ctx.stateFields[0];
            var labelStr = label != null ? Std.string(label) : "";
            var clickCode:String = null;
            if (labelStr == "+" || labelStr == "Increment" || labelStr == "+ Increment") {
                clickCode = 's_${ctx.cppId(sf.name)}++; notify_${ctx.cppId(sf.name)}();';
            } else if (labelStr == "-" || labelStr == "Decrement" || labelStr == "- Decrement") {
                clickCode = 's_${ctx.cppId(sf.name)}--; notify_${ctx.cppId(sf.name)}();';
            } else if (labelStr == "Reset") {
                clickCode = 's_${ctx.cppId(sf.name)} = ${sf.initial}; notify_${ctx.cppId(sf.name)}();';
            }
            if (clickCode != null) {
                ctx.lines.push('$varName.Click([](winrt::Windows::Foundation::IInspectable const&, winrt_xaml::RoutedEventArgs const&) {');
                ctx.lines.push('    $clickCode');
                ctx.lines.push('});');
            }
        }

        ctx.applyModifiers(varName, "Button", node.modifiers);
        return varName;
    }
    #end
}
