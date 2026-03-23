package wui.macros;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;

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

                        newFields.push({
                            name: field.name,
                            doc: field.doc,
                            access: field.access,
                            pos: field.pos,
                            meta: field.meta,
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

        return newFields;
    }
    #end
}
