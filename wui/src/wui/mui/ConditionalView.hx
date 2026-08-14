package wui.mui;


/**
	`wui`'s conformance for `mui.ui.ConditionalView`.

	`mui` resolves this by name through `mui.Contract` and `mui.macros.Bind`,
	which is why nothing in `mui` mentions `wui`. Moved here, unchanged, from the
	`#if (mui_backend == "wui")` branch it used to live in.
**/
class ConditionalView extends wui.ui.ConditionalView {
    public function new(condition:wui.state.State<Bool>, thenView:wui.View, ?elseView:wui.View) {
        super(condition, thenView, elseView);
    }
}
