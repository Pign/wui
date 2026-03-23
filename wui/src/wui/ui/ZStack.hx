package wui.ui;

import wui.View;

/**
 * Overlapping layout. Maps to WinUI Grid with all children in the same cell.
 *
 * Usage:
 *   new ZStack([
 *       new Image("background.png"),
 *       new Text("Overlay text")
 *   ])
 */
class ZStack extends View {
    public function new(children:Array<View>) {
        super("Grid", children);
        properties.set("overlapping", true);
    }
}
