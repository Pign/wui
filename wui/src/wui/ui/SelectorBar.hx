package wui.ui;

import wui.View;

/**
	A segmented selector: a row of choices, one of them picked.

	## Why it exists alongside `NavigationView`

	They answer different questions. `NavigationView` moves between the
	**sections of an app** and owns the page behind them. A `SelectorBar` filters
	or switches something **inside** one page — a range, a mode, a view of the
	same data — and owns nothing but which segment is lit.

	`mui.ui.TabView` maps to the first, because that is what a tab means on the
	other three backends. This one has no `mui` equivalent and is not trying to
	get one: it is a wui control, for an app willing to say so. Reaching for it
	is choosing Windows' idiom over a shared one, which is a decision worth
	making deliberately rather than inheriting.

	## What it does not do

	It does not hold the views its segments select. A `NavigationView` has a
	`Content` and so can show a page; a selector bar is a control, and what it
	changes is up to the view around it. Give it an `onSelect` and decide there.

	```haxe
	new SelectorBar(["Day", "Week", "Month"], range.get(), i -> range.set(i))
	```
**/
@:winuiType("SelectorBar")
@:build(wui.macros.ControlBuilder.build())
class SelectorBar extends Control {
	/**
		Which segment is lit.

		Not a real WinRT member, for the same reason as `NavigationView`'s:
		`SelectorBar` selects by item. The generated setter does the lookup, and
		leaves the control alone when the answer is the segment already lit --
		re-asserting it would fight the user mid-tap.
	**/
	@:winrt("SelectedItemIndex") public var selectedIndex:Null<Int>;

	public function new(labels:Array<String>, selected:Int = 0, ?onSelect:Int->Void) {
		super("SelectorBar", [for (l in labels) new SelectorBarItem(l)]);
		this.selectedIndex = selected < 0 || selected >= labels.length ? 0 : selected;
		if (onSelect != null) properties.set("onSelect", onSelect);
	}
}
