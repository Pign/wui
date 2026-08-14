package wui.mui;


/**
	`wui`'s conformance for `mui.ui.ScrollView`.

	`mui` resolves this by name through `mui.Contract` and `mui.macros.Bind`,
	which is why nothing in `mui` mentions `wui`. Moved here, unchanged, from the
	`#if (mui_backend == "wui")` branch it used to live in.
**/
class ScrollView extends wui.ui.ScrollViewer {
	public function new(content:Array<wui.View>) {
		super(new wui.ui.VStack(content));
	}
}
