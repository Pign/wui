package wui.ui;

import wui.View;

/** A single-line text field. **/
@:node("TextBox")
@:winuiType("TextBox")
@:build(wui.macros.ControlBuilder.build())
class TextBox extends View {
	@:winrt("Text")
	public var text:Null<String>;

	@:winrt("PlaceholderText")
	public var placeholder:Null<String>;

	public function new(?placeholder:String, ?binding:Dynamic) {
		super("TextBox");
		if (placeholder != null) this.placeholder = placeholder;
		if (binding != null) properties.set("binding", binding);
	}
}
