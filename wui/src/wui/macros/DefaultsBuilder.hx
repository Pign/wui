package wui.macros;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import wui.nui.Vocabulary;
#end

/**
	Builds the runtime half: what an absent property becomes.

	The reconciler needs this **at runtime**, so unlike `Vocabulary` — which
	answers macro-time questions by reading the controls on demand — this has to
	be a real table in the binary. Hence `@:build`, and hence a type nothing
	macro-side ever touches: Haxe forbids a `@:build` type from being used inside
	a macro, which is exactly what sank the first attempt at generating the whole
	vocabulary.

	Two views, one source. Both read the same `@:winrt` declarations; only the
	moment they are needed differs.
**/
class DefaultsBuilder {
	#if macro
	public static function build():Array<Field> {
		var fields = Context.getBuildFields();
		var entries:Array<Expr> = [];

		for (type in Vocabulary.types()) {
			var cls = classFor(type);
			if (cls == null) continue;

			var perType:Array<Expr> = [];
			Vocabulary.eachProp(cls, function(field, kind) {
				var meta = field.meta.extract(":defaultValue");
				if (meta.length == 0 || meta[0].params.length == 0) return;

				var value = meta[0].params[0];
				var wrapped = switch (kind) {
					case "KString": macro nui.PropValue.PString($value);
					case "KInt": macro nui.PropValue.PInt($value);
					case "KFloat": macro nui.PropValue.PFloat($value);
					case "KBool": macro nui.PropValue.PBool($value);
					case _: null;
				};
				if (wrapped != null) perType.push(macro $v{field.name} => $wrapped);
			});

			if (perType.length > 0) entries.push(macro $v{type} => [$a{perType}]);
		}

		fields.push({
			name: "byType",
			doc: "What an absent property becomes, per node type. Derived from the controls.",
			access: [APublic, AStatic, AFinal],
			pos: Context.currentPos(),
			kind: FVar(macro :Map<String, Map<String, nui.PropValue>>,
				entries.length == 0 ? macro new Map() : macro [$a{entries}])
		});

		return fields;
	}

	static function classFor(type:String):Null<haxe.macro.Type.ClassType> {
		for (path in Context.getClassPath()) {
			var dir = haxe.io.Path.join([path, "wui/ui"]);
			if (!sys.FileSystem.exists(dir)) continue;

			for (entry in sys.FileSystem.readDirectory(dir)) {
				if (!StringTools.endsWith(entry, ".hx")) continue;
				var name = entry.substr(0, entry.length - 3);
				try {
					switch (Context.getType("wui.ui." + name)) {
						case TInst(ref, _):
							var cls = ref.get();
							if (Vocabulary.nodeNameOf(cls) == type) return cls;
						case _:
					}
				} catch (e:Dynamic) {}
			}
			return null;
		}
		return null;
	}
	#end
}
