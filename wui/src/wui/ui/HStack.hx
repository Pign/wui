package wui.ui;

import wui.View;

/**
 * Horizontal stack layout. Maps to WinUI StackPanel with Horizontal orientation.
 *
 * Usage:
 *   new HStack([
 *       new Text("Left"),
 *       new Spacer(),
 *       new Text("Right")
 *   ])
 */
@:winuiType("Grid")
@:build(wui.macros.ControlBuilder.build())
class HStack extends View {
	// A Grid, not a StackPanel, and not because a Grid is fancier.
	//
	// A StackPanel distributes nothing: it hands every child the size that
	// child asks for and lays them end to end. So a `Spacer` between two labels
	// -- an empty Border, asking for nothing -- came out zero wide, and a row
	// written as "left, spacer, middle, spacer, right" drew "leftmiddleright".
	// There is no property that fixes this; the panel has no leftover room to
	// give away because it never claimed any.
	//
	// A Grid does. Each child gets a column, sized `Auto` for real content and
	// `*` for a spacer, so the spacers share whatever is left. That is WinUI's
	// answer to the question a spacer asks, and `wui_node_insert` builds the
	// columns as the children arrive.
	@:winrt("ColumnSpacing") public var spacing:Float = 0;

	// Declared here rather than inherited from `Stack`: these are the ones a
	// Grid actually has. `Spacing` is not among them -- it is a StackPanel
	// member, and asking a Grid for it does not compile, which is the sort of
	// thing worth finding out from MSVC rather than from a blank row.
	@:winrt("Padding") public var padding:Null<Float>;
	@:winrt("Background") public var background:Null<String>;
	@:winrt("BorderBrush") public var borderBrush:Null<String>;
	@:winrt("BorderThickness") public var borderThickness:Null<Float>;
	@:winrt("CornerRadius") public var cornerRadius:Null<Float>;

	/**
		What kind of Grid this is, for code that only sees a control.

		`wui_node_insert` receives a handle, not a node type, and a `ZStack` is
		a Grid too -- one whose children are meant to overlap, not to queue up
		in columns. The tag is how the two are told apart at the moment a child
		arrives.
	**/
	@:winrt("Tag") public var kind:String = "row";

    public function new(children:Array<View>, ?spacing:Float) {
        // The class name, not the WinRT type -- see `VStack`, which explains
        // what the two stacks sharing one name cost.
        super("HStack", children);
        if (spacing != null) this.spacing = spacing;
    }
}
