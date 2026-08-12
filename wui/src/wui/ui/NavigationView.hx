package wui.ui;

import wui.View;

/**
	A few top-level sections, with the one you picked showing.

	## Why this and not `TabView`

	`TabView` is WinUI's **document** control — browser tabs. Each one carries a
	close button, and the strip carries a "+" to open another. That is right for
	things a user opens and closes, and wrong for the sections of an app, which
	are fixed: nothing about "Layout, Controls, Data" can be closed or added.
	Mapping `mui.ui.TabView` onto it produced a strip offering both — and, the
	day the items failed to insert, a lone "+" and nothing else.

	`NavigationView` is what WinUI offers for sections. In `Top` mode it reads
	the way tabs read on the other three backends.

	## Where the selection lives

	In a shared cell here, not in the application. `sui` settled this first: its
	dynamic renderer keeps the selected tab on the **renderer's** side, so an app
	that says nothing about selection still gets working tabs — which is why none
	of the four backends made `mui.ui.TabView` ask for one.

	The cell has to outlive a render. Created while describing the tree it would
	be new on every write, and the selection would snap back to the first section
	each time anything else changed. It is static for the same reason
	`SuiTabs.shared` is a singleton, and carries the same limit, stated rather
	than discovered: **one navigation bar per application**.

	Reading it here is what subscribes the render to it, so clicking a section
	re-describes the tree with that section's view in `Content`.

	## Two shapes, one control

	`items` is kept for the transpiled path, which reads it at compile time. The
	children and the `@:winrt` declarations are for the push sink. `TabView` does
	the same thing for the same reason; neither path is asked to understand the
	other's shape.
**/
@:winuiType("NavigationView")
@:build(wui.macros.ControlBuilder.build())
class NavigationView extends Control {
	/** The selected section. See the class doc for why it is shared. **/
	public static var selection(default, null):rui.state.State<Int> = new rui.state.State(0);

	// Applied by the generated `create` from these defaults, and again by the
	// property setters on a re-render. `PaneDisplayMode` and
	// `IsBackButtonVisible` are WinRT enums, so both have a conversion in
	// `BridgeGenerator.nodeSetter`: a string arriving at an enum is the one
	// thing that does not compile.
	@:winrt("PaneDisplayMode") public var paneMode:String = "Top";
	@:winrt("IsBackButtonVisible") public var backButton:String = "Collapsed";
	@:winrt("IsSettingsVisible") public var settingsVisible:Bool = false;

	/**
		Which section is showing.

		Not a real WinRT member: `NavigationView` selects by *item*, not by
		index. The generated setter turns one into the other — the same service
		`FontScale` and `Padding` already get, where the annotation names what
		applies the value and that turns out to be a small translation.
	**/
	@:winrt("SelectedIndex") public var selectedIndex:Null<Int>;

	/**
		Build the pane's items, and the view behind the selected one.

		The children are the items, then **one** view: the section showing. A
		`TabView` receives every content at once because each of its items holds
		one; this control has a single `Content`, so Haxe supplies the view that
		belongs there and the sink puts it in place.
	**/
	public function new(items:Array<NavigationItem>) {
		var index = selection.get();
		if (index < 0 || index >= items.length) index = 0;

		var children:Array<View> = [for (i in items) new NavigationViewItem(i.label)];
		if (items.length > 0) {
			var page = items[index].content;
			// The page is keyed by the section it belongs to, so switching
			// sections *replaces* it instead of reusing one control and pouring
			// a different section's children into it -- which would carry the
			// old page's scroll position into the new one.
			if (page != null) page.properties.set("nodeId", "section-" + index);
			if (page != null) children.push(page);
		}

		super("NavigationView", children);
		this.selectedIndex = index;
		properties.set("items", items);
		properties.set("onSelect", function(i:Int) selection.set(i));
	}
}

typedef NavigationItem = {
	label:String,
	?icon:String,
	content:View
};
