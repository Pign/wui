package wui.nui;

import nui.PropValue;

/**
	What an absent property becomes — the runtime half of the vocabulary.

	**This is why the push contract needs no `clearProp`.** "Erase this property"
	is not well defined — erase a colour to *what*? — but "apply this value" is,
	and the value is the one the control declared as its default. Six operations,
	not seven.

	A property with no declared default is **left alone**: keeping the old value
	is wrong, but inventing one is wrong in a way that is harder to notice.

	Derived, not written: `DefaultsBuilder` reads the same `@:winrt` declarations
	`Vocabulary` reads, so the two views cannot disagree.
**/
@:build(wui.macros.DefaultsBuilder.build())
class Defaults {
	/** What to apply when `key` disappears from a node of `type`. **/
	public static function whenAbsent(type:String, key:String):Null<PropValue> {
		var own = byType.get(type);
		return own == null ? null : own.get(key);
	}
}
