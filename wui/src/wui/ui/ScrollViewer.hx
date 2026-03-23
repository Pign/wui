package wui.ui;

import wui.View;

/**
 * A scrollable container. Maps to WinUI ScrollViewer.
 *
 * Usage:
 *   new ScrollViewer(
 *       new VStack(longListOfItems)
 *   )
 */
class ScrollViewer extends View {
    public function new(content:View) {
        super("ScrollViewer", [content]);
    }
}
