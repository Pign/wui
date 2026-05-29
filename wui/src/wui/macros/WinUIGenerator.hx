package wui.macros;

#if macro
import haxe.macro.Context;
import haxe.macro.Compiler;
import haxe.macro.Type;
import haxe.macro.Expr;
import sys.io.File;
import sys.FileSystem;
import haxe.io.Path;
import wui.macros.UIBuilder.ViewNode;
import wui.macros.UIBuilder.ModifierData;

using haxe.macro.Tools;
#end

/**
 * Main code generation orchestrator. Registered as a macro in build.hxml:
 *   --macro wui.macros.WinUIGenerator.register()
 *
 * After Haxe compilation completes, this macro:
 * 1. Finds all App subclasses
 * 2. Analyzes their body() method to build a ViewNode tree
 * 3. Calls ProjectGenerator to emit .vcxproj, packages.config, pch.h
 * 4. Calls BridgeGenerator to emit App.h/cpp, WuiRuntime.h
 * 5. Calls UIBuilder to emit MainWindow.h/cpp with imperative C++/WinRT code
 */
class WinUIGenerator {
    #if macro
    static var registered:Bool = false;
    static var collectedTypes:Array<Type> = [];

    /** Map of fully-qualified Haxe static function path -> generated C
        wrapper name. Each unique callback gets a wrapper, regenerated
        only on first reference (subsequent references reuse the name). */
    static var callbackRegistry:Map<String, String> = new Map();

    /** Anonymous lambdas passed to `StateAction.Custom(() -> {...})`.
        We can't share wrappers (each lambda has its own body), so this
        is a plain list. Names are unique within the build. */
    static var lambdaRegistry:Array<{name:String, body:haxe.macro.Type.TypedExpr}> = [];

    /**
     * Call this from build.hxml:
     *   --macro wui.macros.WinUIGenerator.register()
     */
    public static function register():Void {
        if (registered) return;
        registered = true;

        // Collect types AND run the analysis during typing — this is
        // crucial because `Context.defineType` (used by
        // `emitCallbackModule`) must run before code generation starts,
        // otherwise the generated `wui.generated.Callbacks` class never
        // makes it into the static lib.
        Context.onAfterTyping(function(types:Array<haxe.macro.Type.ModuleType>) {
            for (mt in types) {
                switch (mt) {
                    case TClassDecl(ref):
                        var cls = ref.get();
                        if (isAppSubclass(cls)) {
                            collectedTypes.push(TInst(ref, []));
                        }
                    default:
                }
            }
            if (!analyzed && collectedTypes.length > 0) {
                analyze();
                analyzed = true;
            }
        });

        // Emit the C++/WinRT files after all generation is done.
        Context.onAfterGenerate(function() {
            emit();
        });
    }

    static var analyzed:Bool = false;
    static var cachedViewTree:ViewNode;
    static var cachedAppName:String;
    static var cachedDisplayName:String;
    static var cachedWindowWidth:Int;
    static var cachedWindowHeight:Int;
    static var cachedBackdrop:String;
    static var cachedTitleBarTree:ViewNode;

    /** Analyse the first collected App subclass: extract names, state
        fields, body() ViewNode tree, and (critically) emit the
        synthesised `wui.generated.Callbacks` and `wui.generated.StateAccessor`
        modules so hxcpp picks them up during normal compilation. */
    static function analyze():Void {
        var appType = collectedTypes[0];
        cachedAppName = getClassName(appType);
        cachedDisplayName = getDisplayName(appType);
        cachedWindowWidth = getWindowWidth(appType);
        cachedWindowHeight = getWindowHeight(appType);
        cachedBackdrop = getBackdrop(appType);
        UIBuilder.stateFields = collectStateFields(appType);
        cachedViewTree = buildViewTree(appType);
        cachedTitleBarTree = buildTitleBarTree(appType);
        collectEffects(appType);
        emitCallbackModule();
        // Note: state read/write from Haxe lambdas goes through the
        // stable `wui.state.StateBridge` class in the wui lib. The
        // per-type dispatch functions it calls are emitted by UIBuilder
        // when MainWindow.cpp is generated — no per-app generated type.
    }

    /** Emit a `wui.generated.StateAccessor` Haxe class with get/set
        methods for every @:state field. Each method bridges to the
        matching `extern "C" clw_state_get/set_<name>` defined in
        MainWindow.cpp via `untyped __cpp__`. This is what lambda
        click handlers use to read / write @:state fields. */
    static function emitStateAccessorModule():Void {
        if (UIBuilder.stateFields.length == 0) return;
        var pos = haxe.macro.Context.currentPos();
        var fields:Array<haxe.macro.Expr.Field> = [];
        for (sf in UIBuilder.stateFields) {
            var setterBody:String;
            var getterBody:String;
            var argType:haxe.macro.Expr.ComplexType;
            var retType:haxe.macro.Expr.ComplexType;
            switch (sf.type) {
                case "std::wstring":
                    argType = macro :String; retType = macro :String;
                    setterBody = '{ untyped __cpp__(\'clw_state_set_${sf.name}(reinterpret_cast<const wchar_t*>(({0}).wc_str()), ({0}).length)\', v); }';
                    getterBody = '{ var r:String = ""; untyped __cpp__(\'const wchar_t* _buf; int _len; clw_state_get_${sf.name}(&_buf, &_len); {0} = ::String((const char16_t*)_buf, _len);\', r); return r; }';
                case "int":
                    argType = macro :Int; retType = macro :Int;
                    setterBody = '{ untyped __cpp__(\'clw_state_set_${sf.name}({0})\', v); }';
                    getterBody = '{ var r:Int = 0; untyped __cpp__(\'{0} = clw_state_get_${sf.name}()\', r); return r; }';
                case "double":
                    argType = macro :Float; retType = macro :Float;
                    setterBody = '{ untyped __cpp__(\'clw_state_set_${sf.name}({0})\', v); }';
                    getterBody = '{ var r:Float = 0.0; untyped __cpp__(\'{0} = clw_state_get_${sf.name}()\', r); return r; }';
                case "bool":
                    argType = macro :Bool; retType = macro :Bool;
                    setterBody = '{ untyped __cpp__(\'clw_state_set_${sf.name}({0})\', v); }';
                    getterBody = '{ var r:Bool = false; untyped __cpp__(\'{0} = clw_state_get_${sf.name}()\', r); return r; }';
                default:
                    continue;
            }
            fields.push({
                name: 'set_${sf.name}',
                pos: pos,
                meta: [{ name: ":keep", pos: pos }],
                access: [APublic, AStatic],
                kind: FFun({
                    args: [{ name: "v", type: argType }],
                    ret: macro :Void,
                    expr: haxe.macro.Context.parse(setterBody, pos)
                })
            });
            fields.push({
                name: 'get_${sf.name}',
                pos: pos,
                meta: [{ name: ":keep", pos: pos }],
                access: [APublic, AStatic],
                kind: FFun({
                    args: [],
                    ret: retType,
                    expr: haxe.macro.Context.parse(getterBody, pos)
                })
            });
        }
        haxe.macro.Context.defineType({
            pos: pos,
            pack: ["wui", "generated"],
            name: "StateAccessor",
            kind: TDClass(),
            fields: fields,
            meta: [{ name: ":keep", pos: pos }]
        });
    }

