package wui.nui;

import rui.Signal.Effect;

/**
	Everything one mounted surface owns: the per-surface record the surfaces
	chantier converges on -- {driver, effect, lifetime} plus the registered
	root handle the tree reconciles into.

	This is what used to be four statics on `HaxeBridge` (`nuiSink`,
	`nuiReconciler`, `nuiTree`, `nuiEffect`). Statics were fine while exactly
	one tree ever mounted; a second surface would have fought over all four.
	The Primary surface holds the application's own `rui.Lifetime` -- its
	passes bracket `body()`, which is where an app's `keep` keys are declared
	-- while a later surface (an Auxiliary window) brings a fresh one, so its
	sweep cannot touch the app's keys.

	`dispose` is idempotent by the same contract as `mui`'s MountedSurface:
	container loss and application release overlap, and both call it. It
	releases the effect and the lifetime; the native controls die with their
	window, and their handles become permanent holes in the handle table.
**/
class SurfaceRecord {
	/** The registered root handle this surface's tree reconciles into. **/
	public final root:Int;

	public final sink:WinUISink;
	public final reconciler:Reconciler<Int>;
	public final lifetime:rui.Lifetime;

	/** The mounted tree, replaced on every reconcile. **/
	public var tree:Null<Mounted<Int>> = null;

	/** The render effect; set once the first render is wired. **/
	public var effect:Null<Effect> = null;

	var disposed = false;

	public function new(root:Int, sink:WinUISink, reconciler:Reconciler<Int>, lifetime:rui.Lifetime) {
		this.root = root;
		this.sink = sink;
		this.reconciler = reconciler;
		this.lifetime = lifetime;
	}

	public function dispose():Void {
		if (disposed) return;
		disposed = true;
		if (effect != null) effect.dispose();
		lifetime.release();
	}
}
