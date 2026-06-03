package wui.ui;

import wui.View;

#if macro
import haxe.macro.Context;
import haxe.macro.Type;
import wui.macros.UIBuilder.ViewNode;
import wui.macros.PrimitiveCtx;
#end

/**
 * Repeats a view template for each item in a collection.
 *
 *   new ForEach(items, (item) -> new HStack([
 *       new Text(item.from),
 *       new Text(item.subject),
 *   ]))
 *
 * `items` must be a `@:state` field whose type implements
 * `wui.state.Immutable` (typically `ImmutableList<T>`). The macro
 * recognises that via the synthetic `<name>__v:Int` companion the
 * `StateMacro` adds — that companion is the bridge trigger ForEach
 * subscribes to for re-rendering.
 *
 * Constructor signature stays `Dynamic`-typed so callers don't have
 * to surface a specific item type at the View level — the actual
 * accessors that read `item.<field>` are built at compile time from
 * the template body's `<param>.<field>` references.
 */
@:wuiPrimitive
class ForEach extends View {
    public function new(items:Dynamic, template:Dynamic) {
        super("ForEach");
        properties.set("items", items);
        properties.set("template", template);
    }

    #if macro
    /** Build the ForEach ViewNode. The template body is restricted
        (MVP) to a single HStack or VStack root containing only Text
        children whose argument is either a string literal or
        `<param>.<field>`. Anything outside this envelope warns +
        falls back to `defaultNode()` so the build keeps going. */
    public static function wuiAnalyze(args:Array<TypedExpr>, ctx:AnalyzeCtx):ViewNode {
        if (args.length < 2) {
            Context.warning("ForEach: expected (items, template) — got fewer args", Context.currentPos());
            return ctx.defaultNode();
        }

        var stateName = extractStateNameFromAnyField(args[0]);
        if (stateName == null) {
            Context.warning("ForEach: could not resolve the @:state field name from the first argument. Pass the bare field, e.g. `new ForEach(inbox, ...)`.", Context.currentPos());
            return ctx.defaultNode();
        }

        var versionKey = stateName + "__v";
        var hasVersion = false;
        for (sf in wui.macros.UIBuilder.stateFields) if (sf.name == versionKey) { hasVersion = true; break; }
        if (!hasVersion) {
            Context.warning('ForEach: state "$stateName" has no `__v` companion — is it declared as `@:state var $stateName:ImmutableList<...>`?', Context.currentPos());
            return ctx.defaultNode();
        }

        var lambdaParamName:String = null;
        var lambdaItemVar:haxe.macro.Type.TVar = null;
        var lambdaIdxName:String = null;
        var lambdaBody:TypedExpr = null;
        switch (args[1].expr) {
            case TFunction(tf):
                if (tf.args.length > 0) {
                    lambdaParamName = tf.args[0].v.name;
                    lambdaItemVar = tf.args[0].v;
                }
                // Optional second arg = row index. When provided, the
                // ForEach codegen routes typed `(Int) -> Void` Custom
                // callbacks (and direct `idx` references in closures)
                // through a parametric wrapper that receives the C++
                // loop counter at runtime.
                if (tf.args.length > 1) lambdaIdxName = tf.args[1].v.name;
                lambdaBody = tf.expr;
            default:
                Context.warning("ForEach: second argument must be a lambda `(item) -> view` or `(item, idx) -> view`", Context.currentPos());
                return ctx.defaultNode();
        }
        if (lambdaBody == null || lambdaParamName == null) return ctx.defaultNode();

        lambdaBody = unwrapReturnAndBlock(lambdaBody);

        // Drill down through any TCall modifier chain on the template
        // root AND through Phase 3 user-component inlining, in a single
        // loop. Each TCall layer yields one modifier we'll apply to the
        // row container in wuiEmit ; each TNew(UserComponent) triggers
        // an inline pass that may itself produce more TCalls (the
        // component's body may have its own `.padding()` etc.). After
        // the loop, `lambdaBody` should be a `TNew(HStack/VStack, …)`
        // — that's the row's panel orientation + children.
        //
        // We set `foreachContextIdxName` on WinUIGenerator for the
        // duration of the walk so `extractStateAction` (reached
        // transitively from `modifierFromCall` for `.onTap(...)`) can
        // route typed `(Int) -> Void` Custom callbacks through the
        // parametric wrapper path. Reset right after.
        var rowModifiers:Array<wui.macros.UIBuilder.ModifierData> = [];
        var prevForeachIdx = wui.macros.WinUIGenerator.foreachContextIdxName;
        var prevForeachItemVar = wui.macros.WinUIGenerator.foreachContextItemVar;
        var prevForeachState = wui.macros.WinUIGenerator.foreachContextStateName;
        wui.macros.WinUIGenerator.foreachContextIdxName = lambdaIdxName;
        wui.macros.WinUIGenerator.foreachContextItemVar = lambdaItemVar;
        wui.macros.WinUIGenerator.foreachContextStateName = stateName;
        var walking = true;
        while (walking) {
            walking = false;
            switch (lambdaBody.expr) {
                case TCall(func, callArgs):
                    switch (func.expr) {
                        case TField(obj, fa):
                            var fieldName = switch (fa) {
                                case FInstance(_, _, cf): cf.get().name;
                                case FStatic(_, cf): cf.get().name;
                                case FAnon(cf): cf.get().name;
                                case FClosure(_, cf): cf.get().name;
                                default: null;
                            };
                            if (fieldName != null) {
                                var mod = wui.macros.WinUIGenerator.modifierFromCall(fieldName, callArgs);
                                if (mod != null) rowModifiers.unshift(mod);
                            }
                            lambdaBody = obj;
                            walking = true;
                        default:
                    }
                case TNew(clsRef, _, newArgs):
                    var cls = clsRef.get();
                    var fullName = cls.pack.join(".") + (cls.pack.length > 0 ? "." : "") + cls.name;
                    if (fullName != "wui.ui.HStack" && fullName != "wui.ui.VStack"
                        && wui.macros.WinUIGenerator.isUserViewComponent(cls)) {
                        var inlined = wui.macros.WinUIGenerator.inlineUserBodyExpr(cls, newArgs);
                        if (inlined != null) {
                            lambdaBody = unwrapReturnAndBlock(inlined);
                            walking = true;
                        }
                    }
                default:
            }
        }
        wui.macros.WinUIGenerator.foreachContextIdxName = prevForeachIdx;
        wui.macros.WinUIGenerator.foreachContextItemVar = prevForeachItemVar;
        wui.macros.WinUIGenerator.foreachContextStateName = prevForeachState;

        var rowOrientation = "Horizontal";
        var childExprs:Array<TypedExpr> = [];
        switch (lambdaBody.expr) {
            case TNew(clsRef, _, newArgs):
                var cls = clsRef.get();
                var fullName = cls.pack.join(".") + (cls.pack.length > 0 ? "." : "") + cls.name;
                switch (fullName) {
                    case "wui.ui.HStack": rowOrientation = "Horizontal";
                    case "wui.ui.VStack": rowOrientation = "Vertical";
                    default:
                        Context.warning('ForEach (MVP): template root must be HStack or VStack, got $fullName', Context.currentPos());
                        return ctx.defaultNode();
                }
                if (newArgs.length > 0) {
                    switch (newArgs[0].expr) {
                        case TArrayDecl(items): childExprs = items;
                        default:
                    }
                }
            default:
                Context.warning("ForEach (MVP): template body must directly return `new HStack(...)` or `new VStack(...)`", Context.currentPos());
                return ctx.defaultNode();
        }

        var childSpecs:Array<Dynamic> = [];
        for (childExpr in childExprs) {
            var spec = analyzeTextChild(childExpr, lambdaParamName, stateName);
            if (spec != null) childSpecs.push(spec);
        }

        wui.macros.WinUIGenerator.foreachAccessorLengths.set(stateName, true);

        var props:Map<String, Dynamic> = new Map();
        props.set("foreachStateName", stateName);
        props.set("foreachVersionKey", versionKey);
        props.set("foreachRowOrientation", rowOrientation);
        props.set("foreachChildSpecs", childSpecs);
        if (rowModifiers.length > 0) props.set("foreachRowModifiers", rowModifiers);
        return { viewType: "ForEach", children: [], modifiers: [], properties: props };
    }

