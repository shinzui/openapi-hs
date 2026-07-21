---
id: 9
slug: drop-optics-dependencies-in-favor-of-lens
title: "Drop optics dependencies in favor of lens"
kind: exec-plan
created_at: 2026-07-21T17:06:22Z
intention: "intention_01ky2t2vtcekm9mrttbtye8m13"
---


# Drop optics dependencies in favor of lens

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

`openapi-hs` is a Haskell library for building and validating OpenAPI 3.1 documents. Today it
ships **two parallel accessor systems** for reaching into its records: one built on the
[`lens`](https://hackage.haskell.org/package/lens) library (the module `Data.OpenApi.Lens`,
giving you accessors such as `schema`, `type_`, `paths`) and one built on the
[`optics`](https://hackage.haskell.org/package/optics) library (the module
`Data.OpenApi.Optics`, giving you overloaded labels such as `#schema`, `#type`, `#paths`).
Maintaining both doubles the surface area that must be kept in sync every time a record field
is added, and it forces every consumer of `openapi-hs` to compile the `optics-core`,
`optics-th`, `optics-extra` and `indexed-profunctors` packages even if they never write a
single `#label`.

The owner of this repository uses `lens` exclusively across their projects. After this plan is
complete, `openapi-hs` will offer **only** the `lens` accessors, and the `optics` family of
packages will be gone from the build entirely — not merely removed from the `build-depends`
list, but absent from the resolved build plan, so that a downstream project that depends on
`openapi-hs` never compiles an optics package on its account.

Removing the direct `optics-core` and `optics-th` dependencies is not enough on its own.
`openapi-hs` depends on `insert-ordered-containers`, and version `0.3.0` of that package
**unconditionally** depends on `optics-core` and `optics-extra` with no Cabal flag to turn them
off. So optics would still be pulled into every build plan. This plan therefore also brings the
small amount of `insert-ordered-containers` code that `openapi-hs` actually uses into this
repository (a technique called *vendoring*: copying third-party source into your own tree,
preserving its copyright notice, so you no longer depend on the upstream package), strips the
optics instances out of the copies, and drops `insert-ordered-containers` from
`build-depends` as well.

Here is what you will be able to observe when this plan is done. From the repository root you
run a dependency resolution and inspect the resulting build plan, and no package whose name
begins with `optics` appears, nor `indexed-profunctors`, nor `insert-ordered-containers`:

```bash
cabal build all --dry-run
python3 - <<'PY'
import json
plan = json.load(open('dist-newstyle/cache/plan.json'))
names = sorted({u['pkg-name'] for u in plan['install-plan']})
offenders = [n for n in names
             if n.startswith('optics')
             or n in ('indexed-profunctors', 'insert-ordered-containers')]
print('offenders:', offenders)
PY
```

Expected output:

```text
offenders: []
```

Today, before any of the work in this plan, the same command prints:

```text
offenders: ['indexed-profunctors', 'insert-ordered-containers', 'optics-core', 'optics-extra', 'optics-th']
```

And the library still does everything it did before: `cabal test all` passes every existing
test, and the bundled `example` executable still prints a byte-for-byte identical OpenAPI 3.1
document.

Because the module `Data.OpenApi.Optics` disappears and the module
`Data.HashSet.InsOrd` (previously supplied by `insert-ordered-containers`) is replaced by a
module shipped from this repository, this is a **breaking change** for downstream users and
will be released as version `5.0.0`.


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented here,
even if it requires splitting a partially completed task into two ("done" vs. "remaining").
This section must always reflect the actual current state of the work.

- [ ] M0: Record the baseline. Run `cabal build all` and `cabal test all` on the untouched
      tree and paste the tail of the output into Surprises & Discoveries so later failures can
      be attributed correctly. Capture the current `offenders:` list from the command in
      Purpose / Big Picture.
- [ ] M1: Delete `src/Data/OpenApi/Optics.hs`, remove its re-export and import from
      `src/Data/OpenApi.hs`, strip the optics instance block out of
      `src/Data/HashMap/Strict/InsOrd/Compat.hs`, and remove `optics-core` / `optics-th` /
      `OverloadedLabels` from `openapi-hs.cabal`.
- [ ] M1: Update `README.md` (section "Lenses and optics") and the `$lens` Haddock note in
      `src/Data/OpenApi.hs` so they no longer advertise an optics interface.
- [ ] M1: `cabal build all && cabal test all` green.
- [ ] M1: Commit.
- [ ] M2: Add `Data/HashMap/InsOrd/Compat/Internal.hs` (the vendored `SortedAp` helper) and
      `Data/HashMap/Strict/InsOrd/Compat/Impl.hs` (the vendored `InsOrdHashMap`
      implementation, optics stripped) under `src/`, and register both in `openapi-hs.cabal`.
- [ ] M2: Repoint `src/Data/HashMap/Strict/InsOrd/Compat.hs` at the vendored implementation
      and delete its `MIN_VERSION_insert_ordered_containers` CPP branch.
- [ ] M2: `cabal build all && cabal test all` green.
- [ ] M2: Commit.
- [ ] M3: Add `src/Data/HashSet/InsOrd/Compat.hs` (the vendored `InsOrdHashSet`, optics
      stripped), register it in `openapi-hs.cabal`, and repoint the four modules that import
      `Data.HashSet.InsOrd`.
- [ ] M3: Remove `insert-ordered-containers` from both `build-depends` stanzas in
      `openapi-hs.cabal`.
- [ ] M3: `cabal build all && cabal test all` green.
- [ ] M3: Commit.
- [ ] M4: Prove the build plan is optics-free with the `offenders:` command; update `LICENSE`
      with the vendored code's copyright notice; bump `version:` to `5.0.0`; write the `5.0.0`
      CHANGELOG entry; re-run `nix fmt` (or `treefmt`) and the full test suite.
- [ ] M4: Commit and fill in Outcomes & Retrospective.


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

(None yet.)


## Decision Log

Record every decision made while working on the plan.

- Decision: Remove `Data.OpenApi.Optics` outright rather than shipping a deprecated shim for
  one release cycle.
  Rationale: A `{-# DEPRECATED #-}` shim would keep `optics-core` and `optics-th` in
  `build-depends` for another release, which defeats the stated purpose of the work (the
  packages must actually stop being compiled). The repository owner uses `lens` in every
  project, so there is no internal consumer to shield, and `4.1.0 -> 5.0.0` already signals a
  breaking release.
  Date: 2026-07-21

