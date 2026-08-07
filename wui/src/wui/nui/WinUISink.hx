package wui.nui;

import nui.Modifier;
import nui.Node;
import nui.NodeSink;
import nui.PropValue;
import wui.bridge.Callbacks;

/**
	Drives WinUI through [nui's push contract](https://lapavoiserie.github.io/nui/#/push-mode).

	WinUI 3 is retained-mode: a tree of XAML controls is built once and mutated.
	It diffs nothing, so it has to be told what changed — the push side of the
	model, with `qui` as the reference implementation and this as the **second**.

	## `Native` is an `Int`, and that is the interesting part

	`qui` holds a `ui.Item` in Haxe because Silica items are visible to it. A
	WinRT control is not visible to hxcpp at all: it lives in the C++/WinRT world
	the generated project compiles. So the tree lives on the C++ side, and what
	Haxe holds is an **index into a handle table** — the same discipline that
	already governs callbacks here, where an id crosses and a closure never does.

	A sink whose `Native` is opaque is worth noting for the contract: nothing in
	`NodeSink` requires the handle to be inspectable, and this proves it, because
	`applyProp` receives the node `type` rather than asking the handle what it
	is. That parameter was added for `qui`, whose Silica items carry no type
	name. It turns out to be load-bearing for a second, unrelated reason.

	## What this settles about the three gaps left open in B4

	`qui` could not honour three of the contract's assumptions, and they were
	deliberately **not** softened — softening for a sample of one would have
	crippled the next adopter. WinUI is that next adopter, and it honours all
	three:

	| Assumption | `qui` | `wui` |
	|---|---|---|
	| `create` and `insert` are separable | no — QML instantiates into a parent | **yes** |
	| the insertion index is choosable | no — positioners append | **yes**, `Children().InsertAt` |
	| `destroy` frees | no — it only hides, and leaks | **yes**, releasing the last reference |

	So the decision to leave them alone was right, and the contract is not
	over-specified: it was `qui` that was under-capable.

	## Granularity

	`bindReactive` is the one hook. Left at its default a property is applied
	immediately; set to wrap each application in a `rui` effect and a write
	re-applies exactly one property, with no tree walk — the fine-grained path
	`qui` validated on device.

	```haxe
	sink.bindReactive = fn -> new rui.Signal.Effect(fn);
	```
**/
#if cpp
// Declared, not included: these live in the generated WuiNodes.cpp, on the
// WinUI side of the build. This library must keep compiling without it -- a
// test binary links the sink and simply has no controls to talk to.
@:cppFileCode('
extern "C" int  wui_node_create(const char* type, int parent);
extern "C" void wui_node_prop_string(int h, const char* type, const char* key, const char* value);
extern "C" void wui_node_prop_int(int h, const char* type, const char* key, int value);
extern "C" void wui_node_prop_float(int h, const char* type, const char* key, double value);
extern "C" void wui_node_prop_bool(int h, const char* type, const char* key, bool value);
extern "C" void wui_node_prop_callback(int h, const char* type, const char* key, int callbackId);
extern "C" void wui_node_modifier(int h, const char* type, const char* modType, double f0, const char* s0);
extern "C" void wui_node_insert(int parent, int child, int index);
extern "C" void wui_node_remove(int parent, int child);
extern "C" void wui_node_destroy(int h);
')
#end
@:keep
class WinUISink implements NodeSink<Int> {
	var _bind:(Void->Void)->Void = function(fn) fn();

	public var bindReactive(get, set):(Void->Void)->Void;

	function get_bindReactive()
		return _bind;

	function set_bindReactive(v) {
		_bind = v;
		return v;
	}

	/**
		Which id carries the handler for a given (node, property).

		Allocated once and reused. A re-render hands a fresh closure for the same
		button every time — they can never compare equal, so the property is
		always re-applied — and minting an id per application would grow the
		registry for the life of the app.
	**/
	final callbackIds = new Map<String, Int>();

	public function new() {}

	/**
		Materialise a control — and nothing else.

		`parent` is ignored, and that is the point: WinUI can build a control
		before it has anywhere to live, so mounting belongs to `insert`. The
		first adopter had no such freedom.
	**/
	public function create(node:Node, parent:Null<Int>):Int {
		return nativeCreate(node.type, parent == null ? -1 : parent);
	}

	/**
		Apply one property, through `bindReactive` so the binding can own an
		effect.

		The value may be `PReactive`, so it is resolved rather than switched on
		directly — and resolved *inside* the bound function, so that re-running
		the effect re-reads it.
	**/
	public function applyProp(target:Int, type:String, key:String, value:PropValue):Void {
		_bind(function() {
			var resolved = PropValueTools.resolve(value);
			if (resolved == null) return;

			switch (resolved) {
				case PString(v):
					nativePropString(target, type, key, v == null ? "" : v);
				case PInt(v):
					nativePropInt(target, type, key, v);
				case PFloat(v):
					nativePropFloat(target, type, key, v);
				case PBool(v):
					nativePropBool(target, type, key, v);

				case PCallback(fn):
					// An id crosses, never the closure: a closure held only by
					// native code is invisible to the hxcpp GC, which is the wall
					// both sibling backends hit before this one.
					var slot = target + ":" + key;
					if (callbackIds.exists(slot)) {
						// Same id, new meaning. The control does not need telling.
						Callbacks.setNode(callbackIds.get(slot), fn);
					} else {
						var id = Callbacks.registerNode(fn);
						callbackIds.set(slot, id);
						nativePropCallback(target, type, key, id);
					}

				case PCallbackString(_) | PCallbackFloat(_) | PCallbackInt(_):
					// These need the control to hand its live value back. The
					// plumbing for that is not written yet, and reporting beats a
					// handler that silently never fires.
					trace('[wui] $type.$key: value-carrying handlers are not wired yet');

				case PReactive(_):
					// resolve() is a fixed point, so this cannot happen. Saying so
					// beats a silent default branch.
					trace('[wui] $type.$key: PReactive survived resolution');
			}
		});
	}

	/** Apply the ordered chain. Order is significant, so it is not sorted. **/
	public function applyModifiers(target:Int, type:String, modifiers:Array<Modifier>):Void {
		if (modifiers == null) return;

		for (m in modifiers) {
			var f0 = (m.floats != null && m.floats.length > 0) ? m.floats[0] : 0.0;
			var s0 = (m.strings != null && m.strings.length > 0) ? m.strings[0] : "";
			nativeModifier(target, type, m.type, f0, s0);
		}
	}

	public function insert(parent:Int, child:Int, index:Int):Void {
		nativeInsert(parent, child, index);
	}

	public function remove(parent:Int, child:Int):Void {
		nativeRemove(parent, child);
	}

	public function destroy(target:Int):Void {
		nativeDestroy(target);
	}

	// ---- the crossing itself ----

	static function nativeCreate(type:String, parent:Int):Int {
		#if cpp
		var handle:Int = 0;
		untyped __cpp__("{0} = wui_node_create({1}.utf8_str(), {2})", handle, type, parent);
		return handle;
		#else
		return -1;
		#end
	}

	static function nativePropString(h:Int, type:String, key:String, value:String):Void {
		#if cpp
		untyped __cpp__("wui_node_prop_string({0}, {1}.utf8_str(), {2}.utf8_str(), {3}.utf8_str())",
			h, type, key, value);
		#end
	}

	static function nativePropInt(h:Int, type:String, key:String, value:Int):Void {
		#if cpp
		untyped __cpp__("wui_node_prop_int({0}, {1}.utf8_str(), {2}.utf8_str(), {3})", h, type, key, value);
		#end
	}

	static function nativePropFloat(h:Int, type:String, key:String, value:Float):Void {
		#if cpp
		untyped __cpp__("wui_node_prop_float({0}, {1}.utf8_str(), {2}.utf8_str(), {3})", h, type, key, value);
		#end
	}

	static function nativePropBool(h:Int, type:String, key:String, value:Bool):Void {
		#if cpp
		untyped __cpp__("wui_node_prop_bool({0}, {1}.utf8_str(), {2}.utf8_str(), {3})", h, type, key, value);
		#end
	}

	static function nativePropCallback(h:Int, type:String, key:String, id:Int):Void {
		#if cpp
		untyped __cpp__("wui_node_prop_callback({0}, {1}.utf8_str(), {2}.utf8_str(), {3})", h, type, key, id);
		#end
	}

	static function nativeModifier(h:Int, type:String, modType:String, f0:Float, s0:String):Void {
		#if cpp
		untyped __cpp__("wui_node_modifier({0}, {1}.utf8_str(), {2}.utf8_str(), {3}, {4}.utf8_str())",
			h, type, modType, f0, s0);
		#end
	}

	static function nativeInsert(parent:Int, child:Int, index:Int):Void {
		#if cpp
		untyped __cpp__("wui_node_insert({0}, {1}, {2})", parent, child, index);
		#end
	}

	static function nativeRemove(parent:Int, child:Int):Void {
		#if cpp
		untyped __cpp__("wui_node_remove({0}, {1})", parent, child);
		#end
	}

	static function nativeDestroy(h:Int):Void {
		#if cpp
		untyped __cpp__("wui_node_destroy({0})", h);
		#end
	}
}
