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
		check("install() finds the closures", installed == 3, 'got $installed');
		check("registry agrees", Callbacks.count() == installed);

		// --- what the generator wrote ---
		var generated = idsFromGeneratedCpp("build/winui/MainWindow.cpp");
		var genCount = Lambda.count(generated);
		check("generated C++ has the same number of ids", genCount == installed,
			'C++ has $genCount, runtime has $installed');

		// --- the agreement itself ---
		for (id in 0...installed) {
			var label = generated.exists(id) ? generated.get(id) : null;
			if (label == null) {
				check('id $id is present in the generated C++', false);
				continue;
			}

			Counter.last = null;
			Callbacks.invoke(id);

			// "Haxe A" -> "A": the closure reports the bare letter.
			var expected = StringTools.replace(label, "Haxe ", "");
			check('id $id runs the closure of "$label"', Counter.last == expected,
				'ran "${Counter.last}", expected "$expected"');
		}

		// --- an id nobody assigned must not run anything ---
		Counter.last = null;
		Callbacks.invoke(99);
		check("an out-of-range id runs nothing", Counter.last == null);

		Sys.println(failures == 0 ? "\nall good" : '\n$failures failed');
		Sys.exit(failures == 0 ? 0 : 1);
	}
}
