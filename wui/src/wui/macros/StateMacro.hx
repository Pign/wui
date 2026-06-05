package wui.macros;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
import haxe.macro.ExprTools;

using haxe.macro.Tools;
#end

/**
 * Compile-time macro that transforms @:state fields on App subclasses
 * and Observable subclasses. Auto-built via the meta on `wui.App` and
 * `wui.state.Observable`.
 *
 * Type rule (enforced here with `Context.error`):
 *
 *     @:state var foo:T
 *
 * requires `T` to be one of:
 *  - A primitive: `String`, `Int`, `Float`, `Bool`
 *  - A class extending `wui.state.Observable`
 *  - A class implementing `wui.state.Immutable`
 *
 * (Nullary enums come in a later phase.)
 *
 * Codegen rules:
 *  - Primitive `@:state` on App: wrapped in `wui.state.State<T>` and
 *    constructed in `new()` with the bare field name as the bridge key
 *    ("darkMode").
 *  - Primitive `@:state` on Observable: same wrapping, but construction
 *    is deferred to a generated `_attach(scope)` override so the bridge
 *    key picks up the scope set by the enclosing App or Observable
 *    ("settings.darkMode").
 *  - Observable-typed `@:state` on App: the field stays a plain
 *    instance of the user type. After construction the macro injects
 *    `field._attach("field")`, propagating the dotted scope into the
 *    Observable's own `@:state` fields. Nested Observables fan out
 *    recursively because each layer's `_attach` prefixes the scope it
 *    receives.
 *  - Observable-typed `@:state` on Observable: rejected for now (phase
 *    1 limitation) — flag with `Context.error` so the user knows to
 *    flatten or wait.
 *  - Immutable-typed `@:state` on App: wrapped in `wui.state.State<T>`
 *    (same as primitive) and paired with a synthetic companion
 *    primitive `@:state var <name>__v:Int = 0;` that the State<T>
 *    bumps on every `.value = ...` write. The list/record value
 *    itself stays Haxe-side — only the `Int` trigger crosses the
 *    bridge, which is what `ForEach` listens on.
 */
