package wui.nui;

import nui.Node;
import nui.NodeSink;

/**
	Walks a `nui.Node` tree and drives a sink through it.

	The order is the contract's, not a convenience:

	1. `create` — materialise, and nothing else
	2. `applyProp` for each property
	3. `applyModifiers` for the ordered chain
	4. recurse into the children, inserting each into this node

	**Splitting create from apply is what makes `bindReactive` possible.** A
	sink that applied properties inside `create` would leave each binding
	without its own effect, and the first adopter of the contract read it that
	way and mounted a tree whose reactive property was never evaluated. The
	contract now spells it out; this driver follows it.

	## What this is not

	This mounts. It does not diff: a second call builds a second tree. Targeted
	patching — comparing against the previous tree and calling only the
	operations that differ — is the next increment, and it is what makes the
	push contract worth its name.
**/
class Mount {
	/**
		Build `node` and everything under it, inserting into `parent`.

		Returns the handle of the node created, so a caller can keep it — the
		root of a subtree it may later want to remove.
	**/
	public static function tree<Native>(sink:NodeSink<Native>, node:Node, parent:Null<Native>, index:Int = -1):Native {
		var handle = sink.create(node, parent);

		for (key in node.props.keys()) {
			sink.applyProp(handle, node.type, key, node.props.get(key));
		}

		sink.applyModifiers(handle, node.type, node.modifiers);

		// `childrenThunk` wins when set: it is how a list says its contents are
		// produced on demand rather than fixed at construction.
		var children = node.childrenThunk != null ? node.childrenThunk() : node.children;
		if (children != null) {
			for (child in children) {
				tree(sink, child, handle, -1);
			}
		}

		if (parent != null) {
			sink.insert(parent, handle, index);
		}

		return handle;
	}
}