    /** Emit the C++/WinRT project files. Runs at `onAfterGenerate`, by
        which time `analyze()` has populated everything we need. */
    static function emit():Void {
        var cppOutput = Compiler.getOutput();
        if (cppOutput == null) cppOutput = "build/cpp";
        var buildDir = Path.directory(cppOutput);
        if (buildDir == "") buildDir = ".";
        var winuiDir = Path.join([buildDir, "winui"]);
        if (!FileSystem.exists(winuiDir)) FileSystem.createDirectory(winuiDir);

        if (cachedViewTree == null) {
            Context.warning("wui: No App subclass found. Create a class extending wui.App.", Context.currentPos());
            return;
        }

        Sys.println('[wui] Generating C++/WinRT project for "$cachedAppName" (display "$cachedDisplayName")...');

        ProjectGenerator.generate(cachedAppName, winuiDir);
        Sys.println("[wui]   Generated .vcxproj, packages.config, pch.h");

        BridgeGenerator.generate(cachedAppName, cachedDisplayName, winuiDir, cachedWindowWidth, cachedWindowHeight, cachedBackdrop, cachedTitleBarTree != null);
        Sys.println("[wui]   Generated App.h, App.cpp, WuiRuntime.h");

        UIBuilder.generateMainWindow(cachedViewTree, cachedTitleBarTree, winuiDir);
        Sys.println("[wui]   Generated MainWindow.h, MainWindow.cpp");

        Sys.println('[wui] C++/WinRT project generated at: $winuiDir');
    }

    /**
     * Collect @:state fields from the App subclass.
     */
    static function collectStateFields(type:Type):Array<{name:String, type:String, initial:String}> {
        var result:Array<{name:String, type:String, initial:String}> = [];
        switch (type) {
            case TInst(ref, _):
                var cls = ref.get();
                for (field in cls.fields.get()) {
                    // Check if the field is a State<T> type
                    switch (field.type) {
                        case TInst(tref, params):
                            var typeName = tref.get().name;
                            if (typeName == "State" && params.length > 0) {
                                var cppType = "int"; // default
                                var initial = "0";

                                // Pull the declared default expression out of
                                // the `@:wuiInitial` meta StateMacro stashed.
                                var explicitInitial:String = null;
                                for (m in field.meta.get()) {
                                    if (m.name == ":wuiInitial" && m.params != null && m.params.length > 0) {
                                        explicitInitial = exprToCppLiteral(m.params[0]);
                                    }
                                }

                                switch (params[0]) {
                                    case TAbstract(aref, _):
                                        var aname = aref.get().name;
                                        if (aname == "Int") { cppType = "int"; initial = explicitInitial != null ? explicitInitial : "0"; }
                                        else if (aname == "Float") { cppType = "double"; initial = explicitInitial != null ? explicitInitial : "0.0"; }
                                        else if (aname == "Bool") { cppType = "bool"; initial = explicitInitial != null ? explicitInitial : "false"; }
                                    case TInst(sref, _):
                                        if (sref.get().name == "String") {
                                            cppType = "std::wstring";
                                            initial = explicitInitial != null ? explicitInitial : 'L""';
                                        }
                                    default:
                                }
                                result.push({ name: field.name, type: cppType, initial: initial });
                            }
                        default:
                    }
                }
            default:
        }
        return result;
    }

    /** Render an untyped (build-macro-time) Expr as a C++ literal of
        the matching type — used to seed `s_<name>` from `@:wuiInitial`
        in MainWindow.cpp. Returns null when the expression isn't a
        recognisable literal (caller falls back to a per-type default). */
    static function exprToCppLiteral(expr:haxe.macro.Expr):String {
        if (expr == null) return null;
        switch (expr.expr) {
            case EConst(CString(s, _)):
                return 'L"' + UIBuilder.escapeWideString(s) + '"';
            case EConst(CInt(s, _)):
                return s;
            case EConst(CFloat(s, _)):
                return s;
            case EConst(CIdent(i)) if (i == "true" || i == "false"):
                return i;
            default:
                return null;
        }
    }

    static function isAppSubclass(cls:ClassType):Bool {
        if (cls.superClass == null) return false;
        var superRef = cls.superClass.t.get();
        if (superRef.pack.join(".") == "wui" && superRef.name == "App") return true;
        return isAppSubclass(superRef);
    }

    /** Plain Haxe class name — used for filenames + the App C++ class. */
    static function getClassName(type:Type):String {
        switch (type) {
            case TInst(ref, _): return ref.get().name;
            default: return "WuiApp";
        }
    }

    /**
     * User-facing display name. Read from the `appName():String` override
     * if it returns a string literal, else falls back to the class name.
     * Used for the window title; never used for filenames (so it can
     * contain spaces and non-ASCII).
     */
    static function getDisplayName(type:Type):String {
        switch (type) {
            case TInst(ref, _):
                var cls = ref.get();
                for (field in cls.fields.get()) {
                    if (field.name == "appName") {
                        switch (field.type) {
                            case TFun(_, ret):
                                if (field.expr() != null) {
                                    var str = extractStringReturn(field.expr());
                                    if (str != null) return str;
                                }
                            default:
                        }
                    }
                }
                return cls.name;
            default:
                return "WuiApp";
        }
    }

    /**
     * Window backdrop material. Read from the `backdrop():Backdrop`
     * override if the body is a single `return EnumCtor;`, else falls
     * back to "Mica" (the App.backdrop default — see wui.App.hx).
     *
     * Returned as the bare constructor name ("Mica", "MicaAlt",
     * "Acrylic", "None") so BridgeGenerator can switch on it without
     * pulling the Backdrop enum into the macro caller.
     */
    static function getBackdrop(type:Type):String {
        switch (type) {
            case TInst(ref, _):
                var cls = ref.get();
                for (field in cls.fields.get()) {
                    if (field.name == "backdrop") {
                        if (field.expr() != null) {
                            var name = extractEnumReturn(field.expr());
                            if (name != null && name != "") return name;
                        }
                    }
                }
            default:
        }
        return "Mica";
    }

    /** Walk a typed function body looking for a `return EnumCtor;` and
        return the constructor name. Mirrors `extractStringReturn` for
        nullary enum constructors (Mica, MicaAlt, Acrylic, None). */
    static function extractEnumReturn(texpr:TypedExpr):String {
        if (texpr == null) return null;
        switch (texpr.expr) {
            case TReturn(e):
                return extractEnumName(e);
            case TBlock(exprs):
                for (e in exprs) {
                    var s = extractEnumReturn(e);
                    if (s != null) return s;
                }
            case TFunction(tf):
                return extractEnumReturn(tf.expr);
            default:
        }
        return null;
    }

