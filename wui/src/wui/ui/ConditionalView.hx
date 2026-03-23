package wui.ui;

import wui.View;

/**
 * Shows or hides content based on a condition.
 *
 * Usage:
 *   new ConditionalView(isLoggedIn, loggedInView, loginView)
 */
class ConditionalView extends View {
    public function new(condition:Dynamic, thenView:View, ?elseView:View) {
        super("ConditionalView");
        properties.set("condition", condition);
        properties.set("thenView", thenView);
        if (elseView != null) properties.set("elseView", elseView);
    }
}