- Decision: Also vendor the parts of `insert-ordered-containers` that `openapi-hs` uses, so
  that `insert-ordered-containers` can be dropped from `build-depends`.
  Rationale: `insert-ordered-containers-0.3.0` lists `optics-core` and `optics-extra` as
  unconditional library dependencies with no Cabal flag guarding them (verified by reading the
  `.cabal` file for `0.3.0` out of the local Hackage index). Keeping the dependency would leave
  `optics-core`, `optics-extra` and `indexed-profunctors` in every resolved build plan, so the
  goal "drop the optics dependencies" would not actually be met.
  Date: 2026-07-21

- Decision: Vendor rather than fork-and-publish a patched `insert-ordered-containers`, and
  rather than replacing `InsOrdHashMap` with a different data structure.
  Rationale: Publishing a fork means maintaining and releasing another package, and it would
  still be an external dependency. Swapping the data structure would change JSON key ordering
  in every generated schema and touch essentially every module. Vendoring is contained: this
  repository already wraps the upstream type in its **own** `newtype` inside
  `src/Data/HashMap/Strict/InsOrd/Compat.hs`, and the total upstream code involved is about
  1,000 lines across three modules, of which roughly twelve lines per module are optics.
  Date: 2026-07-21

- Decision: Ship the vendored code under module names that mirror the upstream paths
  (`Data.HashMap.Strict.InsOrd.Compat.Impl`, `Data.HashMap.InsOrd.Compat.Internal`,
  `Data.HashSet.InsOrd.Compat`) instead of burying it under `Data.OpenApi.Internal.*`.
  Rationale: Mirroring the upstream layout makes the provenance obvious and makes it cheap to
  re-diff against a future upstream release. It also matches the naming already used by the
  existing wrapper module `Data.HashMap.Strict.InsOrd.Compat`.
  Date: 2026-07-21

- Decision: Drop the `OverloadedLabels` default extension from `openapi-hs.cabal` in M1.
  Rationale: It exists only so that `Data.OpenApi.Optics`'s `#field` labels resolve. A search
  of `src/`, `test/` and `examples/` finds no other use of the `#label` syntax.
  Date: 2026-07-21

- Decision: While vendoring, drop the upstream instances that `openapi-hs` does not use —
  `NFData`/`NFData1`/`NFData2` (from `deepseq`), `Apply`/`Bind` (from `semigroupoids`), and the
  `aeson` instances on the *map* type — instead of copying them verbatim.
  Rationale: Each dropped instance removes a package from the vendored module's import list.
  Dropping them is observably safe: the public wrapper `newtype` in
  `src/Data/HashMap/Strict/InsOrd/Compat.hs` derives only `Show`, `Read`, `Data`, `Functor`,
  `Foldable`, `Traversable` (stock) plus `Semigroup`, `Monoid` (newtype), and hand-writes its
  own `Eq`, `ToJSON`/`FromJSON` and indexed instances, so no `NFData`, `Apply`, `Bind` or
  upstream-`aeson` instance is reachable from `openapi-hs`'s public API today. The *set* type
  has no wrapper, so its `aeson` instances **are** reachable and must be kept.
  Date: 2026-07-21

- Decision: Release as `5.0.0`.
  Rationale: `Data.OpenApi.Optics` is removed from the public module list, and the module
  `Data.HashSet.InsOrd` that downstream code needs in order to build a value for
  `OpenApi._openApiTags` moves from `insert-ordered-containers` into this package under a new
  name. Both are source-breaking for downstream users.
  Date: 2026-07-21


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose.

(To be filled during and after implementation.)


## Context and Orientation

This section assumes you have never opened this repository before. Everything you need to
navigate the work is spelled out here.

**What the project is.** `openapi-hs` is a single-package Cabal project at the repository root.
The package description lives in `openapi-hs.cabal`; the project-level Cabal settings live in
`cabal.project` (which is just `packages: .` plus `tests: true`). The library source is under
`src/`, the test suite under `test/`, and a single demonstration executable under `examples/`.
The Haskell module namespace is `Data.OpenApi.*` — that is a deliberate holdover from the
`openapi3` package this project forked from, so the module names do not match the package name.
Builds target GHC 9.12.4 and 9.14.1. There is a Nix flake (`flake.nix`, with the real wiring in
`nix/haskell.nix`, `nix/treefmt.nix`, `nix/pre-commit.nix`) that provides a dev shell, but every
command in this plan works with a plain `cabal` and `ghc` on `PATH`; `ghc --version` should
print `9.12.4`.

**Terms used in this plan.**

An *optic* is a first-class value that focuses on part of a larger data structure so you can
read it, write it, or traverse it. A *lens* is the kind of optic that focuses on exactly one
part (for example, the `title` field of an `Info` record). There are two competing Haskell
libraries that provide optics: `lens` (the older, larger one, where optics compose with the
ordinary function composition operator `.`) and `optics` (the newer one, where optics compose
with `%` and are usually written as overloaded labels like `#title`). This repository currently
supports both. This plan deletes the `optics` support.

*Template Haskell* is GHC's compile-time code generation facility. Both accessor modules use it:
`makeFields`/`makeLensesWith` (from `lens`) and `makeFieldLabels`/`makePrismLabels` (from
`optics-th`) read a record definition at compile time and emit one accessor per field. This is
why adding a field to a record automatically produces accessors in both styles today — and why
deleting the optics module costs nothing in ongoing maintenance beyond the deletion itself.

*Vendoring* means copying third-party source code into your own repository (keeping its
copyright notice) so that you no longer depend on the upstream package.

*Orphan instance* is a typeclass instance defined in a module that owns neither the class nor
the type. Several modules here carry `{-# OPTIONS_GHC -fno-warn-orphans #-}` for that reason;
leave those pragmas alone.

**The files that matter, and how they fit together.**

`src/Data/OpenApi/Internal.hs` (about 1,400 lines) defines every record type in the OpenAPI
data model — `OpenApi`, `Info`, `PathItem`, `Operation`, `Schema`, `Responses`, and so on. It
defines no accessors itself.

`src/Data/OpenApi/Lens.hs` (191 lines) is the `lens` accessor module. It calls `makeFields` and
`makeLensesWith openApiFieldRules` on each record type from `Internal.hs`, then hand-writes a
few extra instances: prisms for `SecuritySchemeType` and `Referenced`, the reviews
`_OpenApiItemsBoolean` and `_OpenApiItemsObject`, `Ixed`/`At` instances that let you write
`at 404` directly on a `Responses` or an `Operation`, and a block of `OVERLAPPABLE` instances
that forward schema accessors (`format`, `items`, `maximum_`, …) through a `NamedSchema` to its
inner `Schema`. **This module survives untouched.**

