package wui.ui;

import wui.View;
import wui.state.StateAction;

/**
 * A clickable button. Maps to WinUI Button.
 *
 * Usage:
 *   new Button("Click me", null, count.inc(1))
 *   new Button("Submit", myIcon, submitAction)
 */
class Button extends View {
    public function new(label:String, ?icon:Dynamic, ?action:StateAction) {
        super("Button");
        properties.set("label", label);
        if (icon != null) properties.set("icon", icon);
        if (action != null) properties.set("action", action);
    }

    /** Set a callback function instead of a StateAction. */
    public function onClick(callback:() -> Void):Button {
        properties.set("onClick", callback);
        return cast this;
    }
}