    static function getWindowWidth(type:Type):Int {
        return getIntField(type, "windowWidth", 800);
    }

    static function getWindowHeight(type:Type):Int {
        return getIntField(type, "windowHeight", 600);
    }

    static function getIntField(type:Type, fieldName:String, defaultVal:Int):Int {
        switch (type) {
            case TInst(ref, _):
                var cls = ref.get();
                for (field in cls.fields.get()) {
                    if (field.name == fieldName) {
                        if (field.expr() != null) {
                            var val = extractIntValue(field.expr());
                            if (val != null) return val;
                        }
                    }
                }
            default:
        }
        return defaultVal;
    }

    /**
     * Build a ViewNode tree from the `titleBar()` override, if one exists
     * AND its body actually returns a non-null View. Returns null
     * otherwise so codegen skips the BuildTitleBar function and the
     * system title bar stays in place.
     *
     * `cls.fields.get()` only lists own fields, so an unoverridden
     * `titleBar()` doesn't show up here — `null` is the natural answer.
     * When the user *does* override but still returns the literal `null`
     * (e.g. behind a runtime check), `returnsLiteralNull()` catches it
     * before `analyzeBodyExpr` falls through to its "Hello from WUI!"
     * defaultNode().
     */
    static function buildTitleBarTree(type:Type):ViewNode {
        switch (type) {
            case TInst(ref, _):
                var cls = ref.get();
                for (field in cls.fields.get()) {
                    if (field.name == "titleBar") {
                        if (field.expr() == null) return null;
                        if (returnsLiteralNull(field.expr())) return null;
                        return analyzeBodyExpr(field.expr());
                    }
                }
            default:
        }
        return null;
    }

    /** True iff the body is `{ return null; }` (or wraps to that after
        block/function unwrapping). Used to filter out the App.titleBar()
        no-op default before codegen runs. */
    static function returnsLiteralNull(texpr:TypedExpr):Bool {
        if (texpr == null) return false;
        switch (texpr.expr) {
            case TReturn(e):
                if (e == null) return true;
                switch (e.expr) {
                    case TConst(TNull): return true;
                    default: return false;
                }
            case TBlock(exprs):
                for (e in exprs) if (returnsLiteralNull(e)) return true;
            case TFunction(tf):
                return returnsLiteralNull(tf.expr);
            default:
        }
        return false;
    }

    /**
     * Scan `static function main()` for `wui.Effect.run(fn, [...deps])`
     * call sites. Each one lifts its lambda body into the Callbacks
     * module (reusing the click-handler infrastructure) and records the
     * dep list so UIBuilder can wire matching `s_<dep>_listeners`
     * subscriptions in BuildUI.
     *
     * Constraints surfaced via warnings (not hard errors — the macro
     * stays as friendly as possible during iteration):
     *  - The deps argument must be an inline array literal of string
     *    constants (`["unreadCount"]`), not a variable.
     *  - Each dep must match a declared `@:state` field.
     */
    static function collectEffects(type:Type):Void {
        UIBuilder.effects = [];
        switch (type) {
            case TInst(ref, _):
                var cls = ref.get();
                // Instance `effects():Void` override is the canonical
                // place — typed @:state refs are in scope there.
                for (f in cls.fields.get()) {
                    if (f.name == "effects" && f.expr() != null) {
                        scanForEffectCalls(f.expr());
                    }
                }
                // Legacy / escape-hatch: also scan static `main()` so
                // the old string-key form keeps working without forcing
                // users to migrate every effect at once.
                for (sf in cls.statics.get()) {
                    if (sf.name == "main" && sf.expr() != null) {
                        scanForEffectCalls(sf.expr());
                    }
                }
            default:
        }
    }

    static function scanForEffectCalls(texpr:TypedExpr):Void {
        if (texpr == null) return;
        switch (texpr.expr) {
            case TCall(callee, args):
                if (isEffectRunCall(callee) && args.length >= 2) {
                    registerEffectCall(args[0], args[1]);
                }
                scanForEffectCalls(callee);
                for (a in args) scanForEffectCalls(a);
            case TBlock(exprs):
                for (e in exprs) scanForEffectCalls(e);
            case TIf(c, t, e):
                scanForEffectCalls(c); scanForEffectCalls(t);
                if (e != null) scanForEffectCalls(e);
            case TWhile(c, b, _):
                scanForEffectCalls(c); scanForEffectCalls(b);
            case TTry(e, catches):
                scanForEffectCalls(e);
                for (c in catches) scanForEffectCalls(c.expr);
            case TReturn(e):
                if (e != null) scanForEffectCalls(e);
            case TVar(_, e):
                if (e != null) scanForEffectCalls(e);
            case TBinop(_, l, r):
                scanForEffectCalls(l); scanForEffectCalls(r);
            case TUnop(_, _, e):
                scanForEffectCalls(e);
            case TParenthesis(e):
                scanForEffectCalls(e);
            case TMeta(_, e):
                scanForEffectCalls(e);
            case TCast(e, _):
                scanForEffectCalls(e);
            case TFunction(tf):
                scanForEffectCalls(tf.expr);
            default:
        }
    }

    static function isEffectRunCall(callee:TypedExpr):Bool {
        if (callee == null) return false;
        switch (callee.expr) {
            case TField(_, fa):
                switch (fa) {
                    case FStatic(clsRef, cf):
                        var cls = clsRef.get();
                        var pack = cls.pack.join(".");
                        var path = (pack.length > 0 ? pack + "." : "") + cls.name;
                        return path == "wui.Effect" && cf.get().name == "run";
                    default: return false;
                }
            default: return false;
        }
    }

    /** Extract a `@:state` field name from a single deps-array entry.
        Accepts a string literal (legacy form) or a typed field access
        — `this.searchQuery` or implicit `searchQuery` from instance
        scope — provided the field is actually @:state-tagged. Returns
        `null` when neither shape matches. */
    static function extractDepName(item:TypedExpr):String {
        if (item == null) return null;
        switch (item.expr) {
            case TConst(TString(s)):
                return s;
            case TField(_, fa):
                var fieldName = switch (fa) {
                    case FInstance(_, _, cfRef): cfRef.get().name;
                    case FStatic(_, cfRef): cfRef.get().name;
                    case FDynamic(s): s;
                    default: null;
                };
                if (fieldName == null) return null;
                for (sf in UIBuilder.stateFields) {
                    if (sf.name == fieldName) return fieldName;
                }
                return null;
            case TParenthesis(e):
                return extractDepName(e);
            case TCast(e, _):
                return extractDepName(e);
            default:
                return null;
        }
    }

