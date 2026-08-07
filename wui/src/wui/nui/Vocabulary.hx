package wui.nui;

#if macro
import haxe.macro.Context;
import haxe.macro.Type;

using haxe.macro.Tools;
#end

/**
	What `wui` can render, read from the controls themselves.

	Everything is derived, including the properties every element has: `View`
	declares `width`, `height`, `visible` and `enabled` as vars, so the
	hand-written `UNIVERSAL` table that used to sit here is gone.

	## Two readers, one source

	The knowledge has two audiences, and trying to serve both with one generated
	table failed outright: **Haxe forbids a type carrying `@:build` from being
	used inside a macro**, and this is consumed at macro time by
	`wui.macros.NodeValidator` and by `mui.macros.Backend`.

	So there is no table. This reads the `wui.ui.*` classes **on demand**, at
	macro time, which is the only moment its callers need an answer. The other
	audience — the reconciler, at runtime, wanting to know what an absent
	property becomes — is served by `wui.nui.Defaults`, a small generated map.

	Two views, one place they are derived from: a class carrying `@:winuiType` is
	a node type — named after itself — and its `@:winrt` vars are its properties, and their Haxe declarations give the name,
	the kind, the nullability and the default.

	## Why it is not in `nui`

	Nobody writes against a common core: `mui` picks its target at compile time,
	so the vocabulary that matters while authoring is the *target backend's*, and
	the useful error is "`placeholder` does not exist **here**". A core would also
	become the union of five widget sets — `wui` has `ProgressRing`, `cui` has
	`Table` — turning `nui` from *what a node is* into *which nodes exist*.

	What must stay common is the **naming**, which `nui` settled in B2. A
	discipline, not a vocabulary.

	## Why "vocabulary" and not "schema"

	A schema is a document you declare. `qui`'s node types *are* existing Haxe
	classes, so its vocabulary is read from them; `wui`'s are strings the C++
	knows how to build. Nothing is shared between those artefacts — only the
	question `mui` asks. The name says what is described and stays silent on how
	it is obtained.
**/
class Vocabulary {
	#if macro
	static inline var CONTROLS = "wui/ui";

	static var cache:Map<String, Map<String, String>> = null;

	/** Does `wui` know how to build this node type? **/
	public static function knows(type:String):Bool {
		return all().exists(type);
	}

	/** Every property this type accepts. **/
	public static function keysOf(type:String):Array<String> {
		var own = all().get(type);
		return own == null ? [] : [for (k in own.keys()) k];
	}

	/** Properties this type requires: not nullable, and with no declared default. **/
	public static function requiredOf(type:String):Array<String> {
		var out = [];
		var cls = classOf(type);
		if (cls == null) return out;

		eachProp(cls, function(field, kind) {
			if (!isNullable(field.type) && !field.meta.has(":defaultValue")) out.push(field.name);
		});
		return out;
	}

	/** Which `PropValue` constructor a property takes, by name. `null` if unknown. **/
	public static function kindOf(type:String, key:String):Null<String> {
		var own = all().get(type);
		return (own != null && own.exists(key)) ? own.get(key) : null;
	}

	/**
		The WinRT member a property maps to — the one thing a Haxe type cannot
		say, and therefore the only thing still written by hand.
	**/
	public static function winrtOf(type:String, key:String):Null<String> {
		var cls = classOf(type);
		if (cls == null) return null;

		var found:String = null;
		eachProp(cls, function(field, kind) {
			if (field.name != key) return;
			var meta = field.meta.extract(":winrt");
			if (meta.length > 0 && meta[0].params.length > 0) {
				switch (meta[0].params[0].expr) {
					case EConst(CString(v, _)): found = v;
					case _:
				}
			}
		});
		return found;
	}

	/**
		The same lookup, on `View` itself.

		The two rendering paths name their types differently — the transpiled one
		uses WinUI's (`TextBlock`, `StackPanel`), the node one uses nui's (`Text`,
		`VStack`) — so a lookup keyed by node type misses when the caller holds a
		transpiled name. The properties every element has are declared on `View`,
		which both paths share, so asking it directly answers either way.
	**/
	public static function viewProp(key:String):Null<{winrt:String, kind:String}> {
		var cls = resolveClass("wui.View");
		if (cls == null) return null;

		var found:{winrt:String, kind:String} = null;
		eachProp(cls, function(field, kind) {
			if (field.name != key || found != null) return;
			var meta = field.meta.extract(":winrt");
			if (meta.length > 0 && meta[0].params.length > 0) {
				switch (meta[0].params[0].expr) {
					case EConst(CString(v, _)): found = {winrt: v, kind: kind};
					case _:
				}
			}
		});
		return found;
	}

