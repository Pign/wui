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

	// N3 : les lignes vivent dans un signal, et la liste s'y abonne elle-même.
	static var items = new rui.Signal(["première ligne"]);
	static var added = 1;
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

		// Une liste à enfants différés. Le thunk lit `items`, donc l'effet créé par
		// le réconciliateur est abonné exactement à ce dont la liste dépend : une
		// écriture dans `items` la met à jour seule, sans que l'arbre au-dessus
		// soit reparcouru.
		var list = new Node("VStack", "liste").prop("spacing", PInt(2));
		list.childrenThunk = function() {
			return [for (it in items.value) new Node("Text", it).prop("text", PString("· " + it))];
		};
		list.modifiers.push({type: "padding", floats: [12]});

		// Ce bouton n'appelle PAS rerenderNui(). Il écrit dans le signal, et
		// c'est tout — si la liste s'allonge quand même, N3 fonctionne.
		var add = new Node("Button", "add")
			.prop("text", PString("Ajouter une ligne (sans re-rendu)"))
			.prop("onClick", PCallback(function() {
				added++;
				items.value = items.value.concat(["ligne " + added]);
				trace('[nui] liste : ${items.value.length} ligne(s), sans re-rendu');
			}));
		add.modifiers.push({type: "padding", floats: [12]});

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
			.child(add)
			.child(list)
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
