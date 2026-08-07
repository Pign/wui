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
class HStack extends Stack {
    public function new(children:Array<View>, ?spacing:Float) {
        super("StackPanel", children);
        properties.set("orientation", "Horizontal");
        if (spacing != null) this.spacing(spacing);
    }
}
