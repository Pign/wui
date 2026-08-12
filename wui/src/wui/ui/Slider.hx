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
		if (step != null) this.step = step;
	}
}
