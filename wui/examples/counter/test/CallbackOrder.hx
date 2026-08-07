import wui.bridge.Callbacks;
import wui.bridge.HaxeBridge;

/**
	Pins the one agreement W2 rests on: the ids the macro wrote into the C++ and
	the ids the runtime walk hands out must name the same buttons.

	Two independent walks produce those numbers -- `WinUIGenerator.assignCallbackIds`
	over the compile-time tree, `HaxeBridge.collect` over the runtime tree. Each is
	internally consistent, so a drift between them does not crash: **a click simply
	runs the wrong closure.** Nothing else in the build would notice.

	So this test does not check the runtime side alone. It reads the *generated*
	`MainWindow.cpp`, recovers each button's label and the id its Click handler
	passes, then invokes that id through the registry and checks the closure that
	answers belongs to that same button.

	    haxe build.hxml && haxe test.hxml && ./build/test/CallbackOrder

	Requires the generated project to be present, which the normal build produces.
**/
class CallbackOrder {
	static var failures = 0;

	static function check(what:String, ok:Bool, detail:String = ""):Void {
		if (ok) {
			Sys.println('  ok   $what');
		} else {
			failures++;
			Sys.println('  FAIL $what${detail == "" ? "" : "  -- " + detail}');
		}
	}

	/**
		Recover `id -> label` from the generated C++.

		Deliberately reads the artefact rather than re-deriving the mapping: the
		point is to compare against what actually ships, not against a second copy
		of the same assumption.
	**/
	static function idsFromGeneratedCpp(path:String):Map<Int, String> {
		var out = new Map<Int, String>();
		if (!sys.FileSystem.exists(path)) return out;

		var lines = sys.io.File.getContent(path).split("\n");
		var pendingLabel:String = null;

		var labelRe = ~/Content\(winrt::box_value\(L"([^"]*)"\)\)/;
		var invokeRe = ~/wui_bridge_invoke\((\d+)\)/;

		for (line in lines) {
			if (labelRe.match(line)) {
				pendingLabel = labelRe.matched(1);
			} else if (invokeRe.match(line) && pendingLabel != null) {
				out.set(Std.parseInt(invokeRe.matched(1)), pendingLabel);
				pendingLabel = null;
			}
		}
		return out;
	}

	static function main() {
		Sys.println("CallbackOrder");

		// --- the runtime walk ---
		var installed = HaxeBridge.install("Counter");
		check("install() finds closures at all", installed > 0, 'got $installed');
		check("registry agrees", Callbacks.count() == installed);

		// --- what the generator wrote ---
		//
		// The count is not hardcoded: it comes from the generated file, so adding
		// a button to the example cannot silently half-break this test.
		var generated = idsFromGeneratedCpp("build/winui/MainWindow.cpp");
		var genCount = Lambda.count(generated);
		check("generated C++ has the same number of ids", genCount == installed,
			'C++ has $genCount, runtime has $installed');

		// --- the agreement itself ---
		var state:Dynamic = wui.state.State.getByName("count");
		check("the @:state field registered itself", state != null);

		for (id in 0...installed) {
			var label = generated.exists(id) ? generated.get(id) : null;
			if (label == null) {
				check('id $id is present in the generated C++', false);
				continue;
			}

			var before:Int = state.peek();
			Counter.last = null;
			Callbacks.invoke(id);
			var after:Int = state.peek();

			// Since W4 every button routes through Haxe, whether its action was
			// written as a closure or as a StateAction. So the expectation is per
			// label, and the StateAction ones are the interesting half: they used
			// to be C++ that mutated `s_count` behind Haxe's back.
			switch (label) {
				case "+":
					check('id $id — StateAction Increment', after == before + 1,
						'$before -> $after');
				case "-":
					check('id $id — StateAction Decrement', after == before - 1,
						'$before -> $after');
				case "Reset":
					check('id $id — StateAction SetValue', after == 0, '$before -> $after');
				case "Haxe +10":
					check('id $id — closure writes the state', after == before + 10,
						'$before -> $after');
				case "Custom ×2":
					// The one the translator dropped in silence.
					check('id $id — StateAction Custom runs at all', after == before * 2,
						'$before -> $after');
				case _:
					// "Haxe A" -> "A": the closure reports the bare letter.
					var expected = StringTools.replace(label, "Haxe ", "");
					check('id $id runs the closure of "$label"', Counter.last == expected,
						'ran "${Counter.last}", expected "$expected"');
			}
		}

		// --- the subscriber the push rides on ---
		//
		// `wui.state.State` routes its platform sink through the subscriber list,
		// and HaxeBridge.bindStates() adds one that forwards to native. Checking a
		// write reaches a subscriber checks that route without needing the app.
		var seen:Array<Int> = [];
		state.subscribe(function(v:Dynamic) seen.push(v));
		// set(), not `.value =` -- a property assigned through Dynamic throws
		// "Invalid field:value" on hxcpp.
		state.set(4242);
		check("a write reaches the subscribers", seen.length == 1 && seen[0] == 4242,
			'received $seen');

		// A write of the same value must not re-notify: rui.state.State stops it,
		// and every push costs a thread hop to the UI.
		seen = [];
		state.set(4242);
		check("an unchanged write notifies nobody", seen.length == 0, 'received $seen');

		// --- an id nobody assigned must not run anything ---
		Counter.last = null;
		Callbacks.invoke(99);
		check("an out-of-range id runs nothing", Counter.last == null);

		Sys.println(failures == 0 ? "\nall good" : '\n$failures failed');
		Sys.exit(failures == 0 ? 0 : 1);
	}
}
