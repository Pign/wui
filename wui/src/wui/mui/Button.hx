package wui.mui;


/**
	`wui`'s conformance for `mui.ui.Button`.

	`mui` resolves this by name through `mui.Contract` and `mui.macros.Bind`,
	which is why nothing in `mui` mentions `wui`. Moved here, unchanged, from the
	`#if (mui_backend == "wui")` branch it used to live in.
**/
class Button extends wui.ui.Button {
    public function new(label:String, ?action:() -> Void) {
        super(label);
        // The property, not the field of the same name. `wui.ui.Button` has
        // both a `public var onClick` and a generator that reads `.onClick(fn)`
        // call syntax, but what the push bridge consumes is
        // `properties.get("onClick")` -- so that is where a closure has to land
        // to be reachable. Calling the field did not even compile.
        if (action != null) properties.set("onClick", action);
    }
}
