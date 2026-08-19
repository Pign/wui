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

	// ---- list rows: a separate, deliberately short-lived numbering ----
	//
	// Row callbacks are rebuilt every time the list changes, so their ids cannot
	// live in the table above: appending to it on each rebuild would grow it
	// without bound, and renumbering it would break the compile-time agreement
	// that table rests on. Rows get their own range, cleared on every rebuild,
	// and native code reaches them through a different entry point so the two
	// can never be confused for one another.

	static var rowHandlers:Array<Void->Void> = [];

	/** Drop the previous rows' callbacks. Called before each rebuild. **/
	public static function resetRows():Void {
		rowHandlers = [];
	}

	/** Add a row's callback and return the id for this rebuild only. **/
	public static function registerRow(fn:Void->Void):Int {
		rowHandlers.push(fn);
		return rowHandlers.length - 1;
	}

	/** How many row callbacks the current rebuild registered. **/
	public static function rowCount():Int {
		return rowHandlers.length;
	}

	/**
		Run a row's callback.

		A stale id — a click landing after a rebuild replaced the rows — is
		reported and ignored rather than throwing: the window is small but real,
		and killing the app over a late click would be worse than dropping it.
	**/
	public static function invokeRow(id:Int):Void {
		if (id < 0 || id >= rowHandlers.length) {
			trace('[wui] no row callback for id $id (${rowHandlers.length} rows)');
			return;
		}
		rowHandlers[id]();
	}

	// ---- nui nodes: a third range, for the push contract ----
	//
	// Node handlers outlive a rebuild (a node keeps its control) but are not
	// numbered at compile time either, so they belong to neither table above.
	// Three ranges rather than one shared counter: the cost is a few lines, and
	// the alternative is an id from one world reaching a closure from another.
	//
	// Ids are MONOTONIC and the table is never wiped. It used to be reset on
	// every mount, which was fine while exactly one tree ever mounted -- and a
	// day-one bug the moment a second surface exists, because mounting it would
	// wipe the first surface's handlers while its controls still point at the
	// ids. Same policy as the native handle table: a destroyed node's ids
	// become holes (see `clearNode`), permanently, and a click landing in a
	// hole is reported rather than running someone else's closure.

	// Typed as `Dynamic` because a handler is not always nullary. A control that
	// carries a value hands it back -- the text in the field at the moment of the
	// keystroke, the state of the switch at the moment of the tap -- and that
	// value has to reach the closure. One table rather than four keeps a single
	// id space: an id names a (node, property) slot whatever shape its handler
	// has, so the four entry points below can never disagree about who id 3 is.
	static var nodeHandlers:Array<Dynamic> = [];

	/** Add a node property handler and return its id. **/
	public static function registerNode(fn:Dynamic):Int {
		nodeHandlers.push(fn);
		return nodeHandlers.length - 1;
	}

	/** How many node handlers are registered. **/
	public static function nodeCount():Int {
		return nodeHandlers.length;
	}

	/**
		Turn one id into a hole, when its node is destroyed.

		The slot is nulled, never recycled: the control that pointed at this id
		is gone, and the next node gets the next id. A late event against a
		hole -- the small-but-real window every destroy has -- is reported by
		`nodeHandler` instead of poking whatever closure a recycled slot would
		hold.
	**/
	public static function clearNode(id:Int):Void {
		if (id < 0 || id >= nodeHandlers.length) return;
		nodeHandlers[id] = null;
	}

	/**
		Overwrite the handler at `id`.

		Node ids are allocated once per (node, property) and then reused: a
		re-render hands fresh closures, and allocating a new id for each would
		grow this table for as long as the app runs. The control keeps pointing at
		the same id; only what the id means changes.
	**/
	public static function setNode(id:Int, fn:Dynamic):Void {
		if (id < 0 || id >= nodeHandlers.length) {
			trace('[wui] setNode: id $id out of range');
			return;
		}
		nodeHandlers[id] = fn;
	}

	/** Run a node property handler. **/
	public static function invokeNode(id:Int):Void {
		var fn = nodeHandler(id);
		if (fn != null) fn();
	}

	/**
		Run a handler with the value its control just reported.

		Four entry points rather than one taking `Dynamic`: what crosses from C++
		is a C type, and choosing the Haxe one at the boundary is what keeps a
		text field's contents from arriving as a printed number. The control is
		the authority on its own value -- that is the whole reason the contract
		hands it back instead of letting Haxe assume what it wrote is still there.
	**/
	public static function invokeNodeString(id:Int, value:String):Void {
		var fn = nodeHandler(id);
		if (fn != null) fn(value == null ? "" : value);
	}

	public static function invokeNodeFloat(id:Int, value:Float):Void {
		var fn = nodeHandler(id);
		if (fn != null) fn(value);
	}

	public static function invokeNodeInt(id:Int, value:Int):Void {
		var fn = nodeHandler(id);
		if (fn != null) fn(value);
	}

	public static function invokeNodeBool(id:Int, value:Bool):Void {
		var fn = nodeHandler(id);
		if (fn != null) fn(value);
	}

	/** The handler at `id`, or null with a message naming what went wrong. **/
	static function nodeHandler(id:Int):Null<Dynamic> {
		if (id < 0 || id >= nodeHandlers.length) {
			trace('[wui] no node callback for id $id (${nodeHandlers.length} registered)');
			return null;
		}
		if (nodeHandlers[id] == null) {
			// A hole: the node was destroyed and its id retired. A late event
			// in destroy's window lands here; saying so is what makes the
			// window observable at all.
			trace('[wui] node callback $id was cleared with its node; late event dropped');
			return null;
		}
		return nodeHandlers[id];
	}
}
