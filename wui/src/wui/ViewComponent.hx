package wui;

/**
 * Base class for reusable view components.
 * Each ViewComponent subclass generates a separate
 * C++/WinRT function for UI construction.
 */
class ViewComponent extends View {
    public function new() {
        super("ViewComponent");
    }

    /** Override to define this component's view tree. */
    public function body():View {
        return new View();
    }
}
