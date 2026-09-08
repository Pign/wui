import nui.Node;
import nui.NodeSink;
import nui.PropValue;
import nui.Modifier;
import rui.Signal;
import wui.mui.Chords;

/**
	The Commands surface as a WinUI menu bar, end to end minus WinRT. Run with:

	    haxe -cp src -cp test -lib rui -lib nui -lib mui -lib kui -D mui_backend=wui --macro "mui.macros.Bind.all()" -main MenuBarCheck --interp

	A real mui application (Bind, `@:surface` collection) declares two command
	sets; `nuiBody()` injects them as ORDINARY NODES above the body, which is
	the design's whole bet — no new bridge machinery, and reconciliation gives
	live labels for free. What this pins:

	- the described shape: a VStack whose FIRST child is the MenuBar, one
	  MenuBarItem per set in declaration order, titled from the ids;
	- the click is a PCallback that runs the right action;
	- the chord grammar: "ctrl+k" packs to Control|K, a chordless command has
	  no accelerator prop at all, and an unparseable chord degrades to the
	  same — label and click intact;
	- live labels: a state write a label reads re-applies exactly that text
	  prop through the reconciler, with no node recreated.
**/
class MenuBarCheck {
	static var failures = 0;

	static function check(label:String, actual:Dynamic, expected:Dynamic) {
		var ok = Std.string(actual) == Std.string(expected);
		if (!ok) failures++;
		trace((ok ? "ok   " : "FAIL ") + label + " = " + actual + (ok ? "" : " (expected " + expected + ")"));
	}

	static function stringProp(n:Node, key:String):String {
		var pv = n.props.get(key);
		if (pv == null) return "";
		return switch (nui.PropValueTools.resolve(pv)) {
			case PString(s): s;
			case _: "";
		};
	}

	static function intProp(n:Node, key:String):Null<Int> {
		var pv = n.props.get(key);
		if (pv == null) return null;
		return switch (nui.PropValueTools.resolve(pv)) {
			case PInt(i): i;
			case _: null;
		};
	}

	static function main() {
		// ---- the chord grammar, pinned where it lives ----
		check("ctrl+k packs Control|K", Chords.parse("ctrl+k"), (1 << 16) | 75);
		check("modifiers combine", Chords.parse("alt+shift+f"), ((2 | 4) << 16) | 70);
		check("chords are case-insensitive", Chords.parse("CTRL+K"), (1 << 16) | 75);
		check("a bare letter needs no modifier", Chords.parse("q"), 81);
		check("digits are keys too", Chords.parse("ctrl+2"), (1 << 16) | 50);
		check("enter is a key", Chords.parse("enter"), 13);
		check("esc is escape", Chords.parse("esc"), 27);
		check("shift+tab combines a named key", Chords.parse("shift+tab"), (4 << 16) | 9);
		check("an unknown modifier answers null", Chords.parse("meta+p") == null, true);
		check("a trailing plus answers null", Chords.parse("ctrl+") == null, true);

		// ---- the described shape ----
		var app = new MenuApp();
		var tree = app.nuiBody();
		check("the root is a wrapper VStack", tree.type, "VStack");
		check("the MenuBar is its FIRST child", tree.children[0].type, "MenuBar");
		check("the body follows the bar", tree.children.length, 2);

		var bar = tree.children[0];
		check("one MenuBarItem per set, in declaration order", bar.children.length, 2);
		check("titles come from the ids, one capital", stringProp(bar.children[0], "title")
			+ "," + stringProp(bar.children[1], "title"), "File,Edit");

		var file = bar.children[0];
		check("the set's commands are its flyout items", file.children.length, 2);
		check("a label is a text prop", stringProp(file.children[0], "text"), "Items: 0");
		check("the chord rode along, packed", intProp(file.children[0], "accelerator"), (1 << 16) | 75);
		check("a chordless command has NO accelerator prop",
			file.children[1].props.exists("accelerator"), false);

		var edit = bar.children[1];
		check("an unparseable chord degrades to no accelerator",
			edit.children[0].props.exists("accelerator"), false);
		check("its label survives", stringProp(edit.children[0], "text"), "Bad chord");

		// ---- the click is the declared action ----
		switch (nui.PropValueTools.resolve(file.children[0].props.get("onClick"))) {
			case PCallback(fn): fn();
			case _: failures++; trace("FAIL onClick is not a PCallback");
		}
		check("clicking ran the right action", Probe.cleared, 1);

		// ---- live labels, through the reconciler ----
		var sink = new RecordingSink();
		var reconciler = new wui.nui.Reconciler(sink);
		var root = sink.create(new Node("Root"), null);
		var mounted = null;
		new Effect(function() {
			mounted = reconciler.reconcile(mounted, app.nuiBody(), root);
		});
		var createdAtMount = sink.created.length;
		var liveLabel = sink.firstHandleOf("MenuFlyoutItem");
		check("the menu mounted its label", sink.textAt(liveLabel), "Items: 1");

		app.bump();
		check("a state write the label reads re-applied the text, on that node",
			sink.textAt(liveLabel), "Items: 2");
		check("no node was recreated for it", sink.created.length, createdAtMount);

		trace(failures == 0 ? "\nall checks passed" : '\n$failures failed');
		#if sys
		Sys.exit(failures == 0 ? 0 : 1);
		#end
	}
}

/** Action counters, off the app: bookkeeping about the test, not state a
	view depends on (the view rule judges the command thunks). **/
class Probe {
	public static var cleared = 0;
}

class MenuApp extends mui.App {
	@:state var items:Int = 0;

	/** The test's way to write what a label reads. **/
	public function bump() {
		items += 1;
	}

	override function body():mui.View {
		return new mui.ui.Text("body");
	}

	@:surface(Commands)
	function file():Array<mui.surface.Command> {
		return [
			new mui.surface.Command("Items: " + items, function() {
				Probe.cleared++;
				items += 1;
			}).key("ctrl+k"),
			new mui.surface.Command("No chord", function() {}),
		];
	}

	@:surface(Commands, "edit")
	function other():Array<mui.surface.Command> {
		return [
			new mui.surface.Command("Bad chord", function() {}).key("meta+p"),
		];
	}
}

/** A sink that records what was drawn: creates by type, and the last text
	each NODE received — by handle, so the live-label check proves the
	re-apply landed on the right node, not just somewhere. **/
class RecordingSink implements NodeSink<Int> {
	public var created:Array<String> = [];

	var texts:Map<Int, String> = new Map();
	var next = 1;
	var _bind:(Void->Void)->Null<Void->Void> = function(fn) { fn(); return null; };

	public var bindReactive(get, set):(Void->Void)->Null<Void->Void>;

	function get_bindReactive() return _bind;

	function set_bindReactive(v) { _bind = v; return v; }

	public function new() {}

	/** Handles start at 1 and are handed out in creation order. **/
	public function firstHandleOf(type:String):Int {
		return created.indexOf(type) + 1;
	}

	public function textAt(handle:Int):String {
		var t = texts.get(handle);
		return t == null ? "" : t;
	}

	public function create(node:Node, parent:Null<Int>):Int {
		created.push(node.type);
		return next++;
	}

	public function applyProp(target:Int, type:String, key:String, value:PropValue):Void {
		if (key != "text") return;
		switch (nui.PropValueTools.resolve(value)) {
			case PString(s): texts.set(target, s);
			case _:
		}
	}

	public function applyModifiers(target:Int, type:String, modifiers:Array<Modifier>):Void {}

	public function insert(parent:Int, child:Int, index:Int):Void {}

	public function remove(parent:Int, child:Int):Void {}

	public function destroy(target:Int):Void {}
}
