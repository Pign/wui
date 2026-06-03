package wui.ui;

import wui.View;

#if macro
import haxe.macro.Type;
import wui.macros.UIBuilder.ViewNode;
import wui.macros.PrimitiveCtx;
#end

/**
 * Text input field. Maps to WinUI TextBox.
 *
 * Usage:
 *   new TextBox("Enter name...")
 *       .width(200)
 */
@:wuiPrimitive
class TextBox extends View {
    public function new(?placeholder:String, ?binding:Dynamic) {
        super("TextBox");
        if (placeholder != null) properties.set("placeholder", placeholder);
        if (binding != null) properties.set("binding", binding);
    }

    #if macro
    public static function wuiAnalyze(args:Array<TypedExpr>, ctx:AnalyzeCtx):ViewNode {
        var props:Map<String, Dynamic> = new Map();
        if (args.length > 0) {
            var placeholder = ctx.extractString(args[0]);
            if (placeholder != null) props.set("placeholder", placeholder);
        }
        if (args.length > 1) {
            var stateRef = ctx.extractStateRef(args[1]);
            if (stateRef != null) props.set("boundState", stateRef);
        }
        return { viewType: "TextBox", children: [], modifiers: [], properties: props };
    }

    /** Two-way binding: TextBox.Text → C++ static (on TextChanged) AND
        listener subscription that pushes C++ → TextBox.Text on
        change-from-Haxe. The `if (Text() != s_...)` guard in the
        listener avoids a re-entry loop with the TextChanged handler
        (setting Text fires TextChanged, which would notify, which
        would call the listener…). */
    public static function wuiEmit(node:ViewNode, ctx:EmitCtx):String {
        var varName = ctx.nextVar("textBox");
        ctx.lines.push('winrt_controls::TextBox $varName;');

        var placeholder = node.properties.get("placeholder");
        if (placeholder != null) {
            var escaped = ctx.escapeWideString(Std.string(placeholder));
            ctx.lines.push('$varName.PlaceholderText(L"$escaped");');
        }

        var boundState = node.properties.get("boundState");
        if (boundState != null) {
            var stateName = Std.string(boundState);
            var id = ctx.cppId(stateName);
            ctx.lines.push('$varName.Text(winrt::hstring(s_$id));');
            ctx.lines.push('$varName.TextChanged([](winrt::Windows::Foundation::IInspectable const& sender, winrt_controls::TextChangedEventArgs const&) {');
            ctx.lines.push('    auto h = sender.as<winrt_controls::TextBox>().Text();');
            ctx.lines.push('    s_$id = std::wstring(h.c_str(), h.size());');
            ctx.lines.push('    notify_$id();');
            ctx.lines.push('});');
            ctx.pushStateBinding({
                stateName: stateName,
                controlVar: varName,
                format: 'if ($varName.Text() != winrt::hstring(s_$id)) $varName.Text(winrt::hstring(s_$id));'
            });
        }

        ctx.applyModifiers(varName, "TextBox", node.modifiers);
        return varName;
    }
    #end
}
