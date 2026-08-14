package wui.mui;

import nui.Node;
import nui.PropValue;

/**
	Describes a `mui` view tree as `nui` nodes.

	Lives in `wui` rather than in `mui`, because it is `wui` that needs it: push
	mode is what has to be handed a node tree, and `wui` is the only backend in
	push mode. It used to sit in `mui` behind `#if (mui_backend == "wui")` — the
	last conditional there, and the one that most obviously belonged elsewhere.

	## Why this exists

	`mui` had two shapes of application, and which one you wrote depended on the
	backend you were targeting — which is the one thing a layer like this exists
	to stop being true:

	- `body():View`, built from `mui.ui.*`, on sui, aui and cui.
	- `view():nui.Node`, built from `ui()` markup, on wui alone.

	An app written the first way compiled for wui and drew an empty window: the
	push renderer asks for `nuiBody()`, and `body()` was a stub nobody called.
	The kitchen sink — one source for four backends — could not run on the
	fourth.

	So the tree is *described* rather than rewritten. A `mui.ui.Button` on wui
	already **is** a `wui.ui.Button`, carrying a type name, properties and
	children; a `nui.Node` wants exactly those. This walks one and produces the
	other, which is what `nui` is for: the shared model both halves agree on.

	Markup stays available. An app that overrides `view()` is describing nodes
	directly and this is never reached.

	## Identity

	A node's key is its **place**, unless the view carries a `nodeId`. That is
	the rule the whole ecosystem settled on — see `wui.nui.Reconciler`, which
	explains what it costs to get wrong: without a key, "the text box they are
	typing in silently becomes a different one".
**/
class FromViews {
	/** Describe a view tree, or an empty root when there is nothing to draw. **/
	public static function describe(view:wui.View):Node {
		if (view == null) return new Node("VStack");

		// Where *one* node is expected there are no siblings to become, so an
		// expansion is wrapped in the stack it would have filled.
		var expansion:Array<Node> = [];
		if (expanded(view, expansion, 0)) {
			var root = new Node("VStack", "#0");
			for (child in expansion) root.children.push(child);
			return root;
		}

		return node(view, 0);
	}

	/**
		Nodes with no rendering of their own, expanded before the sink sees them.

		A `ForEach` is a loop that yields siblings; a `ConditionalView` is the
		branch its condition picks. Neither is a control, and asking the sink for
		one would be asking for a WinRT type that does not exist. `sui` and `aui`
		expand them in their own walks for the same reason -- this is that rule,
		on the push side.
	**/
	static function expanded(view:wui.View, into:Array<Node>, index:Int):Bool {
		switch (view.viewType) {
			case "ForEach":
				for (item in loopItems(view)) into.push(node(item, into.length));
				return true;

			case "ConditionalView":
				var taken = branchOf(view);
				if (taken != null) into.push(node(taken, into.length));
				return true;

			case _:
				return false;
		}
	}

	/** The views a `ForEach` yields, or none when it cannot be run. **/
	static function loopItems(view:wui.View):Array<wui.View> {
		var out:Array<wui.View> = [];
		if (view.properties == null) return out;

		var template:Dynamic = view.properties.get("template");
		if (template == null || !Reflect.isFunction(template)) return out;

		var source:Dynamic = view.properties.get("items");
		if (Std.isOfType(source, rui.state.State)) source = (cast source : rui.state.State<Dynamic>).get();
		if (source == null || !Std.isOfType(source, Array)) return out;

		var items:Array<Dynamic> = source;
		for (item in items) {
			var built:Dynamic = Reflect.callMethod(null, template, [item]);
			if (built != null) out.push(cast built);
		}
		return out;
	}

	/**
		The branch a condition selects, or null when it cannot be read.

		Null rather than the else-branch: an unreadable condition is not `false`,
		and taking a branch on a guess puts half a screen up on one.
	**/
	static function branchOf(view:wui.View):Null<wui.View> {
		if (view.properties == null) return null;

		var condition:Dynamic = view.properties.get("condition");
		var holds:Null<Bool> = null;
		if (Std.isOfType(condition, rui.state.State)) {
			holds = (cast condition : rui.state.State<Dynamic>).get() == true;
		} else if (Std.isOfType(condition, Bool)) {
			holds = condition;
		}
		if (holds == null) return null;

		var taken:Dynamic = holds ? view.properties.get("thenView") : view.properties.get("elseView");
		return taken == null ? null : cast taken;
	}

