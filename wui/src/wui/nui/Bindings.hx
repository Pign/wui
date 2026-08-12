package wui.nui;

/**
	What a control's *value* is called, and how it reports a change.

	## Why this is a table and not a convention

	A two-way control has one property that is its value, and one event that
	reports a new one. Neither is guessable: a switch calls it `isOn`, a field
	calls it `text`, a slider calls it `value`, and WinUI names their events
	after three unrelated things. A layer describing a view tree has to be told.

	## Why it lives in wui

	Because the names are WinRT's. `mui` describes a tree of views and should not
	have to know that a `ToggleSwitch` reports through `Toggled` — it asks here,
	and the answer stays next to the generator that emits the matching C++. Put
	the table in the describing layer instead and there would be two copies of
	one fact, free to drift in the direction that hurts: a control gaining an
	event nobody wired.

	## What a missing entry means

	`null`, and the caller says so. A control carrying a binding that nothing can
	deliver is a defect worth a message — silently dropping it is how a switch
	ends up showing `Off` while the cell it is bound to says `true`, which is
	precisely the bug this table was written to end.
**/
class Bindings {
	/** The property that holds this control's value, or null if it has none. **/
	public static function valueKey(type:String):Null<String> {
		return switch (type) {
			case "ToggleSwitch": "isOn";
			case "TextBox": "text";
			case "Slider": "value";
			case _: null;
		};
	}

	/**
		The property under which this control's change handler is carried.

		These are the keys `wui_node_prop_callback` switches on, so a name added
		here without a branch there is a handler that never fires.
	**/
	public static function changeKey(type:String):Null<String> {
		return switch (type) {
			case "ToggleSwitch": "onToggle";
			case "TextBox": "onText";
			case "Slider": "onValue";
			case _: null;
		};
	}
}
