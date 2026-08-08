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
#if macro
/** One `.prop()` application, as the chain walk recovered it. **/
private typedef ChainKey = {
	name:String,
	pos:haxe.macro.Expr.Position,
	ctor:Null<String>,
	valuePos:haxe.macro.Expr.Position
};
#end

class NodeValidator {
	#if macro
	/** Positions of calls and `new`s already claimed by a chain: each chain is
		judged once, at its outermost call. **/
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
			// missing required property can be judged. The walk descends into
			// the receiver afterwards, so every inner call of the chain is seen
			// again — `markChain` records their positions so each chain is
			// judged exactly once, at its outermost call, never as the partial
			// chain an inner call would resolve to.
			case TCall(func, args):
				if (!chainRoots.exists(posKey(e.pos))) {
					markChain(e);
					var chain = resolveChain(e);
					if (chain != null) checkChain(chain, e);
				}
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

					// A bare `new Node("X")` is a chain with no keys: a required
					// property missing here used to escape unjudged, because
					// only TCall ever reached checkChain.
					if (type != null && Vocabulary.knows(type) && !chainRoots.exists(posKey(e.pos))) {
						checkChain({type: type, keys: []}, e);
					}
				}
			default:
		}

		e.iter(walk);
	}

	/** A stable identity for one occurrence of an expression. **/
	static function posKey(pos:haxe.macro.Expr.Position):String {
		var i = Context.getPosInfos(pos);
		return i.file + ":" + i.min + ":" + i.max;
	}

	/**
		Record every call and the `new` of a chain, so the walk's descent does
		not judge them again as partial chains. Marked unconditionally — even a
		chain `resolveChain` refuses (dynamic key, unknown type) must not have
		its inner calls judged, because a partial verdict is a guess.
	**/
	static function markChain(e:TypedExpr):Void {
		var cursor = e;
		while (cursor != null) {
			switch (cursor.expr) {
				case TCall(func, _):
					var name = fieldName(func);
					if (name != "prop" && name != "child" && name != "modifier") return;
					chainRoots.set(posKey(cursor.pos), true);
					cursor = objectOf(func);
				case TNew(_, _, _):
					chainRoots.set(posKey(cursor.pos), true);
					return;
				case TParenthesis(inner) | TMeta(_, inner) | TCast(inner, _):
					cursor = inner;
				default:
					return;
			}
		}
	}

	/** A resolved `new Node("X")` with the keys applied to it. **/
	static function resolveChain(e:TypedExpr):Null<{type:String, keys:Array<ChainKey>}> {
		var keys:Array<ChainKey> = [];
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
						keys.push({
							name: key,
							pos: args[0].pos,
							ctor: args.length > 1 ? ctorName(args[1]) : null,
							valuePos: args.length > 1 ? args[1].pos : args[0].pos
						});
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

	static function checkChain(chain:{type:String, keys:Array<ChainKey>}, e:TypedExpr):Void {
		var allowed = Vocabulary.keysOf(chain.type);
		var seen = new Map<String, Bool>();

		for (k in chain.keys) {
			seen.set(k.name, true);
			if (allowed.indexOf(k.name) < 0) {
				Context.error('"${chain.type}" n\'a pas de propriete "${k.name}".\n'
					+ '  Proprietes acceptees : ${allowed.join(", ")}.',
					k.pos);
			}

			// The value's constructor is visible in the typed AST, and the
			// declaration says which one the property takes. A mismatch used to
			// pass here and route, at runtime, to a setter with no branch for
			// the key -- doing nothing, silently. `PReactive` can hold anything,
			// so it is left to the runtime; so is a value that is not a literal
			// constructor call.
			var expected = Vocabulary.kindOf(chain.type, k.name);
			if (expected != null && k.ctor != null && k.ctor != "PReactive"
				&& !ctorMatchesKind(k.ctor, expected)) {
				Context.error('"${chain.type}" : la propriete "${k.name}" attend '
					+ '${ctorForKind(expected)}, pas ${k.ctor}.',
					k.valuePos);
			}
		}

		for (req in Vocabulary.requiredOf(chain.type)) {
			if (!seen.exists(req)) {
				Context.error('"${chain.type}" exige la propriete "$req", absente ici.', e.pos);
			}
		}
	}

	static function ctorMatchesKind(ctor:String, kind:String):Bool {
		return switch (kind) {
			case "KString": ctor == "PString";
			case "KInt": ctor == "PInt";
			case "KFloat": ctor == "PFloat";
			case "KBool": ctor == "PBool";
			case "KCallback": ctor == "PCallback" || ctor == "PCallbackString"
				|| ctor == "PCallbackFloat" || ctor == "PCallbackInt";
			case _: true;
		};
	}

	static function ctorForKind(kind:String):String {
		return switch (kind) {
			case "KString": "PString";
			case "KInt": "PInt";
			case "KFloat": "PFloat";
			case "KBool": "PBool";
			case "KCallback": "PCallback (ou PCallbackString/Float/Int)";
			case _: kind;
		};
	}

	/** The `PropValue` constructor a value was written with, if it is one. **/
	static function ctorName(e:TypedExpr):Null<String> {
		if (e == null) return null;
		return switch (e.expr) {
			case TCall({expr: TField(_, FEnum(_, ef))}, _): ef.name;
			case TParenthesis(inner) | TMeta(_, inner) | TCast(inner, _): ctorName(inner);
			case _: null;
		};
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
		return Vocabulary.types();
	}
	#end
}