    /** Emit a vertical StackPanel + `std::function<void()>` rebuild
        closure. We synchronously call the closure once (initial
        render — safe, we're on the UI thread inside BuildUI), then
        push a copy into `s_<versionKey>_listeners`. Each listener
        defers the rebuild to the next dispatcher tick via
        `TryEnqueue` — synchronous re-renders from inside a Haxe
        lambda trigger the same XAML compositor re-entrance crash
        the state-binding subscriptions guard against.

        The std::function lifetime is what keeps the StackPanel
        handle alive: it captures the panel by value (cheap WinRT
        smart-pointer copy), and the listener captures the
        std::function by value, so the closure persists for the
        window's lifetime — exactly what we want for a list. */
    public static function wuiEmit(node:ViewNode, ctx:EmitCtx):String {
        var panelVar = ctx.nextVar("foreach_panel");
        var rebuildVar = "rebuild_" + panelVar;

        ctx.lines.push('winrt_controls::StackPanel $panelVar;');
        ctx.lines.push('$panelVar.Orientation(winrt_controls::Orientation::Vertical);');

        var stateName = Std.string(node.properties.get("foreachStateName"));
        var versionKey = Std.string(node.properties.get("foreachVersionKey"));
        var rowOrientation = Std.string(node.properties.get("foreachRowOrientation"));
        var childSpecs:Array<Dynamic> = cast node.properties.get("foreachChildSpecs");
        if (childSpecs == null) childSpecs = [];

        var rowModsAny:Dynamic = node.properties.get("foreachRowModifiers");
        var rowMods:Array<wui.macros.UIBuilder.ModifierData> =
            rowModsAny != null ? cast rowModsAny : [];

        ctx.lines.push('std::function<void()> $rebuildVar = [$panelVar]() {');
        ctx.lines.push('    $panelVar.Children().Clear();');
        ctx.lines.push('    int _count = ::wui::generated::ForEachAccessor_obj::${stateName}_length();');
        ctx.lines.push('    for (int i = 0; i < _count; i++) {');
        ctx.lines.push('        winrt_controls::StackPanel _row;');
        ctx.lines.push('        _row.Orientation(winrt_controls::Orientation::$rowOrientation);');
        // Modifiers chainés sur la racine du template lambda (collectés
        // par wuiAnalyze en walkant la TCall chain). Le OnTap est
        // traité à part parce que son snippet peut référencer `i` (le
        // loop counter de la boucle row) — le Tapped handler doit donc
        // capturer `[i]` explicitement. Les autres modifiers (padding,
        // background, etc.) passent par le chemin standard.
        var rowTapSnippets:Array<String> = [];
        var rowOtherMods:Array<wui.macros.UIBuilder.ModifierData> = [];
        for (m in rowMods) {
            if (m.type == "OnTap") rowTapSnippets.push(Std.string(m.values[0]));
            else rowOtherMods.push(m);
        }
        if (rowOtherMods.length > 0) ctx.applyModifiers("_row", "StackPanel", rowOtherMods);
        for (snippet in rowTapSnippets) {
            ctx.lines.push('        _row.Tapped([i](winrt::Windows::Foundation::IInspectable const&, winrt::Microsoft::UI::Xaml::Input::TappedRoutedEventArgs const&) {');
            ctx.lines.push('            $snippet');
            ctx.lines.push('        });');
        }

        for (spec in childSpecs) {
            var kind:String = spec.kind;
            var specMods:Dynamic = spec.modifiers;
            var mods:Array<wui.macros.UIBuilder.ModifierData> =
                specMods != null ? cast specMods : [];
            switch (kind) {
                case "static":
                    var literal:String = spec.text != null ? spec.text : "";
                    var escaped = ctx.escapeWideString(literal);
                    ctx.lines.push('        {');
                    ctx.lines.push('            winrt_controls::TextBlock _t;');
                    ctx.lines.push('            _t.Text(L"$escaped");');
                    if (mods.length > 0) ctx.applyModifiers("_t", "TextBlock", mods);
                    ctx.lines.push('            _row.Children().Append(_t);');
                    ctx.lines.push('        }');
                case "dynamic":
                    var fieldStateName:String = spec.stateName;
                    var fieldName:String = spec.fieldName;
                    ctx.lines.push('        {');
                    ctx.lines.push('            winrt_controls::TextBlock _t;');
                    ctx.lines.push('            ::String _s = ::wui::generated::ForEachAccessor_obj::${fieldStateName}_field_${fieldName}(i);');
                    ctx.lines.push('            _t.Text(winrt::hstring(reinterpret_cast<const wchar_t*>(_s.wc_str()), _s.length));');
                    if (mods.length > 0) ctx.applyModifiers("_t", "TextBlock", mods);
                    ctx.lines.push('            _row.Children().Append(_t);');
                    ctx.lines.push('        }');
                default:
                    ctx.lines.push('        // Unknown ForEach child kind: $kind');
            }
        }

        ctx.lines.push('        $panelVar.Children().Append(_row);');
        ctx.lines.push('    }');
        ctx.lines.push('};');
        ctx.lines.push('$rebuildVar();');

        var versionId = ctx.cppId(versionKey);
        ctx.lines.push('s_${versionId}_listeners.push_back([$rebuildVar]() {');
        ctx.lines.push('    if (wui::runtime::dispatcherQueue) {');
        ctx.lines.push('        wui::runtime::dispatcherQueue.TryEnqueue([$rebuildVar]() { $rebuildVar(); });');
        ctx.lines.push('    }');
        ctx.lines.push('});');

        ctx.applyModifiers(panelVar, "StackPanel", node.modifiers);
        return panelVar;
    }

