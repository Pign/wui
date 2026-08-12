package wui.ui;

import wui.View;

/**
	A rectangle of colour, sized or stretched.

	WinUI has no divider and no spacer, and both are this: a `Border` given a
	thickness and a brush is a rule, and one given room to grow is a gap. They
	are separate types in `mui`'s vocabulary because that is what an application
	means; they are one control here because that is what Windows draws.

	Extends `View`, not `Control`. A WinRT `Border` is a `FrameworkElement` and
	has no `IsEnabled` -- annotating it as a control made the generated C++ ask
	for one, and MSBuild said so: "'IsEnabled': is not a member of ... Border".
	`Stack` sits at the same level for the same reason.
**/
@:winuiType("Border")
@:build(wui.macros.ControlBuilder.build())
class Border extends View {
	@:winrt("Background") public var background:Null<String>;
	@:winrt("BorderBrush") public var borderBrush:Null<String>;
	@:winrt("BorderThickness") public var borderThickness:Null<Float>;
	@:winrt("CornerRadius") public var cornerRadius:Null<Float>;
	@:winrt("Padding") public var padding:Null<Float>;

	public function new(?viewType:String, ?children:Array<View>) {
		super(viewType == null ? "Border" : viewType, children);
	}
}
