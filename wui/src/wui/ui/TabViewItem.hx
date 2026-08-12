package wui.ui;

/**
	One tab: a header, and the view behind it.

	A `TabView` in WinUI does not hold contents directly — it holds items, and
	each item holds one. `mui`'s vocabulary has no such thing, and should not:
	a tab is a label and a view, which is what `TabView`'s constructor turns
	into these.
**/
@:winuiType("TabViewItem")
@:build(wui.macros.ControlBuilder.build())
class TabViewItem extends Control {
	@:winrt("Header") public var header:Null<String>;

	public function new(header:String, content:View) {
		super("TabViewItem", [content]);
		this.header = header;
	}
}
