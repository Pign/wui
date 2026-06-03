package wui.ui;

import wui.View;

#if macro
import haxe.macro.Type;
import wui.macros.UIBuilder.ViewNode;
import wui.macros.PrimitiveCtx;
#end

/**
 * Displays read-only text. Maps to WinUI TextBlock.
 *
 * Usage:
 *   new Text("Hello World")
 *       .font(TitleLarge)
 *       .foregroundColor(AccentColor)
 */
@:wuiPrimitive
class Text extends View {
    public function new(content:Dynamic) {
        super("TextBlock");
        properties.set("text", content);
    }

    #if macro
    /**
     * The argument is either a literal (`"Hello"`), a state-bound
     * expression (`"Count: " + count`, decoded via `extractStateBoundText`),
     * or a direct state ref handled by the same helper. The
     * `boundState` + `boundFormat` props travel to `wuiEmit` and there
     * drive both the initial `Text(...)` and the listener subscription.
     */
    public static function wuiAnalyze(args:Array<TypedExpr>, ctx:AnalyzeCtx):ViewNode {
        var props:Map<String, Dynamic> = new Map();
        var textArg = args.length > 0 ? args[0] : null;
        var bound = textArg != null ? ctx.extractStateBoundText(textArg) : null;
        if (bound != null) {
            props.set("text", bound.text);
            props.set("boundState", bound.boundState);
            props.set("boundFormat", bound.format);
        } else {
            var text = args.length > 0 ? ctx.extractString(args[0]) : "Text";
            props.set("text", text);
        }
        return { viewType: "TextBlock", children: [], modifiers: [], properties: props };
    }

    /** Three cases:
         - Explicit binding (`boundState != null`): use `boundFormat` for
           both the initial set and the listener body, swapping `CTRL`
           for the var name so the format string is reusable.
         - Plain literal text: emit `Text(L"...")` once.
         - Auto-bind heuristic: if the literal happens to match a known
           @:state field's initial value, treat it as a binding. Legacy
           behaviour kept for counter-style demos. */
    public static function wuiEmit(node:ViewNode, ctx:EmitCtx):String {
        var varName = ctx.nextVar("text");
        ctx.lines.push('winrt_controls::TextBlock $varName;');

        var text = node.properties.get("text");
        var boundState = node.properties.get("boundState");
        var boundFormat = node.properties.get("boundFormat");

        if (boundState != null) {
            var stateName = Std.string(boundState);
            var format = boundFormat != null
                ? Std.string(boundFormat)
                : '$varName.Text(wui::runtime::toHString(s_${ctx.cppId(stateName)}));';
            format = StringTools.replace(format, "CTRL", varName);
            ctx.lines.push(format);
            ctx.pushStateBinding({ stateName: stateName, controlVar: varName, format: format });
        } else if (text != null) {
            var escaped = ctx.escapeWideString(Std.string(text));
            ctx.lines.push('$varName.Text(L"$escaped");');
        }

        if (boundState == null && ctx.stateFields.length > 0 && text != null) {
            var textStr = Std.string(text);
            for (sf in ctx.stateFields) {
                if (textStr == sf.initial || textStr == Std.string(Std.parseInt(sf.initial))) {
                    ctx.pushStateBinding({
                        stateName: sf.name,
                        controlVar: varName,
                        format: '$varName.Text(winrt::hstring(std::to_wstring(s_${ctx.cppId(sf.name)})));'
                    });
                    break;
                }
            }
        }

        ctx.applyModifiers(varName, "TextBlock", node.modifiers);
        return varName;
    }
    #end
}
