package wui;

import wui.modifiers.ViewModifier;

/**
	Base class for every wui view.

	## Properties every element has

	`Width`, `Height`, `Visibility` and `IsEnabled` are ordinary WinRT properties
	of any `FrameworkElement`, so they are declared here as vars and the
	vocabulary derives them like any other. They used to be fluent methods
	pushing onto a modifier chain, and the vocabulary had to name them in a
	hand-written `UNIVERSAL` table — the last hand-written list, now gone.

	They had **no call sites**: the fluent forms existed for symmetry with
	`padding`, which is the only modifier the examples actually use.

	## The modifier chain is gone from the runtime

	`modifierChain` was only ever read by this class. The generator does not use
	it: it recognises `.padding()` in the **typed AST** and emits the WinRT call
	itself. Keeping an unread list on every view was a second model for something
	that is, in WinUI, just properties — `Padding` and `Margin` are setters like
	any other.

	The style methods below still route through that macro-side extraction, so
	they stay for now. Finishing the job needs a way to say *this method sets
	that declared property*, and 19 `.padding()` call sites to move; doing it
	half-way would put back the ambiguity that was just removed.
**/
@:build(wui.macros.ControlBuilder.build())
class View {
    public var viewType:String;
    public var children:Array<View>;
    public var properties:Map<String, Dynamic>;

    @:winrt("Width") public var width:Null<Float>;
    @:winrt("Height") public var height:Null<Float>;
    @:winrt("Visibility") public var visible:Bool = true;
    @:winrt("IsEnabled") public var enabled:Bool = true;

    public function new(?viewType:String, ?children:Array<View>) {
        this.viewType = viewType != null ? viewType : "View";
        this.children = children != null ? children : [];
        this.properties = new Map();
    }

    // --- Layout Modifiers ---

    public function padding(?amount:Float):View {
        // Read from the typed AST by WinUIGenerator, not stored here.
        return this;
    }

    public function margin(?amount:Float):View {
        // Read from the typed AST by WinUIGenerator, not stored here.
        return this;
    }

    public function frame(?width:Float, ?height:Float, ?minWidth:Float, ?maxWidth:Float, ?minHeight:Float, ?maxHeight:Float):View {
        // Read from the typed AST by WinUIGenerator, not stored here.
        return this;
    }

    public function horizontalAlignment(align:HorizontalAlign):View {
        // Read from the typed AST by WinUIGenerator, not stored here.
        return this;
    }

    public function verticalAlignment(align:VerticalAlign):View {
        // Read from the typed AST by WinUIGenerator, not stored here.
        return this;
    }

    // --- Typography Modifiers ---

    public function font(style:FontStyle):View {
        // Read from the typed AST by WinUIGenerator, not stored here.
        return this;
    }

    public function fontSize(size:Float):View {
        // Read from the typed AST by WinUIGenerator, not stored here.
        return this;
    }

    public function bold():View {
        // Read from the typed AST by WinUIGenerator, not stored here.
        return this;
    }

    public function italic():View {
        // Read from the typed AST by WinUIGenerator, not stored here.
        return this;
    }

    // --- Color Modifiers ---

    public function foregroundColor(color:ColorValue):View {
        // Read from the typed AST by WinUIGenerator, not stored here.
        return this;
    }

    public function background(color:ColorValue):View {
        // Read from the typed AST by WinUIGenerator, not stored here.
        return this;
    }

    public function opacity(value:Float):View {
        // Read from the typed AST by WinUIGenerator, not stored here.
        return this;
    }

    // --- Shape Modifiers ---

    public function cornerRadius(radius:Float):View {
        // Read from the typed AST by WinUIGenerator, not stored here.
        return this;
    }

    public function borderBrush(color:ColorValue):View {
        // Read from the typed AST by WinUIGenerator, not stored here.
        return this;
    }

    public function borderThickness(thickness:Float):View {
        // Read from the typed AST by WinUIGenerator, not stored here.
        return this;
    }

    // --- Interaction Modifiers ---

    public function toolTip(text:String):View {
        // Read from the typed AST by WinUIGenerator, not stored here.
        return this;
    }

    // --- Lifecycle Modifiers ---

    public function onLoaded(callback:() -> Void):View {
        // Read from the typed AST by WinUIGenerator, not stored here.
        return this;
    }
}
