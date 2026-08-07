package wui.macros;

#if macro
import haxe.macro.Context;
import haxe.macro.Type;
import wui.nui.Vocabulary;

using haxe.macro.Tools;
#end

/**
	Refuses to compile a node this backend cannot render.

	## What it is for

	`?TypeName` on screen used to answer two unrelated situations. One is
	legitimate — a tree that arrived as **data**, which nothing can check ahead
	of time. The other is a mistake in the source, turned into a visual artefact
	that gets found late or never.

	This checks the second. A node whose type is a **string literal** is written
	here, compiled for a known backend, and can be judged now:

	- an unknown type is an error;
	- a property the type does not accept is an error (a `"txt"` for `"text"`
	  currently does *nothing at all*, silently);
	- a required property that is missing is an error.

	`wui.nui.Foreign.node(type)` is the way out, and it is not a flag that turns
	checking off: it takes the type as a parameter, so it is dynamic by
	construction and nothing static could have been said about it anyway. The
	escape hatch is exactly the boundary of what this can see.

	## What it cannot see

	A type or key that is not a literal — `new Node(fromNetwork)` — is left to
	the runtime, where `?TypeName` still applies. That boundary is the same line
	as the one between an authored tree and a received one, which is why the two
	answers do not overlap any more.
**/
class NodeValidator {
	#if macro
	/** Positions already handled as part of a `.prop()` chain. **/
	static var chainRoots:Map<String, Bool> = new Map();

	public static function check(types:Array<ModuleType>):Void {
		chainRoots = new Map();

		for (mt in types) {
			switch (mt) {
				case TClassDecl(ref):
					var cls = ref.get();
					// The library's own code builds nodes generically; checking it
					// would flag its parameters, not its mistakes.
					if (cls.pack.length > 0 && cls.pack[0] == "wui") continue;

					for (field in cls.fields.get()) walkField(field);
					for (field in cls.statics.get()) walkField(field);
				default:
			}
		}
	}

	static function walkField(field:ClassField):Void {
		var e = field.expr();
		if (e != null) walk(e);
	}

	static function walk(e:TypedExpr):Void {
		if (e == null) return;

		switch (e.expr) {
			// The outermost end of a `new Node("X").prop(...).prop(...)` chain:
			// this is where the whole set of keys is known, so this is where a
			// missing required property can be judged.
			case TCall(func, args):
				var chain = resolveChain(e);
				if (chain != null) checkChain(chain, e);
			default:
		}

		// An unknown type is judged wherever it appears, chain or not.
		switch (e.expr) {
			case TNew(ref, _, args):
				var c = ref.get();
				if (c.name == "Node" && c.pack.join(".") == "nui" && args.length > 0) {
					var type = literalString(args[0]);
					if (type != null && !Vocabulary.knows(type)) {
						Context.error('wui ne sait pas construire un noeud "$type".\n'
							+ '  Types connus : ${sortedTypes().join(", ")}.\n'
							+ '  Si le type vient de l\'exterieur, utilisez wui.nui.Foreign.node("$type").',
							args[0].pos);
					}
				}
			default:
		}

		e.iter(walk);
	}

	/** A resolved `new Node("X")` with the keys applied to it. **/
	static function resolveChain(e:TypedExpr):Null<{type:String, keys:Array<{name:String, pos:haxe.macro.Expr.Position}>}> {
		var keys:Array<{name:String, pos:haxe.macro.Expr.Position}> = [];
		var cursor = e;

		while (true) {
			switch (cursor.expr) {
				case TCall(func, args):
					var name = fieldName(func);
					if (name == "prop" && args.length > 0) {
						var key = literalString(args[0]);
						// A dynamic key stops the chain being judgeable: some of
						// its keys are unknown, so a missing-required verdict
						// would be a guess.
						if (key == null) return null;
						keys.push({name: key, pos: args[0].pos});
						cursor = objectOf(func);
					} else if (name == "child" || name == "modifier") {
						cursor = objectOf(func);
					} else {
						return null;
					}
					if (cursor == null) return null;

				case TNew(ref, _, args):
					var c = ref.get();
					if (c.name != "Node" || c.pack.join(".") != "nui") return null;
					if (args.length == 0) return null;
					var type = literalString(args[0]);
					if (type == null || !Vocabulary.knows(type)) return null;
					keys.reverse();
					return {type: type, keys: keys};

				case TParenthesis(inner) | TMeta(_, inner) | TCast(inner, _):
					cursor = inner;

				default:
					return null;
			}
		}
	}

	static function checkChain(chain:{type:String, keys:Array<{name:String, pos:haxe.macro.Expr.Position}>}, e:TypedExpr):Void {
		var allowed = Vocabulary.keysOf(chain.type);
		var seen = new Map<String, Bool>();

		for (k in chain.keys) {
			seen.set(k.name, true);
			if (allowed.indexOf(k.name) < 0) {
				Context.error('"${chain.type}" n\'a pas de propriete "${k.name}".\n'
					+ '  Proprietes acceptees : ${allowed.join(", ")}.',
					k.pos);
			}
		}

		for (req in Vocabulary.requiredOf(chain.type)) {
			if (!seen.exists(req)) {
				Context.error('"${chain.type}" exige la propriete "$req", absente ici.', e.pos);
			}
		}
	}

	static function fieldName(e:TypedExpr):Null<String> {
		return switch (e.expr) {
			case TField(_, fa): switch (fa) {
					case FInstance(_, _, cf): cf.get().name;
					case FDynamic(s): s;
					case FClosure(_, cf): cf.get().name;
					case _: null;
				}
			case _: null;
		};
	}

	static function objectOf(e:TypedExpr):Null<TypedExpr> {
		return switch (e.expr) {
			case TField(obj, _): obj;
			case _: null;
		};
	}

	static function literalString(e:TypedExpr):Null<String> {
		if (e == null) return null;
		return switch (e.expr) {
			case TConst(TString(s)): s;
			case TParenthesis(inner) | TMeta(_, inner) | TCast(inner, _): literalString(inner);
			case _: null;
		};
	}

	static function sortedTypes():Array<String> {
		var out = [for (t in Vocabulary.types.keys()) t];
		out.sort(function(a, b) return a < b ? -1 : (a > b ? 1 : 0));
		return out;
	}
	#end
}
