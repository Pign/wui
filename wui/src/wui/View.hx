package wui;


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

	They are all vars now, declared on the class whose WinRT type actually has
	them -- which is what lets the generator emit against the concrete control
	and let MSVC check membership.
**/
@:build(wui.macros.ControlBuilder.build())
class View {
    public var viewType:String;
    public var children:Array<View>;
    public var properties:Map<String, Dynamic>;

    public function new(?viewType:String, ?children:Array<View>) {
        this.viewType = viewType != null ? viewType : "View";
        this.children = children != null ? children : [];
        this.properties = new Map();
    }

    // --- What every element really has ---
    //
    // These are `UIElement` and `FrameworkElement` members, so every control
    // carries them. Anything narrower is declared on the class that has it:
    // `IsEnabled` is a `Control` member and a StackPanel is not a Control, so
    // putting it here would emit code MSVC rejects.
    //
    // That is the point of dropping the owner table. It said which WinRT type
    // declared each member -- a fourth hand-kept copy of the truth, and already
    // wrong about Panel. Emitting against the concrete control instead lets the
    // C++ compiler answer, and it knows.

    @:winrt("Width") public var width:Null<Float>;
    @:winrt("Height") public var height:Null<Float>;
    @:winrt("Margin") public var margin:Null<Float>;
    @:winrt("Opacity") public var opacity:Float = 1;
    @:winrt("Visibility") public var visible:Bool = true;
    @:winrt("HorizontalAlignment") public var horizontalAlignment:Null<String>;
    @:winrt("VerticalAlignment") public var verticalAlignment:Null<String>;
}
