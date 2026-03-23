package wui.modifiers;

/**
 * All supported view modifiers, mapped to WinUI 3 C++/WinRT properties.
 */
enum ViewModifier {
    // Layout
    Padding(amount:Float);
    Margin(amount:Float);
    Frame(width:Null<Float>, height:Null<Float>, minWidth:Null<Float>, maxWidth:Null<Float>, minHeight:Null<Float>, maxHeight:Null<Float>);
    Width(w:Float);
    Height(h:Float);
    HorizontalAlignment(align:HorizontalAlign);
    VerticalAlignment(align:VerticalAlign);
    Spacing(s:Float);

    // Typography
    Font(style:FontStyle);
    FontSize(size:Float);
    Bold;
    Italic;

    // Colors
    ForegroundColor(color:ColorValue);
    Background(color:ColorValue);
    Opacity(value:Float);

    // Shapes / Borders
    CornerRadius(radius:Float);
    BorderBrush(color:ColorValue);
    BorderThickness(thickness:Float);

    // Interaction
    Disabled(isDisabled:Bool);
    Visible(isVisible:Bool);
    ToolTip(text:String);

    // Lifecycle
    OnLoaded(callback:() -> Void);
}

enum HorizontalAlign {
    Left;
    Center;
    Right;
    Stretch;
}

enum VerticalAlign {
    Top;
    Center;
    Bottom;
    Stretch;
}

enum FontStyle {
    Caption;
    Body;
    BodyStrong;
    Subtitle;
    Title;
    TitleLarge;
    Display;
}

enum ColorValue {
    // Named colors
    Black;
    White;
    Red;
    Green;
    Blue;
    Yellow;
    Orange;
    Purple;
    Gray;
    Transparent;

    // System accent colors
    AccentColor;
    AccentColorLight1;
    AccentColorLight2;
    AccentColorDark1;
    AccentColorDark2;

    // Custom RGB / ARGB
    Rgb(r:Int, g:Int, b:Int);
    Argb(a:Int, r:Int, g:Int, b:Int);

    // Hex string
    Hex(hex:String);
}