class StateMacro {
    #if macro
    public static function build():Array<Field> {
        var fields = Context.getBuildFields();
        var isObservableClass = currentClassExtendsObservable();

        // Categorise @:state fields into primitive / Observable-typed /
        // Immutable-typed so we can fork the codegen below.
        var primitiveStates:Array<{name:String, type:ComplexType, initialValue:Expr, pos:Position}> = [];
        var observableStates:Array<{name:String, type:ComplexType, initialValue:Expr, pos:Position}> = [];
        var immutableStates:Array<{name:String, type:ComplexType, initialValue:Expr, pos:Position, versionKey:String}> = [];

        var newFields:Array<Field> = [];
        for (field in fields) {
            if (!hasStateMeta(field)) {
                newFields.push(field);
                continue;
            }
            switch (field.kind) {
                case FVar(t, e):
                    var initialValue = e;
                    var category = categoriseType(t, field.pos);
                    switch (category) {
                        case Primitive:
                            if (initialValue == null) initialValue = defaultExprForType(t, field.pos);
                            primitiveStates.push({name: field.name, type: t, initialValue: initialValue, pos: field.pos});
                            newFields.push(wrapAsState(field, t, initialValue));

                        case ObservableType:
                            if (isObservableClass) {
                                Context.error("@:state on nested Observable is not supported yet (phase 1 limitation). Flatten to primitive @:state fields for now.", field.pos);
                            }
                            if (initialValue == null) {
                                Context.error("@:state field of Observable type must have an explicit initial value (e.g. `= new Settings()`).", field.pos);
                            }
                            observableStates.push({name: field.name, type: t, initialValue: initialValue, pos: field.pos});
                            // Field keeps its declared type (Settings) — no State<T> wrapper.
                            // We strip the initializer because we'll re-emit it in the constructor.
                            newFields.push({
                                name: field.name,
                                doc: field.doc,
                                access: field.access,
                                pos: field.pos,
                                meta: field.meta,
                                kind: FVar(t, null)
                            });

                        case ImmutableType:
                            if (isObservableClass) {
                                Context.error("@:state of Immutable type inside an Observable is not supported (an Observable already decomposes per-field; nest only primitives).", field.pos);
                            }
                            if (initialValue == null) {
                                Context.error("@:state field of Immutable type must have an explicit initial value (e.g. `= ImmutableList.empty()`).", field.pos);
                            }
                            // The user-facing field keeps Haxe-side semantics:
                            // wrapped in State<T>, .value returns the immutable
                            // ref directly. The companion __v field below carries
                            // the C++ trigger.
                            var versionFieldName = field.name + "__v";
                            immutableStates.push({
                                name: field.name,
                                type: t,
                                initialValue: initialValue,
                                pos: field.pos,
                                versionKey: versionFieldName
                            });
                            newFields.push(wrapAsState(field, t, initialValue));

                            // Synthetic primitive @:state Int — same shape the
                            // existing code already knows how to bridge.
                            var zero = macro 0;
                            primitiveStates.push({
                                name: versionFieldName,
                                type: macro :Int,
                                initialValue: zero,
                                pos: field.pos
                            });
                            var syntheticVersionField:Field = {
                                name: versionFieldName,
                                access: [],
                                pos: field.pos,
                                meta: [{name: ":state", params: [], pos: field.pos}],
                                kind: FVar(macro :Int, zero)
                            };
                            newFields.push(wrapAsState(syntheticVersionField, macro :Int, zero));

                        case Ineligible(reason):
                            Context.error('@:state var ${field.name}:T — $reason', field.pos);
                    }

                default:
                    Context.error("@:state can only be applied to var fields", field.pos);
            }
        }

        // Generate `_attach(scope)` override on Observable subclasses
        // so the deferred State<T> construction picks up the bridge key
        // prefix decided by the enclosing scope.
        if (isObservableClass && primitiveStates.length > 0) {
            newFields.push(buildAttachOverride(primitiveStates));
        }

        // Inject construction at the top of `new()` on App subclasses
        // (or any non-Observable class with @:state). Observable
        // subclasses don't touch the constructor — their State<T>s
        // live in `_attach` instead.
        if (!isObservableClass && (primitiveStates.length > 0 || observableStates.length > 0 || immutableStates.length > 0)) {
            injectAppConstructor(newFields, primitiveStates, observableStates, immutableStates);
        }

        // Immutable @:state fields rely on the Haxe-side State<T>
        // wrapper to hold the list payload — so the App MUST be
        // instantiated at runtime. The user's `static main()` typically
        // doesn't `new` the App (the WUI macro pipeline reads `body()`
        // and `effects()` at compile time and never invokes them as
        // Haxe code), so we add a `static __init__()` block that does
        // a one-shot construction. The resulting instance is unnamed —
        // its only job is to populate `wui.state.State._registry` so
        // `wui.generated.ForEachAccessor` can find the list.
        if (!isObservableClass && immutableStates.length > 0) {
            injectAppMain(newFields);
        }

        // Pre-typing rewrite of `state.value` reads/writes inside
        // `effects()` — see rewriteStateValueAccess. Runs after the
        // field list is finalised so we know exactly which idents are
        // @:state.
        //
        // For Observable composites, enumerate the sub-class's @:state
        // leaves and append them as synthetic primitives keyed
        // `<root>.<leaf>` so a `settings.fontSize.value` read inside
        // an effect (or any lifted closure) rewrites cleanly through
        // the bridge instead of dereferencing the stale Haxe-side
        // `_value`.
        var rewriteStates:Array<{name:String, type:ComplexType, initialValue:Expr, pos:Position}> = primitiveStates.copy();
        for (obs in observableStates) {
            var leaves = enumerateObservableLeaves(obs);
            for (leaf in leaves) rewriteStates.push(leaf);
        }
        var allStateNames = rewriteStates;
        if (allStateNames.length > 0) {
            for (i in 0...newFields.length) {
                switch (newFields[i].name) {
                    case "effects":
                        // The whole effects() body lives in a single
                        // static-call context — apply the rewrite to
                        // its full expression so every `<state>.value`
                        // read (including the ones inside `Effect.run`
                        // lambdas) reaches the bridge.
                        switch (newFields[i].kind) {
                            case FFun(f) if (f.expr != null):
                                f.expr = rewriteStateValueAccess(f.expr, rewriteStates);
                            default:
                        }
                    case "body" | "titleBar":
                        // The view tree itself mustn't be rewritten —
                        // widget bindings like `new Text(searchQuery)`
                        // need to stay as state-ref reads for the
                        // analyzer to wire listeners. But `.onTap(() ->
                        // { … })`, `Button(label, null, () -> { … })`
                        // and other 0-arg closures get lifted into
                        // static `Callbacks_obj` methods that have no
                        // access to the App instance — there the
                        // bridge is the only way to read live state.
                        // Walk for 0-arg lambdas and rewrite their
                        // bodies only.
                        switch (newFields[i].kind) {
                            case FFun(f) if (f.expr != null):
                                f.expr = rewriteLambdasInBody(f.expr, rewriteStates);
                            default:
                        }
                    default:
                }
            }
        }

        return newFields;
    }

