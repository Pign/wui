package wui.ui;

/**
	One entry in a `NavigationView`'s pane: a label, and nothing else.

	Unlike a `TabViewItem`, an item does **not** hold the view behind it. WinUI's
	navigation control shows one content at a time, in its own `Content`, and the
	pane holds only the things you can click. That is the difference between a
	document tab strip and a section selector, and it is why the two controls
	take their children so differently.
**/
@:winuiType("NavigationViewItem")
@:build(wui.macros.ControlBuilder.build())
class NavigationViewItem extends Control {
	// `Content` on a NavigationViewItem is what it displays, which for a section
	// selector is its label. It is an IInspectable, so the generated setter
	// boxes it -- the same rule a TabViewItem's Header follows.
	@:winrt("Content") public var label:Null<String>;

	public function new(label:String) {
		super("NavigationViewItem");
		this.label = label;
	}
}
