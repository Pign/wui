package wui.ui;

/** A progress indicator, determinate when given a value. **/
@:winuiType("ProgressRing")
@:build(wui.macros.ControlBuilder.build())
class ProgressRing extends Control {
	@:winrt("Value") public var value:Null<Float>;
	@:winrt("IsIndeterminate") public var isIndeterminate:Null<Bool>;
	@:winrt("IsActive") public var isActive:Null<Bool>;

	public function new(?value:Float) {
		super("ProgressRing");
		this.isActive = true;
		if (value != null) {
			this.value = value;
			this.isIndeterminate = false;
		} else {
			this.isIndeterminate = true;
		}
	}
}
