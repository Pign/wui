package wui.ui;

import wui.View;
import wui.state.StateAction;

/**
	A clickable button.

	`text` rather than `label`: the transpiled path called it `label` while the
	node path called it `text`, for the same thing. `nui` settled that naming in
	B2 — text is an ordinary property — so the declaration follows it and the
	generator accepts both while the old name is still in the wild.
**/
@:winuiType("Button")
@:build(wui.macros.ControlBuilder.build())
class Button extends View {
	@:winrt("Content")
	public var text:String;

	public function new(label:String, ?icon:Dynamic, ?action:StateAction) {
		super("Button");
		this.text = label;
		if (icon != null) properties.set("icon", icon);
		if (action != null) properties.set("action", action);
	}

	/** Set a Haxe closure instead of a StateAction. **/
	public function onClick(callback:() -> Void):Button {
		properties.set("onClick", callback);
		return cast this;
	}
}
