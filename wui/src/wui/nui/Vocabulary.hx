package wui.nui;

import nui.PropValue;

/**
	What kind of value a property holds.

	The markup needs this. `qui`'s existing `jsx()` guesses from the attribute
	name — a hardcoded list where `text`/`title`/`label` are strings and
	`spacing` is an int — and has to special-case `value` by tag, because
	`<Slider value=…>` is a number and `<ComboBox value=…>` is a string. A schema
	knows, per node type, so nothing has to be guessed.
**/
enum PropKind {
	KString;
	KInt;
	KFloat;
	KBool;
	KCallback;
}

/** What one property of a node type may hold. **/
typedef PropSpec = {
	/** What `{expr}` becomes: `PString`, `PInt`, `PCallback`… **/
	var kind:PropKind;

	/** Absent is an error; the macro refuses to compile a node without it. **/
	var required:Bool;

	/**
		What to apply when a nullable property stops being carried.

		This is why the contract needs no `clearProp`. "Erase this property" is
		not well defined — erase a colour to *what*? — but "apply this value" is,
		and the value is declared here, next to the property it belongs to.
		`null` means the property cannot be dropped once set.
	**/
	var ?whenAbsent:PropValue;
};

/**
	What `wui` can render, and with which properties.

	## Why "vocabulary" and not "schema"

	A schema is a document you declare. That describes this file, which lists
	types and their properties by hand — but it does **not** describe what the
	other backends will do. `qui`'s node types *are existing Haxe classes*
	(`ui.Slider` with `public var value(default, set):Float`), so its vocabulary
	is **read from the types**, exhaustive by construction and unable to drift.
	Its types are classes; `wui`'s are strings the C++ knows how to build, with
	no class behind them.

	Nothing is shared between those two artefacts. What is shared is the
	**question `mui` asks**: do you know this type, which attributes does it take,
	of what kind, which are required. The name says what is described and stays
	silent on how it is obtained. `wui` has to declare because its vocabulary
	lives in C++, where nothing can be read back.

	## Why this lives here and not in `nui`

	It was tempting to put a shared core vocabulary in `nui`. It does not earn
	its place:

	- **Nobody writes against a core.** `mui` picks its target at compile time,
	  so the schema that matters while authoring is the *target backend's*. The
	  useful error is "`placeholder` does not exist here", not "`placeholder` is
	  not in the core".
	- **The one real cross-backend case degrades instead.** A tree arriving as
	  data — over a protocol, from a devtool — meets `?TypeName`, which is the
	  honest answer and needs no guarantee.
	- **A core would become the union of five widget sets.** `wui` has
	  `ProgressRing` and `InfoBar`; `cui` has `Table` and `Tabs`. Hoisting those
	  would turn `nui` from *what a node is* into *which nodes exist*, and change
	  it every time any backend grew a widget.

	What genuinely has to stay common is the **naming** — that five backends do
	not call the same thing `text`, `content` and `label`. `nui` already settled
	that in B2 (`type` not `viewType`; text is a plain property). That is a
	discipline, and it is much smaller than a vocabulary.

	So: local schema, no contract change, and if `qui` and `cui` adopt the same
	shape then a common core becomes an observation rather than a bet. Same
	discipline B4 taught — do not generalise from one sample.
**/
class Vocabulary {
	/**
		Node types `wui` knows how to build, with their properties.

		Kept in step with `wui_node_create` in the generated node runtime: a type
		here that the C++ cannot build would compile and then render `?Type`,
		which is the failure this whole schema exists to prevent.
	**/
	public static final types:Map<String, Map<String, PropSpec>> = [
		"VStack" => [
			"spacing" => {kind: KFloat, required: false, whenAbsent: PFloat(0)}
		],
		"HStack" => [
			"spacing" => {kind: KFloat, required: false, whenAbsent: PFloat(0)}
		],
		"Text" => [
			"text" => {kind: KString, required: true}
		],
		"Button" => [
			"text" => {kind: KString, required: true},
			"onClick" => {kind: KCallback, required: false}
		],
		"TextBox" => [
			"text" => {kind: KString, required: false, whenAbsent: PString("")},
			"placeholder" => {kind: KString, required: false, whenAbsent: PString("")}
		]
	];

	/** Properties every type accepts, so each entry above need not repeat them. **/
	public static final universal:Map<String, PropSpec> = [
		"width" => {kind: KFloat, required: false},
		"height" => {kind: KFloat, required: false},
		"visible" => {kind: KBool, required: false, whenAbsent: PBool(true)},
		"enabled" => {kind: KBool, required: false, whenAbsent: PBool(true)}
	];

	public static function knows(type:String):Bool {
		return types.exists(type);
	}

	public static function spec(type:String, key:String):Null<PropSpec> {
		var own = types.get(type);
		if (own != null && own.exists(key)) return own.get(key);
		return universal.exists(key) ? universal.get(key) : null;
	}

	/** Keys a node of this type may carry. **/
	public static function keysOf(type:String):Array<String> {
		var out = [for (k in universal.keys()) k];
		var own = types.get(type);
		if (own != null) for (k in own.keys()) out.push(k);
		return out;
	}

	/** Keys a node of this type must carry. **/
	public static function requiredOf(type:String):Array<String> {
		var out = [];
		var own = types.get(type);
		if (own != null) {
			for (k in own.keys()) if (own.get(k).required) out.push(k);
		}
		return out;
	}

	/** What kind of value `key` holds on `type`, or `null` if it has no such property. **/
	public static function kindOf(type:String, key:String):Null<PropKind> {
		var s = spec(type, key);
		return s == null ? null : s.kind;
	}

	/**
		What to apply when `key` disappears from a node of `type`.

		`null` means nothing sensible can be applied, and the reconciler leaves
		the old value alone rather than guessing.
	**/
	public static function whenAbsent(type:String, key:String):Null<PropValue> {
		var s = spec(type, key);
		return s == null ? null : s.whenAbsent;
	}
}
