package wui.state;

/**
 * Minimal persistent-by-copy list. Every mutating operation returns a
 * fresh `ImmutableList` whose internal `Array<T>` is a copy of the
 * previous one with the change applied — there is no structural
 * sharing yet (a real persistent vector with O(log n) clones is the
 * follow-up when inboxes start hitting tens of thousands of items).
 *
 * Usage:
 *
 *     var inbox = ImmutableList.empty();
 *     inbox = inbox.cons(newEmail);            // append at the tail
 *     inbox = inbox.update(5, e -> e.withIsRead(true));  // Immer-style
 *
 * Plays as a citizen of `wui.state.Immutable`, so it can sit behind a
 * `@:state` field on an App. The macro pairs the field with a hidden
 * trigger primitive so `ForEach` gets a re-render whenever the
 * reference is replaced.
 */
class ImmutableList<T> implements Immutable {
    final _items:Array<T>;

    function new(items:Array<T>) {
        _items = items;
    }

    /** Brand-new empty list. Identity-equal returns from `empty()` may
        eventually become a shared singleton — don't rely on uniqueness. */
    public static function empty<T>():ImmutableList<T> {
        return new ImmutableList<T>([]);
    }

    /** Wrap an existing Array<T>. The input is *copied* so the caller
        can keep mutating their own array without affecting the list. */
    public static function fromArray<T>(arr:Array<T>):ImmutableList<T> {
        return new ImmutableList<T>(arr.copy());
    }

    public var length(get, never):Int;
    inline function get_length():Int return _items.length;

    public function get(i:Int):T {
        return _items[i];
    }

    public function iterator():Iterator<T> {
        return _items.iterator();
    }

    /** Append at the tail. (Named `cons` for the functional flavour,
        even though it's really `snoc`/push for an ordered list — the
        intent is "build a new list with one more item".) */
    public function cons(item:T):ImmutableList<T> {
        var next = _items.copy();
        next.push(item);
        return new ImmutableList<T>(next);
    }

    /** Replace the item at index `i`. Out-of-range indices behave like
        Haxe's `Array` setter — extends or no-ops depending on platform.
        Callers are expected to check `length` first. */
    public function setAt(i:Int, item:T):ImmutableList<T> {
        var next = _items.copy();
        next[i] = item;
        return new ImmutableList<T>(next);
    }

    /** Drop the item at index `i`. Returns the same list (by identity)
        if `i` is out of range — caller should validate. */
    public function removeAt(i:Int):ImmutableList<T> {
        if (i < 0 || i >= _items.length) return this;
        var next = _items.copy();
        next.splice(i, 1);
        return new ImmutableList<T>(next);
    }

    /** Immer-style functional update: `inbox.update(i, e -> e.withRead(true))`. */
    public function update(i:Int, fn:T -> T):ImmutableList<T> {
        var next = _items.copy();
        next[i] = fn(next[i]);
        return new ImmutableList<T>(next);
    }

    /** Snapshot as a plain Array<T>. The returned array is a copy —
        mutating it doesn't affect the list. */
    public function toArray():Array<T> {
        return _items.copy();
    }
}