    /** Walker that finds every 0-arg `EFunction` reachable from a
        `body()` / `titleBar()` expression and applies
        `rewriteStateValueAccess` to its inner expression. Multi-arg
        functions (ForEach row lambdas, etc.) are descended through
        but their bodies are not rewritten as a whole — only any
        nested 0-arg closures inside them get the treatment. */
    static function rewriteLambdasInBody(e:Expr, states:Array<{name:String, type:ComplexType, initialValue:Expr, pos:Position}>):Expr {
        if (e == null) return null;
        switch (e.expr) {
            case EFunction(kind, fn) if (fn != null && fn.args != null && fn.args.length == 0 && fn.expr != null):
                var rewritten = rewriteStateValueAccess(fn.expr, states);
                return {
                    expr: EFunction(kind, {
                        args: fn.args,
                        ret: fn.ret,
                        expr: rewritten,
                        params: fn.params
                    }),
                    pos: e.pos
                };
            default:
        }
        return haxe.macro.ExprTools.map(e, function(c) return rewriteLambdasInBody(c, states));
    }

    /** Look up an `@:state var <name>:<ObservableSubclass>` field's
        type via the typer and produce one synthetic primitive entry
        per `@:state` field declared on the Observable.

        Each entry's `name` is the bridge key (`<name>.<leaf>`), its
        `type` is the leaf's declared primitive ComplexType (the type
        parameter of the State<T> wrapping that StateMacro applied
        when it built the Observable subclass). Used by
        `rewriteStateValueAccess` to recognise multi-level chains
        like `settings.darkMode.value` and rewrite them to
        `StateBridge.getBool("settings.darkMode")`. */
    static function enumerateObservableLeaves(obs:{name:String, type:ComplexType, initialValue:Expr, pos:Position}):Array<{name:String, type:ComplexType, initialValue:Expr, pos:Position}> {
        var out:Array<{name:String, type:ComplexType, initialValue:Expr, pos:Position}> = [];
        var typeName:String = switch (obs.type) {
            case TPath(p):
                (p.pack.length > 0 ? p.pack.join(".") + "." : "") + p.name;
            default: null;
        };
        if (typeName == null) return out;
        var t:haxe.macro.Type;
        try {
            t = Context.getType(typeName);
        } catch (_:Dynamic) {
            return out;
        }
        var fields:Array<haxe.macro.Type.ClassField> = switch (t) {
            case TInst(cref, _): cref.get().fields.get();
            default: null;
        };
        if (fields == null) return out;
        for (cf in fields) {
            // Pick up the original @:state meta — it survives macro
            // expansion (StateMacro adds the synthetic State<T> wrap
            // but keeps the source field's meta list).
            if (!fieldHasStateMeta(cf)) continue;
            // The field's type is now `State<T>` post-expansion.
            // Pull out T as the bridge-suffix-determining primitive.
            var leafType:ComplexType = extractStateInnerType(cf.type);
            if (leafType == null) continue;
            out.push({
                name: obs.name + "." + cf.name,
                type: leafType,
                initialValue: macro null,
                pos: obs.pos
            });
        }
        return out;
    }

