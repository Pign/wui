package wui.ui;

import wui.View;

/**
 * A flexible spacer that expands to fill available space.
 * In a VStack/HStack, it pushes siblings apart.
 */
class Spacer extends View {
    public function new(?minSize:Float) {
        super("Spacer");
        if (minSize != null) properties.set("minSize", minSize);
    }
}
