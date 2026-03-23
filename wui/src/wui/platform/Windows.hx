package wui.platform;

/**
 * Windows-specific APIs for customizing the application window.
 */
class Windows {
    /** Whether to extend content into the title bar area. */
    public static var extendIntoTitleBar:Bool = false;

    /** Custom title bar background color (ARGB hex). */
    public static var titleBarColor:Null<String> = null;

    /** Whether to show the minimize button. */
    public static var showMinimize:Bool = true;

    /** Whether to show the maximize button. */
    public static var showMaximize:Bool = true;

    /** Minimum window size. */
    public static var minWidth:Int = 320;
    public static var minHeight:Int = 240;
}
