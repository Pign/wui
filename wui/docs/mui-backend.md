# Being a `mui` backend

[`mui`](https://lapavoiserie.github.io/mui/) lets one source build for every
backend in this family. `wui` is the one that draws through WinUI 3.

## The conformance lives here

Under `wui/mui/` — one file per entry in
[`mui.Contract`](https://github.com/lapavoiserie/mui/blob/main/src/mui/Contract.hx).
A `typedef` where the signature already matches, a small subclass where it does
not:

```haxe
package wui.mui;

typedef View = wui.View;
```

`mui` holds **no branch for `wui`**, and none for any other backend. It states
the vocabulary as data, and one line in the build file resolves it:

```
-D mui_backend=wui
--macro mui.macros.Bind.all()
```

`Bind` defines `mui.ui.Button` as an alias of `wui.mui.Button`, then checks
every constructor against the contract — arity, optionality, argument types — and
names what does not match, at the top of the build rather than at first use.

It used to be the other way round: `mui` held 132 conditional branches and had to
know all six backends. Adding a seventh meant editing twenty-two files in a
repository that had nothing to learn from it.

## What else is ours

`wui/mui/init.hxml` is the build file `mui init` writes into a new project. It
lives here because what a build for this backend needs — which libraries, which
generator macro, which output — is ours to state, and `mui` had no way of keeping
six of them honest.

`wui.mui.TabView` binds `NavigationView`, not WinUI's `TabView`: the latter is
the *document* control, with a close button on each tab and a "+" on the strip,
and nothing about the sections of an app can be closed or added.

`wui.mui.FromViews` also lives here. It describes a `mui` view tree as `nui`
nodes, which is what push mode needs — and `wui` is the only backend in push
mode, so it is the only one that needed it. It used to sit in `mui` behind a
conditional.

## See also

- [Adding a backend](https://lapavoiserie.github.io/mui/#/adding-a-backend) — the
  whole contract, and the two rules the six backends made necessary.
- [Backend support](https://lapavoiserie.github.io/mui/#/backend-support) — the
  generated table of what every backend answers for every type. It is generated
  by reading these very files.
