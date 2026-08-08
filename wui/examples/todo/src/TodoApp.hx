import wui.View;
import wui.ui.VStack;
import wui.ui.HStack;
import wui.ui.Text;
import wui.ui.Button;
import wui.ui.TextBox;
import wui.ui.ListView;

/**
	The acceptance app: `sui`'s todo-app, on `wui`.

	## Why this one

	The `wui`-on-hxcpp design note opened with this app as the thing `wui`
	**could not express**. Not for want of a feature — structurally: without a
	Haxe runtime, no closure could be translated, so a button could only
	increment, decrement, assign a literal or toggle a boolean. The `Add` button
	below reads a text field, builds an object, appends it to a list and clears
	the field. None of that is expressible in four verbs.

	It runs now because W1 linked the runtime, W2 gave buttons real closures, W3
	let Haxe state drive the controls, and W4 removed the translator entirely.

	## What is honestly different from the `sui` source

	The APIs were never identical — `sui` has `new Button(label, closure)`,
	`TextField`, `List` and `NavigationStack`; `wui` has `new Button(label)`
	with `.onClick`, `TextBox` and `ListView`. So this is the same *app*, not the
	same *file*. What matters is that nothing here had to be simplified to fit.

	One real limit remains, and it is the row template: a row is read as one text
	and at most one button. That is enough for a to-do list and is not a general
	`ForEach` — the general answer is the `nui` push contract, which is its own
	chantier.
**/
class TodoItem {
	public var title:String;
	public var completed:Bool;

	public function new(title:String, completed:Bool = false) {
		this.title = title;
		this.completed = completed;
	}
}

// Reached by `Type.resolveClass` from the bridge, so nothing references it
// statically. `-main` keeps it in the app itself; a test binary with another
// entry point would see it stripped, and the failure reads as "class not found"
// far from the cause.
@:keep
class TodoApp extends wui.App {
	@:state var todos:rui.structures.ImmutableList<TodoItem> = new rui.structures.ImmutableList();
	@:state var newItemText:String = "";

	static function main() {}

	// Note: this is *not* what names the generated project. The macro cannot
	// evaluate a method, so it uses the class name, while the CLI looks for the
	// .vcxproj under `appName` from wui.json. The two have to agree — see the
	// check in tools/cli/Build.hx.
	override function appName():String {
		return "TodoApp";
	}

	override function body():View {
		// Statement style: the macro follows what is done to a local after its
		// declaration, and a property assignment is a statement, not a chain.
		var heading = new Text("Todo List");
		heading.font = "TitleLarge";
		heading.padding = 12;

		var field = new TextBox("New item...", newItemText);

		// The closure the transpiler could never carry.
		var add = new Button("Add");
		add.onClick = function() {
			var title = newItemText.value;
			if (title == "") return;

			// `push` returns a NEW list -- the point of the structure. With an
			// Array this had to be written as a concat under a comment
			// explaining why, and nothing stopped the next reader writing
			// `push` and losing the notification. Now the obvious call is the
			// correct one.
			todos.value = todos.value.push(new TodoItem(title, false));
			newItemText.value = "";
			trace('[todo] ajouté : $title (${todos.value.length} au total)');
		};

		var entry = new HStack([field, add], 8);
		entry.padding = 12;

		var list = new ListView(todos, function(item:Dynamic) {
			var todo:TodoItem = cast item;
			var mark = todo.completed ? "[x] " : "[ ] ";
			var caption = new Text(mark + todo.title);
			var toggle = new Button(todo.completed ? "Undo" : "Done");
			toggle.onClick = function() {
				todo.completed = !todo.completed;
				// The item mutated in place, so the list is still the same value
				// and `set` would see no change. Rebuilding it makes the write
				// visible -- and an immutable *item* would not need this either,
				// which is the next step the rule points at.
				todos.value = todos.value.map(function(t) return t);
				trace('[todo] ${todo.title} -> ${todo.completed}');
			};
			return new HStack([caption, toggle], 8);
		});
		// ListView declares no padding of its own; margin is a View property.
		list.margin = 12;

		var hint = new Text("Astuce : tapez, Add, puis Done sur une ligne");
		hint.padding = 12;

		return new VStack([heading, entry, list, hint]);
	}
}