    // ---- Private analyze helpers ----

    /** Field-name extraction tolerant of `inbox`, `this.inbox`, and
        TLocal aliases. We don't go through `extractStateRef` because
        Immutable @:state fields aren't in `UIBuilder.stateFields`
        (only their `__v` companion is). The `<name>__v` lookup is
        the real Immutable signal. */
    static function extractStateNameFromAnyField(expr:TypedExpr):String {
        if (expr == null) return null;
        switch (expr.expr) {
            case TField(_, fa):
                return switch (fa) {
                    case FInstance(_, _, cf): cf.get().name;
                    case FDynamic(s): s;
                    default: null;
                };
            case TLocal(v):
                return v.name;
            default:
                return null;
        }
    }

    /** Strip TBlock([TReturn(e)]) / single-elem TBlock / TReturn / TMeta
        / TParenthesis wrappers so the caller can pattern-match the
        actual `new XStack(...)` expression. */
    static function unwrapReturnAndBlock(e:TypedExpr):TypedExpr {
        if (e == null) return null;
        switch (e.expr) {
            case TBlock(exprs):
                if (exprs.length == 1) return unwrapReturnAndBlock(exprs[0]);
                if (exprs.length > 0) return unwrapReturnAndBlock(exprs[exprs.length - 1]);
                return e;
            case TReturn(inner):
                if (inner != null) return unwrapReturnAndBlock(inner);
                return e;
            case TMeta(_, inner):
                return unwrapReturnAndBlock(inner);
            case TParenthesis(inner):
                return unwrapReturnAndBlock(inner);
            default:
                return e;
        }
    }

