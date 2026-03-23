package wui;

import wui.modifiers.ViewModifier;

/**
 * Base class for all WUI view elements.
 * Views form a tree structure and carry modifier chains
 * that are translated to C++/WinRT properties during code generation.
 */
class View {
    public var viewType:String;
    public var children:Array<View>;
    public var modifierChain:Array<ViewModifier>;
    public var properties:Map<String, Dynamic>;

    public function new(?viewType:String, ?children:Array<View>) {
        this.viewType = viewType != null ? viewType : "View";
        this.children = children != null ? children : [];
        this.modifierChain = [];
        this.properties = new Map();
    }

    // --- Layout Modifiers ---

    public function padding(?amount:Float):View {
        modifierChain.push(Padding(amount != null ? amount : 12.0));
        return this;
    }

    public function margin(?amount:Float):View {
        modifierChain.push(Margin(amount != null ? amount : 12.0));
        return this;
    }

    public function frame(?width:Float, ?height:Float, ?minWidth:Float, ?maxWidth:Float, ?minHeight:Float, ?maxHeight:Float):View {
        modifierChain.push(Frame(width, height, minWidth, maxWidth, minHeight, maxHeight));
        return this;
    }

    public function width(w:Float):View {
        modifierChain.push(Width(w));
        return this;
    }

    public function height(h:Float):View {
        modifierChain.push(Height(h));
        return this;
    }

    public function horizontalAlignment(align:HorizontalAlign):View {
        modifierChain.push(HorizontalAlignment(align));
        return this;
    }

    public function verticalAlignment(align:VerticalAlign):View {
        modifierChain.push(VerticalAlignment(align));
        return this;
    }

    public function spacing(s:Float):View {
        modifierChain.push(Spacing(s));
        return this;
    }

    // --- Typography Modifiers ---

    public function font(style:FontStyle):View {
        modifierChain.push(Font(style));
        return this;
    }

    public function fontSize(size:Float):View {
        modifierChain.push(FontSize(size));
        return this;
    }

    public function bold():View {
        modifierChain.push(Bold);
        return this;
    }

    public function italic():View {
        modifierChain.push(Italic);
        return this;
    }

    // --- Color Modifiers ---

    public function foregroundColor(color:ColorValue):View {
        modifierChain.push(ForegroundColor(color));
        return this;
    }

    public function background(color:ColorValue):View {
        modifierChain.push(Background(color));
        return this;
    }

    public function opacity(value:Float):View {
        modifierChain.push(Opacity(value));
        return this;
    }

    // --- Shape Modifiers ---

    public function cornerRadius(radius:Float):View {
        modifierChain.push(CornerRadius(radius));
        return this;
    }

    public function borderBrush(color:ColorValue):View {
        modifierChain.push(BorderBrush(color));
        return this;
    }

    public function borderThickness(thickness:Float):View {
        modifierChain.push(BorderThickness(thickness));
        return this;
    }

    // --- Interaction Modifiers ---

    public function disabled(isDisabled:Bool = true):View {
        modifierChain.push(Disabled(isDisabled));
        return this;
    }

    public function visible(isVisible:Bool = true):View {
        modifierChain.push(Visible(isVisible));
        return this;
    }

    public function toolTip(text:String):View {
        modifierChain.push(ToolTip(text));
        return this;
    }

    // --- Lifecycle Modifiers ---

    public function onLoaded(callback:() -> Void):View {
        modifierChain.push(OnLoaded(callback));
        return this;
    }
}
