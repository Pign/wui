package wui.ui;

import wui.View;

/**
	A scrollable region around one child.

	No properties of its own yet. `HorizontalScrollBarVisibility` was the obvious
	one and it takes a WinRT enum, not a string, so it needs a conversion in
	`BridgeGenerator.nodeSetter` before it can be declared here — the same shape
	`Orientation` and `Visibility` already have. The default behaviour is right
	for a column of content, so that wait costs nothing.
**/
@:winuiType("ScrollViewer")
@:build(wui.macros.ControlBuilder.build())
class ScrollViewer extends Control {
	public function new(content:View) {
		super("ScrollViewer", [content]);
	}
}
