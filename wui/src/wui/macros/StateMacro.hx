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
 *
 * (Nullary enums and `wui.state.Immutable` come in later phases.)
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
 */
class StateMacro {
    #if macro
    public static function build():Array<Field> {
        var fields = Context.getBuildFields();
        var isObservableClass = currentClassExtendsObservable();

        // Categorise @:state fields into primitive vs Observable-typed
        // so we can fork the codegen below.
        var primitiveStates:Array<{name:String, type:ComplexType, initialValue:Expr, pos:Position}> = [];
        var observableStates:Array<{name:String, type:ComplexType, initialValue:Expr, pos:Position}> = [];

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
        if (!isObservableClass && (primitiveStates.length > 0 || observableStates.length > 0)) {
            injectAppConstructor(newFields, primitiveStates, observableStates);
        }

        // Pre-typing rewrite of `state.value` reads/writes inside
        // `effects()` — see rewriteStateValueAccess. Runs after the
        // field list is finalised so we know exactly which idents are
        // @:state.
        var allStateNames = primitiveStates.concat(observableStates);
        if (allStateNames.length > 0) {
            for (i in 0...newFields.length) {
                if (newFields[i].name != "effects") continue;
                switch (newFields[i].kind) {
                    case FFun(f):
                        if (f.expr != null) {
                            f.expr = rewriteStateValueAccess(f.expr, primitiveStates);
                        }
                    default:
                }
            }
        }

        return newFields;
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
        return Ineligible("type must be a primitive (String/Int/Float/Bool) or extend wui.state.Observable.");
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
        calls to the App's `new()` (or create one if absent). Mirrors
        the previous behaviour for primitive @:state plus the new
        Observable handling. */
    static function injectAppConstructor(
        newFields:Array<Field>,
        primitives:Array<{name:String, type:ComplexType, initialValue:Expr, pos:Position}>,
        observables:Array<{name:String, type:ComplexType, initialValue:Expr, pos:Position}>
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

    /** Return the field name if `e` is `<knownStateIdent>.value`. */
    static function matchStateValueExpr(e:Expr, states:Array<{name:String, type:ComplexType, initialValue:Expr, pos:Position}>):String {
        if (e == null) return null;
        switch (e.expr) {
            case EField(receiver, "value"):
                switch (unwrapExpr(receiver).expr) {
                    case EConst(CIdent(ident)):
                        for (sf in states) if (sf.name == ident) return ident;
                    case EField({expr: EConst(CIdent("this"))}, ident):
                        for (sf in states) if (sf.name == ident) return ident;
                    default:
                }
            default:
        }
        return null;
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

    /** Map the Haxe field type to the StateBridge get/set suffix. */
    static function bridgeSuffix(t:ComplexType):String {
        return switch (t) {
            case TPath(p):
                switch (p.name) {
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
    Ineligible(reason:String);
}
#end
