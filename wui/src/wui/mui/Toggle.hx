package wui.mui;


/**
	`wui`'s conformance for `mui.ui.Toggle`.

	`mui` resolves this by name through `mui.Contract` and `mui.macros.Bind`,
	which is why nothing in `mui` mentions `wui`. Moved here, unchanged, from the
	`#if (mui_backend == "wui")` branch it used to live in.
**/
class Toggle extends wui.ui.ToggleSwitch {
    public function new(label:String, state:ToggleBinding) {
        super(label, state.unwrap());
    }
}
