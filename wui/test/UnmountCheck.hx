import nui.Node;
import nui.NodeSink;
import nui.PropValue;
import nui.Modifier;
import rui.Signal;
import wui.nui.Reconciler;

/**
	That unmounting a subtree stops the bindings made against it. Run with:

	    haxe -cp src -cp test -lib rui -lib nui -main UnmountCheck --interp

	The reconciler is plain Haxe — only `WinUISink` reaches native code — so this
	drives it with a sink that records instead of drawing, and no Windows is
	needed to answer the question.

	The question is worth a test of its own because getting it wrong is silent.
	A property binding is an effect subscribed to signals the application keeps
	for its whole run; when the node goes and the effect does not, a later write
	re-runs it against a handle that has been freed. Nothing reports that at the
	moment it happens.
**/
class UnmountCheck {
	static var failures = 0;

	static function check(label:String, actual:Dynamic, expected:Dynamic) {
		var ok = Std.string(actual) == Std.string(expected);
		if (!ok) failures++;
		trace((ok ? "ok   " : "FAIL ") + label + " = " + actual + (ok ? "" : " (expected " + expected + ")"));
	}

	static function main() {
		var label = new Signal("before");
		var sink = new RecordingSink();
		// Fine granularity: every property owns an effect, and says how to stop it.
		sink.bindReactive = fn -> {
			var e = new Effect(fn);
			return () -> e.dispose();
		};

		var reconciler = new Reconciler(sink);
		var root = sink.create(new Node("Root"), null);

		function tree(withChild:Bool):Node {
			var stack = new Node("VStack");
			if (withChild) {
				var text = new Node("Text");
				text.props.set("text", PReactive(() -> PString(label.value)));
				stack.children.push(text);
			}
			return stack;
		}

		// `reconcile(null, …)` is the mount: there is nothing to compare against.
		var mounted = reconciler.reconcile(null, tree(true), root);
		check("the binding applied once", sink.applied, 1);

		label.value = "after";
		check("and again when its signal changed", sink.applied, 2);

		// Take the child away.
		reconciler.reconcile(mounted, tree(false), root);
		check("the binding was stopped when the node went", sink.stopped, 1);

		// The signal outlives the node — this is the write that used to reach a
		// freed handle.
		label.value = "later";
		check("a later write does not reach the gone node", sink.applied, 2);

		trace(failures == 0 ? "\nall checks passed" : '\n$failures failed');
		#if sys
		Sys.exit(failures == 0 ? 0 : 1);
		#end
	}
}

/** A sink that records instead of drawing, and honours the teardown contract. **/
class RecordingSink implements NodeSink<Int> {
	public var applied = 0;
	public var stopped = 0;

	var next = 1;
	var _bind:(Void->Void)->Null<Void->Void> = function(fn) { fn(); return null; };
	var _bindings:Map<Int, Array<Void->Void>> = new Map();

	public var bindReactive(get, set):(Void->Void)->Null<Void->Void>;

	function get_bindReactive() return _bind;

	function set_bindReactive(v) { _bind = v; return v; }

	public function new() {}

	public function create(node:Node, parent:Null<Int>):Int return next++;

	public function applyProp(target:Int, type:String, key:String, value:PropValue):Void {
		var stop = _bind(function() {
			nui.PropValueTools.resolve(value);
			applied++;
		});
		if (stop != null) {
			var made = _bindings.get(target);
			if (made == null) { made = []; _bindings.set(target, made); }
			made.push(stop);
		}
	}

	public function applyModifiers(target:Int, type:String, modifiers:Array<Modifier>):Void {}

	public function insert(parent:Int, child:Int, index:Int):Void {}

	public function remove(parent:Int, child:Int):Void {}

	public function destroy(target:Int):Void {
		var made = _bindings.get(target);
		if (made != null) {
			_bindings.remove(target);
			for (stop in made) { stop(); stopped++; }
		}
	}
}
