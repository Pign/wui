package wui.ui;

import wui.View;

/**
	What a stack has beyond a plain view.

	`spacing` lives here rather than on `View` because it means nothing on a
	`Text`. It used to sit on `View` as a **modifier** — `.spacing(8)` pushed
	onto the modifier chain — while `new VStack(children, 8)` set a *property*
	for the same thing. Two mechanisms, and the node path only ever knew about
	the property.

	It is a property now, set by a fluent method so the existing call sites keep
	working. The `@:winrt` annotation is what makes the method a **declaration**:
	the vocabulary reads it, and the generator sets the property instead of
	guessing at a modifier.
**/
@:build(wui.macros.ControlBuilder.build())
class Stack extends View {
	public function new(?viewType:String, ?children:Array<View>) {
		super(viewType, children);
	}

	/** Space between children. Fluent, and it sets the property. **/
	@:winrt("Spacing")
	public function spacing(s:Float):Stack {
		properties.set("spacing", s);
		return this;
	}
}