    static function registerEffectCall(lambdaExpr:TypedExpr, depsExpr:TypedExpr):Void {
        // Lift the lambda body. The user always writes
        // `() -> { ... }` so the typed shape is TFunction(tf); we hand
        // `tf.expr` (the body block) to registerLambda the same way
        // StateAction.Custom(...) does for click handlers.
        var body:TypedExpr = null;
        switch (lambdaExpr.expr) {
            case TFunction(tf):
                body = tf.expr;
            default:
                haxe.macro.Context.warning(
                    "wui.Effect.run: first argument must be a lambda literal `() -> { ... }`.",
                    lambdaExpr.pos);
                return;
        }
        if (body == null) return;
        var wrapperName = registerLambda(body);

        // Walk the deps array literal. Each entry is either:
        //   - a string literal (escape hatch for static contexts)
        //   - a typed `@:state` field reference (e.g. `searchQuery`),
        //     reachable from instance methods like `effects()`. We pull
        //     the field name straight off the typed AST so the binding
        //     survives Haxe-level renames.
        var deps:Array<String> = [];
        switch (depsExpr.expr) {
            case TArrayDecl(items):
                for (item in items) {
                    var name = extractDepName(item);
                    if (name != null) {
                        deps.push(name);
                    } else {
                        haxe.macro.Context.warning(
                            "wui.Effect.run: deps array entries must be string literals or @:state field references.",
                            item.pos);
                    }
                }
            default:
                haxe.macro.Context.warning(
                    "wui.Effect.run: deps must be an inline array literal — `[searchQuery]` or `[\"searchQuery\"]`.",
                    depsExpr.pos);
        }

        // Cross-check each dep names an actual @:state field — typos
        // here would silently never fire otherwise.
        for (d in deps) {
            var found = false;
            for (sf in UIBuilder.stateFields) if (sf.name == d) { found = true; break; }
            if (!found) {
                haxe.macro.Context.warning(
                    'wui.Effect.run: dep "$d" does not match any @:state field. The effect will run once but never re-run.',
                    depsExpr.pos);
            }
        }

        UIBuilder.effects.push({ wrapperName: wrapperName, deps: deps });
    }

    /**
     * Build a ViewNode tree by analyzing the body() method's AST.
     */
    static function buildViewTree(type:Type):ViewNode {
        switch (type) {
            case TInst(ref, _):
                var cls = ref.get();
                for (field in cls.fields.get()) {
                    if (field.name == "body") {
                        if (field.expr() != null) {
                            return analyzeBodyExpr(field.expr());
                        }
                    }
                }
            default:
        }

        // Default empty view
        var defaultProps:Map<String, Dynamic> = new Map();
        defaultProps.set("orientation", "Vertical");
        var textProps:Map<String, Dynamic> = new Map();
        textProps.set("text", "Hello from WUI!");
        return {
            viewType: "StackPanel",
            children: [{
                viewType: "TextBlock",
                children: [],
                modifiers: [],
                properties: textProps
            }],
            modifiers: [],
            properties: defaultProps
        };
    }

    /**
     * Analyze a typed expression to build a ViewNode tree.
     */
    // Map of local variable names to their expressions (for temp var resolution)
    static var localExprs:Map<String, TypedExpr> = new Map();

    static function analyzeBodyExpr(texpr:TypedExpr):ViewNode {
        if (texpr == null) {
            return defaultNode();
        }

        switch (texpr.expr) {
            case TReturn(e):
                if (e != null) return analyzeBodyExpr(e);

            case TBlock(exprs):
                // First pass: collect all local variable bindings
                for (expr in exprs) {
                    switch (expr.expr) {
                        case TVar(v, e):
                            if (e != null) localExprs.set(v.name, e);
                        default:
                    }
                }
                // Second pass: find the return or last expression
                for (expr in exprs) {
                    switch (expr.expr) {
                        case TReturn(e):
                            if (e != null) return analyzeBodyExpr(e);
                        default:
                    }
                }
                if (exprs.length > 0) {
                    return analyzeBodyExpr(exprs[exprs.length - 1]);
                }

            case TNew(cls, _, args):
                return analyzeNewExpr(cls.get(), args);

            case TCall(func, args):
                return analyzeCallExpr(func, args, texpr);

            case TParenthesis(e):
                return analyzeBodyExpr(e);

            case TFunction(tfunc):
                if (tfunc.expr != null) return analyzeBodyExpr(tfunc.expr);

            case TCast(e, _):
                return analyzeBodyExpr(e);

            case TLocal(v):
                // Resolve temp variables to their original expressions
                var resolved = localExprs.get(v.name);
                if (resolved != null) return analyzeBodyExpr(resolved);

            case TVar(v, e):
                if (e != null) {
                    localExprs.set(v.name, e);
                    return analyzeBodyExpr(e);
                }

            default:
                // Unhandled expression types are silently ignored
        }

        return defaultNode();
    }

