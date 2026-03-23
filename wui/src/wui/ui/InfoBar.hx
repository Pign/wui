package wui.ui;

import wui.View;

/**
 * An information notification bar. Maps to WinUI InfoBar.
 *
 * Usage:
 *   new InfoBar("Update available", "A new version is ready.", InfoBarSeverity.Informational)
 */
class InfoBar extends View {
    public function new(title:String, ?message:String, ?severity:InfoBarSeverity) {
        super("InfoBar");
        properties.set("title", title);
        if (message != null) properties.set("message", message);
        properties.set("severity", severity != null ? severity : Informational);
    }
}

enum InfoBarSeverity {
    Informational;
    Success;
    Warning;
    Error;
}
