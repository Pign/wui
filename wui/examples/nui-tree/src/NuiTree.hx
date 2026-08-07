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

	static function main() {}

	override function appName():String {
		return "NuiTree";
	}

	// Unused in push mode, but `wui.App` requires it. The generator skips it
	// entirely when the class is `@:nui`.
	override function body():View {
		return new VStack([]);
	}

	/** The tree the sink is driven through. **/
	public function nuiBody():Node {
		var title = new Node("Text")
			.prop("text", PString("Arbre nui, rendu par WinUI"));
		title.modifiers.push({type: "padding", floats: [12]});

		var status = new Node("Text", "status")
			.prop("text", PString("aucun clic"));
		status.modifiers.push({type: "foregroundColor", strings: ["accent"]});

		var row = new Node("HStack")
			.prop("spacing", PInt(8))
			.child(button("Alpha", status))
			.child(button("Bravo", status))
			.child(button("Charlie", status));
		row.modifiers.push({type: "padding", floats: [12]});

		// A type the sink does not know. It must render `?Hologramme` on screen
		// rather than leave a silent hole -- the same call `cui` made.
		var unknown = new Node("Hologramme");

		var root = new Node("VStack")
			.prop("spacing", PInt(4))
			.child(title)
			.child(status)
			.child(row)
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
			}));
	}
}