    /**
     * Analyze a `new ClassName(args)` expression.
     */
    static function analyzeNewExpr(cls:ClassType, args:Array<TypedExpr>):ViewNode {
        var fullName = cls.pack.join(".") + (cls.pack.length > 0 ? "." : "") + cls.name;

        return switch (fullName) {
            case "wui.ui.VStack":
                var children = args.length > 0 ? extractChildArray(args[0]) : [];
                var spacing = args.length > 1 ? extractFloatValue(args[1]) : null;
                var props:Map<String, Dynamic> = new Map();
                props.set("orientation", "Vertical");
                if (spacing != null) props.set("spacing", spacing);
                { viewType: "StackPanel", children: children, modifiers: [], properties: props };

            case "wui.ui.HStack":
                var children = args.length > 0 ? extractChildArray(args[0]) : [];
                var spacing = args.length > 1 ? extractFloatValue(args[1]) : null;
                var props:Map<String, Dynamic> = new Map();
                props.set("orientation", "Horizontal");
                if (spacing != null) props.set("spacing", spacing);
                { viewType: "StackPanel", children: children, modifiers: [], properties: props };

            case "wui.ui.ZStack":
                var children = args.length > 0 ? extractChildArray(args[0]) : [];
                { viewType: "Grid", children: children, modifiers: [], properties: new Map() };

            case "wui.ui.Text":
                var props:Map<String, Dynamic> = new Map();
                // Check for state-bound text (e.g., "Count: " + count)
                var textArg = args.length > 0 ? args[0] : null;
                // Resolve local variable if needed
                if (textArg != null) {
                    switch (textArg.expr) {
                        case TLocal(v):
                            var resolved = localExprs.get(v.name);
                            if (resolved != null) textArg = resolved;
                        default:
                    }
                }
                var bound = textArg != null ? extractStateBoundText(textArg) : null;
                if (bound != null) {
                    props.set("text", bound.text);
                    props.set("boundState", bound.boundState);
                    props.set("boundFormat", bound.format);
                } else {
                    var text = args.length > 0 ? extractStringOrExpr(args[0]) : "Text";
                    props.set("text", text);
                }
                { viewType: "TextBlock", children: [], modifiers: [], properties: props };

            case "wui.ui.Button":
                var label = args.length > 0 ? extractStringOrExpr(args[0]) : "Button";
                var props:Map<String, Dynamic> = new Map();
                props.set("label", label);
                // args[1] = icon (optional), args[2] = action (StateAction)
                if (args.length > 2) {
                    var actionCode = extractStateAction(args[2]);
                    if (actionCode != null) {
                        props.set("onClick", actionCode);
                    }
                }
                { viewType: "Button", children: [], modifiers: [], properties: props };

            case "wui.ui.Spacer":
                var props:Map<String, Dynamic> = new Map();
                if (args.length > 0) {
                    var minSize = extractFloatValue(args[0]);
                    if (minSize != null) props.set("minSize", minSize);
                }
                { viewType: "Spacer", children: [], modifiers: [], properties: props };

            case "wui.ui.TextBox":
                var props:Map<String, Dynamic> = new Map();
                if (args.length > 0) {
                    var placeholder = extractStringOrExpr(args[0]);
                    if (placeholder != null) props.set("placeholder", placeholder);
                }
                if (args.length > 1) {
                    var stateRef = deepExtractStateRef(args[1]);
                    if (stateRef != null) props.set("boundState", stateRef);
                }
                { viewType: "TextBox", children: [], modifiers: [], properties: props };

            case "wui.ui.ToggleSwitch":
                var props:Map<String, Dynamic> = new Map();
                if (args.length > 0) {
                    var label = extractStringOrExpr(args[0]);
                    if (label != null) props.set("label", label);
                }
                if (args.length > 1) {
                    var stateRef = deepExtractStateRef(args[1]);
                    if (stateRef != null) props.set("boundState", stateRef);
                }
                { viewType: "ToggleSwitch", children: [], modifiers: [], properties: props };

            case "wui.ui.CheckBox":
                var props:Map<String, Dynamic> = new Map();
                if (args.length > 0) {
                    var label = extractStringOrExpr(args[0]);
                    if (label != null) props.set("label", label);
                }
                if (args.length > 1) {
                    var stateRef = deepExtractStateRef(args[1]);
                    if (stateRef != null) props.set("boundState", stateRef);
                }
                { viewType: "CheckBox", children: [], modifiers: [], properties: props };

            case "wui.ui.Slider":
                var props:Map<String, Dynamic> = new Map();
                if (args.length > 0) props.set("min", extractFloatValue(args[0]));
                if (args.length > 1) props.set("max", extractFloatValue(args[1]));
                // args[2] = binding, args[3] = step
                if (args.length > 2) {
                    var stateRef = deepExtractStateRef(args[2]);
                    if (stateRef != null) props.set("boundState", stateRef);
                }
                if (args.length > 3) props.set("step", extractFloatValue(args[3]));
                { viewType: "Slider", children: [], modifiers: [], properties: props };

            case "wui.ui.Image":
                var props:Map<String, Dynamic> = new Map();
                if (args.length > 0) props.set("source", extractStringOrExpr(args[0]));
                { viewType: "Image", children: [], modifiers: [], properties: props };

            case "wui.ui.ScrollViewer":
                var children = args.length > 0 ? [analyzeBodyExpr(args[0])] : [];
                { viewType: "ScrollViewer", children: children, modifiers: [], properties: new Map() };

            case "wui.ui.ProgressRing":
                var props:Map<String, Dynamic> = new Map();
                if (args.length > 0) {
                    props.set("value", extractFloatValue(args[0]));
                    props.set("isIndeterminate", "false");
                } else {
                    props.set("isIndeterminate", "true");
                }
                { viewType: "ProgressRing", children: [], modifiers: [], properties: props };

            default:
                defaultNode();
        };
    }

    /**
     * Analyze a method call — could be a modifier chain.
     */
    static function analyzeCallExpr(func:TypedExpr, args:Array<TypedExpr>, fullExpr:TypedExpr):ViewNode {
        switch (func.expr) {
            case TField(obj, fa):
                var fieldName = switch (fa) {
                    case FInstance(_, _, cf): cf.get().name;
                    case FStatic(_, cf): cf.get().name;
                    case FAnon(cf): cf.get().name;
                    case FDynamic(s): s;
                    case FClosure(_, cf): cf.get().name;
                    case FEnum(_, ef): ef.name;
                };

                var baseNode = analyzeBodyExpr(obj);

                var modifier = extractModifier(fieldName, args);
                if (modifier != null) {
                    baseNode.modifiers.push(modifier);
                }

                return baseNode;
            default:
        }

        return defaultNode();
    }

    /**
     * Extract a modifier from a method name and arguments.
     */
    static function extractModifier(name:String, args:Array<TypedExpr>):ModifierData {
        return switch (name) {
            case "padding":
                var amount = args.length > 0 ? extractFloatValue(args[0]) : null;
                { type: "Padding", values: [amount != null ? amount : 12.0] };
            case "margin":
                var amount = args.length > 0 ? extractFloatValue(args[0]) : null;
                { type: "Margin", values: [amount != null ? amount : 12.0] };
            case "font":
                var style = args.length > 0 ? extractEnumName(args[0]) : "Body";
                { type: "Font", values: [style] };
            case "fontSize":
                var size = args.length > 0 ? extractFloatValue(args[0]) : 14.0;
                { type: "FontSize", values: [size] };
            case "bold":
                { type: "Bold", values: [] };
            case "italic":
                { type: "Italic", values: [] };
            case "foregroundColor":
                var vals = args.length > 0 ? extractColorValues(args[0]) : ["Black"];
                { type: "ForegroundColor", values: vals };
            case "background":
                var vals = args.length > 0 ? extractColorValues(args[0]) : ["White"];
                { type: "Background", values: vals };
            case "opacity":
                var value = args.length > 0 ? extractFloatValue(args[0]) : 1.0;
                { type: "Opacity", values: [value] };
            case "width":
                var w = args.length > 0 ? extractFloatValue(args[0]) : 0.0;
                { type: "Width", values: [w] };
            case "height":
                var h = args.length > 0 ? extractFloatValue(args[0]) : 0.0;
                { type: "Height", values: [h] };
            case "cornerRadius":
                var r = args.length > 0 ? extractFloatValue(args[0]) : 0.0;
                { type: "CornerRadius", values: [r] };
            case "horizontalAlignment":
                var align = args.length > 0 ? extractEnumName(args[0]) : "Stretch";
                { type: "HorizontalAlignment", values: [align] };
            case "verticalAlignment":
                var align = args.length > 0 ? extractEnumName(args[0]) : "Stretch";
                { type: "VerticalAlignment", values: [align] };
            case "spacing":
                var s = args.length > 0 ? extractFloatValue(args[0]) : 8.0;
                { type: "Spacing", values: [s] };
            case "disabled":
                var d = args.length > 0 ? extractBoolValue(args[0]) : true;
                { type: "Disabled", values: [d] };
            case "visible":
                var v = args.length > 0 ? extractBoolValue(args[0]) : true;
                { type: "Visible", values: [v] };
            case "toolTip":
                var text = args.length > 0 ? extractStringOrExpr(args[0]) : "";
                { type: "ToolTip", values: [text] };
            case "borderBrush":
                var vals = args.length > 0 ? extractColorValues(args[0]) : ["Gray"];
                { type: "BorderBrush", values: vals };
            case "borderThickness":
                var t = args.length > 0 ? extractFloatValue(args[0]) : 1.0;
                { type: "BorderThickness", values: [t] };
            case "frame":
                var vals:Array<Dynamic> = [];
                for (i in 0...6) {
                    vals.push(i < args.length ? extractFloatValue(args[i]) : null);
                }
                { type: "Frame", values: vals };
            default:
                null;
        };
    }