    static function fieldHasStateMeta(cf:haxe.macro.Type.ClassField):Bool {
        var meta = cf.meta.get();
        for (m in meta) {
            if (m.name == ":state" || m.name == "state") return true;
        }
        return false;
    }

    /** Given the post-macro `State<T>` field type, return T as a
        ComplexType so `bridgeSuffix` can pick the right
        StateBridge.get/setX flavour. */
    static function extractStateInnerType(t:haxe.macro.Type):ComplexType {
        switch (t) {
            case TInst(cref, params):
                var c = cref.get();
                if (c.name == "State" && c.pack.length == 2 && c.pack[0] == "wui" && c.pack[1] == "state" && params.length == 1) {
                    return haxe.macro.TypeTools.toComplexType(params[0]);
                }
            default:
        }
        return null;
    }

    // ---- Field categorisation -------------------------------------------------

    static function hasStateMeta(field:Field):Bool {
        if (field.meta == null) return false;
        for (meta in field.meta) {
            if (meta.name == ":state" || meta.name == "state") return true;
        }
        return false;
    }

    /** Enum-style result for `categoriseType`. */
    static function categoriseType(t:ComplexType, pos:Position):TypeCategory {
        if (t == null) return Ineligible("@:state field must declare an explicit type.");
        // Primitive shortcut on TPath shape — avoids a typer round-trip
        // for the hot case.
        switch (t) {
            case TPath(p) if (p.pack.length == 0):
                switch (p.name) {
                    case "String" | "Int" | "Float" | "Bool": return Primitive;
                    default:
                }
            default:
        }
        // Anything else: resolve through the typer to inspect the
        // super chain. Wrapped in try/catch because non-existent types
        // throw here.
        var resolved:Type = null;
        try {
            resolved = Context.resolveType(t, pos);
        } catch (e:Dynamic) {
            return Ineligible("Could not resolve the field type.");
        }
        if (isObservable(resolved)) return ObservableType;
        if (implementsImmutable(resolved)) return ImmutableType;
        return Ineligible("type must be a primitive (String/Int/Float/Bool), extend wui.state.Observable, or implement wui.state.Immutable.");
    }

    /** Walk a Type's class+interface chain looking for the
        `wui.state.Immutable` marker interface. Reactive `ImmutableList`
        and any user-defined value type implementing the marker qualify
        for the version-trigger codegen path. */
    static function implementsImmutable(t:Type):Bool {
        if (t == null) return false;
        switch (t) {
            case TInst(ref, _):
                var cls = ref.get();
                var cur = cls;
                while (cur != null) {
                    if (cur.interfaces != null) {
                        for (iface in cur.interfaces) {
                            var ic = iface.t.get();
                            if (ic.pack.length == 2 && ic.pack[0] == "wui" && ic.pack[1] == "state" && ic.name == "Immutable") return true;
                        }
                    }
                    if (cur.superClass == null) break;
                    cur = cur.superClass.t.get();
                }
            default:
        }
        return false;
    }

    /** Walk a Type's class chain looking for wui.state.Observable. */
    static function isObservable(t:Type):Bool {
        if (t == null) return false;
        switch (t) {
            case TInst(ref, _):
                var cls = ref.get();
                var cur = cls;
                while (cur != null) {
                    if (cur.pack.length == 2 && cur.pack[0] == "wui" && cur.pack[1] == "state" && cur.name == "Observable") return true;
                    if (cur.superClass == null) return false;
                    cur = cur.superClass.t.get();
                }
            default:
        }
        return false;
    }

    /** True iff the class currently being built (the `@:autoBuild`
        target) is an Observable subclass. Used to fork codegen. */
    static function currentClassExtendsObservable():Bool {
        var clsRef = Context.getLocalClass();
        if (clsRef == null) return false;
        var cls = clsRef.get();
        if (cls.superClass == null) return false;
        var superT:Type = TInst(cls.superClass.t, cls.superClass.params);
        return isObservable(superT);
    }

