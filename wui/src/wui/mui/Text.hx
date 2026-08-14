package wui.mui;

import mui.ui.TextScale;

/**
	`wui`'s conformance for `mui.ui.Text`.

	`mui` resolves this by name through `mui.Contract` and `mui.macros.Bind`,
	which is why nothing in `mui` mentions `wui`. Moved here, unchanged, from the
	`#if (mui_backend == "wui")` branch it used to live in.
**/
class Text extends wui.ui.Text {
    public function new(content:String, ?scale:TextScale) {
        super(content);
        if (scale != null) this.font = switch (scale) {
            case Title: "Title";
            case Subtitle: "Subtitle";
            // WinUI's step table has no Body: it is the size a TextBlock takes
            // when nothing is said, and naming it keeps the four symmetrical.
            case Body: "Body";
            case Caption: "Caption";
        };
    }
}
