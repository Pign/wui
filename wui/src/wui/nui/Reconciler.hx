package wui.nui;

import nui.Modifier;
import nui.Node;
import nui.NodeSink;
import nui.PropValue;
import wui.nui.Mounted;
import wui.nui.Schema;

/**
	Compares a new `nui.Node` tree with the mounted one and calls the sink only
	for what differs.

	This is what makes push mode worth its name. `Mount` builds; a second call
	would build a second tree. Here a re-render walks both trees together and
	emits `applyProp` for the properties that changed, `insert`/`remove` for the
	children that moved, and `destroy` for what left — leaving every untouched
	control exactly as it is, with its focus, its caret and its scroll position.

	## Why keys matter, concretely

	Without a key, identity is positional: the third child stays the third child.
	Insert a row at the top of a list and every control below it is now matched
	against a different node — same type, different content — so each is
	*reused with new properties*. That is cheap and correct for text, and
	**wrong for anything the user is interacting with**: the text box they are
	typing in silently becomes a different one.

	With a key, the reconciler matches by identity and *moves* the control
	instead. `nui.Node` says to set one on anything interactive; this is the
	code that makes that advice pay.

	## What this cannot do, and why

	**A property that disappears is not unset.** The contract has `applyProp` but
	no `clearProp`, so a node that stops carrying `text` leaves the old text in
	place. Reporting it here would be noise on every render; the honest fix is a
	contract change, and that decision belongs with two adopters at the table,
	not with this file. `qui` has the same hole.
**/
class Reconciler<Native> {
	final sink:NodeSink<Native>;

	public function new(sink:NodeSink<Native>) {
		this.sink = sink;
	}

	/**
		Mount `node` under `parent`, or reconcile it against `prev`.

		Returns the mounted tree to keep for next time.
	**/
	public function reconcile(prev:Null<Mounted<Native>>, node:Node, parent:Native, index:Int = -1):Mounted<Native> {
		if (node == null) {
			if (prev != null) unmount(prev, parent);
			return null;
		}

		// Nothing there yet, or something incompatible: build.
		//
		// Type or key changing means it is a different thing, not the same thing
		// with new values — reusing the control would put a Button's properties
		// on a TextBox.
		if (prev == null || prev.node.type != node.type || prev.node.key != node.key) {
			if (prev != null) unmount(prev, parent);
			return mount(node, parent, index);
		}

		var mounted = new Mounted(node, prev.handle);

		applyChangedProps(prev.node, node, prev.handle);
		applyChangedModifiers(prev.node, node, prev.handle);

		// A deferred list is re-established rather than diffed here: the new node
		// carries a **new** thunk, closing over whatever the app just read, and
		// the old effect is subscribed to the old one.
		if (prev.effect != null) prev.effect.dispose();

		if (node.childrenThunk != null) {
			mounted.children = prev.children;
			installListEffect(mounted, node);
		} else {
			mounted.children = reconcileList(prev.children, node.children == null ? [] : node.children, prev.handle);
		}

		return mounted;
	}

	/** Build a node and everything under it. **/
	function mount(node:Node, parent:Null<Native>, index:Int):Mounted<Native> {
		var handle = sink.create(node, parent);
		var mounted = new Mounted(node, handle);

		for (key in node.props.keys()) {
			sink.applyProp(handle, node.type, key, node.props.get(key));
		}
		sink.applyModifiers(handle, node.type, node.modifiers);

		if (node.childrenThunk != null) {
			// Mounting the list is the effect's first run, so it happens here and
			// then again by itself whenever the data it read changes.
			installListEffect(mounted, node);
		} else {
			for (child in (node.children == null ? [] : node.children)) {
				mounted.children.push(mount(child, handle, -1));
			}
		}

		if (parent != null) sink.insert(parent, handle, index);
		return mounted;
	}

	/**
		Give a node with deferred children an effect that owns them.

		This is the whole of N3. Without it a list still works — a full re-render
		rebuilds the tree and the diff finds the change — but the cost is
		proportional to the size of the **interface**, not of the change. With it,
		adding one row to a thousand touches that list and nothing else: the thunk
		reads the data, so the effect is subscribed to exactly what the list
		depends on, and the tree above is never walked.

		`bindReactive` does this for one **property**; this does it for one
		**list**. Same idea, one level up.
	**/
	function installListEffect(mounted:Mounted<Native>, node:Node):Void {
		mounted.effect = new rui.Signal.Effect(function() {
			var children = node.childrenThunk();
			mounted.children = reconcileList(mounted.children, children == null ? [] : children, mounted.handle);
		});
	}

	/** Take a subtree off screen and release it. **/
	function unmount(mounted:Mounted<Native>, parent:Native):Void {
		if (parent != null) sink.remove(parent, mounted.handle);
		destroyDeep(mounted);
	}

