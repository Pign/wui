package wui.ui;

/**
	One segment of a `SelectorBar`.

	Its label is `Text`, not `Content`: a selector bar item is a small labelled
	segment rather than a container for an arbitrary element, and WinUI names it
	accordingly. Getting that wrong is a compile error rather than a blank
	segment, which is the point of declaring it here.
**/
@:winuiType("SelectorBarItem")
@:build(wui.macros.ControlBuilder.build())
class SelectorBarItem extends Control {
	@:winrt("Text") public var label:Null<String>;

	public function new(label:String) {
		super("SelectorBarItem");
		this.label = label;
	}
}