    // ---- Field & constructor codegen ------------------------------------------

    /** Replace the user's `@:state var foo:T = init` declaration with a
        `var foo:wui.state.State<T>` declaration. The original initial
        expression is stashed in a `@:wuiInitial` meta for the C++
        codegen (`UIBuilder.collectStateFields`) to read back. */
    static function wrapAsState(field:Field, t:ComplexType, initialValue:Expr):Field {
        var stateType = TPath({
            pack: ["wui", "state"],
            name: "State",
            params: t != null ? [TPType(t)] : []
        });
        var existingMeta = field.meta != null ? field.meta : [];
        var withInitial = existingMeta.concat([{
            name: ":wuiInitial",
            params: [initialValue],
            pos: field.pos
        }]);
        return {
            name: field.name,
            doc: field.doc,
            access: field.access,
            pos: field.pos,
            meta: withInitial,
            kind: FVar(stateType, null)
        };
    }

    /** Generated `_attach(scope:String):Void` override on an Observable
        subclass: calls `super._attach(scope)` to set `_scope`, then
        constructs each `State<T>` with a scope-prefixed bridge key. */
    static function buildAttachOverride(states:Array<{name:String, type:ComplexType, initialValue:Expr, pos:Position}>):Field {
        var stmts:Array<Expr> = [macro super._attach(scope)];
        for (sf in states) {
            var nameLit = sf.name;
            stmts.push(macro $i{nameLit} = new wui.state.State($e{sf.initialValue}, scope + "." + $v{nameLit}));
        }
        return {
            name: "_attach",
            access: [APublic, AOverride],
            pos: Context.currentPos(),
            kind: FFun({
                args: [{name: "scope", type: macro :String}],
                ret: macro :Void,
                expr: macro $b{stmts}
            })
        };
    }

    /** Prepend the State<T> constructor calls and Observable attach
        calls to the App's `new()` (or create one if absent). Handles
        primitive @:state, Observable-typed @:state, and Immutable-typed
        @:state in the order they were collected — Immutables come last
        so their synthetic `<name>__v` companion primitive (already
        appended to `primitives`) is constructed before the Immutable
        State<T> that references it. */
    static function injectAppConstructor(
        newFields:Array<Field>,
        primitives:Array<{name:String, type:ComplexType, initialValue:Expr, pos:Position}>,
        observables:Array<{name:String, type:ComplexType, initialValue:Expr, pos:Position}>,
        immutables:Array<{name:String, type:ComplexType, initialValue:Expr, pos:Position, versionKey:String}>
    ):Void {
        var initExprs:Array<Expr> = [];
        for (sf in primitives) {
            var nameLit = sf.name;
            initExprs.push(macro $i{nameLit} = new wui.state.State($e{sf.initialValue}, $v{nameLit}));
        }
        for (sf in observables) {
            var nameLit = sf.name;
            initExprs.push(macro $i{nameLit} = ${sf.initialValue});
            initExprs.push(macro $i{nameLit}._attach($v{nameLit}));
        }
        for (sf in immutables) {
            var nameLit = sf.name;
            var versionLit = sf.versionKey;
            initExprs.push(macro $i{nameLit} = new wui.state.State($e{sf.initialValue}, $v{nameLit}, $v{versionLit}));
        }

        var constructorFound = false;
        for (i in 0...newFields.length) {
            var field = newFields[i];
            if (field.name != "new") continue;
            constructorFound = true;
            switch (field.kind) {
                case FFun(f):
                    var existingExprs:Array<Expr> = [];
                    if (f.expr != null) {
                        switch (f.expr.expr) {
                            case EBlock(exprs): existingExprs = exprs;
                            default: existingExprs = [f.expr];
                        }
                    }
                    f.expr = macro $b{initExprs.concat(existingExprs)};
                default:
            }
        }
        if (!constructorFound) {
            initExprs.unshift(macro super());
            newFields.push({
                name: "new",
                access: [APublic],
                pos: Context.currentPos(),
                kind: FFun({
                    args: [],
                    ret: null,
                    expr: macro $b{initExprs}
                })
            });
        }
    }