`src/Data/OpenApi/Optics.hs` (379 lines) is the mirror image of `Lens.hs` for the `optics`
library. It calls `makeFieldLabels`/`makePrismLabels`, hand-writes `LabelOptic` instances for
`_OpenApiItemsBoolean`/`_OpenApiItemsObject`, `Optics.Ixed`/`Optics.At` for `Responses` and
`Operation`, and eighteen `LabelOptic` instances forwarding `#type`, `#default`, `#format`, …
from `NamedSchema` to its inner `Schema`. Its module header exports nothing (`module
Data.OpenApi.Optics () where`); it exists purely for its instances. **This module is deleted.**

`src/Data/OpenApi.hs` (441 lines) is the umbrella module users import. Line 36 re-exports
`module Data.OpenApi.Lens`, line 37 re-exports `module Data.OpenApi.Optics`, line 135 imports
`Data.OpenApi.Lens`, line 137 imports `Data.OpenApi.Optics ()`, and line 218 is a Haddock
paragraph telling readers to look at `Data.OpenApi.Optics` if they prefer optics.

`src/Data/HashMap/Strict/InsOrd/Compat.hs` (about 520 lines) is this repository's own
compatibility wrapper around `insert-ordered-containers`. An `InsOrdHashMap` is a hash map that
remembers the order in which keys were inserted, which is what makes generated OpenAPI JSON
deterministic. Upstream version `0.3.0` changed the `Eq` and Aeson instances in a way that
breaks this project's expectations (it began encoding maps as arrays of key/value pairs rather
than as JSON objects, and made `Eq` order-sensitive), so this module wraps the upstream type in
a `newtype` and re-implements those instances the way `openapi-hs` needs them: JSON objects for
encoding, order-insensitive `Eq`. The rest of the module is roughly fifty one-line delegations
(`insert`, `lookup`, `union`, `foldrWithKey`, …). It also defines, for its own `newtype`, the
indexed-container instances and both the `lens` and `optics` `Ixed`/`At` instances. It is
guarded by a CPP conditional `#if !MIN_VERSION_insert_ordered_containers(0,3,0)` whose "else"
branch (the one that actually runs today, since `0.3.0` resolves) contains all of the wrapping
code, and whose "then" branch is a bare re-export for older upstream versions.

**How optics currently enters the build.** Two ways. Directly: `openapi-hs.cabal` lists
`optics-core >=0.2 && <0.5` and `optics-th >=0.2 && <0.5` in the library `build-depends`
(lines 81–82), and lists `Data.OpenApi.Optics` in `exposed-modules` (line 49), and enables
`OverloadedLabels` as a default extension (line 93). Indirectly: `insert-ordered-containers`
(library `build-depends` line 79, test-suite `build-depends` line 117) resolves to `0.3.0`,
whose own library `build-depends` include `optics-core >=0.4.1.1 && <0.5` and
`optics-extra >=0.4.2.1 && <0.5` unconditionally.

