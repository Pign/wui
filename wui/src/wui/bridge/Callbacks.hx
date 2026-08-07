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

	static var nodeHandlers:Array<Void->Void> = [];

	/** Add a node property handler and return its id. **/
	public static function registerNode(fn:Void->Void):Int {
		nodeHandlers.push(fn);
		return nodeHandlers.length - 1;
	}

	/** How many node handlers are registered. **/
	public static function nodeCount():Int {
		return nodeHandlers.length;
	}

	/** Drop them all. Called when a tree is mounted from scratch. **/
	public static function resetNodes():Void {
		nodeHandlers = [];
	}

	/**
		Overwrite the handler at `id`.

		Node ids are allocated once per (node, property) and then reused: a
		re-render hands fresh closures, and allocating a new id for each would
		grow this table for as long as the app runs. The control keeps pointing at
		the same id; only what the id means changes.
	**/
	public static function setNode(id:Int, fn:Void->Void):Void {
		if (id < 0 || id >= nodeHandlers.length) {
			trace('[wui] setNode: id $id out of range');
			return;
		}
		nodeHandlers[id] = fn;
	}

	/** Run a node property handler. **/
	public static function invokeNode(id:Int):Void {
		if (id < 0 || id >= nodeHandlers.length) {
			trace('[wui] no node callback for id $id (${nodeHandlers.length} registered)');
			return;
		}
		nodeHandlers[id]();
	}
}