    /** Prepend `new ThisClass();` to the App's `static main()` so the
        Haxe-side State<T> wrappers get constructed and registered into
        `State._registry` before the user's main body runs.

        Why not `static __init__`: hxcpp runs `__init__` blocks during
        the `__boot` phase, but `wui.state.State`'s static `_registry`
        is itself an inline-initialised static (set during *its own*
        `__boot`). Boot order is non-deterministic — if the App's
        `__init__` runs before `State._boot()`, the registry is null
        and `_registry.set(...)` segfaults the process before any
        diagnostic can reach the debug console. By the time `main()`
        runs, every `__boot()` has completed, so the registry is
        guaranteed to be live.

        If the user didn't write a `main()`, we synthesise an empty
        one with just the construction call. */
    static function injectAppMain(newFields:Array<Field>):Void {
        var cls = Context.getLocalClass().get();
        var typePath:TypePath = { pack: cls.pack, name: cls.name };
        var ctorStmt:Expr = macro { new $typePath(); };

        for (i in 0...newFields.length) {
            var field = newFields[i];
            if (field.name != "main") continue;
            switch (field.kind) {
                case FFun(f):
                    var existing:Array<Expr> = [];
                    if (f.expr != null) {
                        switch (f.expr.expr) {
                            case EBlock(exprs): existing = exprs;
                            default: existing = [f.expr];
                        }
                    }
                    existing.unshift(ctorStmt);
                    f.expr = macro $b{existing};
                    return;
                default:
            }
        }
        // No user `main()` — synthesise one. Same shape as `haxelib new`
        // skeletons, just hosting the auto-construction call.
        newFields.push({
            name: "main",
            access: [APublic, AStatic],
            pos: Context.currentPos(),
            kind: FFun({
                args: [],
                ret: macro :Void,
                expr: macro $b{[ctorStmt]}
            })
        });
    }

    /** When the user omits the initialiser on a primitive @:state field
        we fall back to a type-appropriate zero. Keeps the generated
        `new State<T>(...)` call legal. */
    static function defaultExprForType(t:ComplexType, pos:Position):Expr {
        if (t == null) return macro null;
        return switch (t) {
            case TPath(p) if (p.pack.length == 0):
                switch (p.name) {
                    case "Int": macro 0;
                    case "Float": macro 0.0;
                    case "Bool": macro false;
                    case "String": macro "";
                    default: macro null;
                };
            default: macro null;
        };
    }

    // ---- effects() body rewrite -----------------------------------------------

    /**
     * Rewrite `<stateField>.value` reads and writes inside the user's
     * `effects()` body so they reach the C++ side directly via
     * `wui.state.StateBridge.get/setX`. Works at Expr level (pre-typing)
     * to avoid the `Context.typeExpr` re-entrance assertion that fires
     * when the same rewrite runs at `onAfterTyping`.
     */
    static function rewriteStateValueAccess(e:Expr, states:Array<{name:String, type:ComplexType, initialValue:Expr, pos:Position}>):Expr {
        if (e == null) return null;
        switch (e.expr) {
            case EBinop(OpAssign, lhs, rhs):
                var name = matchStateValueExpr(lhs, states);
                if (name != null) {
                    var sf = findStateByName(name, states);
                    var newRhs = rewriteStateValueAccess(rhs, states);
                    return bridgeSetCall(name, sf.type, newRhs, e.pos);
                }
            case EField(_, "value"):
                var name = matchStateValueExpr(e, states);
                if (name != null) {
                    var sf = findStateByName(name, states);
                    return bridgeGetCall(name, sf.type, e.pos);
                }
            default:
        }
        return ExprTools.map(e, function(c) return rewriteStateValueAccess(c, states));
    }

