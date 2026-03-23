package wui.ui;

import wui.View;

/**
 * A circular progress indicator. Maps to WinUI ProgressRing.
 *
 * Usage:
 *   new ProgressRing()           // indeterminate
 *   new ProgressRing(0.5)        // 50% progress
 */
class ProgressRing extends View {
    public function new(?value:Float) {
        super("ProgressRing");
        if (value != null) {
            properties.set("value", value);
            properties.set("isIndeterminate", false);
        } else {
            properties.set("isIndeterminate", true);
        }
    }
}
