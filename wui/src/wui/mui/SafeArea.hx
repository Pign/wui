package wui.mui;


/**
	`wui`'s conformance for `mui.ui.SafeArea`.

	`mui` resolves this by name through `mui.Contract` and `mui.macros.Bind`,
	which is why nothing in `mui` mentions `wui`. Moved here, unchanged, from the
	`#if (mui_backend == "wui")` branch it used to live in.
**/
@:muiSupport("none", "a desktop window has no safe area")
class SafeArea extends wui.ui.VStack {
    public function new(content:Array<wui.View>) {
        super(content);
        // WinUI's page inset. A desktop window has no notch to avoid, but it
        // does have an expected margin, and without one the kitchen sink drew
        // its first character in the very corner of the window.
        padding = 24;
    }

    public function safeArea():wui.View {
        return this;
    }
}
