package wui.ui;

/**
	One command in a menu: a label, a click, and optionally an accelerator.

	The click rides the same id-over-the-bridge path as Button's (a closure
	never crosses; `wui_node_prop_callback` grew a MenuFlyoutItem branch).

	The accelerator is deliberately NOT a `@:winrt` property: the generated
	setters call the named member directly and MSVC checks it exists, but a
	chord is not a member — it becomes a `KeyboardAccelerator` (VirtualKey +
	VirtualKeyModifiers) appended to `KeyboardAccelerators()`. It crosses as
	one packed int (`wui.mui.Chords.parse`) under the undeclared prop key
	"accelerator", handled by a hand-written branch — the same undeclared-prop
	precedent Button's "icon" set.
**/
@:winuiType("MenuFlyoutItem")
@:build(wui.macros.ControlBuilder.build())
class MenuFlyoutItem extends Control {
	@:winrt("Text")
	public var text:String;

	/** The handler. A var like any other property -- see `View`. **/
	@:winrt("Click")
	public var onClick:Null<Void->Void>;

	public function new(text:String, ?onClick:Void->Void) {
		super("MenuFlyoutItem");
		this.text = text;
		if (onClick != null) this.onClick = onClick;
	}
}
