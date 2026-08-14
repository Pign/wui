package wui.mui;


/**
	`wui`'s conformance for `mui.ui.TextInputBinding`.

	`mui` resolves this by name through `mui.Contract` and `mui.macros.Bind`,
	which is why nothing in `mui` mentions `wui`. Moved here, unchanged, from the
	`#if (mui_backend == "wui")` branch it used to live in.
**/
abstract TextInputBinding(wui.state.State<String>) {
    public inline function new(v:wui.state.State<String>) this = v;

    @:from static inline function fromState(s:wui.state.State<String>):TextInputBinding
        return new TextInputBinding(s);

    public inline function unwrap():wui.state.State<String> return this;
}
