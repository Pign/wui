package wui.bridge;

import wui.state.StateAction;

/**
	Runs a `StateAction` in Haxe, at runtime.

	## Why this replaces a translator

	The generator used to turn each `StateAction` into a line of C++
	(`s_count += 1; notify_count();`). That worked for four of the nine
	constructors — `Increment`, `Decrement`, `SetValue`, `Toggle` — and silently
	dropped the rest, `Custom` included, which is the one that existed precisely
	to carry arbitrary code. A button whose action it could not translate simply
	lost its handler.

	Interpreting the enum here removes that ceiling rather than raising it: the
	value arrives as an ordinary Haxe enum holding real `State` references, so
	`Sequence` is a loop and `Custom` is a call. Nothing has to be re-implemented
	in the generator, and nothing new is needed for the constructors it never
	supported.

	The write goes through `State.set`, so it takes the same road as any other
	Haxe write — platform sink, bridge, generated handler, UI thread. **There is
	one path now**, which is the whole point of W4: before it, a `+` button and a
	Haxe closure each held their own idea of `count`.
**/
@:keep
class Actions {
	/** Run one action. Unknown shapes report rather than fail quietly. **/
	public static function run(action:StateAction):Void {
		if (action == null) return;

		switch (action) {
			case Increment(state, amount):
				var st:Dynamic = state;
				st.set(sameKind(st.peek(), num(st.peek()) + num(amount)));

			case Decrement(state, amount):
				var st:Dynamic = state;
				st.set(sameKind(st.peek(), num(st.peek()) - num(amount)));

			case SetValue(state, value):
				var st:Dynamic = state;
				st.set(value);

			case Toggle(state):
				var st:Dynamic = state;
				st.set(st.peek() != true);

			case Append(state, value):
				var st:Dynamic = state;
				var arr:Array<Dynamic> = st.peek();
				if (arr == null) {
					trace("[wui] Append on a state that holds no array");
					return;
				}
				// A new array, not a push: `rui.state.State.set` compares against
				// the held value, and mutating it in place would make the write
				// look like a no-op and notify nobody.
				st.set(arr.concat([value]));

			case Remove(state, value):
				var st:Dynamic = state;
				var arr:Array<Dynamic> = st.peek();
				if (arr == null) {
					trace("[wui] Remove on a state that holds no array");
					return;
				}
				st.set(arr.filter(function(x) return x != value));

			case Custom(callback):
				if (callback != null) callback();

			case Sequence(actions):
				if (actions != null) for (a in actions) run(a);

			case Animated(inner, _):
				// The curve is a WinUI concern and does not reach here yet; running
				// the action unanimated beats dropping it, which is what the
				// translator did.
				run(inner);
		}
	}

	/**
		Give an arithmetic result the same kind as the value it replaces.

		Arithmetic here runs in `Float` because the enum carries its operands
		untyped. Writing that straight back into a `State<Int>` would put a
		`Float` where the bridge expects an `Int`, and the cast on the way to
		C++ is where it would surface — far from the cause.
	**/
	static function sameKind(previous:Dynamic, result:Float):Dynamic {
		if (Std.isOfType(previous, Int)) return Std.int(result);
		return result;
	}

	/** Read a number out of a `Dynamic` the enum carries untyped. **/
	static function num(v:Dynamic):Float {
		if (v == null) return 0;
		if (Std.isOfType(v, Float) || Std.isOfType(v, Int)) return v;
		var parsed = Std.parseFloat(Std.string(v));
		return Math.isNaN(parsed) ? 0 : parsed;
	}
}
