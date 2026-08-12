package wui.ui;

/** A progress indicator, determinate when given a value. **/
@:winuiType("ProgressRing")
@:build(wui.macros.ControlBuilder.build())
class ProgressRing extends Control {
	@:winrt("Value") public var value:Null<Float>;
	@:winrt("Maximum") public var max:Null<Float>;
	@:winrt("IsIndeterminate") public var isIndeterminate:Null<Bool>;
	@:winrt("IsActive") public var isActive:Null<Bool>;

	public function new(?value:Float) {
		super("ProgressRing");
		this.isActive = true;
		if (value != null) {
			// A fraction, on a control whose scale runs to 100 by default. That
			// is what every caller means -- `mui.ui.ProgressView` takes 0..1, as
			// the other backends do -- and left unsaid it drew 0.4 as an arc of
			// four tenths of one percent, which is nothing at all on screen.
			this.max = 1;
			this.value = value;
			this.isIndeterminate = false;
		} else {
			this.isIndeterminate = true;
		}
	}
}
