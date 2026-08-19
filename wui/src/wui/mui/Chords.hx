package wui.mui;

/**
	The portable chord, parsed on the Haxe side of the bridge.

	A `mui.surface.Command.key("ctrl+k")` names the platform's PRIMARY
	modifier — and on Windows that IS Ctrl, so "ctrl" maps literally to
	Control here, where macOS maps the same chord to Command. `alt` is Menu
	(Windows' name for it), `shift` is Shift; modifiers combine. Keys are a
	single letter or digit, or the three named keys every keyboard has
	(`enter`, `escape`/`esc`, `tab`).

	Parsed HERE and not in C++, so the grammar sits where the recording-sink
	test can pin it without a Windows machine. What crosses the bridge is one
	packed int — `(VirtualKeyModifiers << 16) | VirtualKey` — that the
	generated `wui_node_prop_int` unpacks into a `KeyboardAccelerator`. The
	enum values are Windows.System's own: VirtualKey A–Z = 65–90 and 0–9 =
	48–57 (the ASCII uppercase they were designed to match), Enter 13,
	Escape 27, Tab 9; VirtualKeyModifiers Control 1, Menu 2, Shift 4.

	A chord outside the grammar answers null, said once per chord: the menu
	item keeps its label and its click — on a menu bar, discoverability
	survives the unparseable chord, which is better degradation than a key
	table could offer.
**/
class Chords {
	static inline var MOD_CONTROL = 1; // VirtualKeyModifiers.Control
	static inline var MOD_MENU = 2; // VirtualKeyModifiers.Menu (Alt)
	static inline var MOD_SHIFT = 4; // VirtualKeyModifiers.Shift

	/** Packed `(modifiers << 16) | key`, or null for a chord outside the
		grammar. **/
	public static function parse(chord:String):Null<Int> {
		if (chord == null || chord == "") return unknown(chord);
		var parts = chord.toLowerCase().split("+");
		var want = parts.pop();
		if (want == null || want == "") return unknown(chord);

		var mods = 0;
		for (mod in parts) switch (mod) {
			case "ctrl": mods |= MOD_CONTROL;
			case "alt": mods |= MOD_MENU;
			case "shift": mods |= MOD_SHIFT;
			case _: return unknown(chord);
		}

		var key = switch (want) {
			case "enter": 13;
			case "escape" | "esc": 27;
			case "tab": 9;
			case single if (single.length == 1):
				var c = single.charCodeAt(0);
				if (c >= "a".code && c <= "z".code) c - 32 // VirtualKey.A..Z
				else if (c >= "0".code && c <= "9".code) c // VirtualKey.Number0..9
				else -1;
			case _: -1;
		};
		if (key < 0) return unknown(chord);

		return (mods << 16) | key;
	}

	static var warned = new Map<String, Bool>();

	static function unknown(chord:String):Null<Int> {
		var name = chord == null ? "(null)" : chord;
		if (!warned.exists(name)) {
			warned.set(name, true);
			trace('wui: shortcut "' + name + '" is not a chord this backend understands '
				+ '(ctrl+/alt+/shift+ and a letter or digit, or enter/escape/tab); the '
				+ 'menu item keeps its label and its click, without an accelerator');
		}
		return null;
	}
}
