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

	public function new(node:Node, handle:Native) {
		this.node = node;
		this.handle = handle;
		this.children = [];
	}
}
