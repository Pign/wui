package wui.kui;

/**
	Which platform a `wui` build is for, told to `kui`.

	Called once from the build file:

	```
	--macro wui.kui.Platform.registerWithKui()
	```

	Like `aui`, `wui` has nothing to decide — it targets Windows and only
	Windows — and registers anyway, because `kui` is handed a backend's name
	rather than its knowledge. A macro cannot call a function it was only given
	the name of, which is why `mui.macros.Backend.register` takes the same shape.

	## Two toolchains, and the split is unusual

	hxcpp is in the list, but it does not link here: it compiles this build's C++
	into `lib<App>.lib` and stops, because the `main` WinUI provides would clash
	with the one hxcpp emits. **MSBuild performs the only link there is.**

	So a capability's `hxcpp` payload still gets its `files` compiled — that half
	rides on `@:buildXml` as everywhere else — while its `libs` reach nothing,
	because the hxcpp link step never runs. Anything that must be *linked* on
	Windows belongs in the `msbuild` section, and so does anything MSBuild alone
	can do: a NuGet package, a `.cpp` that needs the WinUI headers.

	`pui` reaches Windows through hxcpp end to end and registers `["hxcpp"]`
	alone. Same operating system, two link stories — the reason
	`kui.build.Payload` is keyed by toolchain rather than by platform.
**/
class Platform {
	/** Hand `kui` the platform and the link steps this build has. **/
	public static function registerWithKui():Void {
		#if macro
		kui.macros.Host.register({
			platform: "windows",
			toolchains: ["hxcpp", "msbuild"],
			backend: "wui",
		});
		#end
	}
}