**A subtlety that makes M1 easy.** In `src/Data/HashMap/Strict/InsOrd/Compat.hs`, the block
labelled `-- indexed-traversals` defines `Optics.FunctorWithIndex`, `Optics.FoldableWithIndex`
and `Optics.TraversableWithIndex` instances. Those look like optics-only code, but they are not:
both `lens-5.3.6` and `optics-core-0.4.2` obtain those three classes from the *same* small
package, `indexed-traversable`, and merely re-export them. `Control.Lens` re-exports them via
`Control.Lens.Indexed` (see `FunctorWithIndex(..)`, `FoldableWithIndex(..)` and
`TraversableWithIndex(..)` in that module's export list). So those instances must be **kept**;
only the qualifier on their names changes from `Optics.` to `Lens.`. Only the block labelled
`-- Optics` (the `Optics.Index`/`Optics.IxValue` type instances and the `Optics.Ixed`/
`Optics.At` instances) is genuinely optics-specific and gets deleted.

**What `openapi-hs` actually uses from `insert-ordered-containers`.** Only two modules, and
only through narrow doors:

`Data.HashMap.Strict.InsOrd` is imported by exactly one file — `src/Data/HashMap/Strict/InsOrd/Compat.hs`
— which re-exports a curated fifty-function surface under its own `newtype`. Because the
`newtype`'s data constructor and its `unCompatInsOrdHashMap` field are **not** exported, no
downstream user can obtain an upstream `InsOrdHashMap` from `openapi-hs`, and swapping the
underlying implementation is therefore invisible to them.

`Data.HashSet.InsOrd` is imported directly by four files:
`src/Data/OpenApi/Internal.hs` (for the type `InsOrdHashSet`, used in the fields
`_openApiTags`, `_serverVariableEnum` and `_operationTags`, and in an `OpenApiMonoid`
instance), `src/Data/OpenApi/Internal/AesonUtils.hs` (one `AesonDefaultValue` instance),
`src/Data/OpenApi/Operation.hs` (two calls to `InsOrdHS.fromList`), and
`test/Data/OpenApiSpec.hs` (two calls to `InsOrdHS.fromList`). Unlike the map, the set type is
used *unwrapped* and appears in the public record types, so replacing it is a source-breaking
change for downstream code that constructs tags.

Nothing in this repository imports `Data.HashMap.InsOrd.Internal` directly, but both upstream
modules do: it holds a 41-line free-applicative helper called `SortedAp` used to run an
`Applicative` traversal in insertion order.

**Upstream source you will copy from.** The three files come from
`https://github.com/erikd/insert-ordered-containers` at tag `v0.3.0` (commit `afe9396`,
"Version 0.3.0"). They are `src/Data/HashMap/Strict/InsOrd.hs` (660 lines),
`src/Data/HashSet/InsOrd.hs` (335 lines) and `src/Data/HashMap/InsOrd/Internal.hs` (41 lines).
The package is BSD-3-Clause, authored by Oleg Grenrus and maintained by Erik de Castro Lopo;
the copyright notice must be carried into this repository's `LICENSE`. Obtain the source with:

```bash
git clone --depth 1 --branch v0.3.0 \
  https://github.com/erikd/insert-ordered-containers /tmp/ioc-v0.3.0
```

**Formatting.** The repository formats Haskell with `fourmolu` (configuration in
`fourmolu.yaml`: two-space indentation, trailing commas, trailing import/export style) and
`.cabal` files with `cabal-fmt`, both wired through `nix fmt` / `treefmt` and installed as a
pre-commit hook (`nix/treefmt.nix`, `nix/pre-commit.nix`). Vendored upstream code is written in
a different style (four-space indentation, leading commas) and **will** be reformatted by the
hook. That is expected and fine; do not fight it, and do not hand-reformat before running the
formatter.

**Doctests are not executed.** Several modules contain `>>>` examples in their Haddock
comments, including `src/Data/OpenApi/Optics.hs`. There is no `doctest` test-suite in
`openapi-hs.cabal` (`build-type` is `Simple`, and the only test-suite is `spec`), so those
examples are documentation only and are never run. Do not go looking for a doctest failure that
cannot happen.


## Plan of Work

The work splits into four milestones. Milestone 0 is a five-minute baseline capture. Milestone
1 removes the optics *API surface* and the direct optics dependencies; it is self-contained and
already delivers most of the user-visible change. Milestones 2 and 3 vendor the two
`insert-ordered-containers` modules that stand between us and an optics-free build plan, one
module at a time so each step compiles and tests on its own. Milestone 4 proves the outcome,
records the licence obligation, and prepares the `5.0.0` release.

### Milestone 0 — Baseline

Before changing anything, confirm the tree builds and tests green, and record what the build
plan looks like today. This exists so that if something fails in M1 you know whether you broke
it. At the end of this milestone nothing has changed in the working tree; you have a transcript
pasted into Surprises & Discoveries and the "before" `offenders:` list.

Run, from the repository root:

```bash
cabal build all
cabal test all --test-show-details=direct
```

Both must succeed. A known-good tail of the build output looks like:

```text
Preprocessing test suite 'spec' for openapi-hs-4.1.0...
Building test suite 'spec' for openapi-hs-4.1.0...
```

Then capture the current dependency situation using the `offenders:` script from
Purpose / Big Picture. Today it prints
`offenders: ['indexed-profunctors', 'insert-ordered-containers', 'optics-core', 'optics-extra', 'optics-th']`.

### Milestone 1 — Remove the optics accessor surface

Scope: delete `src/Data/OpenApi/Optics.hs`; unhook it from the umbrella module
`src/Data/OpenApi.hs`; strip the optics-specific instance block out of
`src/Data/HashMap/Strict/InsOrd/Compat.hs` while keeping the indexed-container instances that
merely *looked* like optics; drop `optics-core`, `optics-th` and the now-unused
`OverloadedLabels` default extension from `openapi-hs.cabal`; and correct the two places in the
documentation that advertise an optics interface.

At the end of this milestone the package no longer has any direct dependency on any optics
package, and `import Data.OpenApi.Optics` fails to resolve. `optics-core` and `optics-extra`
will still appear in the build plan, pulled in by `insert-ordered-containers`; that is expected
and is what M2 and M3 fix.

The edits, file by file:

In `openapi-hs.cabal`, delete the line `Data.OpenApi.Optics` from the library's
`exposed-modules` (currently line 49); delete the two `build-depends` entries
`optics-core >=0.2 && <0.5` and `optics-th >=0.2 && <0.5` (currently lines 81–82); and delete
`OverloadedLabels` from `default-extensions` (currently line 93).

In `src/Data/OpenApi.hs`, delete `module Data.OpenApi.Optics,` from the export list (line 37)
and `import Data.OpenApi.Optics ()` from the import list (line 137). Then rewrite the Haddock
note at line 218. It currently reads:

```haskell
-- Note: if you're working with the <https://hackage.haskell.org/package/optics optics> library, take a look at "Data.OpenApi.Optics".
```

Replace it with a sentence that points at the lens module instead, for example:

```haskell
-- Note: all accessors live in "Data.OpenApi.Lens" and are re-exported here.
```

Delete `src/Data/OpenApi/Optics.hs` with `git rm`.

In `src/Data/HashMap/Strict/InsOrd/Compat.hs`, make three changes. Delete the import line
`import qualified Optics.Core         as Optics`. In the block headed `-- indexed-traversals`,
change the three instance heads from `Optics.FunctorWithIndex`, `Optics.FoldableWithIndex` and
`Optics.TraversableWithIndex` to `Lens.FunctorWithIndex`, `Lens.FoldableWithIndex` and
`Lens.TraversableWithIndex` — the module already has `import qualified Control.Lens as Lens`,
and as explained in Context and Orientation these are literally the same three classes, so the
instances keep working. Then delete the entire block headed `-- Optics`, which is the two type
instances `Optics.Index`/`Optics.IxValue` and the two instances `Optics.Ixed`/`Optics.At`. Do
**not** touch the block headed `-- Lens` above it, and in particular keep the helper `ixImpl`,
which the surviving `lens` `Ixed` instance uses.

In `README.md`, rewrite the section currently titled `## Lenses and optics` (around line 120).
It presently says every record field has an accessor in both styles and shows both
`import Data.OpenApi` and `import Data.OpenApi.Optics`. Retitle it `## Lenses`, drop the
`optics` sentence and the second import line, and delete the trailing sentence "The
corresponding optics labels keep the bare name (`#type`, `#const`, …)." Also update the bullet
near line 35 that reads "**`lens` and `optics`** accessors for ergonomic reads and updates." to
mention only `lens`.

Acceptance for M1: `cabal build all` succeeds, `cabal test all --test-show-details=direct`
reports zero failures, and `grep -rn "optics" --include='*.hs' --include='*.cabal' src test examples openapi-hs.cabal`
returns nothing (the historical CHANGELOG entry at `CHANGELOG.md:124` and the `docs/plans/`
files legitimately still mention optics and are out of scope).

### Milestone 2 — Vendor the insertion-ordered hash map

Scope: bring the upstream `InsOrdHashMap` implementation into this repository as two new
internal modules and point the existing wrapper at them, so that
`src/Data/HashMap/Strict/InsOrd/Compat.hs` no longer imports anything from
`insert-ordered-containers`. The set type is still imported from upstream after this milestone,
so the package still depends on `insert-ordered-containers`; M3 finishes the job.

At the end of this milestone two new files exist under `src/`, the CPP conditional in the
wrapper is gone, and everything still builds and tests green.

Create `src/Data/HashMap/InsOrd/Compat/Internal.hs` as a copy of the upstream
`src/Data/HashMap/InsOrd/Internal.hs` (41 lines, the `SortedAp` free applicative used to run a
traversal in insertion order), with the module header renamed to
`Data.HashMap.InsOrd.Compat.Internal` and a Haddock comment recording that it is vendored from
`insert-ordered-containers 0.3.0`, BSD-3-Clause, © Oleg Grenrus. Nothing else changes; this file
imports only `Prelude` and `Control.Applicative`.

Create `src/Data/HashMap/Strict/InsOrd/Compat/Impl.hs` as a copy of the upstream
`src/Data/HashMap/Strict/InsOrd.hs` (660 lines), with the module header renamed to
`Data.HashMap.Strict.InsOrd.Compat.Impl`, the same vendoring/licence Haddock comment, and the
following deletions. Delete the imports `qualified Optics.At as Optics` and
`qualified Optics.Core as Optics`, and delete the whole section headed `-- Optics` (the type
instances `Optics.Index`/`Optics.IxValue` and the instances `Optics.Ixed`/`Optics.At`). Delete
the `Control.DeepSeq` imports and the four `NFData`/`NFData1`/`NFData2` instances (on `P` and on
`InsOrdHashMap`). Delete the `Data.Functor.Apply` and `Data.Functor.Bind` imports and the
`Apply` and `Bind` instances. Delete the `qualified Data.Aeson as A` and
`qualified Data.Aeson.Types as A` imports and the whole `-- Aeson` section (the `ToJSON2`,
`ToJSON1`, `ToJSON`, `FromJSON1` and `FromJSON` instances) — the wrapper in
`src/Data/HashMap/Strict/InsOrd/Compat.hs` defines its own JSON instances on its `newtype` and
never reaches these. Change `import Data.HashMap.InsOrd.Internal` to
`import Data.HashMap.InsOrd.Compat.Internal`. Keep everything else, in particular: the
`FunctorWithIndex`/`FoldableWithIndex`/`TraversableWithIndex` instances, the whole `-- Lens`
section with `ixImpl`, `hashMap` and `unorderedTraversal`, and every exported function, because
the wrapper delegates to about fifty of them.

If GHC reports an unused import after those deletions (for example a name from the explicit
`Prelude` import list that only the deleted Aeson code used), remove just that name. Build with
`-Wall` is not enabled for this package by default, so also do a quick read-through for imports
left dangling.

Register both new modules in `openapi-hs.cabal`. `Data.HashMap.Strict.InsOrd.Compat` stays in
`exposed-modules` because it is part of the public API. Add a `other-modules:` stanza to the
`library` section listing `Data.HashMap.InsOrd.Compat.Internal` and
`Data.HashMap.Strict.InsOrd.Compat.Impl`; there is currently no `other-modules` field in the
library stanza, so create one immediately after `exposed-modules`. These two are implementation
detail and must not be importable by downstream users.

Finally, edit `src/Data/HashMap/Strict/InsOrd/Compat.hs`. Delete the CPP conditional entirely:
remove the `#if !MIN_VERSION_insert_ordered_containers(0,3,0)` line, the two-line "then" branch
(`import Prelude hiding (...)` and `import Data.HashMap.Strict.InsOrd`), the `#else` line and
the closing `#endif` at the very bottom of the file, keeping the body of the "else" branch.
Change `import qualified Data.HashMap.Strict.InsOrd as InsOrdHashMap` to
`import qualified Data.HashMap.Strict.InsOrd.Compat.Impl as InsOrdHashMap`. The `{-# LANGUAGE
CPP #-}` pragma at the top can now be removed as well. Note that the local `newtype
InsOrdHashMap` and the qualified alias `InsOrdHashMap` deliberately share a name; that already
works today and is unaffected.

Acceptance for M2: `cabal build all` succeeds and `cabal test all --test-show-details=direct`
reports zero failures. Additionally,
`grep -rn "Data.HashMap.Strict.InsOrd\b" --include='*.hs' src test` should return nothing —
every reference now goes through the vendored `.Compat.Impl` module or the wrapper.

### Milestone 3 — Vendor the insertion-ordered hash set and drop the dependency

Scope: bring the upstream `InsOrdHashSet` implementation into this repository as one new
exposed module, repoint the four files that import `Data.HashSet.InsOrd`, and remove
`insert-ordered-containers` from both `build-depends` stanzas.

At the end of this milestone the package has no dependency on `insert-ordered-containers` at
all.

Create `src/Data/HashSet/InsOrd/Compat.hs` as a copy of the upstream `src/Data/HashSet/InsOrd.hs`
(335 lines), with the module header renamed to `Data.HashSet.InsOrd.Compat`, the vendoring and
licence Haddock comment, and these deletions: the imports `qualified Optics.At as Optics` and
`qualified Optics.Core as Optics` and the whole section headed `-- Optics` (type instances
`Optics.Index`/`Optics.IxValue`, instances `Optics.Ixed`/`Optics.At`/`Optics.Contains`); the
`Control.DeepSeq` imports and the `NFData`/`NFData1` instances. Change
`import Data.HashMap.InsOrd.Internal` to `import Data.HashMap.InsOrd.Compat.Internal` (the
module you created in M2). **Keep the `Data.Aeson` import and the `ToJSON`/`FromJSON`
instances** — unlike the map, there is no wrapper `newtype` for the set, so `openapi-hs`
serializes `InsOrdHashSet` through these instances directly (`OpenApi._openApiTags` and
`Operation._operationTags` are encoded with them). Keep the `lens` `Ixed`/`At`/`Contains`
instances and the `hashSet` iso.

Add `Data.HashSet.InsOrd.Compat` to `exposed-modules` in `openapi-hs.cabal`. It must be exposed,
not an `other-module`, because `InsOrdHashSet` appears in the public record types and downstream
code needs `fromList` to build a tag set.

Repoint the four importers. In `src/Data/OpenApi/Internal.hs` change
`import Data.HashSet.InsOrd (InsOrdHashSet)` to
`import Data.HashSet.InsOrd.Compat (InsOrdHashSet)`. In
`src/Data/OpenApi/Internal/AesonUtils.hs` and `src/Data/OpenApi/Operation.hs` change
`import Data.HashSet.InsOrd qualified as InsOrdHS` to
`import Data.HashSet.InsOrd.Compat qualified as InsOrdHS`. In `test/Data/OpenApiSpec.hs` make
the same qualified-import change.

Remove `insert-ordered-containers >=0.2.3 && <0.4` from the library `build-depends` (currently
line 79) and the bare `insert-ordered-containers` entry from the test-suite `build-depends`
(currently line 117).

Acceptance for M3: `cabal build all` succeeds; `cabal test all --test-show-details=direct`
reports zero failures; and
`grep -rn "insert-ordered-containers\|Data.HashSet.InsOrd\b" --include='*.hs' --include='*.cabal' src test examples openapi-hs.cabal`
returns nothing.

### Milestone 4 — Prove it, license it, release it

Scope: demonstrate that optics is gone from the resolved build plan, carry the vendored code's
copyright into `LICENSE`, bump the version to `5.0.0`, write the changelog entry, and run the
formatter and the full test suite one final time.

Run the `offenders:` script from Purpose / Big Picture. It must print `offenders: []`. This is
the headline acceptance criterion for the whole plan.

Update `LICENSE`. It currently carries three copyright lines (GetShopTV, Biocad, Nadeem Bitar)
above a standard BSD-3-Clause body. Add a fourth line for the vendored code — the upstream
package is BSD-3-Clause with the same terms, so a single added copyright line plus a short note
naming the three vendored modules is sufficient:

```text
Copyright (c) 2015-2016, GetShopTV
Copyright (c) 2020, Biocad
Copyright (c) 2026, Nadeem Bitar
Copyright (c) 2015, Oleg Grenrus
All rights reserved.

The modules Data.HashMap.Strict.InsOrd.Compat.Impl, Data.HashMap.InsOrd.Compat.Internal
and Data.HashSet.InsOrd.Compat are derived from the insert-ordered-containers package
(version 0.3.0, https://github.com/erikd/insert-ordered-containers), which is
distributed under the same BSD-3-Clause terms below.
```

Bump `version:` in `openapi-hs.cabal` from `4.1.0` to `5.0.0`.

Add a `5.0.0` section at the top of `CHANGELOG.md`, above the existing `4.1.0` heading, using
the same style as the entries already there (a `5.0.0` line, a line of dashes, then bullets).
It must state, as breaking changes: that `Data.OpenApi.Optics` and the `optics` accessors are
removed and users should switch to the `lens` accessors in `Data.OpenApi.Lens` (re-exported
from `Data.OpenApi`); that `openapi-hs` no longer depends on `optics-core`, `optics-th` or
`insert-ordered-containers`; and that code which imported `Data.HashSet.InsOrd` from
`insert-ordered-containers` to construct tag sets must now import
`Data.HashSet.InsOrd.Compat` from `openapi-hs`. Mention that the insertion-ordered map and set
implementations are vendored from `insert-ordered-containers 0.3.0` under BSD-3-Clause.

Also refresh `README.md` if the M1 edits left anything stale, and check the "Lenses" section
reads correctly end to end.

Run the formatter and the full suite:

```bash
nix fmt
cabal build all
cabal test all --test-show-details=direct
```

If you are not in the Nix dev shell, `fourmolu --mode inplace` over `src/`, `test/` and
`examples/` plus `cabal-fmt --inplace openapi-hs.cabal` is equivalent; the pre-commit hook will
run `treefmt` anyway when you commit.

Acceptance for M4: `offenders: []`, tests green, formatter clean, and the `example` executable
produces the same output as it did at M0 (see Validation and Acceptance).


## Concrete Steps

Every command below is run from the repository root,
`/Users/shinzui/Keikaku/bokuno/openapi-hs-project/openapi-hs`. Update this section as work
proceeds if a command turns out to need adjusting.

**M0 — baseline.**

```bash
cabal build all
cabal test all --test-show-details=direct
cabal run -v0 example > /tmp/example-before.json
cabal build all --dry-run
python3 - <<'PY'
import json
plan = json.load(open('dist-newstyle/cache/plan.json'))
names = sorted({u['pkg-name'] for u in plan['install-plan']})
print('offenders:', [n for n in names if n.startswith('optics')
                     or n in ('indexed-profunctors', 'insert-ordered-containers')])
PY
```

Expected, before any change:

```text
offenders: ['indexed-profunctors', 'insert-ordered-containers', 'optics-core', 'optics-extra', 'optics-th']
```

**M1 — remove the optics surface.**

```bash
git rm src/Data/OpenApi/Optics.hs
# then hand-edit openapi-hs.cabal, src/Data/OpenApi.hs,
# src/Data/HashMap/Strict/InsOrd/Compat.hs and README.md as described above
cabal build all
cabal test all --test-show-details=direct
grep -rn "optics" --include='*.hs' --include='*.cabal' src test examples openapi-hs.cabal
```

The final `grep` must print nothing (exit status 1). Then commit:

```bash
git add -A
git commit -F - <<'MSG'
refactor!: remove the optics accessor surface

Delete Data.OpenApi.Optics and its re-export from Data.OpenApi, strip the
optics Ixed/At instances from the InsOrdHashMap compat wrapper, and drop
optics-core, optics-th and the OverloadedLabels default extension.

The FunctorWithIndex/FoldableWithIndex/TraversableWithIndex instances in the
compat wrapper are kept: lens and optics-core both re-export those classes
from indexed-traversable, so only the qualifier changes.

BREAKING CHANGE: Data.OpenApi.Optics and the #label accessors are gone; use
the lens accessors in Data.OpenApi.Lens.

ExecPlan: docs/plans/9-drop-optics-dependencies-in-favor-of-lens.md
Intention: intention_01ky2t2vtcekm9mrttbtye8m13
MSG
```

**M2 — vendor the map.**

```bash
git clone --depth 1 --branch v0.3.0 \
  https://github.com/erikd/insert-ordered-containers /tmp/ioc-v0.3.0

mkdir -p src/Data/HashMap/InsOrd/Compat src/Data/HashMap/Strict/InsOrd/Compat
cp /tmp/ioc-v0.3.0/src/Data/HashMap/InsOrd/Internal.hs \
   src/Data/HashMap/InsOrd/Compat/Internal.hs
cp /tmp/ioc-v0.3.0/src/Data/HashMap/Strict/InsOrd.hs \
   src/Data/HashMap/Strict/InsOrd/Compat/Impl.hs
# then apply the module renames and deletions described in Milestone 2,
# register both modules under `other-modules:` in openapi-hs.cabal,
# and repoint src/Data/HashMap/Strict/InsOrd/Compat.hs

cabal build all
cabal test all --test-show-details=direct
grep -rn "Data.HashMap.Strict.InsOrd\b" --include='*.hs' src test
```

The final `grep` must print nothing. Then commit with subject
`refactor: vendor the insertion-ordered hash map implementation` and the same two trailers.

**M3 — vendor the set and drop the dependency.**

```bash
mkdir -p src/Data/HashSet/InsOrd
cp /tmp/ioc-v0.3.0/src/Data/HashSet/InsOrd.hs src/Data/HashSet/InsOrd/Compat.hs
# apply the renames and deletions from Milestone 3, add the module to
# exposed-modules, repoint the four importers, and remove the two
# insert-ordered-containers build-depends entries

cabal build all
cabal test all --test-show-details=direct
grep -rn "insert-ordered-containers\|Data.HashSet.InsOrd\b" \
  --include='*.hs' --include='*.cabal' src test examples openapi-hs.cabal
```

The final `grep` must print nothing. Then commit with subject
`refactor!: vendor the insertion-ordered hash set and drop insert-ordered-containers`.

**M4 — prove, license, release.**

```bash
cabal build all --dry-run
python3 - <<'PY'
import json
plan = json.load(open('dist-newstyle/cache/plan.json'))
names = sorted({u['pkg-name'] for u in plan['install-plan']})
print('offenders:', [n for n in names if n.startswith('optics')
                     or n in ('indexed-profunctors', 'insert-ordered-containers')])
PY

# edit LICENSE, bump version: to 5.0.0 in openapi-hs.cabal, write the
# 5.0.0 CHANGELOG entry
nix fmt          # or: fourmolu --mode inplace src test examples && cabal-fmt --inplace openapi-hs.cabal
cabal build all
cabal test all --test-show-details=direct
cabal run -v0 example > /tmp/example-after.json
diff /tmp/example-before.json /tmp/example-after.json && echo "example output unchanged"
```

Expected:

```text
offenders: []
example output unchanged
```

Then commit with subject `chore(release): 5.0.0`.


## Validation and Acceptance

Acceptance is phrased as things you can observe, not as files that exist.

**The optics packages are gone from the build.** This is the primary outcome. Resolve the build
plan and inspect it as shown above; the script must print `offenders: []`. Note that
`indexed-traversable` and `indexed-traversable-instances` **will** still be present — those are
`lens`'s own dependencies and have nothing to do with `optics`. If you want a second,
independent confirmation, `cabal build all -v2 2>&1 | grep -i optics` should find nothing but
your own file paths.

**The optics API is gone.** Ask the REPL for the deleted module and confirm it cannot be found:

```bash
cabal repl lib:openapi-hs -v0 <<'GHCI' 2>/dev/null
import Data.OpenApi.Optics
GHCI
```

Expected: an error containing `Could not find module ‘Data.OpenApi.Optics’`.

Note on these REPL snippets: `cabal repl` recompiles the library and prints a large number of
`-Wname-shadowing` warnings to stderr before the session starts. That is pre-existing noise, not
a symptom of anything in this plan. The `2>/dev/null` above discards it so you see only the
lines you asked for.

**The lens API still works.** In a REPL, build a small document with the surviving accessors and
confirm it encodes as expected:

```bash
cabal repl lib:openapi-hs -v0 <<'GHCI' 2>/dev/null
:set -XOverloadedStrings
import Data.OpenApi
import Control.Lens
import Data.Aeson (encode)
import qualified Data.ByteString.Lazy.Char8 as BSL
import qualified Data.HashMap.Strict.InsOrd.Compat as IOHM
BSL.putStrLn $ encode $ (mempty :: OpenApi) & components . schemas .~ IOHM.fromList [("User", mempty & type_ ?~ OpenApiTypeSingle OpenApiString)]
GHCI
```

Expected output, one line, verified against the tree at `4.1.0` before any of this work:

```text
{"info":{"title":"","version":""},"components":{"schemas":{"User":{"type":"string"}}},"openapi":"3.1.0"}
```

The point to verify is that the `lens` accessors `components`, `schemas` and `type_` still
compose, that `IOHM.fromList` still builds an insertion-ordered map through the vendored
implementation, and that the schema encodes as a JSON **object** (not an array of pairs). If it
encodes as an array of `[key, value]` pairs, the compat wrapper's `ToJSON` instance was lost
during M2 — that is the single most likely way to break this refactor, and the test suite
catches it too.

**Insertion order is still preserved.** The whole reason `InsOrdHashMap` exists here is
deterministic output. Confirm directly:

```bash
cabal repl lib:openapi-hs -v0 <<'GHCI' 2>/dev/null
:set -XOverloadedStrings
import Data.Aeson (encode)
import qualified Data.ByteString.Lazy.Char8 as BSL
import qualified Data.HashMap.Strict.InsOrd.Compat as IOHM
BSL.putStrLn $ encode (IOHM.fromList [("b", 1::Int), ("a", 2)])
BSL.putStrLn $ encode (IOHM.fromList [("a", 1::Int), ("b", 2)])
GHCI
```

Expected, verified against the tree at `4.1.0`:

```text
{"b":1,"a":2}
{"a":1,"b":2}
```

Two maps with the same keys in different insertion orders must encode differently. If both
lines come out identical, insertion order was lost during vendoring.

**The existing test suite passes unchanged.** `cabal test all --test-show-details=direct` must
report zero failures at the end of every milestone. The suite (`test/Spec.hs` plus the modules
listed under the `spec` test-suite in `openapi-hs.cabal`) covers JSON round-tripping, schema
generation, 3.1 core types, top-level 3.1 features, migration helpers and validation. Do not
add tests that merely assert the absence of optics; the build plan check above is the real
proof, and the existing suite is what proves nothing regressed.

**The example executable's output is byte-identical.** `cabal run -v0 example` prints a complete
OpenAPI 3.1 document. Capture it at M0 and diff it at M4; `diff` must report no differences.
This is the strongest end-to-end signal that the vendored containers behave exactly like the
upstream ones, because that document exercises ordered maps of paths, operations, responses,
schemas and tag sets all at once.

**Formatting and hooks are clean.** After `nix fmt`, `git status` should show no unexpected
churn, and committing must not be rejected by the `treefmt` pre-commit hook.


## Idempotence and Recovery

Every step in this plan is a source edit in a Git working tree, so recovery is always
`git checkout -- <path>` for an individual file or `git reset --hard HEAD` to return to the last
commit. Commit at the end of each milestone (the plan says so explicitly) precisely so that
each milestone has a clean rollback point.

The commands are safe to re-run. `cabal build all` and `cabal test all` are idempotent.
`cabal build all --dry-run` rewrites `dist-newstyle/cache/plan.json` each time and changes
nothing else. The `python3` inspection script only reads that file.

The `git clone --depth 1 --branch v0.3.0 ... /tmp/ioc-v0.3.0` will fail with "destination path
already exists" on a second run; either delete `/tmp/ioc-v0.3.0` first or skip the clone, since
its only purpose is to supply the three source files to copy. If GitHub is unreachable, the same
sources can be obtained from Hackage with
`cabal get insert-ordered-containers-0.3.0 --destdir=/tmp`.

If a build breaks in the middle of M2 or M3 with a wall of "Not in scope" errors, the usual
cause is having deleted an import line whose names were still used by surviving code (the
upstream modules use explicit `Prelude` import lists, so a missing name is a hard error rather
than a warning). Re-add the specific name to the import list rather than reverting the whole
file.

If the test suite starts failing with JSON-shaped diffs after M2 — arrays of `[key, value]`
pairs where objects were expected, or map comparisons that suddenly care about ordering — the
cause is that the compat wrapper in `src/Data/HashMap/Strict/InsOrd/Compat.hs` lost its own
`Eq`/`ToJSON`/`FromJSON` instances, or that the vendored `Impl` module's instances are being
picked up instead. Confirm that `Compat.hs` still defines `instance (Eq k, Eq v) => Eq
(InsOrdHashMap k v)` using `toHashMap`, and that its `ToJSON1` instance still builds an
`A.object`. The upstream Aeson instances are deleted in M2 exactly so they cannot be selected by
mistake.

Nothing in this plan touches a database, a network service, or any state outside the repository
and `dist-newstyle/`. Deleting `dist-newstyle/` and rebuilding is always a safe reset if the
build cache appears confused.


## Interfaces and Dependencies

**Dependencies removed.** From the `library` stanza of `openapi-hs.cabal`:
`optics-core >=0.2 && <0.5` and `optics-th >=0.2 && <0.5` (M1), and
`insert-ordered-containers >=0.2.3 && <0.4` (M3). From the `spec` test-suite stanza:
`insert-ordered-containers` (M3). Transitively this also removes `optics-extra` and
`indexed-profunctors` from the build plan.

**Dependencies added.** None. Everything the vendored modules need is already a direct
dependency of `openapi-hs`: `base`, `hashable`, `unordered-containers`, `transformers` (for
`Control.Monad.Trans.State.Strict`), `lens` (for `At`, `Ixed`, `Index`, `IxValue`, `Iso`,
`Traversal`, `Contains`, and the re-exported `FunctorWithIndex`/`FoldableWithIndex`/
`TraversableWithIndex` classes) and `aeson` (needed by the vendored *set* module only). The
`deepseq` and `semigroupoids` packages are **not** added because the instances that would
require them are deleted during vendoring.

**Modules deleted.** `Data.OpenApi.Optics` (file `src/Data/OpenApi/Optics.hs`).

**Modules added.**

`Data.HashMap.InsOrd.Compat.Internal` — file `src/Data/HashMap/InsOrd/Compat/Internal.hs`,
listed under `other-modules`. Vendored from `insert-ordered-containers 0.3.0`. Must export the
type `SortedAp` and the functions

```haskell
liftSortedAp    :: Int -> f a -> SortedAp f a
retractSortedAp :: Applicative f => SortedAp f a -> f a
```

`Data.HashMap.Strict.InsOrd.Compat.Impl` — file
`src/Data/HashMap/Strict/InsOrd/Compat/Impl.hs`, listed under `other-modules`. Vendored from
`insert-ordered-containers 0.3.0` with the optics, `NFData`, `Apply`/`Bind` and Aeson instances
removed. Must export the type `InsOrdHashMap` and the same function list the upstream module
exports (`empty`, `singleton`, `null`, `size`, `member`, `lookup`, `lookupDefault`, `insert`,
`insertWith`, `delete`, `adjust`, `update`, `alter`, `union`, `unionWith`, `unionWithKey`,
`unions`, `map`, `mapKeys`, `traverseKeys`, `mapWithKey`, `traverseWithKey`, `unorderedTraverse`,
`unorderedTraverseWithKey`, `difference`, `intersection`, `intersectionWith`,
`intersectionWithKey`, `foldl'`, `foldlWithKey'`, `foldr`, `foldrWithKey`, `foldMapWithKey`,
`unorderedFoldMap`, `unorderedFoldMapWithKey`, `filter`, `filterWithKey`, `mapMaybe`,
`mapMaybeWithKey`, `keys`, `elems`, `toList`, `toRevList`, `fromList`, `toHashMap`,
`fromHashMap`, `hashMap`, `unorderedTraversal`, `valid`), because
`Data.HashMap.Strict.InsOrd.Compat` delegates to all of them. It must retain the instances
`Show`, `Read`, `Data`, `Functor`, `Foldable`, `Traversable`, `Eq`, `Semigroup`, `Monoid`,
`Hashable`, `IsList`, `FunctorWithIndex`, `FoldableWithIndex`, `TraversableWithIndex`, `Ixed`
and `At` — the first eight because the wrapper `newtype` derives from them, the rest because the
wrapper or its users need them.

`Data.HashSet.InsOrd.Compat` — file `src/Data/HashSet/InsOrd/Compat.hs`, listed under
`exposed-modules`. Vendored from `insert-ordered-containers 0.3.0` with the optics and `NFData`
instances removed and the Aeson instances **kept**. Must export the type `InsOrdHashSet` and
`empty`, `singleton`, `null`, `size`, `member`, `insert`, `delete`, `union`, `map`, `difference`,
`intersection`, `filter`, `toList`, `fromList`, `toHashSet`, `fromHashSet`, `hashSet`, `valid`,
and must retain the instances `Eq`, `Show`, `Read`, `Semigroup`, `Monoid`, `Foldable`,
`Hashable`, `IsList`, `Data`, `ToJSON`, `FromJSON`, `Ixed`, `At` and `Contains`.

**Modules changed, and their public contracts.**

`Data.OpenApi` — the export list loses `module Data.OpenApi.Optics`. Everything else it exports
is unchanged.

`Data.HashMap.Strict.InsOrd.Compat` — its export list, the `newtype InsOrdHashMap` (still
abstract: neither the constructor nor `unCompatInsOrdHashMap` is exported) and every function
signature stay **exactly as they are today**. Only the module it delegates to changes, plus the
removal of its optics `Ixed`/`At` instances and the re-qualification of its three indexed
instances. This is what keeps M2 invisible to downstream users.

`Data.OpenApi.Internal`, `Data.OpenApi.Internal.AesonUtils`, `Data.OpenApi.Operation` — their
import of `Data.HashSet.InsOrd` becomes an import of `Data.HashSet.InsOrd.Compat`. No exported
type or function signature changes; `InsOrdHashSet` is still `InsOrdHashSet`, it just comes from
a module in this package now.

`Data.OpenApi.Lens` — untouched. It remains the single accessor module and is still re-exported
from `Data.OpenApi`.
