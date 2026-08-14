package wui.mui;


/**
	`wui`'s conformance for `mui.ui.Slider`.

	`mui` resolves this by name through `mui.Contract` and `mui.macros.Bind`,
	which is why nothing in `mui` mentions `wui`. Moved here, unchanged, from the
	`#if (mui_backend == "wui")` branch it used to live in.
**/
class Slider extends wui.ui.Slider {
    public function new(state:SliderBinding, min:Float = 0.0, max:Float = 1.0) {
        super(min, max, state.unwrap());
    }
}
