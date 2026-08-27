import nui.Node;
import nui.NodeSink;
import nui.PropValue;
import nui.Modifier;
import rui.Signal;
import wui.nui.Reconciler;
import wui.state.State;
import wui.state.StateAction;

/**
	That one gesture crosses the bridge once. Run with:

	    haxe -cp src -cp test -lib rui -lib nui -lib mui -main BatchCheck --interp

	`wui.bridge.Actions` interprets a `StateAction` at runtime, and `Sequence`
	is several writes in one gesture by construction. On this backend a bound
	property is an effect of its own, so before `Scheduler.batch` a three-step
	sequence applied that property three times — three trips to the UI thread
	for two pictures nobody was ever going to see.

	Countable rather than watchable: `WinUISink` compiles to no-ops without
	`-D wui_winui`, so the reconciler can be driven with a sink that records,
	and the question is answered without Windows. What Windows still answers
	is whether the same code compiles and behaves under MSVC.
**/
class BatchCheck {
	static var failures = 0;

	static function check(label:String, actual:Dynamic, expected:Dynamic) {
		var ok = Std.string(actual) == Std.string(expected);
		if (!ok) failures++;
		trace((ok ? "ok   " : "FAIL ") + label + " = " + actual + (ok ? "" : " (expected " + expected + ")"));
	}

	static function main() {
		var count = new State(0, "count");
		var sink = new RecordingSink();
		// Fine granularity: every property owns an effect, the path this
		// backend validated. It is also what makes the count meaningful --
		// a coarse sink would apply once whatever the scheduler did.
		sink.bindReactive = fn -> {
			var e = new Effect(fn);
			return () -> e.dispose();
		};

		var reconciler = new Reconciler(sink);
		var root = sink.create(new Node("Root"), null);

		var text = new Node("Text");
		text.props.set("text", PReactive(() -> PString("Count: " + count.get())));
		var stack = new Node("VStack");
		stack.children.push(text);
		reconciler.reconcile(null, stack, root);
		check("the binding applied once on mount", sink.applied, 1);

		// One write, outside any gesture: unchanged behaviour.
		count.set(1);
		check("a lone write applies the property", sink.applied, 2);

		// The gesture. Three writes to the same cell, one action.
		var before = sink.applied;
		wui.bridge.Actions.run(Sequence([
			Increment(count, 1),
			Increment(count, 1),
			Increment(count, 1)
		]));
		check("the sequence ran every step", count.get(), 4);
		check("but the property crossed ONCE", sink.applied, before + 1);

		// A sequence of writes to DIFFERENT shapes of action, same gesture.
		before = sink.applied;
		wui.bridge.Actions.run(Sequence([
			SetValue(count, 10),
			Increment(count, 5),
			Decrement(count, 3)
		]));
		check("mixed constructors still run in order", count.get(), 12);
		check("and still cross once", sink.applied, before + 1);

		// A lone action is a gesture too: it opens a scope and closes it.
		before = sink.applied;
		wui.bridge.Actions.run(Increment(count, 1));
		check("a single action still applies", sink.applied, before + 1);
		check("and moved the cell", count.get(), 13);

		trace(failures == 0 ? "\nall checks passed" : '\n$failures failed');
		#if sys
		Sys.exit(failures == 0 ? 0 : 1);
		#end
	}
}

/** A sink that records instead of drawing. Same shape as UnmountCheck's. **/
class RecordingSink implements NodeSink<Int> {
	public var applied = 0;

	var next = 1;
	var _bind:(Void->Void)->Null<Void->Void> = function(fn) { fn(); return null; };

	public var bindReactive(get, set):(Void->Void)->Null<Void->Void>;

	function get_bindReactive() return _bind;

	function set_bindReactive(v) { _bind = v; return v; }

	public function new() {}

	public function create(node:Node, parent:Null<Int>):Int return next++;

	public function applyProp(target:Int, type:String, key:String, value:PropValue):Void {
		_bind(function() {
			nui.PropValueTools.resolve(value);
			applied++;
		});
	}

	public function applyModifiers(target:Int, type:String, modifiers:Array<Modifier>):Void {}

	public function insert(parent:Int, child:Int, index:Int):Void {}

	public function remove(parent:Int, child:Int):Void {}

	public function destroy(target:Int):Void {}
}
