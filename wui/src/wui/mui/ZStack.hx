package wui.mui;


/**
	`wui`'s conformance for `mui.ui.ZStack`.

	`mui` resolves this by name through `mui.Contract` and `mui.macros.Bind`,
	which is why nothing in `mui` mentions `wui`. Moved here, unchanged, from the
	`#if (mui_backend == "wui")` branch it used to live in.
**/
class ZStack extends wui.ui.ZStack {
    public function new(content:Array<wui.View>) {
        super(content);
    }
}