    // ---- Value Extraction Helpers ----

    static function extractChildArray(expr:TypedExpr):Array<ViewNode> {
        if (expr == null) return [];
        switch (expr.expr) {
            case TArrayDecl(exprs):
                return [for (e in exprs) analyzeBodyExpr(e)];
            default:
                return [analyzeBodyExpr(expr)];
        }
    }

    static function extractStringOrExpr(expr:TypedExpr):String {
        if (expr == null) return null;
        switch (expr.expr) {
            case TConst(TString(s)):
                return s;
            case TConst(TInt(i)):
                return Std.string(i);
            case TConst(TFloat(s)):
                return s;
            default:
                return "...";
        }
    }

    static function extractStringReturn(texpr:TypedExpr):String {
        if (texpr == null) return null;
        switch (texpr.expr) {
            case TReturn(e):
                return extractStringOrExpr(e);
            case TBlock(exprs):
                for (e in exprs) {
                    var s = extractStringReturn(e);
                    if (s != null) return s;
                }
            case TConst(TString(s)):
                return s;
            case TFunction(tf):
                // `field.expr()` on a method wraps the body in a TFunction;
                // recurse so override appName():String { return "..."; }
                // is recognised (otherwise we fall back to the class name).
                return extractStringReturn(tf.expr);
            default:
        }
        return null;
    }

    static function extractFloatValue(expr:TypedExpr):Null<Float> {
        if (expr == null) return null;
        switch (expr.expr) {
            case TConst(TFloat(s)):
                return Std.parseFloat(s);
            case TConst(TInt(i)):
                return i * 1.0;
            default:
                return null;
        }
    }

    static function extractIntValue(expr:TypedExpr):Null<Int> {
        if (expr == null) return null;
        switch (expr.expr) {
            case TConst(TInt(i)):
                return i;
            case TConst(TFloat(s)):
                return Std.parseInt(s);
            default:
                return null;
        }
    }

    static function extractBoolValue(expr:TypedExpr):Bool {
        if (expr == null) return true;
        switch (expr.expr) {
            case TConst(TBool(b)):
                return b;
            default:
                return true;
        }
    }

    /**
     * Extract a ColorValue enum into a flat [constructorName, ...args] array.
     * Handles both nullary constructors (Gray → ["Gray"]) and parametric
     * ones (Rgb(186, 195, 255) → ["Rgb", 186, 195, 255]).
     *
     * For parametric constructors the typed AST wraps the field access in
     * a TCall — extractEnumName() only looked at TField, so anything with
     * args silently fell through to the empty string and downstream
     * generateColorBrush() returned grayBrush() for every custom colour.
     */
    static function extractColorValues(expr:TypedExpr):Array<Dynamic> {
        if (expr == null) return [];
        switch (expr.expr) {
            case TCall(callee, args):
                var name = extractEnumName(callee);
                var out:Array<Dynamic> = [name];
                for (a in args) {
                    switch (a.expr) {
                        case TConst(TInt(i)): out.push(i);
                        case TConst(TFloat(s)): out.push(Std.parseFloat(s));
                        case TConst(TString(s)): out.push(s);
                        case TConst(TBool(b)): out.push(b);
                        default: out.push(null);
                    }
                }
                return out;
            case TField(_, _):
                return [extractEnumName(expr)];
            case TConst(TString(s)):
                return [s];
            default:
                return [];
        }
    }

    static function extractEnumName(expr:TypedExpr):String {
        if (expr == null) return "";
        switch (expr.expr) {
            case TField(_, fa):
                return switch (fa) {
                    case FEnum(_, ef): ef.name;
                    case FStatic(_, cf): cf.get().name;
                    case FInstance(_, _, cf): cf.get().name;
                    case FDynamic(s): s;
                    default: "";
                };
            case TConst(TString(s)):
                return s;
            default:
                return "";
        }
    }

    /**
     * Check if an expression references a @:state field.
     * Returns the field name if it does, null otherwise.
     */
    static function extractStateFieldRef(expr:TypedExpr):String {
        if (expr == null) return null;
        switch (expr.expr) {
            case TField(obj, fa):
                var fieldName = switch (fa) {
                    case FInstance(_, _, cf): cf.get().name;
                    case FDynamic(s): s;
                    default: null;
                };
                // state.value access
                if (fieldName == "value") return extractStateFieldRef(obj);
                // Direct field reference (this.count)
                if (fieldName != null) {
                    for (sf in UIBuilder.stateFields) {
                        if (fieldName == sf.name) return sf.name;
                    }
                }
                return null;

            case TLocal(v):
                // Check if this local is a known state field
                var resolved = localExprs.get(v.name);
                if (resolved != null) return extractStateFieldRef(resolved);
                // Check against state fields
                for (sf in UIBuilder.stateFields) {
                    if (v.name == sf.name) return sf.name;
                }
                return null;

            case TField(_, fa):
                var name = switch (fa) {
                    case FInstance(_, _, cf): cf.get().name;
                    case FDynamic(s): s;
                    default: null;
                };
                // Direct field reference like this.count
                if (name != null) {
                    for (sf in UIBuilder.stateFields) {
                        if (name == sf.name) return sf.name;
                    }
                }
                return null;
            default:
                return null;
        }
    }

