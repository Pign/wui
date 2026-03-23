package wui.ui;

import wui.View;

/**
 * A slider control for numeric ranges. Maps to WinUI Slider.
 *
 * Usage:
 *   new Slider(0, 100, volumeState)
 */
class Slider extends View {
    public function new(min:Float, max:Float, ?binding:Dynamic, ?step:Float) {
        super("Slider");
        properties.set("min", min);
        properties.set("max", max);
        if (binding != null) properties.set("binding", binding);
        if (step != null) properties.set("step", step);
    }
}