    /** Per-row Text child: either `new Text("literal")` or
        `new Text(<param>.<field>)`. The dynamic form registers the
        field accessor on `WinUIGenerator.foreachAccessorFields` so
        `emitForEachAccessorModule` produces the matching Haxe
        accessor. */
    static function analyzeTextChild(expr:TypedExpr, lambdaParamName:String, stateName:String):Dynamic {
        if (expr == null) return null;

        // Descente dans la chaîne de modifiers : `new Text(x).font(F).foregroundColor(C)`
        // est un TCall(TField(TCall(TField(TNew(Text), font), [F]), foregroundColor), [C]).
        // On déroule en collectant les ModifierData, jusqu'à atteindre le TNew(Text)
        // sous-jacent. L'ordre source→appel (font puis foregroundColor) est
        // restauré via unshift.
        var modifiers:Array<wui.macros.UIBuilder.ModifierData> = [];
        var cur = expr;
        var walking = true;
        while (walking) {
            walking = false;
            switch (cur.expr) {
                case TCall(func, callArgs):
                    switch (func.expr) {
                        case TField(obj, fa):
                            var fieldName = switch (fa) {
                                case FInstance(_, _, cf): cf.get().name;
                                case FStatic(_, cf): cf.get().name;
                                case FAnon(cf): cf.get().name;
                                case FClosure(_, cf): cf.get().name;
                                default: null;
                            };
                            if (fieldName != null) {
                                var mod = wui.macros.WinUIGenerator.modifierFromCall(fieldName, callArgs);
                                if (mod != null) modifiers.unshift(mod);
                            }
                            cur = obj;
                            walking = true;
                        default:
                    }
                default:
            }
        }

        switch (cur.expr) {
            case TNew(clsRef, _, newArgs):
                var cls = clsRef.get();
                var fullName = cls.pack.join(".") + (cls.pack.length > 0 ? "." : "") + cls.name;
                if (fullName != "wui.ui.Text") {
                    Context.warning('ForEach (MVP): only `new Text(...)` rows are supported, got $fullName', Context.currentPos());
                    return null;
                }
                if (newArgs.length == 0) return { kind: "static", text: "", modifiers: modifiers };
                var arg = newArgs[0];
                switch (arg.expr) {
                    case TConst(TString(s)):
                        return { kind: "static", text: s, modifiers: modifiers };
                    case TField(receiver, fa):
                        var fieldName = switch (fa) {
                            case FAnon(cf): cf.get().name;
                            case FInstance(_, _, cf): cf.get().name;
                            case FClosure(_, cf): cf.get().name;
                            case FDynamic(s): s;
                            default: null;
                        };
                        if (fieldName == null) {
                            Context.warning("ForEach: unsupported Text argument shape", arg.pos);
                            return null;
                        }
                        var isLambdaParam = switch (receiver.expr) {
                            case TLocal(v): v.name == lambdaParamName;
                            default: false;
                        };
                        if (!isLambdaParam) {
                            Context.warning('ForEach: Text argument must be `${lambdaParamName}.<field>` or a literal', arg.pos);
                            return null;
                        }
                        var key = stateName + "::" + fieldName;
                        wui.macros.WinUIGenerator.foreachAccessorFields.set(key, {
                            stateName: stateName,
                            fieldName: fieldName,
                            fieldType: "String"
                        });
                        return {
                            kind: "dynamic",
                            stateName: stateName,
                            fieldName: fieldName,
                            modifiers: modifiers
                        };
                    default:
                        Context.warning("ForEach (MVP): Text argument must be a literal or a single field access on the lambda param", arg.pos);
                        return null;
                }
            default:
                Context.warning("ForEach (MVP): row children must be `new Text(...)`", expr.pos);
                return null;
        }
    }
    #end
}
