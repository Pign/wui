package wui.ui;

import wui.View;

/**
 * A modal dialog. Maps to WinUI ContentDialog.
 *
 * Usage:
 *   new ContentDialog("Confirm", "Are you sure?", "Yes", "No")
 */
class ContentDialog extends View {
    public function new(title:String, content:Dynamic, ?primaryButton:String, ?secondaryButton:String, ?closeButton:String) {
        super("ContentDialog");
        properties.set("title", title);
        properties.set("content", content);
        if (primaryButton != null) properties.set("primaryButton", primaryButton);
        if (secondaryButton != null) properties.set("secondaryButton", secondaryButton);
        if (closeButton != null) properties.set("closeButton", closeButton);
    }
}
