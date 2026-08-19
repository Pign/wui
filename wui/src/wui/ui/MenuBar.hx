package wui.ui;

import wui.View;

/**
	The window's menu bar.

	WinUI has no window-owned menu — MenuBar is an ordinary XAML control that
	sits wherever it is placed, which for the Commands surface is the first
	child of the Primary tree (`wui.mui.App.nuiBody` injects it there). Its
	children are `MenuBarItem`s, held in `Items()` — a fifth place a parent
	keeps children, beside the four `wui_node_insert` already knew about.
**/
@:winuiType("MenuBar")
@:build(wui.macros.ControlBuilder.build())
class MenuBar extends Control {
	public function new(?items:Array<View>) {
		super("MenuBar", items);
	}
}
