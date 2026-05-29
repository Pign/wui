package wui.macros;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
import haxe.macro.ExprTools;

using haxe.macro.Tools;
#end

/**
 * Compile-time macro that transforms @:state fields.
 *
 * Transforms:
 *   @:state var count:Int = 0;
 * Into:
 *   var count:State<Int>;
 * With constructor initialization:
 *   count = new State<Int>(0, "count");
 */
class StateMacro {
    #if macro
    public static function build():Array<Field> {
        var fields = Context.getBuildFields();
        var stateFields:Array<{name:String, type:ComplexType, initialValue:Expr}> = [];

        // Find and transform @:state fields
        var newFields:Array<Field> = [];
        for (field in fields) {
            var hasStateMeta = false;
            if (field.meta != null) {
                for (meta in field.meta) {
                    if (meta.name == ":state" || meta.name == "state") {
                        hasStateMeta = true;
                        break;
                    }
                }
            }

            if (hasStateMeta) {
                switch (field.kind) {
                    case FVar(t, e):
                        var initialValue = e != null ? e : macro null;
                        var fieldName = field.name;

                        // Record for constructor injection
                        stateFields.push({
                            name: fieldName,
                            type: t,
                            initialValue: initialValue
                        });

                        // Transform field type to State<T>
                        var stateType = TPath({
                            pack: ["wui", "state"],
                            name: "State",
                            params: t != null ? [TPType(t)] : []
                        });

                        // Forward the declared default expression to the
                        // C++ codegen by stashing it in a `@:wuiInitial`
                        // meta — collectStateFields reads it back to
                        // initialise `static <type> s_<name> = <value>`
                        // in MainWindow.cpp.
                        var existingMeta = field.meta != null ? field.meta : [];
                        var withInitial = existingMeta.concat([{
                            name: ":wuiInitial",
                            params: [initialValue],
                            pos: field.pos
                        }]);

                        newFields.push({
                            name: field.name,
                            doc: field.doc,
                            access: field.access,
                            pos: field.pos,
                            meta: withInitial,
                            kind: FVar(stateType, null)
                        });

                    default:
                        Context.error("@:state can only be applied to var fields", field.pos);
                }
            } else {
                newFields.push(field);
            }
        }

        // If we found @:state fields, inject initialization into constructor
        if (stateFields.length > 0) {
            var constructorFound = false;

            for (i in 0...newFields.length) {
                var field = newFields[i];
                if (field.name == "new") {
                    constructorFound = true;
                    switch (field.kind) {
                        case FFun(f):
                            // Prepend state initialization to constructor body
                            var initExprs:Array<Expr> = [];
                            for (sf in stateFields) {
                                var nameStr = sf.name;
                                initExprs.push(macro $i{nameStr} = new wui.state.State($e{sf.initialValue}, $v{nameStr}));
                            }

                            // Get existing body expressions
                            var existingExprs:Array<Expr> = [];
                            if (f.expr != null) {
                                switch (f.expr.expr) {
                                    case EBlock(exprs):
                                        existingExprs = exprs;
                                    default:
                                        existingExprs = [f.expr];
                                }
                            }

                            f.expr = macro $b{initExprs.concat(existingExprs)};

                        default:
                    }
                }
            }

            // If no constructor found, create one
            if (!constructorFound) {
                var initExprs:Array<Expr> = [];
                for (sf in stateFields) {
                    var nameStr = sf.name;
                    initExprs.push(macro $i{nameStr} = new wui.state.State($e{sf.initialValue}, $v{nameStr}));
                }
                initExprs.push(macro super());

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

        // Pre-typing rewrite of `state.value` reads/writes inside
        // `effects()` — see rewriteStateValueAccess. Runs after the
        // field list is finalised so we know exactly which idents are
        // @:state.
        if (stateFields.length > 0) {
            for (i in 0...newFields.length) {
                if (newFields[i].name != "effects") continue;
                switch (newFields[i].kind) {
                    case FFun(f):
                        if (f.expr != null) {
                            f.expr = rewriteStateValueAccess(f.expr, stateFields);
                        }
                    default:
                }
            }
        }

        return newFields;
    }

    /**
     * Rewrite `<stateField>.value` reads and writes inside the user's
     * `effects()` body so they reach the C++ side directly via
     * `wui.state.StateBridge.get/setX`. Works at Expr level (pre-typing)
     * to avoid the `Context.typeExpr` re-entrance assertion that fires
     * when the same rewrite runs at `onAfterTyping`.
     *
     * Without this, `searchQuery.value` inside a lifted Effect lambda
     * would return the stale Haxe-side `State<T>._value` — never
     * updated by C++ TextChanged events. The rewrite lets users write
     * natural Haxe:
     *
     *     Effect.run(() -> {
     *       Window.setTitle('Recherche : ${searchQuery.value}');
     *     }, [searchQuery]);
     *
     * and get the latest C++ value automatically.
     *
     * Existing explicit `StateBridge.X(...)` calls are untouched —
     * they're already what the rewrite would produce.
     */
    static function rewriteStateValueAccess(e:Expr, states:Array<{name:String, type:ComplexType, initialValue:Expr}>):Expr {
        if (e == null) return null;

        // <state>.value = rhs  ->  StateBridge.setX("state", rhs)
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
    static function matchStateValueExpr(e:Expr, states:Array<{name:String, type:ComplexType, initialValue:Expr}>):String {
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

    static function findStateByName(name:String, states:Array<{name:String, type:ComplexType, initialValue:Expr}>) {
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
