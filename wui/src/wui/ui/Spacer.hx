package wui.ui;

/**
	Flexible space between siblings.

	A `Border` with nothing in it: WinUI has no spacer, and a stack shares its
	leftover room with whatever is willing to grow. Given a `minSize` it holds
	at least that much.
**/
class Spacer extends Border {
	public function new(?minSize:Float) {
		super("Border");
		if (minSize != null) {
			this.height = minSize;
			this.width = minSize;
		}
	}
}
