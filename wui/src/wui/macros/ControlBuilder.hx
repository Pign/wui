package wui.macros;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;

using haxe.macro.Tools;
#end

/**
	Turns a control's declared fields into the single source of truth about it.

	## What it replaces

	`wui` used to keep the same knowledge in four hand-maintained places: the
	property names as **strings** inside `wui.ui.*` constructors, the positional
	extraction in `WinUIGenerator` (`args[0]` is the label, `args[2]` the action),
	the `switch` in the generated C++, and `Vocabulary`'s table. Renaming one
	property took four coordinated edits, and forgetting one broke nothing
	visible — the property was simply ignored.

	A declared field says three of those things by itself:

	```haxe
	@:winuiType("Slider")
	class Slider extends View {
		@:winrt("Minimum")       public var min:Float;
		@:winrt("StepFrequency") public var step:Null<Float>;
	}
	```

	The **name** is the field's, the **kind** is its type, and `Null<T>` is what
	"nullable" means in Haxe already, so `required` needs no declaring. What a
	type cannot express is which WinRT call to make — `Minimum` does not follow
	from `min` — so that stays in metadata, next to the property it concerns
	rather than in a switch three files away.

	## What this macro does

	It rewrites each annotated field into a property whose setter writes into
	`View.properties`, so the map the transpiled path reads is filled by
	assigning the field. One declaration, and the two paths cannot disagree
	about a key: there is only one place the string is written, and it is
	generated.

	`Vocabulary` reads the same fields at macro time, and the C++ node runtime is
	emitted from them — so a property the C++ could not apply cannot be declared.
**/
class ControlBuilder {
	#if macro
	public static function build():Array<Field> {
		var fields = Context.getBuildFields();
		var out:Array<Field> = [];

		for (field in fields) {
			var winrt = metaOf(field, ":winrt");
			if (winrt == null) {
				out.push(field);
				continue;
			}

			switch (field.kind) {
				case FVar(t, init):
					var name = field.name;
					var setter = "set_" + name;

					// The initialiser says what an absent property means, and this
					// is where it would be lost: the field becomes a property and
					// the default is deliberately not emitted as an assignment.
					// Stash it as metadata so the vocabulary can still read it.
					var meta = field.meta == null ? [] : field.meta.copy();
					if (init != null) {
						meta.push({name: ":defaultValue", params: [init], pos: field.pos});
					}

					// The declaration becomes a property backed by the map the
					// rest of wui already reads.
					out.push({
						name: name,
						doc: field.doc,
						access: field.access,
						pos: field.pos,
						meta: meta,
						kind: FProp("default", "set", t, null)
					});

					out.push({
						name: setter,
						access: [APrivate],
						pos: field.pos,
						kind: FFun({
							args: [{name: "v", type: t}],
							ret: t,
							expr: macro {
								properties.set($v{name}, v);
								return v;
							}
						})
					});

				default:
					// One shape per concept: a property is a var, a modifier is a
					// fluent method. Allowing both here meant the vocabulary had to
					// read declarations two ways.
					Context.error("@:winrt déclare une propriété : il s'applique à une var, pas à une méthode", field.pos);
					out.push(field);
			}
		}

		return out;
	}

	static function metaOf(field:Field, name:String):Null<MetadataEntry> {
		if (field.meta == null) return null;
		for (m in field.meta) if (m.name == name) return m;
		return null;
	}
	#end
}
