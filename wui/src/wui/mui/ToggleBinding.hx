package wui.mui;


/**
	`wui`'s conformance for `mui.ui.ToggleBinding`.

	`mui` resolves this by name through `mui.Contract` and `mui.macros.Bind`,
	which is why nothing in `mui` mentions `wui`. Moved here, unchanged, from the
	`#if (mui_backend == "wui")` branch it used to live in.
**/
abstract ToggleBinding(wui.state.State<Bool>) {
    public inline function new(v:wui.state.State<Bool>) this = v;

    @:from static inline function fromState(s:wui.state.State<Bool>):ToggleBinding
        return new ToggleBinding(s);

    public inline function unwrap():wui.state.State<Bool> return this;
}
