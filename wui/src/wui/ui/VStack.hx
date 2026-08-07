package wui.ui;

import wui.View;

/**
 * Vertical stack layout. Maps to WinUI StackPanel with Vertical orientation.
 *
 * Usage:
 *   new VStack([
 *       new Text("Top"),
 *       new Text("Bottom")
 *   ], 8)
 */
@:winuiType("StackPanel")
class VStack extends Stack {
	// Declared with its default, so the generated `create` applies it: both
	// stacks are a StackPanel and only this tells them apart.
	@:winrt("Orientation") public var orientation:String = "Vertical";

    public function new(children:Array<View>, ?spacing:Float) {
        super("StackPanel", children);
        // orientation carries its declared default
        if (spacing != null) this.spacing = spacing;
    }
}
