package wui.mui;

import mui.ui.TabItem;

/**
	`wui`'s conformance for `mui.ui.TabView`.

	`mui` resolves this by name through `mui.Contract` and `mui.macros.Bind`,
	which is why nothing in `mui` mentions `wui`. Moved here, unchanged, from the
	`#if (mui_backend == "wui")` branch it used to live in.
**/
/**
    Sections, not documents.

    This used to extend `wui.ui.TabView`, which is WinUI's **document** control:
    browser tabs, each carrying a close button, the strip carrying a "+" to open
    another. Both offers are wrong for the sections of an app -- nothing about
    "Layout, Controls, Data" can be closed or added -- and both were on screen.

    `NavigationView` in `Top` mode is what WinUI offers for this, and it reads
    the way tabs read on the other three backends. It owns the selection too, so
    this constructor still asks for none: one signature, four backends.
**/
class TabView extends wui.ui.NavigationView {
    public function new(tabs:Array<TabItem>) {
        super([for (t in tabs) {label: t.label, content: t.content}]);
    }
}
