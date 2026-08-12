package wui.ui;

/** A value picked along a track. **/
@:winuiType("Slider")
@:build(wui.macros.ControlBuilder.build())
class Slider extends Control {
	@:winrt("Minimum") public var min:Null<Float>;
	@:winrt("Maximum") public var max:Null<Float>;
	@:winrt("Value") public var value:Null<Float>;
	@:winrt("StepFrequency") public var step:Null<Float>;

	public function new(min:Float, max:Float, ?binding:Dynamic, ?step:Float) {
		super("Slider");
		this.min = min;
		this.max = max;
		if (binding != null) properties.set("binding", binding);

		// A step of 1 is WinUI's default, and it is only sane for a range
		// measured in whole numbers. Over 0..1 -- how a fraction is naturally
		// expressed, and what `mui.ui.Slider` defaults to -- it leaves the
		// control two positions: one bound to 0.4 sat hard left, showing 0. A
		// hundredth of the range keeps the value meaning what it says, and an
		// explicit step still wins.
		this.step = step != null ? step : (max - min) / 100;
	}
}
