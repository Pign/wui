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

    // --- Every property, declared ---
    //
    // These were fluent methods pushing onto a chain that nothing read at
    // runtime, and that the generator reconstructed from the typed AST. They
    // are vars now: the vocabulary derives them, the markup can check them, the
    // generator emits them from the same declaration, and there is one shape
    // per concept.
    //
    // `@:winrt` carries the only thing a Haxe type cannot say -- that `padding`
    // reaches WinUI as `Padding`.

    @:winrt("Padding") public var padding:Null<Float>;
    @:winrt("Margin") public var margin:Null<Float>;
    @:winrt("Opacity") public var opacity:Float = 1;
    @:winrt("CornerRadius") public var cornerRadius:Null<Float>;
    @:winrt("BorderThickness") public var borderThickness:Null<Float>;

    @:winrt("Style") public var font:Null<String>;
    @:winrt("FontSize") public var fontSize:Null<Float>;

    // Colours cross as names. An unknown one leaves the control its own rather
    // than a guessed approximation -- the call `cui` made in B5.
    @:winrt("Foreground") public var foregroundColor:Null<String>;
    @:winrt("Background") public var background:Null<String>;
    @:winrt("BorderBrush") public var borderBrush:Null<String>;

    @:winrt("HorizontalAlignment") public var horizontalAlignment:Null<String>;
    @:winrt("VerticalAlignment") public var verticalAlignment:Null<String>;
}
