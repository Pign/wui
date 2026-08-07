package wui.ui;

import wui.View;

/**
 * Horizontal stack layout. Maps to WinUI StackPanel with Horizontal orientation.
 *
 * Usage:
 *   new HStack([
 *       new Text("Left"),
 *       new Spacer(),
 *       new Text("Right")
 *   ])
 */
@:winuiType("StackPanel")
@:build(wui.macros.ControlBuilder.build())
class HStack extends Stack {
	// Declared with its default, so the generated `create` applies it: both
	// stacks are a StackPanel and only this tells them apart.
	@:winrt("Orientation") public var orientation:String = "Horizontal";

    public function new(children:Array<View>, ?spacing:Float) {
        super("StackPanel", children);
        // orientation carries its declared default
        if (spacing != null) this.spacing = spacing;
    }
}
