package wui.ui;

/** An on/off switch with a label beside it. **/
@:winuiType("ToggleSwitch")
@:build(wui.macros.ControlBuilder.build())
class ToggleSwitch extends Control {
	@:winrt("Header") public var label:Null<String>;
	@:winrt("IsOn") public var isOn:Null<Bool>;

	public function new(?label:String, ?binding:Dynamic) {
		super("ToggleSwitch");
		if (label != null) this.label = label;
		if (binding != null) properties.set("binding", binding);
	}
}
