package wui.mui;


/**
	`wui`'s conformance for `mui.ui.SliderBinding`.

	`mui` resolves this by name through `mui.Contract` and `mui.macros.Bind`,
	which is why nothing in `mui` mentions `wui`. Moved here, unchanged, from the
	`#if (mui_backend == "wui")` branch it used to live in.
**/
abstract SliderBinding(wui.state.State<Float>) {
    public inline function new(v:wui.state.State<Float>) this = v;

    @:from static inline function fromState(s:wui.state.State<Float>):SliderBinding
        return new SliderBinding(s);

    public inline function unwrap():wui.state.State<Float> return this;
}
