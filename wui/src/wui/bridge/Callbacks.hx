package wui.bridge;

/**
	The registry that lets native code run a Haxe closure.

	## Why an id and not a pointer

	A Haxe closure held **only** by native code is invisible to the hxcpp GC:
	nothing on the Haxe side references it, so it is collected while C++ still
	holds what looks like a valid handle, and the app dies at the first click.
	Both sibling backends paid for this -- `sui` with its `Callbacks` table and
	`qui` with the same wall -- so `wui` never hands a closure across the bridge.
	What crosses is an **integer**, and the closure stays in an array here, which
	is a GC root like any other.

	## How ids are assigned

	By a depth-first walk of the view tree, counting only the buttons that carry
	a Haxe closure. The generator numbers the same tree the same way at compile
	time, so the id the C++ click handler passes is the id this array holds.

	**That agreement is the fragile part of the design.** It holds because both
	sides walk `children` in order over the same tree -- not because either one
	knows about the other. `test/CallbackOrder.hx` pins it down; if the two ever
	drift, a click runs the wrong closure rather than failing loudly.
**/
@:keep
class Callbacks {
	static var handlers:Array<Void->Void> = [];

	/** Drop every registration. Called before a walk repopulates the table. **/
	public static function reset():Void {
		handlers = [];
	}

	/** Add a closure and return the id native code should use for it. **/
	public static function register(fn:Void->Void):Int {
		handlers.push(fn);
		return handlers.length - 1;
	}

	/** How many closures are registered. Lets a caller check a walk found them. **/
	public static function count():Int {
		return handlers.length;
	}

	/**
		Run the closure registered under `id`.

		Called from C++ on the UI thread. An unknown id is reported rather than
		thrown: a click arriving out of range means the two numberings drifted,
		and a message naming the id is what makes that diagnosable at all.
	**/
	public static function invoke(id:Int):Void {
		if (id < 0 || id >= handlers.length) {
			trace('[wui] no callback for id $id (${handlers.length} registered)');
			return;
		}
		handlers[id]();
	}
}
