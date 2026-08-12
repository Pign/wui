package wui.ui;

/**
	Flexible space between siblings.

	A `Border` with nothing in it: WinUI has no spacer. Given a `minSize` it
	holds at least that much.

	It only *takes* room inside an `HStack`, which is a Grid and gives a
	spacer's column the leftover width. A StackPanel -- which is what a `VStack`
	is -- distributes nothing, so a spacer in a column is still an empty Border
	asking for no height. Saying so beats a spacer that works in one direction
	and silently does nothing in the other.
**/
class Spacer extends Border {
	public function new(?minSize:Float) {
		super("Border");
		// How an `HStack` recognises one. By the time a child reaches the sink
		// it is a WinRT control like any other, with nothing left to say about
		// what it was meant to be.
		this.tag = "spacer";
		if (minSize != null) {
			this.height = minSize;
			this.width = minSize;
		}
	}
}
