import wui.bridge.HaxeBridge;

/**
	The Auxiliary window host, end to end minus WinRT. Run with:

	    haxe -cp src -cp test -lib rui -lib nui -lib mui -D mui_backend=wui --macro "mui.macros.Bind.all()" -main AuxiliaryCheck --interp

	A real mui application (the whole chain: Bind, `@:surface` collection, the
	hook `wui.mui.App`'s constructor installs) is driven through `install` and
	`renderNui`, with the one native act — creating a winrt Window — replaced
	at the injectable seam by a counting function. What this pins:

	- every Auxiliary declaration gets a window, in declaration order, titled
	  from its id;
	- each surface rebuilds on its own state and nobody else's;
	- closing one disposes exactly that record — its effect dead, its OWN
	  lifetime released — while the Primary and the sibling live on, which is
	  the whole point of the partition;
	- application release disposes whatever is still mounted, and every
	  overlap (a second Closed, a Closed after release) is a no-op.
**/
class AuxiliaryCheck {
	static var failures = 0;

	static function check(label:String, actual:Dynamic, expected:Dynamic) {
		var ok = Std.string(actual) == Std.string(expected);
		if (!ok) failures++;
		trace((ok ? "ok   " : "FAIL ") + label + " = " + actual + (ok ? "" : " (expected " + expected + ")"));
	}

	static function main() {
		// The seam: count and hand out handles the way the native table would.
		var created:Array<String> = [];
		var nextHandle = 100;
		HaxeBridge.windowCreator = function(title) {
			created.push(title);
			return nextHandle++;
		};

		var installed = HaxeBridge.install("AuxApp");
		check("install found the app", installed >= 0, true);
		HaxeBridge.renderNui(0);

		// ---- mounting: one window per declaration, titled from its id ----
		check("every declaration got a window", created.length, 2);
		check("titles come from the ids, prettified", created.join(","), "Inspector,Metrics");
		check("the first record is reachable by its handle", HaxeBridge.auxiliaryRecord(100) != null, true);
		check("each build ran once", Probe.builtA + "," + Probe.builtB, "1,1");

		// ---- each surface rebuilds on its own state, and only its own ----
		AuxApp.last.bumpA();
		check("A rebuilt on its own state", Probe.builtA, 2);
		check("B never heard about it", Probe.builtB, 1);

		// ---- closing one touches nothing else ----
		var releasedA = false;
		HaxeBridge.auxiliaryRecord(100).lifetime.own(function() releasedA = true);
		HaxeBridge.surfaceClosed(100);
		check("the closed surface released its own lifetime", releasedA, true);
		check("its record is gone", HaxeBridge.auxiliaryRecord(100) == null, true);

		AuxApp.last.bumpA();
		check("its effect is dead: a write rebuilds nothing", Probe.builtA, 2);
		AuxApp.last.bumpB();
		check("the sibling still lives", Probe.builtB, 2);

		HaxeBridge.surfaceClosed(100);
		check("a second Closed for the same window is a no-op", failures, failures);

		// ---- application release disposes what is still mounted ----
		var releasedB = false;
		HaxeBridge.auxiliaryRecord(101).lifetime.own(function() releasedB = true);
		HaxeBridge.disposePrimary();
		check("release disposed the remaining auxiliary", releasedB, true);
		check("a Closed arriving after release is a no-op", HaxeBridge.auxiliaryRecord(101) == null, true);
		HaxeBridge.surfaceClosed(101);

		trace(failures == 0 ? "\nall checks passed" : '\n$failures failed');
		#if sys
		Sys.exit(failures == 0 ? 0 : 1);
		#end
	}
}

/** Build counters, on a class of their own: a view method may not read its
	app's mutable fields (the view rule), and these are bookkeeping about the
	test, not state the view depends on. **/
class Probe {
	public static var builtA = 0;
	public static var builtB = 0;
}

/** A real mui application: the hook is installed by wui.mui.App's own
	constructor, the declarations are collected by the real macro. **/
class AuxApp extends mui.App {
	public static var last:AuxApp;

	@:state var countA:Int = 0;
	@:state var countB:Int = 0;

	public function new() {
		super();
		last = this;
	}

	// The cells stay private after the @:state rewrite; the test writes
	// through these, the way any outside caller would.
	public function bumpA() countA.set(countA.get() + 1);
	public function bumpB() countB.set(countB.get() + 1);

	@:surface(Auxiliary)
	function inspector():mui.View {
		Probe.builtA++;
		return new mui.ui.Text('A ${countA.get()}');
	}

	@:surface(Auxiliary)
	function metrics():mui.View {
		Probe.builtB++;
		return new mui.ui.Text('B ${countB.get()}');
	}
}
