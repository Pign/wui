package wui.ui;

import wui.View;

/**
	What WinUI's `Control` adds to an element.

	This class exists to mirror the WinRT hierarchy, because the generator now
	emits against the concrete control and lets MSVC check membership. A
	property declared where its control does not have it is a compile error --
	which is the whole gain: it used to be a lookup table saying who owned what,
	maintained by hand and already wrong.
**/
@:build(wui.macros.ControlBuilder.build())
class Control extends View {
	@:winrt("Padding") public var padding:Null<Float>;
	@:winrt("Background") public var background:Null<String>;
	@:winrt("Foreground") public var foregroundColor:Null<String>;
	@:winrt("BorderBrush") public var borderBrush:Null<String>;
	@:winrt("BorderThickness") public var borderThickness:Null<Float>;
	@:winrt("CornerRadius") public var cornerRadius:Null<Float>;
	@:winrt("FontSize") public var fontSize:Null<Float>;
	@:winrt("IsEnabled") public var enabled:Bool = true;

	public function new(?viewType:String, ?children:Array<View>) {
		super(viewType, children);
	}
}