	/** Every known type, sorted, for an error message that helps. **/
	public static function types():Array<String> {
		var out = [for (t in all().keys()) t];
		out.sort(function(a, b) return a < b ? -1 : (a > b ? 1 : 0));
		return out;
	}

	// ---- reading the controls ----

	static function all():Map<String, Map<String, String>> {
		if (cache != null) return cache;
		cache = new Map();

		for (module in modules()) {
			var cls = resolveClass("wui.ui." + module);
			if (cls == null) continue;

			var type = nodeNameOf(cls);
			if (type == null) continue;

			var props = new Map<String, String>();
			eachProp(cls, function(field, kind) props.set(field.name, kind));
			cache.set(type, props);

			// Answer to the transpiled name as well: same control, same
			// properties, two vocabularies naming it.
			var winui = winuiNameOf(cls);
			if (winui != null && !cache.exists(winui)) cache.set(winui, props);
		}
		return cache;
	}

	static function modules():Array<String> {
		for (path in Context.getClassPath()) {
			var dir = haxe.io.Path.join([path, CONTROLS]);
			if (!sys.FileSystem.exists(dir)) continue;

			var out = [];
			for (entry in sys.FileSystem.readDirectory(dir)) {
				if (StringTools.endsWith(entry, ".hx")) out.push(entry.substr(0, entry.length - 3));
			}
			return out;
		}
		return [];
	}

	static function classOf(type:String):Null<ClassType> {
		for (module in modules()) {
			var cls = resolveClass("wui.ui." + module);
			if (cls == null) continue;
			if (nodeNameOf(cls) == type || winuiNameOf(cls) == type) return cls;
		}
		return null;
	}

	static function resolveClass(path:String):Null<ClassType> {
		try {
			return switch (Context.getType(path)) {
				case TInst(ref, _): ref.get();
				case _: null;
			};
		} catch (e:Dynamic) {
			return null;
		}
	}

	/**
		The name the transpiled path uses, when it differs.

		A control has two identities: its class name is nui's, and the generator
		holds WinUI's — `Text` against `TextBlock`. Nothing could bridge them,
		because the transpiled name is a `super()` argument no macro can read, so
		a lookup by type simply missed and a fallback on `View` hid it for the
		shared properties. A type-specific one would have been dropped in silence.
	**/
	public static function winuiNameOf(cls:ClassType):Null<String> {
		var meta = cls.meta.extract(":winuiType");
		if (meta.length == 0 || meta[0].params.length == 0) return null;
		return switch (meta[0].params[0].expr) {
			case EConst(CString(s, _)): s;
			case _: null;
		};
	}

	/**
		The nui type a control is — its class name.

		There used to be a `@:node("Text")` on a class called `Text`: the same
		word twice, once as a string that could drift from the other. A control
		is a node type because it maps to a real control, which `@:winuiType`
		already says; what it is called needs no restating.
	**/
	public static function nodeNameOf(cls:ClassType):Null<String> {
		return winuiNameOf(cls) == null ? null : cls.name;
	}

	/** Walk the `@:winrt` properties of a class and its ancestors, once each. **/
	public static function eachProp(cls:ClassType, fn:(ClassField, String) -> Void):Void {
		var seen = new Map<String, Bool>();
		var current = cls;

		while (current != null) {
			for (field in current.fields.get()) {
				if (!field.meta.has(":winrt") || seen.exists(field.name)) continue;
				seen.set(field.name, true);

				var kind = kindOfType(field.type);
				if (kind != null) fn(field, kind);
			}
			current = current.superClass == null ? null : current.superClass.t.get();
		}
	}

	public static function isNullable(t:Type):Bool {
		return switch (t) {
			case TAbstract(ref, _) if (ref.get().name == "Null"): true;
			case _: false;
		};
	}

	public static function kindOfType(t:Type):Null<String> {
		return switch (t.follow()) {
			case TAbstract(ref, _):
				switch (ref.get().name) {
					case "Int": "KInt";
					case "Float": "KFloat";
					case "Bool": "KBool";
					case _: null;
				}
			case TInst(ref, _): ref.get().name == "String" ? "KString" : null;
			case TFun(_, _): "KCallback";
			case _: null;
		};
	}
	#end
}
