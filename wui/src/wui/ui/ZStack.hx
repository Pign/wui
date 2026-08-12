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
// A WinRT `Grid` is a panel, not a control: `View` is the level that carries
// what it actually has. See `Border` for the error the other choice produces.
@:winuiType("Grid")
@:build(wui.macros.ControlBuilder.build())
class ZStack extends View {
	@:winrt("Background") public var background:Null<String>;
	@:winrt("Padding") public var padding:Null<Float>;

    public function new(children:Array<View>) {
        super("Grid", children);
        properties.set("overlapping", true);
    }
}
