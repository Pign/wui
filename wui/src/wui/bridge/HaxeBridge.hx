package wui.bridge;

/**
	The entry point WinUI calls to start the Haxe runtime.

	`wui` is currently a transpiler: the generated Visual Studio project links no
	hxcpp, so no Haxe runs in a built app. This class is the first step out of
	that — increment **W1** of the `wui`-on-hxcpp chantier.

	## How the boot works

	WinUI owns the entry point (`wWinMain`, via `App`), so Haxe cannot own `main`.
	The pattern is the one both sibling backends already use:

	- **`qui`**: Qt owns `main` and calls `hx::Init()` *after* the view exists.
	- **`sui`**: Swift owns `@main` and calls `haxe_bridge_init` through `dlsym`,
	  so the runtime stays optional and detected.

	Here, `App::OnLaunched` calls `wui_bridge_init()` before building the window.
	The call is emitted by the generator, so an app gets it without asking.

	## The two mains

	hxcpp emits a `__main__` translation unit whose `main()` would clash with the
	one WinUI provides. The librarian step that packs hxcpp's objects into the
	static library **excludes it** — the same exclusion `sui` makes for the same
	reason.

	## Status

	Compiles and generates. **Not yet linked or run**: that needs Windows, MSVC
	and the Windows App SDK. See `wui-hxcpp.md` in the atelier repo for the
	sequence and what each increment proves.
**/
#if cpp
@:cppFileCode('
#include <hxcpp.h>

static bool s_wui_haxe_started = false;

// Called by App::OnLaunched before the window is built.
//
// Idempotent: WinUI can raise OnLaunched more than once (relaunch, activation),
// and booting the runtime twice would be fatal.
extern "C" void wui_bridge_init() {
    if (s_wui_haxe_started) return;
    s_wui_haxe_started = true;
    hx::Init();
}

// Whether the runtime is up. Lets generated code degrade rather than crash if
// the library was not linked in.
extern "C" bool wui_bridge_ready() {
    return s_wui_haxe_started;
}
')
#end
@:keep
class HaxeBridge {
	/**
		Proof of life, called from Haxe once the runtime is up.

		W1 succeeds when this line appears in the debug output of a running WinUI
		app — it means MSVC linked the hxcpp library, WinUI called into it, and
		Haxe executed. Nothing else about the app changes yet.
	**/
	public static function hello():Void {
		trace("[wui] Haxe runtime started");
	}

	/** Is the native side up? False when the library was not linked. **/
	public static function isReady():Bool {
		#if cpp
		var ready:Bool = false;
		untyped __cpp__("{0} = wui_bridge_ready()", ready);
		return ready;
		#else
		return false;
		#end
	}
}
