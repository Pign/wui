package wui.ui;

import wui.View;

/**
	Read-only text.

	## One declaration

	The fields below are the only place this control's properties are named.
	`Vocabulary` reads them at compile time, the generated C++ node runtime is
	emitted from them, and `@:winrt` says which WinRT call applies each one —
	the one thing a Haxe type cannot express (`Text` does not follow from
	`text`).

	## Two names, on purpose and for now

	`@:node` is the **nui** type name; `super()` passes the **transpiled path's**,
	which is WinUI's own (`TextBlock`). The two rendering paths grew separate
	vocabularies, and rather than pretend otherwise the divergence is stated
	here, in one place, until the transpiled path is retired or aligned.
**/
@:node("Text")
@:build(wui.macros.ControlBuilder.build())
class Text extends View {
	@:winrt("Text")
	public var text:String;

	public function new(content:Dynamic) {
		super("TextBlock");
		this.text = Std.string(content);
	}
}
