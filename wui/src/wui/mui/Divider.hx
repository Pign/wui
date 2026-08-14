package wui.mui;


/**
	`wui`'s conformance for `mui.ui.Divider`.

	`mui` resolves this by name through `mui.Contract` and `mui.macros.Bind`,
	which is why nothing in `mui` mentions `wui`. Moved here, unchanged, from the
	`#if (mui_backend == "wui")` branch it used to live in.
**/
// WinUI has no native Divider. Emits a thin horizontal line via a
// 1px-tall view with a gray background.
@:muiSupport("built", "WinUI has no Divider: a 1px grey Border stands in")
class Divider extends wui.ui.Border {
    public function new() {
        super("Border");
        properties.set("height", 1);
        properties.set("background", "Gray");
    }
}
