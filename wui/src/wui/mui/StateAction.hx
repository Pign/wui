package wui.mui;

/**
	`wui`'s conformance for `mui.state.StateAction`.

	Moved here from the `#if (mui_backend == "wui")` branch it used to live in.
	`mui` resolves it by name through `mui.Contract`, and lists it as optional
	because the six backends genuinely disagree about which of these exist.
**/
typedef StateAction = wui.state.StateAction;
