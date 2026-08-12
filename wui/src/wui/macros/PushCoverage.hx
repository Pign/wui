package wui.macros;

#if macro
import haxe.macro.Context;
import haxe.macro.Type;

/**
	Refuses, at compile time, a view the push sink cannot build.

	## Why a check rather than a placeholder

	A node type the sink does not know is materialised as `?TabView` on screen.
	That is the right answer for a tree arriving as **data**, which nothing could
	have checked ahead of time — the boundary `nui.Foreign` draws. It is the
	wrong answer for a `body()` written here and compiled for a known backend:
	that is a knowable defect, and showing it as a label is how a developer
	learns about it from a screenshot instead of from the build.

	`aui` and `sui` already refuse. This is wui paying the same rule.

	## Why only in push mode

	The transpiled path handles types the push sink does not, so a native wui app
	must keep compiling. The check therefore looks only at applications marked
	`@:nui` — which is what routes an app through the sink, and what `mui.App`
	carries. Metadata is not inherited in Haxe, so the chain is walked.

	## Where the vocabulary comes from

	`wui.nui.Vocabulary`, which reads it off the `@:winrt` annotations on
	`wui.ui.*`. It **is** what the generated `WuiNodes.cpp` can create, so any
	list kept here would be a second copy, free to drift in the direction that
	hurts: a control losing its annotation would still pass.
**/
class PushCoverage {
	/**
		Expanded before the sink sees them, so never asked of it.

		A `ForEach` is a loop that yields siblings and a `ConditionalView` is the
		branch its condition picks. `mui.nui.FromViews` replaces both while it
		describes the tree, so demanding a WinRT control for either would be
		asking for one that cannot exist. The other two backends exempt the same
		pair, for the same reason.
	**/
	static final EXPANDED = ["ForEach", "ConditionalView"];

	public static function register():Void {
		Context.onAfterTyping(check);
	}

	static function check(types:Array<ModuleType>):Void {
		var offenders:Array<{name:String, control:String, pos:haxe.macro.Expr.Position}> = [];

		for (mt in types) {
			switch (mt) {
				case TClassDecl(ref):
					var cls = ref.get();
					if (!isPushApp(cls)) continue;
					for (field in cls.fields.get()) collect(field, offenders);
					for (field in cls.statics.get()) collect(field, offenders);
				default:
			}
		}

		if (offenders.length == 0) return;

		var known = wui.nui.Vocabulary.types();
		known.sort(Reflect.compare);

		for (i in 0...offenders.length) {
			var o = offenders[i];
			var msg = 'The push sink cannot build "' + o.name + '".\n'
				+ '  It knows: ' + known.join(", ") + '.\n'
				+ '  Give wui/ui/' + o.control + '.hx a @:winrt name and properties,\n'
				+ '  which is what puts a control in the vocabulary.';
			if (i == offenders.length - 1) Context.error(msg, o.pos);
			else Context.reportError(msg, o.pos);
		}
	}

	/** An application routed through the sink — `@:nui`, on it or an ancestor. **/
	static function isPushApp(cls:ClassType):Bool {
		var current = cls;
		var pushes = false;
		var isApp = false;
		while (current != null) {
			if (current.meta.has(":nui")) pushes = true;
			if (current.name == "App" && current.pack.join(".") == "wui") isApp = true;
			current = current.superClass == null ? null : current.superClass.t.get();
		}
		return pushes && isApp;
	}

	static function collect(field:ClassField, offenders:Array<{name:String, control:String, pos:haxe.macro.Expr.Position}>):Void {
		if (field.name != "body" && !returnsView(field)) return;
		var e = field.expr();
		if (e != null) walk(e, offenders);
	}

	static function returnsView(field:ClassField):Bool {
		return switch (haxe.macro.TypeTools.follow(field.type)) {
			case TFun(_, ret): isView(ret);
			case _: false;
		};
	}

	static function isView(t:Type):Bool {
		return switch (haxe.macro.TypeTools.follow(t)) {
			case TInst(ref, _): extendsView(ref.get());
			case _: false;
		};
	}

	static function extendsView(cls:ClassType):Bool {
		var current = cls;
		while (current != null) {
			if (current.name == "View" && current.pack.join(".") == "wui") return true;
			current = current.superClass == null ? null : current.superClass.t.get();
		}
		return false;
	}

	/**
		Whether the sink knows this class, or one it inherits from.

		A node reports the `viewType` its constructor set, and a subclass carries
		its parent's unless it sets its own — so `mui.ui.TextInput`, a
		`wui.ui.TextBox`, is a TextBox to the sink. Judging by the Haxe name
		would refuse a control that builds perfectly well.
	**/
	static function known(cls:ClassType):Bool {
		var current = cls;
		while (current != null) {
			if (EXPANDED.indexOf(current.name) >= 0) return true;
			if (wui.nui.Vocabulary.knows(current.name)) return true;
			current = current.superClass == null ? null : current.superClass.t.get();
		}
		return false;
	}

	/**
		The `wui.ui` class that would carry the annotation.

		A layer's view is a subclass -- `mui.ui.ScrollView` extends
		`wui.ui.ScrollViewer` -- so naming the offender's own file sends you to
		one that does not exist. The control to annotate is the nearest ancestor
		wui ships.
	**/
	static function controlOf(cls:ClassType):String {
		var current = cls;
		while (current != null) {
			if (current.pack.join(".") == "wui.ui") return current.name;
			current = current.superClass == null ? null : current.superClass.t.get();
		}
		return cls.name;
	}

	/** `wui.View` itself: what an app returns before it has a body. **/
	static function isBaseView(cls:ClassType):Bool {
		return cls.name == "View" && cls.pack.join(".") == "wui";
	}

	static function walk(e:TypedExpr, offenders:Array<{name:String, control:String, pos:haxe.macro.Expr.Position}>):Void {
		if (e == null) return;

		switch (e.expr) {
			case TNew(ref, _, _):
				var cls = ref.get();
				if (extendsView(cls) && !isBaseView(cls) && !known(cls)) {
					offenders.push({name: cls.name, control: controlOf(cls), pos: e.pos});
				}
			default:
		}

		haxe.macro.TypedExprTools.iter(e, function(sub) walk(sub, offenders));
	}
}
#end
