package wui.ui;

import wui.View;

/**
	What a stack has beyond a plain view.

	`spacing` lives here rather than on `View` because it means nothing on a
	`Text`. It used to be a **modifier** pushed by `View.spacing(8)`, while
	`new VStack(children, 8)` set a *property* for the same thing — two
	mechanisms, and the node path only ever knew the property.

	## A property is a var; a modifier is a fluent method

	It is a `var`, not a fluent setter. Keeping it a method preserved three call
	sites and cost a rule: the vocabulary would have had to read declarations two
	ways, and the generator carried a special case for it. One shape per concept
	is worth more than `.spacing(8)`, which the constructor argument and the
	markup both express already.

	## The default is declared, not applied

	`= 0` says what an absent `spacing` means — which is how the push contract
	avoids needing a `clearProp`. It is read at compile time and deliberately
	**not** emitted as a constructor assignment: a stack that always carried
	`spacing` in its properties would make absence indistinguishable from an
	explicit zero, and the case would never arise.
**/
@:build(wui.macros.ControlBuilder.build())
class Stack extends View {
	@:winrt("Spacing")
	public var spacing:Float = 0;

	public function new(?viewType:String, ?children:Array<View>) {
		super(viewType, children);
	}
}
