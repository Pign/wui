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

    /** Parametric callbacks — `StateAction.Custom(fn)` where `fn` is a
        typed `(Int) -> Void` static reference. Only emitted in ForEach
        row context (the index is materialised from the C++ for-loop's
        `i` and passed to the wrapper). Keyed by the static function
        path to keep wrappers idempotent across multiple identical
        registrations. */
    static var parametricCallbackRegistry:Map<String, String> = new Map();

    /** Parametric closures — `StateAction.Custom(() -> { … idx … })`
        where the closure body is converted to an untyped Expr via
        `closureBodyToExpr`, capturing the ForEach row index as the
        wrapper's `idx:Int` parameter. Non-idempotent (each closure
        carries its own body), so this is a flat list. */
    static var parametricLambdaRegistry:Array<{name:String, body:haxe.macro.Expr}> = [];

    /** Set by `ForEach.wuiAnalyze` for the duration of its modifier
        walk to the index-param name of the lambda (e.g. "idx" in
        `(item, idx) -> …`). Null outside ForEach context. Read by
        `extractStateAction` to decide whether to route a Custom
        callback through the parametric path. */
    public static var foreachContextIdxName:Null<String> = null;

    /** Set by `ForEach.wuiAnalyze` alongside `foreachContextIdxName`.
        The TVar of the lambda's first param (the row item), used to
        detect `item.<field>` references inside closures and rewrite
        them as calls into `wui.generated.ForEachAccessor`. */
    public static var foreachContextItemVar:Null<haxe.macro.Type.TVar> = null;

    /** Set by `ForEach.wuiAnalyze` for the @:state field the ForEach
        iterates over. Used to build the per-field accessor method
        names (`<state>_field_<field>`) when a closure captures an
        item field. */
    public static var foreachContextStateName:Null<String> = null;

    /** Pre-walked map of TVar declarations in the ForEach row lambda
        body — keyed by `TVar.id`, value is the initializer expression.
        Lets a closure capture locals declared in the row lambda by
        substituting the initializer inline (the closure has no
        runtime scope, but its converted body re-types in the wrapper
        scope and the substituted expression re-types against the
        wrapper's `idx` param). */
    public static var foreachContextLocalInits:Null<Map<Int, haxe.macro.Type.TypedExpr>> = null;

    /** Accessors needed by emitted ForEach widgets — one entry per
        unique (stateName, fieldName) pair. Each gets a static method on
        `wui.generated.ForEachAccessor`: `<state>_field_<field>(i:Int):String`
        (string-only for the MVP). Length helpers are tracked separately. */
    public static var foreachAccessorFields:Map<String, {stateName:String, fieldName:String, fieldType:String}> = new Map();
    public static var foreachAccessorLengths:Map<String, Bool> = new Map();

    /**
     * Per-class analyze functions registered by primitive widget
     * classes. See `wui.macros.PrimitiveCtx` for the contract.
     *
     * Keyed by the fully-qualified Haxe class name (e.g.
     * `wui.ui.VStack`), the same key `analyzeNewExpr` already
     * computes via `cls.pack.join(".") + "." + cls.name`. Consulted
     * BEFORE the legacy switch; the switch is being drained one
     * widget at a time as primitives migrate.
     */
    public static var primitiveRegistry:Map<String, Array<haxe.macro.Type.TypedExpr> -> wui.macros.PrimitiveCtx.AnalyzeCtx -> wui.macros.UIBuilder.ViewNode> = new Map();

    /** Register a primitive widget's analyze function under its
        fully-qualified class name. Called from `register()` once per
        framework primitive; user widgets can register from their own
        `#if macro` blocks via the same API. */
    public static function registerPrimitive(fqClassName:String, fn:Array<haxe.macro.Type.TypedExpr> -> wui.macros.PrimitiveCtx.AnalyzeCtx -> wui.macros.UIBuilder.ViewNode):Void {
        primitiveRegistry.set(fqClassName, fn);
    }

    /**
     * Call this from build.hxml:
     *   --macro wui.macros.WinUIGenerator.register()
     */
    public static function register():Void {
        if (registered) return;
        registered = true;

        // Wire up framework primitives that have migrated to the
        // self-emit pattern. Each one contributes (a) its analyze
        // function under its FQ class name, and (b) optionally an
        // emit function under its viewType. Re-registration is a
        // no-op (last wins), so widgets that share a viewType (e.g.
        // HStack ↔ VStack both StackPanel) only need to register
        // their analyze and can share an emit.
        registerPrimitive("wui.ui.VStack",       wui.ui.VStack.wuiAnalyze);
        registerPrimitive("wui.ui.HStack",       wui.ui.HStack.wuiAnalyze);
        registerPrimitive("wui.ui.ZStack",       wui.ui.ZStack.wuiAnalyze);
        registerPrimitive("wui.ui.Text",         wui.ui.Text.wuiAnalyze);
        registerPrimitive("wui.ui.Button",       wui.ui.Button.wuiAnalyze);
        registerPrimitive("wui.ui.Spacer",       wui.ui.Spacer.wuiAnalyze);
        registerPrimitive("wui.ui.TextBox",      wui.ui.TextBox.wuiAnalyze);
        registerPrimitive("wui.ui.ToggleSwitch", wui.ui.ToggleSwitch.wuiAnalyze);
        registerPrimitive("wui.ui.CheckBox",     wui.ui.CheckBox.wuiAnalyze);
        registerPrimitive("wui.ui.Slider",       wui.ui.Slider.wuiAnalyze);
        registerPrimitive("wui.ui.Image",        wui.ui.Image.wuiAnalyze);
        registerPrimitive("wui.ui.ScrollViewer", wui.ui.ScrollViewer.wuiAnalyze);
        registerPrimitive("wui.ui.ProgressRing", wui.ui.ProgressRing.wuiAnalyze);
        registerPrimitive("wui.ui.ForEach",      wui.ui.ForEach.wuiAnalyze);
        registerPrimitive("wui.ui.Show",         wui.ui.Show.wuiAnalyze);
        UIBuilder.registerEmitter("StackPanel",   wui.ui.VStack.wuiEmit);
        UIBuilder.registerEmitter("Grid",         wui.ui.ZStack.wuiEmit);
        UIBuilder.registerEmitter("TextBlock",    wui.ui.Text.wuiEmit);
        UIBuilder.registerEmitter("Button",       wui.ui.Button.wuiEmit);
        UIBuilder.registerEmitter("Spacer",       wui.ui.Spacer.wuiEmit);
        UIBuilder.registerEmitter("TextBox",      wui.ui.TextBox.wuiEmit);
        UIBuilder.registerEmitter("ToggleSwitch", wui.ui.ToggleSwitch.wuiEmit);
        UIBuilder.registerEmitter("CheckBox",     wui.ui.CheckBox.wuiEmit);
        UIBuilder.registerEmitter("Slider",       wui.ui.Slider.wuiEmit);
        UIBuilder.registerEmitter("Image",        wui.ui.Image.wuiEmit);
        UIBuilder.registerEmitter("ScrollViewer", wui.ui.ScrollViewer.wuiEmit);
        UIBuilder.registerEmitter("ProgressRing", wui.ui.ProgressRing.wuiEmit);
        UIBuilder.registerEmitter("ForEach",      wui.ui.ForEach.wuiEmit);
        UIBuilder.registerEmitter("Show",         wui.ui.Show.wuiEmit);

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
        emitForEachAccessorModule();
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
        collectStateFieldsRec(type, "", result);
        return result;
    }

    /** Walk a class' State<T>-typed fields (primitive @:state) and flatten
        Observable-typed fields by recursing into their own @:state
        layouts with the dotted scope prefix.

        Composite keys ("settings.darkMode") are what UIBuilder uses for
        bridge dispatch and listener subscription. The C++ side sanitises
        them to `s_settings_darkMode` via `sanitizeCppName`. */
    static function collectStateFieldsRec(type:Type, scope:String, out:Array<{name:String, type:String, initial:String}>):Void {
        switch (type) {
            case TInst(ref, _):
                var cls = ref.get();
                for (field in cls.fields.get()) {
                    var fieldScope = (scope.length == 0) ? field.name : scope + "." + field.name;
                    switch (field.type) {
                        case TInst(tref, params):
                            var typeName = tref.get().name;
                            var typePack = tref.get().pack.join(".");
                            if (typeName == "State" && params.length > 0) {
                                appendPrimitiveStateField(field, params[0], fieldScope, out);
                            } else if (extendsObservable(tref.get())) {
                                // Nested Observable @:state — recurse so its
                                // own State<T> fields land in the flat list
                                // with a dotted prefix.
                                collectStateFieldsRec(field.type, fieldScope, out);
                            }
                        default:
                    }
                }
            default:
        }
    }

    static function appendPrimitiveStateField(field:ClassField, paramType:Type, name:String, out:Array<{name:String, type:String, initial:String}>):Void {
        var cppType:String = null;
        var initial:String = null;

        var explicitInitial:String = null;
        for (m in field.meta.get()) {
            if (m.name == ":wuiInitial" && m.params != null && m.params.length > 0) {
                explicitInitial = exprToCppLiteral(m.params[0]);
            }
        }

        switch (paramType) {
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
        // Immutable-typed State<T> (e.g. State<ImmutableList<Email>>) has
        // no C++-side payload — the list lives Haxe-side, only the
        // companion `<name>__v:Int` trigger gets registered. We bail out
        // here when the inner T isn't a recognised primitive so we don't
        // emit a bogus `s_inbox` static.
        if (cppType == null) return;
        out.push({ name: name, type: cppType, initial: initial });
    }

    /** True iff the class's super chain hits wui.state.Observable. */
    static function extendsObservable(cls:ClassType):Bool {
        var cur = cls;
        while (cur != null) {
            if (cur.pack.length == 2 && cur.pack[0] == "wui" && cur.pack[1] == "state" && cur.name == "Observable") return true;
            if (cur.superClass == null) return false;
            cur = cur.superClass.t.get();
        }
        return false;
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

        // First : framework primitives have explicit entries in the
        // registry (wired in `register()`), each owns its `wuiAnalyze`.
        var analyzeFn = primitiveRegistry.get(fullName);
        if (analyzeFn != null) {
            return analyzeFn(args, buildAnalyzeCtx());
        }

        // Phase 3 : user components — any class extending `wui.View`
        // that overrides `body()` is inlined here. Constructor args
        // are substituted into the body's `this.<field>` references
        // and the resulting expression is re-analysed as if the user
        // had written it directly. Lets the app factor its UI into
        // reusable components without polluting the framework with
        // app-specific styling.
        if (extendsView(cls)) {
            var inlined = inlineUserBody(cls, args);
            if (inlined != null) return inlined;
        }

        return defaultNode();
    }

    /** Walk a class chain looking for `wui.View` as ancestor. */
    static function extendsView(cls:ClassType):Bool {
        var cur = cls;
        while (cur != null) {
            if (cur.pack.length == 1 && cur.pack[0] == "wui" && cur.name == "View") return true;
            if (cur.superClass == null) return false;
            cur = cur.superClass.t.get();
        }
        return false;
    }

    /** Phase 3 inlining. Walks the user component's `body()` typed AST,
        substitutes `this.<field>` references with the matching
        constructor argument, and feeds the result back into
        `analyzeBodyExpr`. Returns `null` if the component doesn't fit
        the supported shape (no body method, body() returns void, ctor
        doesn't store params into same-named fields, …) — caller falls
        back to `defaultNode()` in that case. */
    static function inlineUserBody(cls:ClassType, args:Array<TypedExpr>):ViewNode {
        var bodyField:ClassField = null;
        for (f in cls.fields.get()) {
            if (f.name == "body") { bodyField = f; break; }
        }
        if (bodyField == null) return null;
        var bodyExpr = bodyField.expr();
        if (bodyExpr == null) return null;

        // Build the param-to-field substitution from the constructor.
        // We only support `this.X = paramName;` assignments for now —
        // anything more elaborate (transforms, conditional init)
        // falls back to the empty substitution and the body keeps its
        // original `this.X` references, which then fail to resolve at
        // the call site. Document the constraint when migrating user
        // components.
        var subst:Map<String, TypedExpr> = new Map();
        var ctor = cls.constructor;
        if (ctor != null && args.length > 0) {
            var ctorField = ctor.get();
            var ctorExpr = ctorField.expr();
            if (ctorExpr != null) {
                var ctorParams:Array<String> = [];
                switch (ctorField.type) {
                    case TFun(params, _):
                        for (p in params) ctorParams.push(p.name);
                    default:
                }
                var fieldToParam:Map<String, String> = new Map();
                walkCtorBody(ctorExpr, fieldToParam);
                for (fname in fieldToParam.keys()) {
                    var pname = fieldToParam.get(fname);
                    var idx = -1;
                    for (i in 0...ctorParams.length) {
                        if (ctorParams[i] == pname) { idx = i; break; }
                    }
                    if (idx >= 0 && idx < args.length) {
                        subst.set(fname, args[idx]);
                    }
                }
            }
        }

        var bodyReturn = extractReturnExpr(bodyExpr);
        if (bodyReturn == null) return null;
        var substituted = substituteThisFields(bodyReturn, subst);
        return analyzeBodyExpr(substituted);
    }

    /** Same as `inlineUserBody` but returns the substituted typed
        expression instead of a ViewNode. Lets other analyzers (e.g.
        `ForEach.wuiAnalyze` for its template body) continue their
        own pattern matching on the inlined tree rather than going
        straight to `analyzeBodyExpr`. */
    public static function inlineUserBodyExpr(cls:ClassType, args:Array<TypedExpr>):TypedExpr {
        var bodyField:ClassField = null;
        for (f in cls.fields.get()) {
            if (f.name == "body") { bodyField = f; break; }
        }
        if (bodyField == null) return null;
        var bodyExpr = bodyField.expr();
        if (bodyExpr == null) return null;

        var subst:Map<String, TypedExpr> = new Map();
        var ctor = cls.constructor;
        if (ctor != null && args.length > 0) {
            var ctorField = ctor.get();
            var ctorExpr = ctorField.expr();
            if (ctorExpr != null) {
                var ctorParams:Array<String> = [];
                switch (ctorField.type) {
                    case TFun(params, _):
                        for (p in params) ctorParams.push(p.name);
                    default:
                }
                var fieldToParam:Map<String, String> = new Map();
                walkCtorBody(ctorExpr, fieldToParam);
                for (fname in fieldToParam.keys()) {
                    var pname = fieldToParam.get(fname);
                    var idx = -1;
                    for (i in 0...ctorParams.length) {
                        if (ctorParams[i] == pname) { idx = i; break; }
                    }
                    if (idx >= 0 && idx < args.length) {
                        subst.set(fname, args[idx]);
                    }
                }
            }
        }

        var bodyReturn = extractReturnExpr(bodyExpr);
        if (bodyReturn == null) return null;
        return substituteThisFields(bodyReturn, subst);
    }

    /** Public alias of `extendsView` so other macro modules
        (notably `wui.ui.ForEach`) can guard their Phase-3 inlining. */
    public static function isUserViewComponent(cls:ClassType):Bool {
        return extendsView(cls);
    }

    /** Public alias of `extractModifier` for cross-module reuse —
        `ForEach.analyzeTextChild` walks modifier chains on its Text
        rows and needs the same name→ModifierData conversion. */
    public static function modifierFromCall(name:String, args:Array<TypedExpr>):ModifierData {
        return extractModifier(name, args);
    }

    /** Recursively scan ctor body for `this.<field> = <localParam>`
        and populate `out` with `<field> -> <localParamName>`. Only
        TLocal RHS counts — `this.X = compute()` doesn't qualify
        because we can't trace the value back to a ctor argument. */
    static function walkCtorBody(e:TypedExpr, out:Map<String, String>):Void {
        if (e == null) return;
        switch (e.expr) {
            case TBinop(OpAssign, lhs, rhs):
                switch (lhs.expr) {
                    case TField(receiver, fa):
                        var isThis = switch (receiver.expr) {
                            case TConst(TThis): true;
                            default: false;
                        };
                        if (isThis) {
                            var fieldName = switch (fa) {
                                case FInstance(_, _, cf): cf.get().name;
                                default: null;
                            };
                            if (fieldName != null) {
                                switch (rhs.expr) {
                                    case TLocal(v): out.set(fieldName, v.name);
                                    default:
                                }
                            }
                        }
                    default:
                }
            default:
        }
        haxe.macro.TypedExprTools.iter(e, function(c) walkCtorBody(c, out));
    }

    /** Body() in user code typically wraps its return in a `TBlock`
        with a single `TReturn`. Unwrap layers until we reach the
        actual View constructor expression. */
    static function extractReturnExpr(e:TypedExpr):TypedExpr {
        if (e == null) return null;
        switch (e.expr) {
            case TFunction(tf):
                // `field.expr()` sur un FMethod renvoie le TypedExpr
                // wrappant la fonction entière (TFunction avec args + body).
                // On descend dans le body — sinon les callers qui matchent
                // sur TNew(...) du body voient TFunction et tombent.
                return extractReturnExpr(tf.expr);
            case TBlock(exprs):
                var i = exprs.length - 1;
                while (i >= 0) {
                    var sub = extractReturnExpr(exprs[i]);
                    if (sub != null) return sub;
                    i--;
                }
                return null;
            case TReturn(inner):
                return inner == null ? null : extractReturnExpr(inner);
            case TMeta(_, inner):
                return extractReturnExpr(inner);
            case TParenthesis(inner):
                return extractReturnExpr(inner);
            default:
                return e;
        }
    }

    /** Replace `this.<field>` accesses with their substituted value
        from the caller's args. Uses `TypedExprTools.map` so the new
        tree keeps type information intact — that's why we don't
        round-trip through Expr/typeExpr (the resulting expressions
        feed directly back into `analyzeBodyExpr`). */
    static function substituteThisFields(e:TypedExpr, subst:Map<String, TypedExpr>):TypedExpr {
        if (e == null) return null;
        switch (e.expr) {
            case TField(receiver, fa):
                var isThis = switch (receiver.expr) {
                    case TConst(TThis): true;
                    default: false;
                };
                if (isThis) {
                    var fieldName = switch (fa) {
                        case FInstance(_, _, cf): cf.get().name;
                        default: null;
                    };
                    if (fieldName != null && subst.exists(fieldName)) {
                        return subst.get(fieldName);
                    }
                }
            default:
        }
        return haxe.macro.TypedExprTools.map(e, function(c) return substituteThisFields(c, subst));
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
            case "onTap":
                // Same compile-to-C++ path Button uses for its `action`
                // arg. Yields a C++ snippet that runs the chosen
                // StateAction ; `applyModifiers` wraps it in a Tapped
                // event handler.
                var snippet = args.length > 0 ? extractStateAction(args[0]) : null;
                snippet != null ? { type: "OnTap", values: [snippet] } : null;
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

    /** Wire WinUIGenerator's static analyze helpers into the immutable
        record a migrated widget's `wuiAnalyze` expects. Single-shot,
        cheap to construct — these are all references to closures over
        the file-scope state. */
    static function buildAnalyzeCtx():wui.macros.PrimitiveCtx.AnalyzeCtx {
        return {
            recurseChild: analyzeBodyExpr,
            recurseChildren: extractChildArray,
            extractString: extractStringOrExpr,
            extractFloat: extractFloatValue,
            extractStateBoundText: extractStateBoundText,
            extractStateRef: deepExtractStateRef,
            extractStateAction: extractStateAction,
            defaultNode: defaultNode,
        };
    }

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
                if (fieldName != null) {
                    // 1. Direct @:state field (App-level primitive)
                    for (sf in UIBuilder.stateFields) {
                        if (fieldName == sf.name) return sf.name;
                    }
                    // 2. Composite @:state field (Observable-decomposed —
                    //    e.g. `settings.darkMode` resolves to the bridge
                    //    key "settings.darkMode" in stateFields).
                    var parentChain = buildAccessChain(obj);
                    if (parentChain != null) {
                        var composite = parentChain + "." + fieldName;
                        for (sf in UIBuilder.stateFields) {
                            if (sf.name == composite) return sf.name;
                        }
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
                                    // In ForEach row context, a typed
                                    // `(Int) -> Void` static reference
                                    // gets routed through the parametric
                                    // wrapper — the C++ side captures
                                    // the row index from the rebuild
                                    // loop and passes it through.
                                    if (foreachContextIdxName != null && isIntToVoidFn(arg)) {
                                        var wrapperName = registerParametricCallback(path);
                                        return '::wui::generated::Callbacks_obj::$wrapperName(i);';
                                    }
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
                                        // In ForEach context, convert
                                        // the closure body to an
                                        // untyped Expr that re-types
                                        // cleanly inside a generated
                                        // wrapper with `idx:Int` as
                                        // its parameter — references
                                        // to the ForEach lambda's
                                        // index local get rewritten
                                        // to `idx` and resolve to the
                                        // param. Handles common Haxe
                                        // shapes (TBlock, TCall,
                                        // TIf, TBinop, TVar, …) ;
                                        // unsupported constructs and
                                        // captures of non-idx locals
                                        // fall back to the standard
                                        // zero-arg lift, which won't
                                        // compile but at least makes
                                        // the failure mode explicit.
                                        if (foreachContextIdxName != null) {
                                            var asExpr = closureBodyToExpr(tf.expr, foreachContextIdxName);
                                            if (asExpr != null) {
                                                var wrapperName = registerParametricLambda(asExpr);
                                                return '::wui::generated::Callbacks_obj::$wrapperName(i);';
                                            }
                                        }
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
    /** Reconstruct the dotted access path for a typed expression so we
        can match nested @:state on Observable composites against the
        flat stateFields list (which already uses composite keys like
        "settings.darkMode"). Returns null for expressions that aren't
        a chain of instance-field reads off `this` / `super`. */
    static function buildAccessChain(expr:TypedExpr):String {
        if (expr == null) return null;
        switch (expr.expr) {
            case TField(receiver, fa):
                var fieldName = switch (fa) {
                    case FInstance(_, _, cf): cf.get().name;
                    case FDynamic(s): s;
                    default: null;
                };
                if (fieldName == null) return null;
                switch (receiver.expr) {
                    case TConst(TThis) | TConst(TSuper):
                        return fieldName;
                    default:
                }
                var parent = buildAccessChain(receiver);
                if (parent != null) return parent + "." + fieldName;
                // Fallback — if the receiver itself isn't a chain we
                // accept the bare field name. Helps recognise patterns
                // like `local.settings.darkMode` once we resolve
                // locals upstream.
                return fieldName;
            case TLocal(v):
                var resolved = localExprs.get(v.name);
                if (resolved != null) return buildAccessChain(resolved);
                return null;
            case TParenthesis(inner):
                return buildAccessChain(inner);
            case TCast(inner, _):
                return buildAccessChain(inner);
            case TMeta(_, inner):
                return buildAccessChain(inner);
            default:
                return null;
        }
    }

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
        var n = nextWrapperIndex();
        var wrapperName = 'wui_cb_$n';
        callbackRegistry.set(fnPath, wrapperName);
        return wrapperName;
    }

    /** Same as `registerCallback` but the wrapper takes an `Int` arg
        and forwards it to the target. Used by ForEach row taps where
        the C++ side captures the loop index and passes it through. */
    static function registerParametricCallback(fnPath:String):String {
        var existing = parametricCallbackRegistry.get(fnPath);
        if (existing != null) return existing;
        var n = nextWrapperIndex();
        var wrapperName = 'wui_cb_$n';
        parametricCallbackRegistry.set(fnPath, wrapperName);
        return wrapperName;
    }

    /** Register an anonymous closure converted via `closureBodyToExpr`.
        The body is an untyped `Expr` ; Haxe re-types it inside the
        generated wrapper where `idx:Int` is a function parameter,
        so references to the ForEach lambda's index local — rewritten
        to bare `idx` during conversion — resolve correctly. */
    static function registerParametricLambda(body:haxe.macro.Expr):String {
        var n = nextWrapperIndex();
        var wrapperName = 'wui_cb_$n';
        parametricLambdaRegistry.push({name: wrapperName, body: body});
        return wrapperName;
    }

    /** Register an anonymous lambda body; not idempotent (each lambda
        is unique). Returns the generated wrapper name. */
    static function registerLambda(body:haxe.macro.Type.TypedExpr):String {
        var n = nextWrapperIndex();
        var wrapperName = 'wui_cb_$n';
        lambdaRegistry.push({name: wrapperName, body: body});
        return wrapperName;
    }

    static function nextWrapperIndex():Int {
        return Lambda.count(callbackRegistry)
            + Lambda.count(parametricCallbackRegistry)
            + lambdaRegistry.length
            + parametricLambdaRegistry.length;
    }

    /** True when `expr` is a static function reference typed
        `(Int) -> Void`. Used by the ForEach Custom-callback path to
        decide whether to route through the parametric wrapper.
        Caller has already extracted a static function path via
        `extractStaticFunctionPath` — this just inspects the type. */
    static function isIntToVoidFn(expr:TypedExpr):Bool {
        if (expr == null) return false;
        switch (expr.t) {
            case TFun(params, ret):
                if (params.length != 1) return false;
                if (!isVoidType(ret)) return false;
                return isIntType(params[0].t);
            default:
                return false;
        }
    }

    static function isIntType(t:Type):Bool {
        switch (t) {
            case TAbstract(aref, _):
                var a = aref.get();
                return a.pack.length == 0 && a.name == "Int";
            case TType(tref, _):
                return isIntType(tref.get().type);
            default:
                return false;
        }
    }

    static function isVoidType(t:Type):Bool {
        switch (t) {
            case TAbstract(aref, _):
                var a = aref.get();
                return a.pack.length == 0 && a.name == "Void";
            case TType(tref, _):
                return isVoidType(tref.get().type);
            default:
                return false;
        }
    }

    /** Detects the trivial "forwarding closure" pattern :
            () -> SomeStatic.method(idx)
        where `idx` is the ForEach lambda's index parameter. Returns
        the fully-qualified target method path when the pattern
        matches — caller threads it through `registerParametricCallback`
        as if the user had written `Custom(SomeStatic.method)` directly.
        Returns null for any other body shape ; the caller falls back
        to the regular zero-arg lift (which won't compile if the body
        captures locals, but that's the existing documented behaviour).

        Why this is enough as a v1 — the canonical use case is :
            new ForEach(items, (item, idx:Int) ->
                new MyRow(...).onTap(StateAction.Custom(() -> handleTap(idx)))
            )
        which is just sugar over the typed-callback form. Richer
        closures (multi-statement, multi-call, captures beyond idx)
        still hit the existing "no closure scope" wall — solving them
        properly needs a TVar-substituting lift that's deferred. */
    /** Convert a typed closure body into an untyped `Expr` so it
        retypes cleanly inside a generated wrapper exposing the row
        index as an `idx:Int` parameter. References to the ForEach
        lambda's index local are rewritten as bare `idx` identifiers
        — when Haxe types the wrapper, they resolve to the param.
        Returns null when the body uses a construct we don't model
        (TSwitch, TTry, captures other than `idx`, …). */
    static function closureBodyToExpr(e:TypedExpr, idxName:String):Null<haxe.macro.Expr> {
        if (e == null) return null;
        var pos = e.pos;
        function mk(def:haxe.macro.Expr.ExprDef):haxe.macro.Expr return { expr: def, pos: pos };
        switch (e.expr) {
            case TConst(c):
                return switch (c) {
                    case TInt(i):    mk(EConst(CInt(Std.string(i))));
                    case TFloat(s):  mk(EConst(CFloat(s)));
                    case TString(s): mk(EConst(CString(s)));
                    case TBool(b):   mk(EConst(CIdent(b ? "true" : "false")));
                    case TNull:      mk(EConst(CIdent("null")));
                    case TThis:      mk(EConst(CIdent("this")));
                    case TSuper:     mk(EConst(CIdent("super")));
                };
            case TLocal(v):
                // ForEach idx capture → wrapper's `idx` param.
                if (v.name == idxName) return mk(EConst(CIdent("idx")));
                // Direct capture of the ForEach item var (without
                // field access) — we can't materialise the row item
                // as a whole inside the wrapper, only its individual
                // fields via the accessor. Surface as null so the
                // caller drops to the failing fallback explicitly.
                if (foreachContextItemVar != null && v.id == foreachContextItemVar.id) return null;
                // Capture of a local declared in the ForEach row
                // lambda body — substitute its initializer inline.
                // The initializer is recursively converted so it
                // re-types against the wrapper's scope (`idx` etc.).
                if (foreachContextLocalInits != null) {
                    var init = foreachContextLocalInits.get(v.id);
                    if (init != null) return closureBodyToExpr(init, idxName);
                }
                // Locals declared inside the closure carry the
                // declared name and resolve once their TVar
                // declarations are converted. Captures of further-
                // out locals (outside the ForEach lambda) will
                // trip the wrapper's re-typing with "unknown
                // identifier" — the right place for the user to
                // see the error.
                return mk(EConst(CIdent(v.name)));
            case TField(obj, fa):
                var name = fieldAccessName(fa);
                if (name == null) return null;
                // `item.<field>` access — rewrite as a call into the
                // generated `wui.generated.ForEachAccessor` module.
                // The field's actual Haxe type drives the accessor's
                // return type (and the suffix on the method name)
                // so non-string fields (Int, Bool, …) compose
                // naturally with the rest of the closure body.
                switch (obj.expr) {
                    case TLocal(v) if (foreachContextItemVar != null
                            && v.id == foreachContextItemVar.id
                            && foreachContextStateName != null):
                        var stateName = foreachContextStateName;
                        var fieldType = fieldHaxeType(fa);
                        if (fieldType == null) return null;
                        var typeName = haxeTypeToAccessorType(fieldType);
                        if (typeName == null) return null;
                        var key = stateName + "::" + name + "::" + typeName;
                        foreachAccessorFields.set(key, {
                            stateName: stateName,
                            fieldName: name,
                            fieldType: typeName
                        });
                        var accessorPath = pathToExpr(["wui", "generated", "ForEachAccessor"], pos);
                        var methodName = accessorMethodName(stateName, name, typeName);
                        return mk(ECall(
                            mk(EField(accessorPath, methodName)),
                            [mk(EConst(CIdent("idx")))]
                        ));
                    default:
                }
                switch (fa) {
                    case FStatic(cl, _):
                        return staticFieldExpr(cl.get(), name, pos);
                    case FEnum(en, _):
                        var path = en.get().pack.copy();
                        path.push(en.get().name);
                        return mk(EField(pathToExpr(path, pos), name));
                    default:
                        var inner = closureBodyToExpr(obj, idxName);
                        if (inner == null) return null;
                        return mk(EField(inner, name));
                }
            case TTypeExpr(mt):
                var path = switch (mt) {
                    case TClassDecl(c):    c.get().pack.concat([c.get().name]);
                    case TEnumDecl(en):    en.get().pack.concat([en.get().name]);
                    case TTypeDecl(t):     t.get().pack.concat([t.get().name]);
                    case TAbstract(a):     a.get().pack.concat([a.get().name]);
                };
                return pathToExpr(path, pos);
            case TCall(func, args):
                var f = closureBodyToExpr(func, idxName);
                if (f == null) return null;
                var converted:Array<haxe.macro.Expr> = [];
                for (a in args) {
                    var ce = closureBodyToExpr(a, idxName);
                    if (ce == null) return null;
                    converted.push(ce);
                }
                return mk(ECall(f, converted));
            case TBlock(exprs):
                var converted:Array<haxe.macro.Expr> = [];
                for (sub in exprs) {
                    var ce = closureBodyToExpr(sub, idxName);
                    if (ce == null) return null;
                    converted.push(ce);
                }
                return mk(EBlock(converted));
            case TIf(cond, then, _else):
                var c = closureBodyToExpr(cond, idxName);
                var t = closureBodyToExpr(then, idxName);
                if (c == null || t == null) return null;
                var el:haxe.macro.Expr = null;
                if (_else != null) {
                    el = closureBodyToExpr(_else, idxName);
                    if (el == null) return null;
                }
                return mk(EIf(c, t, el));
            case TBinop(op, e1, e2):
                var l = closureBodyToExpr(e1, idxName);
                var r = closureBodyToExpr(e2, idxName);
                if (l == null || r == null) return null;
                return mk(EBinop(op, l, r));
            case TUnop(op, postFix, sub):
                var s = closureBodyToExpr(sub, idxName);
                if (s == null) return null;
                return mk(EUnop(op, postFix, s));
            case TReturn(sub):
                var s:haxe.macro.Expr = null;
                if (sub != null) {
                    s = closureBodyToExpr(sub, idxName);
                    if (s == null) return null;
                }
                return mk(EReturn(s));
            case TParenthesis(sub):
                var s = closureBodyToExpr(sub, idxName);
                if (s == null) return null;
                return mk(EParenthesis(s));
            case TMeta(_, sub):
                return closureBodyToExpr(sub, idxName);
            case TVar(v, init):
                var ie:haxe.macro.Expr = null;
                if (init != null) {
                    ie = closureBodyToExpr(init, idxName);
                    if (ie == null) return null;
                }
                return mk(EVars([{ name: v.name, type: null, expr: ie }]));
            case TArray(e1, e2):
                var a = closureBodyToExpr(e1, idxName);
                var b = closureBodyToExpr(e2, idxName);
                if (a == null || b == null) return null;
                return mk(EArray(a, b));
            case TArrayDecl(exprs):
                var converted:Array<haxe.macro.Expr> = [];
                for (sub in exprs) {
                    var ce = closureBodyToExpr(sub, idxName);
                    if (ce == null) return null;
                    converted.push(ce);
                }
                return mk(EArrayDecl(converted));
            case TObjectDecl(fields):
                var converted:Array<haxe.macro.Expr.ObjectField> = [];
                for (f in fields) {
                    var ce = closureBodyToExpr(f.expr, idxName);
                    if (ce == null) return null;
                    converted.push({ field: f.name, expr: ce });
                }
                return mk(EObjectDecl(converted));
            case TNew(c, _, args):
                var cls = c.get();
                var converted:Array<haxe.macro.Expr> = [];
                for (a in args) {
                    var ce = closureBodyToExpr(a, idxName);
                    if (ce == null) return null;
                    converted.push(ce);
                }
                return mk(ENew({ pack: cls.pack, name: cls.name }, converted));
            case TBreak:    return mk(EBreak);
            case TContinue: return mk(EContinue);
            case TThrow(sub):
                var s = closureBodyToExpr(sub, idxName);
                if (s == null) return null;
                return mk(EThrow(s));
            case TWhile(cond, body, normalWhile):
                var c = closureBodyToExpr(cond, idxName);
                var b = closureBodyToExpr(body, idxName);
                if (c == null || b == null) return null;
                return mk(EWhile(c, b, normalWhile));
            case TFor(v, it, body):
                var itc = closureBodyToExpr(it, idxName);
                var bc = closureBodyToExpr(body, idxName);
                if (itc == null || bc == null) return null;
                var ident:haxe.macro.Expr = { expr: EConst(CIdent(v.name)), pos: pos };
                return mk(EFor({ expr: EBinop(OpIn, ident, itc), pos: pos }, bc));
            case TSwitch(subj, cases, edef):
                var s = closureBodyToExpr(subj, idxName);
                if (s == null) return null;
                var newCases:Array<haxe.macro.Expr.Case> = [];
                for (cs in cases) {
                    var ce = closureBodyToExpr(cs.expr, idxName);
                    if (ce == null) return null;
                    var vals:Array<haxe.macro.Expr> = [];
                    for (val in cs.values) {
                        var vc = closureBodyToExpr(val, idxName);
                        if (vc == null) return null;
                        vals.push(vc);
                    }
                    newCases.push({ values: vals, guard: null, expr: ce });
                }
                var newDef:Null<haxe.macro.Expr> = null;
                if (edef != null) {
                    newDef = closureBodyToExpr(edef, idxName);
                    if (newDef == null) return null;
                }
                return mk(ESwitch(s, newCases, newDef));
            case TTry(e, catches):
                var be = closureBodyToExpr(e, idxName);
                if (be == null) return null;
                var newCatches:Array<haxe.macro.Expr.Catch> = [];
                for (c in catches) {
                    var ce = closureBodyToExpr(c.expr, idxName);
                    if (ce == null) return null;
                    var ct = haxe.macro.TypeTools.toComplexType(c.v.t);
                    if (ct == null) return null;
                    newCatches.push({ name: c.v.name, type: ct, expr: ce });
                }
                return mk(ETry(be, newCatches));
            case TCast(e, m):
                var be = closureBodyToExpr(e, idxName);
                if (be == null) return null;
                var ct:Null<haxe.macro.Expr.ComplexType> = null;
                if (m != null) ct = moduleTypeToComplexType(m);
                return mk(ECast(be, ct));
            case TFunction(tf):
                var bodyExpr = closureBodyToExpr(tf.expr, idxName);
                if (bodyExpr == null) return null;
                var argsConverted:Array<haxe.macro.Expr.FunctionArg> = [];
                for (a in tf.args) {
                    var argType = haxe.macro.TypeTools.toComplexType(a.v.t);
                    argsConverted.push({
                        name: a.v.name,
                        type: argType,
                        opt: a.value != null,
                    });
                }
                var ret = haxe.macro.TypeTools.toComplexType(tf.t);
                return mk(EFunction(FAnonymous, {
                    args: argsConverted,
                    ret: ret,
                    expr: bodyExpr,
                }));
            default:
                return null;
        }
    }

    /** Walk a typed expression collecting every `TVar(v, init)` we
        find, keyed by `v.id`. Used by `ForEach.wuiAnalyze` to seed
        `foreachContextLocalInits` from the row lambda body. */
    public static function collectLocalInits(e:haxe.macro.Type.TypedExpr, out:Map<Int, haxe.macro.Type.TypedExpr>):Void {
        if (e == null) return;
        switch (e.expr) {
            case TVar(v, init): if (init != null) out.set(v.id, init);
            default:
        }
        haxe.macro.TypedExprTools.iter(e, function(c) collectLocalInits(c, out));
    }

    /** Map a Haxe Type to one of the "accessor type" names we emit
        bodies for : "String", "Int", "Float", "Bool", "Dynamic".
        Returns null for types we don't have a typed body for ;
        caller falls back to the (failing) zero-arg lift so the user
        sees a clear error rather than a silent miscompile. */
    static function haxeTypeToAccessorType(t:haxe.macro.Type.Type):Null<String> {
        return switch (t) {
            case TAbstract(aref, _):
                var a = aref.get();
                if (a.pack.length != 0) null;
                else switch (a.name) {
                    case "Int":   "Int";
                    case "Float": "Float";
                    case "Bool":  "Bool";
                    default:      null;
                };
            case TInst(cref, _):
                var c = cref.get();
                if (c.pack.length == 0 && c.name == "String") "String"
                else null;
            case TDynamic(_): "Dynamic";
            case TType(tref, _):
                haxeTypeToAccessorType(tref.get().type);
            default: null;
        };
    }

    /** Pull the field's Haxe type out of a `FieldAccess` so the
        accessor can be sized correctly. */
    static function fieldHaxeType(fa:haxe.macro.Type.FieldAccess):Null<haxe.macro.Type.Type> {
        return switch (fa) {
            case FAnon(cf):           cf.get().type;
            case FInstance(_, _, cf): cf.get().type;
            case FStatic(_, cf):      cf.get().type;
            case FClosure(_, cf):     cf.get().type;
            default: null;
        };
    }

    /** Stable method-name convention :
          - String fields keep the legacy `<state>_field_<field>`
            shape so existing analyzeTextChild emissions stay valid
          - Typed variants get a `_<Type>` suffix
        Both can co-exist on the same (state, field) pair when one
        consumer needs a String view and another needs the raw
        typed value. */
    public static function accessorMethodName(stateName:String, fieldName:String, fieldType:String):String {
        return fieldType == "String"
            ? stateName + "_field_" + fieldName
            : stateName + "_field_" + fieldName + "_" + fieldType;
    }

    static function moduleTypeToComplexType(mt:haxe.macro.Type.ModuleType):haxe.macro.Expr.ComplexType {
        return switch (mt) {
            case TClassDecl(c): TPath({ pack: c.get().pack, name: c.get().name, params: [] });
            case TEnumDecl(en): TPath({ pack: en.get().pack, name: en.get().name, params: [] });
            case TTypeDecl(t):  TPath({ pack: t.get().pack,  name: t.get().name,  params: [] });
            case TAbstract(a):  TPath({ pack: a.get().pack,  name: a.get().name,  params: [] });
        };
    }

    static function fieldAccessName(fa:haxe.macro.Type.FieldAccess):Null<String> {
        return switch (fa) {
            case FInstance(_, _, cf): cf.get().name;
            case FStatic(_, cf):      cf.get().name;
            case FAnon(cf):           cf.get().name;
            case FClosure(_, cf):     cf.get().name;
            case FDynamic(s):         s;
            case FEnum(_, ef):        ef.name;
        };
    }

    static function staticFieldExpr(cls:haxe.macro.Type.ClassType, fieldName:String, pos:haxe.macro.Expr.Position):haxe.macro.Expr {
        var path = cls.pack.copy();
        path.push(cls.name);
        return { expr: EField(pathToExpr(path, pos), fieldName), pos: pos };
    }

    static function pathToExpr(parts:Array<String>, pos:haxe.macro.Expr.Position):haxe.macro.Expr {
        if (parts.length == 0) return { expr: EConst(CIdent("null")), pos: pos };
        var e:haxe.macro.Expr = { expr: EConst(CIdent(parts[0])), pos: pos };
        for (i in 1...parts.length) {
            e = { expr: EField(e, parts[i]), pos: pos };
        }
        return e;
    }

    // Note: the .value -> StateBridge rewrite happens at Expr level
    // inside StateMacro (pre-typing) — Context.typeExpr at this point
    // in onAfterTyping trips an internal compiler assertion. See
    // StateMacro.rewriteStateValueAccess for the implementation.

    /** Emit a generated `wui.generated.Callbacks` class containing one
        static wrapper per registered callback. MainWindow.cpp's click
        handlers call into this class via its hxcpp-generated qualified
        name (`::wui::generated::Callbacks_obj::wui_cb_<N>()`), no C
        linkage needed. Called from `analyze()` during the typing pass
        so hxcpp picks the class up as part of the normal compilation. */
    static function emitCallbackModule():Void {
        var totalRegistered = Lambda.count(callbackRegistry)
            + Lambda.count(parametricCallbackRegistry)
            + lambdaRegistry.length
            + parametricLambdaRegistry.length;
        if (totalRegistered == 0) return;
        var pos = haxe.macro.Context.currentPos();
        var fields:Array<haxe.macro.Expr.Field> = [];
        // Static-function callbacks (zero-arg).
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
        // Parametric static-function callbacks — take the row index
        // and forward to a typed `(Int) -> Void` target.
        for (fnPath in parametricCallbackRegistry.keys()) {
            var wrapperName = parametricCallbackRegistry.get(fnPath);
            var bodyExpr = haxe.macro.Context.parse('{ $fnPath(idx); }', pos);
            fields.push({
                name: wrapperName,
                pos: pos,
                meta: [{ name: ":keep", pos: pos }],
                access: [APublic, AStatic],
                kind: FFun({
                    args: [{ name: "idx", type: macro :Int }],
                    ret: macro :Void,
                    expr: bodyExpr
                })
            });
        }
        // Parametric closures — body comes from `closureBodyToExpr`
        // which has already rewritten ForEach idx captures to `idx`.
        for (entry in parametricLambdaRegistry) {
            fields.push({
                name: entry.name,
                pos: pos,
                meta: [{ name: ":keep", pos: pos }],
                access: [APublic, AStatic],
                kind: FFun({
                    args: [{ name: "idx", type: macro :Int }],
                    ret: macro :Void,
                    expr: entry.body
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
        for (n in parametricCallbackRegistry) all.push(n);
        for (e in lambdaRegistry) all.push(e.name);
        for (e in parametricLambdaRegistry) all.push(e.name);
        UIBuilder.exposedCallbacks = all;
    }

    /** Emit `wui.generated.ForEachAccessor` — one static method per
        unique `(stateName, fieldName)` pair surfaced by a ForEach
        widget, plus one `<state>_length()` per ForEach'd state. The
        C++ rebuild function in MainWindow.cpp calls these via
        `::wui::generated::ForEachAccessor_obj::inbox_field_from(i)`,
        i.e. the same hxcpp qualified-name path as Callbacks.

        Each accessor walks the State registry (no per-app singleton:
        `State.getByName` is enough) and pulls the requested field via
        Dynamic field access — that works for both class instances and
        anonymous-typedef rows (which is what `EmailRow` is). */
    static function emitForEachAccessorModule():Void {
        var hasAny = Lambda.count(foreachAccessorFields) > 0 || Lambda.count(foreachAccessorLengths) > 0;
        if (!hasAny) return;

        var pos = haxe.macro.Context.currentPos();
        var fields:Array<haxe.macro.Expr.Field> = [];

        for (stateName in foreachAccessorLengths.keys()) {
            var lengthBody = '{ var s:wui.state.State<wui.state.ImmutableList<Dynamic>> = cast wui.state.State.getByName("' + stateName + '"); if (s == null || s.value == null) return 0; return s.value.length; }';
            fields.push({
                name: stateName + "_length",
                pos: pos,
                meta: [{ name: ":keep", pos: pos }],
                access: [APublic, AStatic],
                kind: FFun({
                    args: [],
                    ret: macro :Int,
                    expr: haxe.macro.Context.parse(lengthBody, pos)
                })
            });
        }

        for (key in foreachAccessorFields.keys()) {
            var info = foreachAccessorFields.get(key);
            var stateName = info.stateName;
            var fieldName = info.fieldName;
            var fieldType = info.fieldType;
            // Per-type accessor body. The String shape stays the
            // legacy default — the rest of the framework (text rows,
            // existing rebuild emitters) consume it untouched. Typed
            // variants get distinct method names via
            // `accessorMethodName` so they can coexist.
            var defaultValue:String;
            var cast_:String;
            var ret:haxe.macro.Expr.ComplexType;
            switch (fieldType) {
                case "Int":     defaultValue = "0";     cast_ = "(cast v : Int)";     ret = macro :Int;
                case "Float":   defaultValue = "0.0";   cast_ = "(cast v : Float)";   ret = macro :Float;
                case "Bool":    defaultValue = "false"; cast_ = "(cast v : Bool)";    ret = macro :Bool;
                case "Dynamic": defaultValue = "null";  cast_ = "v";                  ret = macro :Dynamic;
                default:        defaultValue = '""';    cast_ = "Std.string(v)";      ret = macro :String;
            }
            var body =
                '{ var s:wui.state.State<wui.state.ImmutableList<Dynamic>> = cast wui.state.State.getByName("' + stateName + '");'
              + ' if (s == null || s.value == null || i < 0 || i >= s.value.length) return $defaultValue;'
              + ' var row:Dynamic = s.value.get(i);'
              + ' if (row == null) return $defaultValue;'
              + ' var v:Dynamic = Reflect.field(row, "' + fieldName + '");'
              + ' return v == null ? $defaultValue : $cast_; }';
            fields.push({
                name: accessorMethodName(stateName, fieldName, fieldType),
                pos: pos,
                meta: [{ name: ":keep", pos: pos }],
                access: [APublic, AStatic],
                kind: FFun({
                    args: [{ name: "i", type: macro :Int }],
                    ret: ret,
                    expr: haxe.macro.Context.parse(body, pos)
                })
            });
        }

        haxe.macro.Context.defineType({
            pos: pos,
            pack: ["wui", "generated"],
            name: "ForEachAccessor",
            kind: TDClass(),
            fields: fields,
            meta: [{ name: ":keep", pos: pos }]
        });

        UIBuilder.foreachAccessorPresent = true;
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

    /** Return C++ expression to convert a state variable to std::wstring.
        Composite Observable keys carry dots in `stateName` (the bridge
        key) — `cppId` flips them to underscores so the emitted symbol
        matches the static variable declaration. */
    static function stateToWstring(stateName:String):String {
        var id = UIBuilder.cppId(stateName);
        for (sf in UIBuilder.stateFields) {
            if (sf.name == stateName) {
                if (sf.type == "std::wstring") return 's_$id';
                if (sf.type == "bool") return '(s_$id ? std::wstring(L"true") : std::wstring(L"false"))';
                return 'std::to_wstring(s_$id)';
            }
        }
        return 'std::to_wstring(s_$id)';
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
