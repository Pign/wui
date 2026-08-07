package wui.nui;

import nui.Node;

/**
	Builds a node whose type `wui` is not expected to know.

	## Why an escape hatch is not a loophole

	`?TypeName` on screen answers two different situations, and only one of them
	is legitimate:

	- **A tree that arrived as data** — over a protocol, from a devtool, from
	  another backend. Nothing can be checked at compile time, and rendering
	  `?TypeName` is the honest degradation.
	- **A tree written here, in Haxe, and compiled.** An unknown type there is a
	  mistake in the source, and turning it into a visual artefact means finding
	  it late, or never.

	The macro refuses the second. Without a way to say *"I know this one is
	foreign"*, it would also make the first impossible to write — a test that
	feeds a deliberately unknown type, or code that forwards a tree it did not
	author.

	## How it works, and why nothing clever is needed

	The validator only inspects `new Node("literal")`. Here the type arrives as a
	**parameter**, so it is dynamic by construction and simply never matched.
	The escape hatch is the honest boundary of what static checking can see,
	rather than a flag that switches it off.

	```haxe
	// refused at compile time: a literal type wui cannot build
	new Node("Hologramme");

	// accepted: this says the type is not ours to know
	Foreign.node("Hologramme");
	```
**/
class Foreign {
	/** A node of a type this backend is not expected to render. **/
	public static function node(type:String, ?key:String):Node {
		return new Node(type, key);
	}
}
