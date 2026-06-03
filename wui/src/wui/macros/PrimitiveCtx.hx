package wui.macros;

#if macro
import haxe.macro.Type;
import wui.macros.UIBuilder.ViewNode;
import wui.macros.UIBuilder.ModifierData;

/**
 * Compile-time contract every WUI primitive widget speaks.
 *
 * A primitive is any class tagged `@:wuiPrimitive` (or registered via
 * the static registry in [[WinUIGenerator]]). It owns two pieces of
 * codegen logic that used to live as separate cases in
 * `WinUIGenerator.analyzeNewExpr` and `UIBuilder.generateNodeImpl`:
 *
 *   public static function wuiAnalyze(args:Array<TypedExpr>, ctx:AnalyzeCtx):ViewNode;
 *   public static function wuiEmit(node:ViewNode, ctx:EmitCtx):String;
 *
 * The two ctx records carry every helper the migrated cases used to
 * reach for. We pass them in by closure rather than letting widgets
 * import [[UIBuilder]] / [[WinUIGenerator]] directly — that would
 * loop the import graph (UIBuilder→Widget→UIBuilder) and Haxe's macro
 * resolver doesn't love cyclic edges across `#if macro` boundaries.
 *
 * User-defined View subclasses don't need to implement this contract:
 * non-primitive views are decomposed by recursing into their `body()`
 * override (Phase 3 — to land after the existing primitives migrate).
 *
 * @see WinUIGenerator.primitiveRegistry
 * @see UIBuilder.emitRegistry
 */

/** Helpers the analyze phase calls into. The ones returning `String`
    use "..." as a sentinel for "couldn't extract", matching the legacy
    helpers' contract. Null returns mean "not present" (e.g. no binding,
    no spacing override). */
typedef AnalyzeCtx = {
    /** Recurse into a single child View expression. */
    recurseChild:TypedExpr -> ViewNode,

    /** Extract a TArrayDecl of View exprs as a flat ViewNode array.
        Single-expression args (no array literal) are wrapped in a
        one-element array so widgets don't have to branch. */
    recurseChildren:TypedExpr -> Array<ViewNode>,

    /** Static String / Int / Float literal extraction. Returns "..."
        when the expr isn't a literal — widgets use that as a "don't
        emit a static text" signal. */
    extractString:TypedExpr -> String,

    /** Float literal extraction. Null when not a literal. */
    extractFloat:TypedExpr -> Null<Float>,

    /** State-bound text: detects `"label " + count` patterns, returns
        the format string the runtime listener uses to update the
        widget's `.Text()`. Null when no binding is detected. */
    extractStateBoundText:TypedExpr -> Null<{text:String, boundState:String, format:String}>,

    /** Reference to a @:state field (e.g. for TextBox's two-way binding).
        Returns the bare field name ("searchQuery") or null. */
    extractStateRef:TypedExpr -> String,

    /** Compile the C++ snippet for a `StateAction` (used by Button). */
    extractStateAction:TypedExpr -> String,

    /** Default placeholder ViewNode — for "couldn't understand this
        expression" paths. */
    defaultNode:Void -> ViewNode,
};

/** Helpers the emit phase calls into. `lines` is the list the widget
    pushes C++ statements into; the caller (UIBuilder) takes care of
    indentation and joining. Modifiers + state-binding listener
    registration are handled by helpers so widgets don't all duplicate
    the same boilerplate. */
typedef EmitCtx = {
    lines:Array<String>,
    depth:Int,

    /** Allocate a unique C++ variable name with the given prefix. */
    nextVar:String -> String,

    /** Recurse to emit a child ViewNode, returns its var name. The
        caller wraps each child with `parent.Children().Append(child)`
        — widgets don't have to remember that. */
    emitChild:ViewNode -> String,

    /** Apply the View's modifier chain (padding, width, foreground
        colour, etc.) to a freshly-emitted control. */
    applyModifiers:String -> String -> Array<ModifierData> -> Void,

    /** Push a state-binding entry so the change listener for that
        state name will update this control on every notification. */
    pushStateBinding:{stateName:String, controlVar:String, format:String} -> Void,

    /** Map a (possibly dotted, observable-keyed) state name to a
        legal C++ identifier suffix: "settings.darkMode" -> "settings_darkMode". */
    cppId:String -> String,

    /** Escape an arbitrary string for emission inside `L"..."`. */
    escapeWideString:String -> String,

    /** Discovered @:state fields (name + C++ type + initial value).
        Reused by `TextBlock` for the "if the literal text matches a
        state initial, auto-bind it" path. */
    stateFields:Array<{name:String, type:String, initial:String}>,
};
#end
