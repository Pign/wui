package wui.nui;

import nui.Node;

/**
	A node that is currently on screen: the tree kept between renders.

	The reconciler needs the *previous* tree to compare against, and a `Node` on
	its own does not remember which control it produced. This pairs the two.
**/
class Mounted<Native> {
	public var node:Node;
	public var handle:Native;
	public var children:Array<Mounted<Native>>;

	/**
		The effect that owns this node's children, when it has a `childrenThunk`.

		A list with a thunk re-evaluates **itself** when its data changes, without
		the tree above it being walked. That effect has to be disposed when the
		node goes away, or it keeps firing against a handle that no longer names
		anything.
	**/
	public var effect:Null<rui.Signal.Effect>;

	public function new(node:Node, handle:Native) {
		this.node = node;
		this.handle = handle;
		this.children = [];
		this.effect = null;
	}
}
