package wui.ui;

import wui.View;

#if macro
import haxe.macro.Type;
import wui.macros.UIBuilder.ViewNode;
import wui.macros.PrimitiveCtx;
#end

/**
 * Displays an image. Maps to WinUI Image.
 *
 * Usage:
 *   new Image("assets/logo.png")
 *       .frame(200, 200)
 */
@:wuiPrimitive
class Image extends View {
    public function new(source:String) {
        super("Image");
        properties.set("source", source);
    }

    #if macro
    public static function wuiAnalyze(args:Array<TypedExpr>, ctx:AnalyzeCtx):ViewNode {
        var props:Map<String, Dynamic> = new Map();
        if (args.length > 0) props.set("source", ctx.extractString(args[0]));
        return { viewType: "Image", children: [], modifiers: [], properties: props };
    }

    /** WinUI Image takes a BitmapImage built from a `Uri`. Local
        relative paths like `"assets/logo.png"` work as long as
        ms-appx://// or pack URI handling kicks in upstream; the user
        is responsible for putting the asset somewhere the URI
        resolves. */
    public static function wuiEmit(node:ViewNode, ctx:EmitCtx):String {
        var varName = ctx.nextVar("img");
        ctx.lines.push('winrt_controls::Image $varName;');
        var source = node.properties.get("source");
        if (source != null) {
            var escaped = ctx.escapeWideString(Std.string(source));
            ctx.lines.push('{');
            ctx.lines.push('    winrt::Microsoft::UI::Xaml::Media::Imaging::BitmapImage bmp;');
            ctx.lines.push('    bmp.UriSource(winrt::Windows::Foundation::Uri(L"$escaped"));');
            ctx.lines.push('    $varName.Source(bmp);');
            ctx.lines.push('}');
        }
        ctx.applyModifiers(varName, "Image", node.modifiers);
        return varName;
    }
    #end
}
