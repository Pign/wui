package wui.ui;

import wui.View;

/**
	One top-level menu: a title in the bar, and the flyout items behind it.

	The Commands surface makes one of these per CommandSet declaration — N
	menus, titled from the set ids. Children are `MenuFlyoutItem`s, held in
	`Items()` (an `IVector<MenuFlyoutItemBase>`, not a Panel's children).
**/
@:winuiType("MenuBarItem")
@:build(wui.macros.ControlBuilder.build())
class MenuBarItem extends Control {
	@:winrt("Title")
	public var title:String;

	public function new(title:String, ?items:Array<View>) {
		super("MenuBarItem", items);
		this.title = title;
	}
}
