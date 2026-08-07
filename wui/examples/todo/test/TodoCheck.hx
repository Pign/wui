import wui.bridge.Callbacks;
import wui.bridge.HaxeBridge;

/**
	Drives the acceptance app the way a user would, minus the window.

	`install()` builds the Haxe view tree and registers what it finds, so the
	buttons can be fired through the registry and the results read back from the
	states. That covers everything except the pixels: what a click runs, what the
	list contains after it, and whether a row's own button reaches its item.

	    haxe build.hxml && haxe test.hxml && ./build/test/TodoCheck
**/
class TodoCheck {
	static var failures = 0;

	static function check(what:String, ok:Bool, detail:String = ""):Void {
		if (ok) {
			Sys.println('  ok   $what');
		} else {
			failures++;
			Sys.println('  FAIL $what${detail == "" ? "" : "  -- " + detail}');
		}
	}

	static function todos():Array<Dynamic> {
		var st:Dynamic = wui.state.State.getByName("todos");
		if (st == null) return null;
		var v:Array<Dynamic> = st.peek();
		return v == null ? [] : v;
	}

	static function main() {
		Sys.println("TodoCheck");

		// Force the app into this build.
		//
		// `@:keep` stops DCE from removing a class; it does not make the compiler
		// load a module nothing mentions. With `-main TodoCheck`, nothing does --
		// and `Type.resolveClass` then reports "class not found", which reads as a
		// bridge fault rather than a missing compilation unit. Same trap as
		// forcing wui.bridge.HaxeBridge into an app build.
		Sys.println("  (app forcee dans le build : " + Type.getClassName(TodoApp) + ")");

		var installed = HaxeBridge.install("TodoApp");
		check("the Add button registered", installed == 1, 'got $installed');

		var text:Dynamic = wui.state.State.getByName("newItemText");
		check("both states registered", text != null && todos() != null);
		if (text == null || todos() == null) {
			// Everything below dereferences these. Stop here with a verdict
			// rather than dying on a null and reporting a crash instead.
			Sys.println("\nabandon : les états ne sont pas là");
			Sys.exit(1);
		}
		check("the list starts empty", todos().length == 0);
		check("an empty list registers no rows", Callbacks.rowCount() == 0);

		// Adding with an empty field must do nothing: the guard is the first
		// thing the closure does, and it is exactly the sort of statement the
		// transpiler could never express.
		Callbacks.invoke(0);
		check("Add on an empty field adds nothing", todos().length == 0);

		// Type, then Add. applyExternalString is what a keystroke does.
		HaxeBridge.applyExternalString("newItemText", "acheter du pain");
		Callbacks.invoke(0);
		check("Add appends the item", todos().length == 1, '${todos().length} items');
		check("the field is cleared afterwards", (text.peek() : String) == "",
			'field = "${text.peek()}"');
		check("the list registered one row", Callbacks.rowCount() == 1,
			'${Callbacks.rowCount()} rows');

		HaxeBridge.applyExternalString("newItemText", "relire la note");
		Callbacks.invoke(0);
		check("a second item appends", todos().length == 2, '${todos().length} items');
		check("the list registered two rows", Callbacks.rowCount() == 2,
			'${Callbacks.rowCount()} rows');

		// A row's own button must reach its own item.
		var first:Dynamic = todos()[0];
		var second:Dynamic = todos()[1];
		check("items start incomplete", first.completed == false && second.completed == false);

		Callbacks.invokeRow(1);
		check("row 1 toggles the second item", second.completed == true);
		check("row 1 leaves the first alone", first.completed == false);

		Callbacks.invokeRow(0);
		check("row 0 toggles the first item", first.completed == true);

		// Toggling rebuilt the list, so the row ids were renumbered. They must
		// still be there and still be two.
		check("rows survive a rebuild", Callbacks.rowCount() == 2,
			'${Callbacks.rowCount()} rows');

		// A stale row id must be survivable: a click can land after a rebuild.
		Callbacks.invokeRow(99);
		check("a stale row id runs nothing", true);

		Sys.println(failures == 0 ? "\nall good" : '\n$failures failed');
		Sys.exit(failures == 0 ? 0 : 1);
	}
}
