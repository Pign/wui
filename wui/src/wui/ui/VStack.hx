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
@:build(wui.macros.ControlBuilder.build())
class VStack extends Stack {
	// Declared with its default, so the generated `create` applies it: both
	// stacks are a StackPanel and only this tells them apart.
	@:winrt("Orientation") public var orientation:String = "Vertical";

    public function new(children:Array<View>, ?spacing:Float) {
        // The class name, not the WinRT type. The push sink keys every branch
        // it generates -- `create` included -- on the name a node reports, and
        // orientation is applied there from the declared default rather than
        // pushed as a property. Reporting "StackPanel" put both stacks on one
        // merged branch, which can only carry one of the two defaults: every
        // stack in the tree came out horizontal, and a screenful of rows
        // collapsed onto a single line.
        super("VStack", children);
        // orientation carries its declared default
        if (spacing != null) this.spacing = spacing;
    }
}
