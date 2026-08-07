import nui.Modifier;
import nui.Node;
import nui.NodeSink;
import nui.PropValue;
import wui.nui.Reconciler;

/**
	Checks the reconciler by recording what it asks the sink to do.

	The interesting assertions are **negative**: after a re-render that changed
	one label, there must be no `create`, no `destroy`, and exactly one
	`applyProp`. A reconciler that quietly rebuilt everything would still put the
	right pixels on screen and would still pass any test that only looked at the
	result — while destroying focus, caret and scroll on every keystroke.

	    haxe test.hxml && ./build/test/ReconcileCheck
**/
class RecordingSink implements NodeSink<Int> {
	public var ops:Array<String> = [];
	var next = 1;

	var _bind:(Void->Void)->Void = function(fn) fn();
	public var bindReactive(get, set):(Void->Void)->Void;
	function get_bindReactive() return _bind;
	function set_bindReactive(v) { _bind = v; return v; }

	public function new() {}

	public function create(node:Node, parent:Null<Int>):Int {
		var h = next++;
		ops.push('create ${node.type} -> $h');
		return h;
	}

	public function applyProp(target:Int, type:String, key:String, value:PropValue):Void {
		_bind(function() {
			ops.push('prop $target $key=${PropValueTools.asString(value, PropValueTools.asInt(value, -1) + "")}');
		});
	}

	public function applyModifiers(target:Int, type:String, modifiers:Array<Modifier>):Void {
		ops.push('mods $target x${modifiers == null ? 0 : modifiers.length}');
	}

	public function insert(parent:Int, child:Int, index:Int):Void ops.push('insert $child into $parent at $index');
	public function remove(parent:Int, child:Int):Void ops.push('remove $child from $parent');
	public function destroy(target:Int):Void ops.push('destroy $target');
}

class ReconcileCheck {
	static var failures = 0;

	static function check(what:String, ok:Bool, detail:String = ""):Void {
		if (ok) Sys.println('  ok   $what');
		else { failures++; Sys.println('  FAIL $what${detail == "" ? "" : "  -- " + detail}'); }
	}

	static function count(ops:Array<String>, prefix:String):Int {
		var n = 0;
		for (o in ops) if (StringTools.startsWith(o, prefix)) n++;
		return n;
	}

	/** A list of rows, each keyed by its own name. **/
	static function tree(labels:Array<String>, title:String):Node {
		var root = new Node("VStack");
		root.child(new Node("Text", "title").prop("text", PString(title)));
		for (l in labels) {
			root.child(new Node("Button", l).prop("text", PString(l)));
		}
		return root;
	}

	static function main() {
		Sys.println("ReconcileCheck");

		var sink = new RecordingSink();
		var r = new Reconciler(sink);

		// --- first render: everything is built ---
		var mounted = r.reconcile(null, tree(["A", "B", "C"], "Titre"), 0);
		// Five: the root plus its four children.
		check("the first render creates every node", count(sink.ops, "create") == 5,
			'${count(sink.ops, "create")} creates');
		check("everything is inserted", count(sink.ops, "insert") == 5,
			'${count(sink.ops, "insert")} inserts');

		// --- one property changes ---
		sink.ops = [];
		mounted = r.reconcile(mounted, tree(["A", "B", "C"], "Autre titre"), 0);
		check("a changed label creates nothing", count(sink.ops, "create") == 0,
			'${count(sink.ops, "create")} creates');
		check("a changed label destroys nothing", count(sink.ops, "destroy") == 0);
		check("a changed label applies exactly one property", count(sink.ops, "prop") == 1,
			sink.ops.join(" | "));

		// --- nothing changes ---
		sink.ops = [];
		mounted = r.reconcile(mounted, tree(["A", "B", "C"], "Autre titre"), 0);
		check("an unchanged render does nothing at all", sink.ops.length == 0,
			sink.ops.join(" | "));

		// --- a keyed child moves to the front ---
		sink.ops = [];
		mounted = r.reconcile(mounted, tree(["C", "A", "B"], "Autre titre"), 0);
		check("a reorder rebuilds nothing", count(sink.ops, "create") == 0,
			sink.ops.join(" | "));
		check("a reorder destroys nothing", count(sink.ops, "destroy") == 0);
		check("a reorder moves the controls", count(sink.ops, "remove") > 0 && count(sink.ops, "insert") > 0,
			sink.ops.join(" | "));
		check("a reorder re-applies no property", count(sink.ops, "prop") == 0,
			sink.ops.join(" | "));

		// --- a child leaves ---
		sink.ops = [];
		mounted = r.reconcile(mounted, tree(["C", "B"], "Autre titre"), 0);
		check("a removed child is taken off its parent", count(sink.ops, "remove") >= 1,
			sink.ops.join(" | "));
		check("a removed child is destroyed", count(sink.ops, "destroy") == 1,
			sink.ops.join(" | "));

		// --- a node changes type: same position, different thing ---
		sink.ops = [];
		var changed = new Node("VStack");
		changed.child(new Node("TextBox", "title").prop("text", PString("Autre titre")));
		changed.child(new Node("Button", "C").prop("text", PString("C")));
		changed.child(new Node("Button", "B").prop("text", PString("B")));
		mounted = r.reconcile(mounted, changed, 0);
		check("a changed type rebuilds that node", count(sink.ops, "create") == 1,
			sink.ops.join(" | "));
		check("a changed type destroys the old control", count(sink.ops, "destroy") == 1,
			sink.ops.join(" | "));

		// --- destroying a subtree frees the children too ---
		sink.ops = [];
		mounted = r.reconcile(mounted, new Node("VStack"), 0);
		check("emptying a tree destroys every child", count(sink.ops, "destroy") == 3,
			sink.ops.join(" | "));

		// --- a nullable property disappears ---
		//
		// This is the hole the contract had, and the reason it needs no
		// `clearProp`: absence is not an operation, it is an application of the
		// value the schema declares for it.
		sink.ops = [];
		var withSpacing = new Node("VStack").prop("spacing", PInt(8));
		var m2 = r.reconcile(null, withSpacing, 0);

        sink.ops = [];
		var withoutSpacing = new Node("VStack");
		m2 = r.reconcile(m2, withoutSpacing, 0);
		check("a vanished property applies its declared default",
			count(sink.ops, "prop") == 1, sink.ops.join(" | "));

		// A property with no declared default is left alone: leaving the old
		// value is wrong, but inventing one is wrong in a harder way to notice.
		sink.ops = [];
		var withWidth = new Node("Text").prop("text", PString("x")).prop("width", PFloat(50));
		var m3 = r.reconcile(null, withWidth, 0);

        sink.ops = [];
		var withoutWidth = new Node("Text").prop("text", PString("x"));
		m3 = r.reconcile(m3, withoutWidth, 0);
		check("a vanished property with no default is left alone",
			count(sink.ops, "prop") == 0, sink.ops.join(" | "));

		Sys.println(failures == 0 ? "\nall good" : '\n$failures failed');
		Sys.exit(failures == 0 ? 0 : 1);
	}
}