	function destroyDeep(mounted:Mounted<Native>):Void {
		// The effect goes first. It is subscribed to signals that outlive this
		// subtree, and a write to one of them would otherwise re-reconcile a list
		// whose handles have just been freed.
		if (mounted.effect != null) {
			mounted.effect.dispose();
			mounted.effect = null;
		}

		// Children next: a parent that frees its handle before its children are
		// released leaves them named by a handle nobody can reach.
		for (child in mounted.children) destroyDeep(child);
		sink.destroy(mounted.handle);
	}

	/** Only the properties whose resolved value differs. **/
	function applyChangedProps(before:Node, after:Node, handle:Native):Void {
		for (key in after.props.keys()) {
			var old = before.props.exists(key) ? before.props.get(key) : null;
			var now = after.props.get(key);

			// A reactive property is re-applied even when it looks equal: its
			// value is a thunk, and `equals` compares what the thunk returned
			// *now*, not whether the binding should be re-established.
			if (!PropValueTools.equals(old, now)) {
				sink.applyProp(handle, after.type, key, now);
			}
		}

		// A property that disappeared.
		//
		// **This is why the contract needs no `clearProp`.** "Erase this
		// property" is not well defined — erase a colour to what? — so the
		// schema declares what absence *means*, and absence becomes an ordinary
		// application of that value. Six operations, not seven.
		//
		// A property with no declared default is left alone rather than guessed
		// at: leaving the old value is wrong, but inventing one is wrong in a
		// way that is harder to notice.
		for (key in before.props.keys()) {
			if (after.props.exists(key)) continue;

			var fallback = Schema.whenAbsent(after.type, key);
			if (fallback != null) {
				sink.applyProp(handle, after.type, key, fallback);
			}
		}
	}

	/**
		Re-apply the whole chain when it changed at all.

		The chain is ordered and a modifier is not addressable — there is no
		`removeModifier` — so a partial update is not expressible. Comparing
		first at least keeps an unchanged chain from being re-applied on every
		render.
	**/
	function applyChangedModifiers(before:Node, after:Node, handle:Native):Void {
		if (!sameModifiers(before.modifiers, after.modifiers)) {
			sink.applyModifiers(handle, after.type, after.modifiers);
		}
	}

	static function sameModifiers(a:Array<Modifier>, b:Array<Modifier>):Bool {
		if (a == null || b == null) return a == b;
		if (a.length != b.length) return false;

		for (i in 0...a.length) {
			if (a[i].type != b[i].type) return false;
			if (!sameFloats(a[i].floats, b[i].floats)) return false;
			if (!sameStrings(a[i].strings, b[i].strings)) return false;
		}
		return true;
	}

	static function sameFloats(a:Null<Array<Float>>, b:Null<Array<Float>>):Bool {
		if (a == null || b == null) return a == b;
		if (a.length != b.length) return false;
		for (i in 0...a.length) if (a[i] != b[i]) return false;
		return true;
	}

	static function sameStrings(a:Null<Array<String>>, b:Null<Array<String>>):Bool {
		if (a == null || b == null) return a == b;
		if (a.length != b.length) return false;
		for (i in 0...a.length) if (a[i] != b[i]) return false;
		return true;
	}

	/**
		Match children by key where there is one, by position otherwise.

		A keyed child that moved is *moved*, not rebuilt: removed from the parent
		and re-inserted at its new index, keeping the control and everything the
		user put into it.
	**/
	function reconcileList(oldChildren:Array<Mounted<Native>>, newChildren:Array<Node>, handle:Native):Array<Mounted<Native>> {
		var result:Array<Mounted<Native>> = [];

		// Index the keyed survivors so a move can find them.
		var byKey = new Map<String, Mounted<Native>>();
		for (m in oldChildren) {
			if (m.node.key != null) byKey.set(m.node.key, m);
		}

		var used = new Map<Mounted<Native>, Bool>();

		for (i in 0...newChildren.length) {
			var childNode = newChildren[i];
			var match:Mounted<Native> = null;

			if (childNode.key != null) {
				match = byKey.get(childNode.key);
			} else if (i < oldChildren.length && oldChildren[i].node.key == null) {
				// Positional identity, and only against another unkeyed child:
				// matching a keyed one positionally would undo the point of keys.
				match = oldChildren[i];
			}

			if (match != null) used.set(match, true);

			var wasAt = match == null ? -1 : oldChildren.indexOf(match);
			var mounted = reconcile(match, childNode, handle, i);

			// A survivor that changed place has to be told: the sink applied
			// properties, but nothing moved the control.
			if (match != null && wasAt != i && mounted.handle == match.handle) {
				sink.remove(handle, mounted.handle);
				sink.insert(handle, mounted.handle, i);
			}

			result.push(mounted);
		}

		for (m in oldChildren) {
			if (!used.exists(m)) unmount(m, handle);
		}

		return result;
	}

}
