package wui.state;

/**
 * Base class for observable data models.
 * Tracks which properties have changed and notifies the UI layer.
 *
 * Usage:
 *   class TodoItem extends Observable {
 *       public var title:String;
 *       public var completed:Bool;
 *   }
 */
class Observable {
    var _changeListeners:Array<String -> Void>;

    public function new() {
        _changeListeners = [];
    }

    /** Subscribe to property changes. */
    public function onPropertyChanged(listener:String -> Void):Void {
        _changeListeners.push(listener);
    }

    /** Notify that a property has changed. */
    public function notifyChanged(propertyName:String):Void {
        for (listener in _changeListeners) {
            listener(propertyName);
        }
    }
}
