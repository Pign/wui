import nui.Node;
import nui.PropValue;
import wui.View;
import wui.ui.VStack;

/**
	`wui` as the **second** adopter of nui's push contract.

	Nothing here is generated from `body()`. The window gets an empty root panel
	and `wui.nui.Mount` drives `wui.nui.WinUISink` through the tree below —
	create, apply properties, apply modifiers, insert — the same six operations
	`qui` implements against Silica.

	The point of a second adopter is not that it works. It is that the three
	assumptions `qui` could not honour, and which B4 refused to soften for a
	sample of one, are honoured here:

	- `create` and `insert` are separable — the buttons below exist before they
	  are mounted;
	- the insertion index is chosen — the counter is inserted at a fixed
	  position, not appended;
	- `destroy` frees, rather than hiding.
**/
@:nui
@:keep
class NuiTree extends wui.App {
	static var clicks = 0;
	static var labels = ["Alpha", "Bravo", "Charlie"];
	static var title = "Arbre nui, rendu par WinUI";

	static function main() {}

	override function appName():String {
		return "NuiTree";
	}

	// Unused in push mode, but `wui.App` requires it. The generator skips it
	// entirely when the class is `@:nui`.
	override function body():View {
		return new VStack([]);
	}

	/** The tree the sink is driven through, rebuilt on every render. **/
	public function nuiBody():Node {
		var heading = new Node("Text", "heading")
			.prop("text", PString(title));
		heading.modifiers.push({type: "padding", floats: [12]});

		var status = new Node("Text", "status")
			.prop("text", PString(clicks == 0 ? "aucun clic" : '$clicks clic(s)'));
		status.modifiers.push({type: "foregroundColor", strings: ["accent"]});

		// The reconciler test, made visible: type in this box, then reorder the
		// row below. The box is keyed, so it is *moved* rather than rebuilt, and
		// what you typed survives. Without a key it would be matched by position
		// and silently replaced.
		var box = new Node("TextBox", "scratch")
			.prop("placeholder", PString("tapez ici, puis mélangez"));
		box.modifiers.push({type: "padding", floats: [12]});

		var row = new Node("HStack")
			.prop("spacing", PInt(8));
		for (l in labels) row.child(button(l, status));
		row.modifiers.push({type: "padding", floats: [12]});

		// A type the sink does not know, declared as foreign on purpose.
		//
		// Written as `new Node("Hologramme")` this now refuses to compile, which
		// is the point: an unknown type in authored source is a mistake. Saying
		// it is foreign is what distinguishes "I know" from a typo, and it still
		// renders `?Hologramme` -- the honest degradation for a tree from
		// elsewhere.
		var unknown = wui.nui.Foreign.node("Hologramme");

		var shuffle = new Node("Button", "shuffle")
			.prop("text", PString("Mélanger"))
			.prop("onClick", PCallback(function() {
				labels.push(labels.shift());
				title = 'ordre : ${labels.join(" ")}';
				wui.bridge.HaxeBridge.rerenderNui();
			}));
		shuffle.modifiers.push({type: "padding", floats: [12]});

		var root = new Node("VStack")
			.prop("spacing", PInt(4))
			.child(heading)
			.child(status)
			.child(box)
			.child(row)
			.child(shuffle)
			.child(unknown);
		root.modifiers.push({type: "padding", floats: [16]});
		return root;
	}

	static function button(label:String, status:Node):Node {
		return new Node("Button", label)
			.prop("text", PString(label))
			.prop("onClick", PCallback(function() {
				clicks++;
				trace('[nui] $label, clic n°$clicks');
				wui.bridge.HaxeBridge.rerenderNui();
			}));
	}
}
