package wui.mui;


/**
	`wui`'s conformance for `mui.ViewComponent`.

	`mui` resolves this by name through `mui.Contract` and `mui.macros.Bind`,
	which is why nothing in `mui` mentions `wui`. Moved here, unchanged, from the
	`#if (mui_backend == "wui")` branch it used to live in.
**/
typedef ViewComponent = wui.ViewComponent;
