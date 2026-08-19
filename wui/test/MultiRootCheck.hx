import nui.Node;
import nui.NodeSink;
import nui.PropValue;
import nui.Modifier;
import rui.Signal;
import wui.nui.Reconciler;
import wui.bridge.Callbacks;

/**
	That two mounted surfaces cannot touch each other. Run with:

	    haxe -cp src -cp test -lib rui -lib nui -lib mui -main MultiRootCheck --interp

	This is the whole point of the P3 partition, pinned before any second
	window exists: each surface owns its sink and reconciler (the record that
	replaced HaxeBridge's four statics), and the one registry they still share
	-- node callbacks -- is monotonic and never wiped, because the old
	reset-on-mount would have taken surface A's handlers down with surface B's
	mount. Getting either wrong is silent until a real second window ships.
**/
class MultiRootCheck {
	static var failures = 0;

	static function check(label:String, actual:Dynamic, expected:Dynamic) {
		var ok = Std.string(actual) == Std.string(expected);
		if (!ok) failures++;
		trace((ok ? "ok   " : "FAIL ") + label + " = " + actual + (ok ? "" : " (expected " + expected + ")"));
	}

	static function main() {
		// ---- two surfaces, each with its own record's worth of machinery ----
		var labelA = new Signal("a-before");
		var labelB = new Signal("b-before");

		var sinkA = new CountingSink();
		var sinkB = new CountingSink();
		for (s in [sinkA, sinkB])
			s.bindReactive = fn -> {
				var e = new Effect(fn);
				return () -> e.dispose();
			};

		var reconcilerA = new Reconciler(sinkA);
		var reconcilerB = new Reconciler(sinkB);
		var rootA = sinkA.create(new Node("Root"), null);
		var rootB = sinkB.create(new Node("Root"), null);

		function tree(sig:Signal<String>, withChild:Bool):Node {
			var stack = new Node("VStack");
			if (withChild) {
				var text = new Node("Text");
				text.props.set("text", PReactive(() -> PString(sig.value)));
				stack.children.push(text);
			}
			return stack;
		}

		var mountedA = reconcilerA.reconcile(null, tree(labelA, true), rootA);
		var mountedB = reconcilerB.reconcile(null, tree(labelB, true), rootB);
		check("A mounted its binding", sinkA.applied, 1);
		check("B mounted its binding", sinkB.applied, 1);

		// A write to A's state reaches A and only A.
		labelA.value = "a-after";
		check("A re-applied on its own signal", sinkA.applied, 2);
		check("B never heard about it", sinkB.applied, 1);

		// Destroying A's child stops A's binding and touches nothing of B's.
		reconcilerA.reconcile(mountedA, tree(labelA, false), rootA);
		check("A's binding stopped with its node", sinkA.stopped, 1);
		check("B's bindings were not stopped", sinkB.stopped, 0);
		check("B's controls were not destroyed", sinkB.destroyed, 0);

		labelB.value = "b-after";
		check("B still lives: its signal still re-applies", sinkB.applied, 2);

		// ---- the shared registry: monotonic, holes on destroy, never wiped ----
		var firedA = 0, firedB = 0;
		var idA = Callbacks.registerNode(function() firedA++);
		var idB = Callbacks.registerNode(function() firedB++);
		check("ids are monotonic, not per-surface", idB, idA + 1);

		var countBefore = Callbacks.nodeCount();
		// Surface A's node dies: its id becomes a hole -- the table never shrinks.
		Callbacks.clearNode(idA);
		check("clearing leaves a hole, not a shorter table", Callbacks.nodeCount(), countBefore);

		Callbacks.invokeNode(idA);
		check("an event on the hole is dropped", firedA, 0);
		Callbacks.invokeNode(idB);
		check("the other surface's handler still fires", firedB, 1);

		trace(failures == 0 ? "\nall checks passed" : '\n$failures failed');
		#if sys
		Sys.exit(failures == 0 ? 0 : 1);
		#end
	}
}

/** A sink that counts instead of drawing, honouring the teardown contract. **/
class CountingSink implements NodeSink<Int> {
	public var applied = 0;
	public var stopped = 0;
	public var destroyed = 0;

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
		destroyed++;
		var made = _bindings.get(target);
		if (made != null) {
			_bindings.remove(target);
			for (stop in made) { stop(); stopped++; }
		}
	}
}