    /**
     * Try to extract a state action from a typed expression.
     * Detects patterns like:
     *   count.inc(1), count.dec(1), count.setTo(0), count.tog()
     *   StateAction.Custom(MyApp.staticFn)  — auto-exposes via a wrapper
     * Returns a C++ code string or null.
     */
    static function extractStateAction(expr:TypedExpr):String {
        if (expr == null) return null;

        // Resolve local variables
        switch (expr.expr) {
            case TLocal(v):
                var resolved = localExprs.get(v.name);
                if (resolved != null) return extractStateAction(resolved);
            default:
        }

        switch (expr.expr) {
            case TCall(func, args):
                // StateAction enum constructors:
                //   Custom(fn), Sequence([...]), SetValue(state, value), Toggle(state).
                // The macro intercepts these before they'd run at runtime.
                switch (func.expr) {
                    case TField(_, FEnum(_, ef)):
                        switch (ef.name) {
                            case "Custom" if (args.length >= 1):
                                var arg = args[0];
                                // Phase 1: static function reference.
                                var path = extractStaticFunctionPath(arg);
                                if (path != null) {
                                    var wrapperName = registerCallback(path);
                                    return '::wui::generated::Callbacks_obj::$wrapperName();';
                                }
                                // Phase 2: anonymous lambda. Lift via
                                // `Context.storeTypedExpr` into a static
                                // wrapper. The lambda body should use
                                // `wui.generated.StateAccessor.set_X / get_X`
                                // to read/write @:state fields (this.X
                                // refs don't survive the lift to static).
                                switch (arg.expr) {
                                    case TFunction(tf):
                                        var wrapperName = registerLambda(tf.expr);
                                        return '::wui::generated::Callbacks_obj::$wrapperName();';
                                    default:
                                }
                                haxe.macro.Context.error(
                                    "StateAction.Custom expects a static function reference (MyApp.fn) or a lambda (() -> { ... })",
                                    arg.pos
                                );
                                return null;

                            case "Sequence" if (args.length >= 1):
                                return extractSequenceAction(args[0]);

                            case "SetValue" if (args.length >= 2):
                                return extractSetValueAction(args[0], args[1]);

                            case "Toggle" if (args.length >= 1):
                                var stateName = extractStateFieldRef(args[0]);
                                if (stateName == null) return null;
                                return 's_$stateName = !s_$stateName; notify_$stateName();';

                            case _:
                        }
                    default:
                }

                switch (func.expr) {
                    case TField(obj, fa):
                        var methodName = switch (fa) {
                            case FInstance(_, _, cf): cf.get().name;
                            case FDynamic(s): s;
                            default: null;
                        };

                        // obj should be a state field
                        var stateName = extractStateFieldRef(obj);
                        if (stateName == null) return null;

                        var amount = args.length > 0 ? extractFloatValue(args[0]) : null;
                        var amountStr = amount != null ? Std.string(Std.int(amount)) : "1";
                        var sf = findStateField(stateName);
                        var stateType = sf != null ? sf.type : "int";

                        return switch (methodName) {
                            case "inc": 's_$stateName += $amountStr; notify_$stateName();';
                            case "dec": 's_$stateName -= $amountStr; notify_$stateName();';
                            case "setTo":
                                var val:String = switch (stateType) {
                                    case "std::wstring":
                                        var s = args.length > 0 ? extractStringOrExpr(args[0]) : null;
                                        if (s == null || s == "...") s = "";
                                        'L"' + UIBuilder.escapeWideString(s) + '"';
                                    case "bool":
                                        var b = args.length > 0 ? extractBoolValue(args[0]) : false;
                                        b ? "true" : "false";
                                    case "double":
                                        amount != null ? Std.string(amount) : "0.0";
                                    case _:
                                        amount != null ? Std.string(Std.int(amount)) : "0";
                                };
                                's_$stateName = $val; notify_$stateName();';
                            case "tog": 's_$stateName = !s_$stateName; notify_$stateName();';
                            default: null;
                        };
                    default:
                }
            default:
        }
        return null;
    }

    /**
     * Analyze a Text argument for state-bound expressions.
     * Detects: "prefix" + stateField patterns.
     * Returns {text, boundState, format} or null if not state-bound.
     */
    /**
     * Recursively search an expression for a state field reference,
     * unwrapping calls like .toString(), Std.string(), etc.
     */
    static function deepExtractStateRef(expr:TypedExpr):String {
        if (expr == null) return null;

        // Direct state ref
        var direct = extractStateFieldRef(expr);
        if (direct != null) return direct;

        switch (expr.expr) {
            case TLocal(v):
                // Check if local name matches a state field
                for (sf in UIBuilder.stateFields) {
                    if (v.name == sf.name) return sf.name;
                }
                var resolved = localExprs.get(v.name);
                if (resolved != null) return deepExtractStateRef(resolved);
            case TCall(func, args):
                // Unwrap: Std.string(count), count.toString(), etc.
                for (arg in args) {
                    var found = deepExtractStateRef(arg);
                    if (found != null) return found;
                }
                // Check the function target too (for count.toString())
                switch (func.expr) {
                    case TField(obj, _):
                        return deepExtractStateRef(obj);
                    default:
                }
            case TField(obj, fa):
                // Check field name against state fields
                var fName = switch (fa) {
                    case FInstance(_, _, cf): cf.get().name;
                    case FDynamic(s): s;
                    default: null;
                };
                if (fName != null) {
                    for (sf in UIBuilder.stateFields) {
                        if (fName == sf.name) return sf.name;
                    }
                }
                return deepExtractStateRef(obj);
            default:
        }
        return null;
    }

    static function extractStateBoundText(expr:TypedExpr):{text:String, boundState:String, format:String} {
        if (expr == null) return null;

        // Resolve locals
        switch (expr.expr) {
            case TLocal(v):
                var resolved = localExprs.get(v.name);
                if (resolved != null) return extractStateBoundText(resolved);
            default:
        }

        switch (expr.expr) {
            case TBinop(op, e1, e2):
                var opName = Std.string(op);
                if (opName == "OpAdd") {
                    var prefix = extractStringOrExpr(e1);
                    // Deep search for state ref in e2 (may be wrapped in toString/Std.string)
                    var stateRef = deepExtractStateRef(e2);
                    if (prefix != null && prefix != "..." && stateRef != null) {
                        var escaped = UIBuilder.escapeWideString(prefix);
                        var valueExpr = stateToWstring(stateRef);
                        return {
                            text: prefix + stateInitialText(stateRef),
                            boundState: stateRef,
                            format: 'CTRL.Text(winrt::hstring(L"$escaped" + $valueExpr));'
                        };
                    }
                    // count + "suffix"
                    var stateRef1 = deepExtractStateRef(e1);
                    var suffix = extractStringOrExpr(e2);
                    if (stateRef1 != null && suffix != null && suffix != "...") {
                        var escaped = UIBuilder.escapeWideString(suffix);
                        var valueExpr = stateToWstring(stateRef1);
                        return {
                            text: stateInitialText(stateRef1) + suffix,
                            boundState: stateRef1,
                            format: 'CTRL.Text(winrt::hstring($valueExpr + L"$escaped"));'
                        };
                    }
                }
            default:
                // Check if the expression itself is a state reference
                var stateRef = deepExtractStateRef(expr);
                if (stateRef != null) {
                    var valueExpr = stateToWstring(stateRef);
                    return {
                        text: stateInitialText(stateRef),
                        boundState: stateRef,
                        format: 'CTRL.Text(winrt::hstring($valueExpr));'
                    };
                }
        }
        return null;
    }

