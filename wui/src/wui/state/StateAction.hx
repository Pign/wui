package wui.state;

/**
 * Tap / click handler — a plain `() -> Void` closure. Captures
 * (idx, item fields, locals from the enclosing scope) are handled
 * natively by hxcpp's runtime closure machinery.
 *
 * For state mutations inside the closure body, just write the
 * typed setter directly :
 *
 *   .onTap(() -> count.value++)
 *   .onTap(() -> serverUrl.value = "https://...")
 *   .onTap(() -> isDark.value = !isDark.value)
 *
 * Static handlers compose via plain function refs :
 *
 *   .onTap(MyApp.requestLogin)
 *   .onTap(() -> Session.handleRowTap(idx))   // ForEach row context
 *
 * `Sequence`-style chains aren't a thing anymore — just do both
 * statements in the same closure body.
 */
typedef StateAction = () -> Void;