	static function node(view:wui.View, index:Int):Node {
		var out = new Node(typeOf(view), keyOf(view, index));

		if (view.properties != null) {
			for (key in view.properties.keys()) {
				// A binding is not a value and does not describe as one. It is a
				// cell, and `bind` turns it into the two things the sink can use.
				if (key == "binding") continue;
				var value = toProp(view.properties.get(key));
				if (value != null) out.prop(key, value);
			}
			bind(out, view.properties.get("binding"));
		}

		if (view.children != null) {
			for (child in view.children) {
				if (child == null) continue;
				if (!expanded(child, out.children, out.children.length)) {
					out.children.push(node(child, out.children.length));
				}
			}
		}

		return out;
	}

	/**
		Describe a bound cell as the two halves of a two-way control.

		A `wui.ui` control stores the cell it is bound to under `binding` and
		never reads it. That was survivable on the transpiled path, which knows
		every state by name at compile time and pushes to it separately. On the
		push path it meant a control was **blind in both directions**: a switch
		bound to a cell holding `true` drew itself `Off`, and flipping it changed
		nothing in Haxe, so the line reading that cell never moved.

		Both halves are established here:

		- the cell's current value, under the property the control calls its
		  value, so a write in Haxe reaches the screen;
		- a handler under the key that control reports through, so an edit by the
		  user reaches the cell.

		Reading the cell here is what subscribes the render to it: `renderNui`
		runs this walk inside an effect, so `get()` makes the re-render happen by
		itself. That is the same rule the view layer follows everywhere else --
		a view reads observable state, and the reading is the subscription.
	**/
	static function bind(node:Node, binding:Dynamic):Void {
		if (binding == null) return;

		var valueKey = wui.nui.Bindings.valueKey(node.type);
		var changeKey = wui.nui.Bindings.changeKey(node.type);
		if (valueKey == null || changeKey == null) {
			trace('[mui] ${node.type} carries a binding, but nothing says what its value is called');
			return;
		}

		if (!Std.isOfType(binding, rui.state.State)) {
			trace('[mui] ${node.type}: a binding has to be a state cell to be observed');
			return;
		}

		var cell:rui.state.State<Dynamic> = cast binding;
		var current:Dynamic = cell.get();

		// The cell's own type decides, not the control's. A slider bound to an
		// Int must put an Int back: rounding is the binding's job here, because
		// the control only ever reports a number.
		if (Std.isOfType(current, Bool)) {
			node.prop(valueKey, PBool(current));
			node.prop(changeKey, PCallbackBool(function(v:Bool) cell.set(v)));
		} else if (Std.isOfType(current, Int)) {
			node.prop(valueKey, PFloat(current));
			node.prop(changeKey, PCallbackFloat(function(v:Float) cell.set(Std.int(v))));
		} else if (Std.isOfType(current, Float)) {
			node.prop(valueKey, PFloat(current));
			node.prop(changeKey, PCallbackFloat(function(v:Float) cell.set(v)));
		} else {
			node.prop(valueKey, PString(current == null ? "" : Std.string(current)));
			node.prop(changeKey, PCallbackString(function(v:String) cell.set(v)));
		}
	}

	/**
		The node type, which is what a host switches on.

		`wui.View` sets it in its constructor — `super("Button")` — so a subclass
		reports its parent's unless it sets its own. That is the same rule the
		other backends follow, and it is why `mui.ui.TextInput` draws as the text
		box it extends.
	**/
	static function typeOf(view:wui.View):String {
		var type = view.viewType;
		return type == null || type == "" ? "VStack" : type;
	}

	static function keyOf(view:wui.View, index:Int):String {
		if (view.properties != null) {
			var declared:Dynamic = view.properties.get("nodeId");
			if (declared != null) {
				var asString = Std.string(declared);
				if (asString != "") return asString;
			}
		}
		return "#" + index;
	}

	/**
		A property, in the form the push contract carries.

		A closure crosses as a callback rather than as data: it is how a button's
		action reaches Haxe, and `PString(Std.string(fn))` would hand the sink a
		printed function. Anything else is described as a string, which is what
		the scalar accessors read.
	**/
	static function toProp(value:Dynamic):Null<PropValue> {
		if (value == null) return null;
		if (Reflect.isFunction(value)) return PCallback(value);
		if (Std.isOfType(value, Bool)) return PBool(value);
		if (Std.isOfType(value, Int)) return PInt(value);
		if (Std.isOfType(value, Float)) return PFloat(value);
		return PString(Std.string(value));
	}
}