    /** Return the bridge key if `e` is `<chain>.value` where `<chain>`
        resolves to a known @:state field (top-level primitive or
        Observable-decomposed composite).

        Supports :
          - `searchQuery.value`               → "searchQuery"
          - `this.searchQuery.value`          → "searchQuery"
          - `settings.fontSize.value`         → "settings.fontSize"
          - `this.settings.fontSize.value`    → "settings.fontSize"

        The chain matcher is recursive on the receiver — multi-level
        Observable composites would extend naturally once the
        enumerator returns deeper leaves. */
    static function matchStateValueExpr(e:Expr, states:Array<{name:String, type:ComplexType, initialValue:Expr, pos:Position}>):String {
        if (e == null) return null;
        switch (e.expr) {
            case EField(receiver, "value"):
                var chain = buildIdentChain(receiver);
                if (chain != null) {
                    for (sf in states) if (sf.name == chain) return chain;
                }
            default:
        }
        return null;
    }

    /** Reconstruct the dotted ident chain rooted at a bare ident or
        at `this.<ident>`. Returns null for anything else (e.g. a call
        result, an array access, a non-ident chain root). */
    static function buildIdentChain(e:Expr):String {
        if (e == null) return null;
        switch (unwrapExpr(e).expr) {
            case EConst(CIdent(ident)):
                return ident == "this" ? null : ident;
            case EField(receiver, field):
                switch (unwrapExpr(receiver).expr) {
                    case EConst(CIdent("this")):
                        return field;
                    default:
                }
                var parent = buildIdentChain(receiver);
                if (parent != null) return parent + "." + field;
                return null;
            default:
                return null;
        }
    }

    static function unwrapExpr(e:Expr):Expr {
        if (e == null) return null;
        return switch (e.expr) {
            case EParenthesis(inner): unwrapExpr(inner);
            case ECast(inner, _):     unwrapExpr(inner);
            case EMeta(_, inner):     unwrapExpr(inner);
            default: e;
        };
    }

    static function findStateByName(name:String, states:Array<{name:String, type:ComplexType, initialValue:Expr, pos:Position}>) {
        for (sf in states) if (sf.name == name) return sf;
        return null;
    }

    /** Map the Haxe field type to the StateBridge get/set suffix.
        Handles both bare type names (`TPath({name: "Bool"})` from
        user-written `:Bool`) and module-qualified ones
        (`TPath({name: "StdTypes", sub: "Bool"})` which is what
        `TypeTools.toComplexType` produces for the standard abstracts
        when reflecting through `Context.getType`). */
    static function bridgeSuffix(t:ComplexType):String {
        return switch (t) {
            case TPath(p):
                var key = (p.sub != null && p.sub != "") ? p.sub : p.name;
                switch (key) {
                    case "String": "String";
                    case "Int":    "Int";
                    case "Float":  "Float";
                    case "Bool":   "Bool";
                    default:       "String";
                };
            default: "String";
        };
    }

    static function bridgeGetCall(name:String, t:ComplexType, pos:Position):Expr {
        var nameLit = name;
        return switch (bridgeSuffix(t)) {
            case "Int":   macro wui.state.StateBridge.getInt($v{nameLit});
            case "Float": macro wui.state.StateBridge.getFloat($v{nameLit});
            case "Bool":  macro wui.state.StateBridge.getBool($v{nameLit});
            default:      macro wui.state.StateBridge.getString($v{nameLit});
        };
    }

    static function bridgeSetCall(name:String, t:ComplexType, rhs:Expr, pos:Position):Expr {
        var nameLit = name;
        return switch (bridgeSuffix(t)) {
            case "Int":   macro wui.state.StateBridge.setInt($v{nameLit}, $rhs);
            case "Float": macro wui.state.StateBridge.setFloat($v{nameLit}, $rhs);
            case "Bool":  macro wui.state.StateBridge.setBool($v{nameLit}, $rhs);
            default:      macro wui.state.StateBridge.setString($v{nameLit}, $rhs);
        };
    }
    #end
}

#if macro
/** Internal tag for `categoriseType`. */
private enum TypeCategory {
    Primitive;
    ObservableType;
    ImmutableType;
    Ineligible(reason:String);
}
#end
