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
@:node("VStack")
class VStack extends Stack {
    public function new(children:Array<View>, ?spacing:Float) {
        super("StackPanel", children);
        properties.set("orientation", "Vertical");
        if (spacing != null) this.spacing = spacing;
    }
}