    /** Look up a state field by name. */
    static function findStateField(name:String):{name:String, type:String, initial:String} {
        for (sf in UIBuilder.stateFields) {
            if (sf.name == name) return sf;
        }
        return null;
    }

    /**
     * Resolve a typed expression to a fully-qualified Haxe static
     * function path (e.g. "MyApp.startLogin" or "pkg.sub.Cls.fn").
     * Returns null if the expression isn't a static reference.
     */
    static function extractStaticFunctionPath(expr:TypedExpr):String {
        if (expr == null) return null;
        switch (expr.expr) {
            case TField(_, FStatic(cl, cf)):
                var clsRef = cl.get();
                var parts = clsRef.pack.copy();
                parts.push(clsRef.name);
                parts.push(cf.get().name);
                return parts.join(".");
            default:
                return null;
        }
    }

    /** Render a literal value as a C++ expression of the requested
        state type. Used by SetValue / setTo to coerce the user's
        argument into the right shape for `s_X = ...` assignment. */
    static function renderLiteralForType(expr:TypedExpr, type:String):String {
        switch (type) {
            case "std::wstring":
                var s = extractStringOrExpr(expr);
                if (s == null || s == "...") s = "";
                return 'L"' + UIBuilder.escapeWideString(s) + '"';
            case "bool":
                return extractBoolValue(expr) ? "true" : "false";
            case "double":
                var f = extractFloatValue(expr);
                return f != null ? Std.string(f) : "0.0";
            case _:
                var f = extractFloatValue(expr);
                return f != null ? Std.string(Std.int(f)) : "0";
        }
    }

    /** Resolve `StateAction.SetValue(stateRef, value)` to C++ assign +
        notify, with the value coerced to the state's declared type. */
    static function extractSetValueAction(stateExpr:TypedExpr, valueExpr:TypedExpr):String {
        var stateName = extractStateFieldRef(stateExpr);
        if (stateName == null) return null;
        var sf = findStateField(stateName);
        var stateType = sf != null ? sf.type : "int";
        var val = renderLiteralForType(valueExpr, stateType);
        return 's_$stateName = $val; notify_$stateName();';
    }

    /** Resolve `StateAction.Sequence([...])` to a concatenation of the
        C++ snippets for each inner action. Inner actions may themselves
        be enum constructors or method calls — recursion handles both. */
    static function extractSequenceAction(arrayExpr:TypedExpr):String {
        switch (arrayExpr.expr) {
            case TArrayDecl(actions):
                var codes:Array<String> = [];
                for (action in actions) {
                    var code = extractStateAction(action);
                    if (code != null) codes.push(code);
                }
                return codes.join(" ");
            default:
                return null;
        }
    }

    /** Register a static-function callback; idempotent. Returns the
        generated wrapper name. */
    static function registerCallback(fnPath:String):String {
        var existing = callbackRegistry.get(fnPath);
        if (existing != null) return existing;
        var n = Lambda.count(callbackRegistry) + lambdaRegistry.length;
        var wrapperName = 'wui_cb_$n';
        callbackRegistry.set(fnPath, wrapperName);
        return wrapperName;
    }

    /** Register an anonymous lambda body; not idempotent (each lambda
        is unique). Returns the generated wrapper name. */
    static function registerLambda(body:haxe.macro.Type.TypedExpr):String {
        var n = Lambda.count(callbackRegistry) + lambdaRegistry.length;
        var wrapperName = 'wui_cb_$n';
        lambdaRegistry.push({name: wrapperName, body: body});
        return wrapperName;
    }

    /** Emit a generated `wui.generated.Callbacks` class containing one
        static wrapper per registered callback. MainWindow.cpp's click
        handlers call into this class via its hxcpp-generated qualified
        name (`::wui::generated::Callbacks_obj::wui_cb_<N>()`), no C
        linkage needed. Called from `analyze()` during the typing pass
        so hxcpp picks the class up as part of the normal compilation. */
    static function emitCallbackModule():Void {
        if (Lambda.count(callbackRegistry) == 0 && lambdaRegistry.length == 0) return;
        var pos = haxe.macro.Context.currentPos();
        var fields:Array<haxe.macro.Expr.Field> = [];
        // Static-function callbacks.
        for (fnPath in callbackRegistry.keys()) {
            var wrapperName = callbackRegistry.get(fnPath);
            var bodyExpr = haxe.macro.Context.parse('{ $fnPath(); }', pos);
            fields.push({
                name: wrapperName,
                pos: pos,
                meta: [{ name: ":keep", pos: pos }],
                access: [APublic, AStatic],
                kind: FFun({
                    args: [],
                    ret: macro :Void,
                    expr: bodyExpr
                })
            });
        }
        // Anonymous lambdas.
        for (entry in lambdaRegistry) {
            fields.push({
                name: entry.name,
                pos: pos,
                meta: [{ name: ":keep", pos: pos }],
                access: [APublic, AStatic],
                kind: FFun({
                    args: [],
                    ret: macro :Void,
                    expr: haxe.macro.Context.storeTypedExpr(entry.body)
                })
            });
        }
        haxe.macro.Context.defineType({
            pos: pos,
            pack: ["wui", "generated"],
            name: "Callbacks",
            kind: TDClass(),
            fields: fields,
            meta: [{ name: ":keep", pos: pos }]
        });
        // Hand the wrapper list to UIBuilder so MainWindow.cpp can pull
        // in the matching header.
        var all = [for (n in callbackRegistry) n];
        for (e in lambdaRegistry) all.push(e.name);
        UIBuilder.exposedCallbacks = all;
    }

    /** Plausible initial text shown before the state has been pushed for the
        first time. Used to keep the compile-time `text` property in the
        ViewNode close to what the user sees on startup. */
    static function stateInitialText(stateName:String):String {
        var sf = findStateField(stateName);
        if (sf == null) return "0";
        return switch (sf.type) {
            case "std::wstring": "";
            case "bool": "false";
            case _: "0";
        };
    }

    /** Return C++ expression to convert a state variable to std::wstring. */
    static function stateToWstring(stateName:String):String {
        for (sf in UIBuilder.stateFields) {
            if (sf.name == stateName) {
                if (sf.type == "std::wstring") return 's_$stateName';
                if (sf.type == "bool") return '(s_$stateName ? std::wstring(L"true") : std::wstring(L"false"))';
                return 'std::to_wstring(s_$stateName)';
            }
        }
        return 'std::to_wstring(s_$stateName)';
    }

    static function defaultNode():ViewNode {
        return {
            viewType: "StackPanel",
            children: [],
            modifiers: [],
            properties: new Map()
        };
    }
    #end
}
