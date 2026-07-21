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
test, a new ordered-container characterization suite passes before and after each vendoring
step, and the bundled `example` executable still prints a byte-for-byte identical OpenAPI 3.1
document. The characterization suite is required because the existing OpenAPI tests exercise
the containers only indirectly and would not reliably catch a change in duplicate-key
handling, union bias, traversal order, lens behavior, or the `valid` invariant.

The release is also gated on a downstream migration rehearsal. The registered reverse
dependents `servant-openapi-hs`, `relay-pagination`, and `kansoku` must compile and run their
OpenAPI tests against the local `5.0.0` candidate before publication. This matters because
`servant-openapi-hs` and `relay-pagination`
currently import `Data.HashMap.Strict.InsOrd` directly. Under their present constraints they
select `insert-ordered-containers-0.2.7`, so the current CPP compatibility branch makes their
map type line up with `openapi-hs-4.1.0`; the always-wrapped map in `5.0.0` requires those
consumers to switch to `Data.HashMap.Strict.InsOrd.Compat`.

Because the module `Data.OpenApi.Optics` disappears and the module
`Data.HashSet.InsOrd` (previously supplied by `insert-ordered-containers`) is replaced by a
module shipped from this repository, this is a **breaking change** for downstream users and
will be released as version `5.0.0`.


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented here,
even if it requires splitting a partially completed task into two ("done" vs. "remaining").
This section must always reflect the actual current state of the work.

- [x] (2026-07-21) Plan validation: confirmed the untouched GHC 9.12.4 baseline builds, all
      463 tests pass, the example renders 1,616 bytes, and the resolved offender list is
      `['indexed-profunctors', 'insert-ordered-containers', 'optics-core', 'optics-extra',
      'optics-th']`; audited Hackage/upstream provenance, dependency bounds, licensing, direct
      test coverage, and Mori reverse dependents. M0 remains unchecked so its committed test
      baseline and before/after artifact are captured during implementation.
- [x] (2026-07-21) M0: Recorded the baseline. `cabal build all` and `cabal test all` on the untouched
      tree and paste the tail of the output into Surprises & Discoveries so later failures can
      be attributed correctly. Captured the current `offenders:` list from the command in
      Purpose / Big Picture, plus the 1,616-byte example at `/tmp/example-before.json`.
- [x] (2026-07-21) M0: Added and ran permanent characterization tests for the public compat map and the
      public insertion-ordered set while they still delegate to the released
      `insert-ordered-containers`; include operation-model properties, order-sensitive output,
      JSON, duplicate-key behavior, folds/traversals, lens operations, `valid`, and upstream
      overflow regression coverage. The expanded suite passes with 487 examples; the set tests
      preserve the released union/`valid` caveat described below.
- [x] (2026-07-21) M1: Deleted `src/Data/OpenApi/Optics.hs`, removed its re-export and import from
      `src/Data/OpenApi.hs`, stripped the optics instance block out of
      `src/Data/HashMap/Strict/InsOrd/Compat.hs`, removed `optics-core` / `optics-th` /
      `OverloadedLabels` from `openapi-hs.cabal`, and raised the honest `lens` lower bound to
      `5.3.6`, the current release tested with both supported compilers.
- [x] (2026-07-21) M1: Updated `README.md` (now section "Lenses") and the `$lens` Haddock note in
      `src/Data/OpenApi.hs` so they no longer advertise an optics interface.
- [x] (2026-07-21) M1: `cabal build all`, the `lens ==5.3.6` dry-run, and all 487 tests are green;
      the scoped `rg` for optics references returns no matches.
- [x] (2026-07-21) M1: Committed the independently validated optics-surface removal.
- [x] (2026-07-21) M2: Added `Data/HashMap/InsOrd/Compat/Internal.hs` (the vendored `SortedAp` helper) and
      `Data/HashMap/Strict/InsOrd/Compat/Impl.hs` (the vendored `InsOrdHashMap`
      implementation, optics stripped) under `src/`, and registered both in `openapi-hs.cabal`.
      Both hash-verified sources were reviewed against Hackage before formatting.
- [x] (2026-07-21) M2: Repointed `src/Data/HashMap/Strict/InsOrd/Compat.hs` at the vendored
      implementation and deleted its `MIN_VERSION_insert_ordered_containers` CPP branch.
- [x] (2026-07-21) M2: `cabal build all` and all 487 tests are green; the scoped search for a
      direct upstream ordered-map import returns no matches.
- [x] (2026-07-21) M2: Committed the independently validated map vendoring milestone.
- [x] (2026-07-21) M3: Added `src/Data/HashSet/InsOrd/Compat.hs` (the vendored
      `InsOrdHashSet`, optics stripped but all non-optics instances retained), registered it in
      `openapi-hs.cabal`, and repointed the five modules that imported `Data.HashSet.InsOrd`
      after M0.
- [x] (2026-07-21) M3: Removed `insert-ordered-containers` from both `build-depends` stanzas in
      `openapi-hs.cabal` and added the direct `deepseq` dependency required by the retained
      public `NFData`/`NFData1` set instances.
- [x] (2026-07-21) M3: `cabal build all` and all 487 tests are green; the dependency/import
      scoped search returns no upstream package declaration or set import.
- [x] (2026-07-21) M3: Committed the independently validated set vendoring milestone.
- [x] (2026-07-21) M4: Proved the build plan is optics-free with `offenders: []`; added the complete
      upstream BSD-3-Clause text under `LICENSES/` and included it in the source distribution;
      bumped `version:` to `5.0.0`; wrote the `5.0.0` CHANGELOG and migration entries; and
      re-ran `nix fmt` and the full test suite.
- [x] (2026-07-21) M4: Ran `cabal check`, built the Haddocks, created and inspected the sdist, and
      built/tested the unpacked sdist so missing internal modules or third-party notices cannot
      reach Hackage.
- [x] (2026-07-21) M4: Re-ran `mori registry dependents shinzui/openapi-hs --packages` and
      completed green detached-worktree migration rehearsals for `servant-openapi-hs`,
      `relay-pagination`, and `kansoku`.
- [x] (2026-07-21) M4: Ran all 487 tests locally with both supported compilers, GHC 9.12.4 and
      GHC 9.14.1.
- [ ] Release gate: require the GitHub Actions GHC 9.12.4 and 9.14.1 jobs to be green on the final
      commit before publishing. This cannot be observed until the local commit is pushed.
- [x] (2026-07-21) M4: Added the durable ADR, filled in Outcomes & Retrospective, and committed
      the locally complete implementation.


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

- Finding: The pre-migration baseline is green on the local GHC 9.12.4 toolchain, but direct
  ordered-container coverage is much thinner than the overall test count suggests.
  Evidence: On 2026-07-21, `cabal test all --test-show-details=direct` completed with
  `463 examples, 0 failures`; `cabal run -v0 example` produced 1,616 bytes. A repository search
  found only scattered calls to `keys`, `lookup`, `unionWith`, and `fromList`, not contract
  tests for the roughly fifty functions exported by `Data.HashMap.Strict.InsOrd.Compat`.

- Finding: The released upstream tag recorded in the first draft was wrong. Hackage currently
  lists `insert-ordered-containers-0.3.0` as the newest release, and the upstream `v0.3.0` tag
  resolves to commit `d4a5c25e19081560b00655f2ffef796189a1e833` dated 2026-03-04, not
  `afe9396`. A source obtained with `cabal get insert-ordered-containers-0.3.0` is identical to
  the three relevant files at that tag. The source-file SHA-256 values are
  `aa7dddd0d4c62d7dbecda0a2a37b3188ab4642cfbfe9ebf798d4145bd7060579` for
  `Data/HashMap/InsOrd/Internal.hs`,
  `59f14017ecba215b9264a25c8d2aa5575bd313ba66b4e02bfb320c6d518e419f` for
  `Data/HashMap/Strict/InsOrd.hs`, and
  `2c0d1e5e65ed18f9b541821917ec67411532e163240dce14f65840f11d637e14` for
  `Data/HashSet/InsOrd.hs`.

- Finding: Removing `NFData`/`NFData1` from the vendored set would be an avoidable public API
  regression. `InsOrdHashSet` appears directly in exported OpenAPI record fields, and both
  `insert-ordered-containers-0.2.7` and `0.3.0` provide those instances. The revised plan keeps
  them and adds `deepseq` as a direct dependency. The map implementation remains hidden behind
  this repository's wrapper, so stripping unused instances from that hidden implementation is
  still safe.

- Finding: Copying the upstream map imports verbatim would introduce an undeclared dependency.
  The `0.3.0` source imports the indexed traversal classes directly from the
  `indexed-traversable` package, while `openapi-hs.cabal` lists only `lens`. Cabal package
  hiding does not make a transitive dependency importable. Importing the classes through
  `Control.Lens` in both the wrapper and hidden implementation uses the public API of the now
  required `lens-5.3.6` without adding or guessing a transitive dependency.

- Finding: The declared `lens >=4.16.1` lower bound is not a usable compatibility claim for the
  current compiler matrix. On GHC 9.12.4, a dry-run with `lens ==4.16.1` fails because that lens
  line requires `vector <0.13`, whose released versions require `base <4.20`; a dry-run with
  `lens ==5.2.3` fails because it requires `template-haskell <2.22`. The authoritative Hackage
  metadata for current `lens-5.3.6` explicitly includes GHC 9.12.2 and GHC 9.14.1 and permits
  `template-haskell <2.25`. An explicit local dry-run with `lens ==5.3.6` resolves on GHC
  9.12.4. The revised v5 bound is `lens >=5.3.6 && <5.4`.

- Finding: The current CPP branch makes the map type selected by `openapi-hs-4.1.0` depend on
  the solver's `insert-ordered-containers` version. Known reverse dependents
  `servant-openapi-hs` and `relay-pagination` constrain that dependency below `0.3` and import
  `Data.HashMap.Strict.InsOrd` directly. The v5 implementation always uses the compat wrapper
  newtype, so those consumers require a compile-time migration to
  `Data.HashMap.Strict.InsOrd.Compat`. This is a known source break, not a runtime behavior to
  leave for users to discover.

- Finding: Merging the upstream copyright line into the repository's existing BSD text is not
  a faithful preservation of the upstream notice because the third non-endorsement clause names
  different parties. The complete upstream license must ship separately and verbatim. Its
  SHA-256 is `eef5ffdb683ddc4f93095f3a222f2d29b109c0e3dcb4dc46e1ed3b984e61391a`.

- Finding: The released `InsOrdHashSet.union` does not preserve its documented `valid`
  invariant when the right operand contributes a new member. The implementation offsets the
  right indices by `i + 1` but records the new exclusive bound as `i + j`, so the last right
  index can equal rather than remain below the bound. Membership, insertion order, JSON, and
  normalization through `fromHashSet . toHashSet` still behave correctly.
  Evidence: The first M0 property run failed after 23 generated cases on `valid`; the minimal
  focused case `union (singleton "a") (singleton "b")` has `valid == False`, while applying
  `fromHashSet . toHashSet` makes it `True`. The permanent set operation model requires
  `valid` for every union-free tree and separately characterizes this released union caveat.

- Finding: Mori's reverse-dependency query works and still reports `shinzui/servant-openapi-hs`,
  `shinzui/relay-pagination`, and `shinzui/kansoku`, but `mori registry list`, `search`, and
  `show` currently fail because the installed CLI queries project lifecycle columns that are
  absent from the registry database schema.
  Evidence: `mori registry dependents shinzui/openapi-hs --packages` succeeded on 2026-07-21;
  the other registry commands returned PostgreSQL error `42703` for `p.lifecycle` or
  `deprecation_alternative`. The vendored dependency source was therefore obtained from the
  authoritative Hackage `0.3.0` release as already prescribed, and all four pinned hashes
  matched.

- Finding: An interrupted/overlapping Cabal rebuild can leave missing `.o.tmp` rename errors in
  `dist-newstyle`, even though the source compiles. The recovery documented in this plan works.
  Evidence: The first M1 test rebuild reported missing temporary objects in four test modules;
  after confirming no repository Cabal process remained, `cabal clean` followed by a single
  `cabal test all --test-show-details=direct` completed with `487 examples, 0 failures`.

- Finding: The original M3 acceptance search was too broad: required provenance comments in
  all three vendored modules intentionally contain the text `insert-ordered-containers`, so a
  blanket text search cannot return no matches after correct implementation.
  Evidence: After both Cabal dependency entries and every upstream set import were removed,
  the original command matched only provenance/Haddock comments. The acceptance command now
  targets Cabal list entries and Haskell import declarations, and returns no matches.

- Finding: The source distribution is self-contained and retains every required source and
  notice file.
  Evidence: `cabal check`, `cabal haddock all`, and `cabal sdist` succeeded. After extracting
  `openapi-hs-5.0.0.tar.gz` into a fresh temporary directory, `cabal build all` and
  `cabal test all --test-show-details=direct` passed all 487 examples. The tarball contains the
  three vendored modules, both characterization specs, `MIGRATION_4_TO_5.md`, and the exact
  upstream license. The post-migration example remains 1,616 bytes with SHA-256
  `908d4c96efe9b693aba1828bd8d4c9009ff2f5a38aa74f66f119f850ed10272f` and is byte-identical
  to the M0 artifact.

- Finding: All three Mori-reported consumers migrate with only the anticipated import,
  dependency, and version-bound edits.
  Evidence: In detached temporary worktrees, `cabal test spec --test-show-details=direct`
  passed 19 `servant-openapi-hs` examples; `cabal test relay-pagination-servant-test
  members-server-test --jobs=1 --test-show-details=direct` passed Relay's 23 and 4 examples;
  `cabal test kansoku-core-test --test-show-details=direct --test-options='--match
  Kansoku.Api.OpenApi.kansokuOpenApi'` passed 15 Kansoku examples; and `cabal build
  exe:kansoku-openapi` succeeded. The provider stack used local `openapi-hs-5.0.0` and migrated
  `servant-openapi-hs-5.0.0` candidates. The worktrees were removed afterward, and the original
  consumer checkouts were unchanged.

- Finding: Running both Relay suites concurrently can strand the servant test server after its
  first ten client/server checks even though neither suite has a migration failure. Cabal's
  serialized `--jobs=1` run completes both suites immediately and repeatably.
  Evidence: The first combined invocation completed all four `members-server-test` cases but
  stopped making progress during `decodes mixed ClientPage as 400 sum`. That process was
  interrupted after the hang; running the servant suite alone passed all 23 tests, then the
  combined `--jobs=1` command passed both suites.

- Finding: The flake's pinned Nixpkgs exposes GHC 9.14.1 even though the default development
  shell currently exposes only GHC 9.12.4.
  Evidence: A temporary Nix shell containing `haskell.compiler.ghc9141` and `cabal-install`
  reported GHC 9.14.1/Cabal 3.16.1.0. `cabal test all --builddir=dist-newstyle-ghc9141
  --test-show-details=direct` then built the candidate and passed all 487 examples. GitHub
  Actions still remains the publication gate for both jobs on the final pushed commit.


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

- Decision: Define all retained indexed-container instances through the classes exported by
  `Control.Lens`, including inside the hidden vendored map implementation.
  Rationale: Cabal exposes only direct dependencies. Keeping the upstream imports from
  `Data.*.WithIndex` would require a new direct `indexed-traversable` dependency.
  `Control.Lens` re-exports the same classes in the required lens release, so using it preserves
  the lens API without relying on a transitive package.
  Date: 2026-07-21

- Decision: Raise the `lens` lower bound from `4.16.1` to `5.3.6` while retaining the `<5.4`
  upper bound.
  Rationale: This package declares GHC 9.12.4 and 9.14.1 as its supported compilers. Older lens
  releases cannot resolve with their installed `base`/`template-haskell` versions, while
  Hackage `lens-5.3.6` is the current release and explicitly tests GHC 9.14.1. A truthful lower
  bound is safer than an untested compatibility claim, especially for a major release.
  Date: 2026-07-21

- Decision: Strip unused instances only from the hidden vendored map implementation. Keep all
  non-optics instances on the public vendored set, including `NFData`, `NFData1`, `ToJSON`, and
  `FromJSON`, and add `deepseq` as a direct library dependency.
  Rationale: The public wrapper `newtype` in `src/Data/HashMap/Strict/InsOrd/Compat.hs` does not
  expose the hidden implementation's `NFData`, `Apply`, `Bind`, or upstream Aeson instances, so
  deleting those instances cannot alter the wrapper's API. `InsOrdHashSet`, in contrast,
  appears unwrapped in exported OpenAPI records, and both supported upstream versions provide
  `NFData` and `NFData1`; deleting them would be an unnecessary regression for downstream code.
  Date: 2026-07-21

- Decision: Release as `5.0.0`.
  Rationale: `Data.OpenApi.Optics` is removed from the public module list, and the module
  `Data.HashSet.InsOrd` that downstream code needs in order to build a value for
  `OpenApi._openApiTags` moves from `insert-ordered-containers` into this package under a new
  name. In addition, consumers that previously forced `insert-ordered-containers <0.3` and used
  `Data.HashMap.Strict.InsOrd` to build OpenAPI map fields must switch to the always-wrapped
  `Data.HashMap.Strict.InsOrd.Compat` type. These are source-breaking changes.
  Date: 2026-07-21

- Decision: Add characterization tests before changing the implementation and keep them as
  permanent regression tests after vendoring.
  Rationale: A green OpenAPI suite and byte-identical example are strong end-to-end signals but
  do not exercise every ordered-container behavior on which deterministic rendering depends.
  Running the same operation-model, ordering, JSON, lens, and invariant tests against the
  released dependency first and the vendored code later turns current behavior into an
  executable contract.
  Date: 2026-07-21

- Decision: Pin vendoring provenance to the immutable Hackage `0.3.0` source and verify its
  three source-file hashes; use upstream tag commit
  `d4a5c25e19081560b00655f2ffef796189a1e833` only as an independent cross-check.
  Rationale: Mori has no registered `insert-ordered-containers` project, and a movable or
  mistyped Git tag is a weak source of truth. Hackage is the authoritative released package;
  hash checks prevent silently copying a different file, while the matching upstream tag gives
  useful provenance for future diffs.
  Date: 2026-07-21

- Decision: Ship the complete upstream BSD-3-Clause license verbatim in
  `LICENSES/insert-ordered-containers-BSD-3-Clause.txt`, list it in `extra-source-files`, and
  retain short provenance comments in every vendored module.
  Rationale: Adding only Oleg Grenrus's copyright line above this repository's BSD text would
  not retain the upstream package's exact non-endorsement condition. The separate notice is
  unambiguous and can be verified in the source distribution.
  Date: 2026-07-21

- Decision: Treat the known reverse-dependent builds and both supported GHC versions as release
  gates.
  Rationale: `openapi-hs` can pass its own tests while breaking the way `servant-openapi-hs`
  constructs ordered maps. Mori currently reports `servant-openapi-hs`, `relay-pagination`,
  and `kansoku` as reverse dependents. Their OpenAPI test suites catch package-boundary and
  integration failures that unit tests cannot.
  Date: 2026-07-21

- Decision: Preserve the released `InsOrdHashSet.union` index-bound behavior during this
  dependency-removal change instead of silently fixing it in the vendored copy.
  Rationale: M0 exists to make the before/after behavior executable, and the plan otherwise
  permits no algorithm changes to the hash-verified vendored source. Membership, ordering, and
  serialization remain correct; changing the `valid` result would be an unrelated behavioral
  fix that should be reviewed separately. The characterization suite requires `valid` for
  union-free operation trees, records the union caveat explicitly, and proves callers can
  normalize with `fromHashSet . toHashSet`.
  Date: 2026-07-21


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose.

Plan-validation outcome (2026-07-21): implementation has not started. The audit converted the
highest-risk assumptions into explicit gates: permanent pre/post characterization tests, full
retention of the set's non-optics instances, hash-pinned released source, an honest lens lower
bound, complete third-party licensing in the sdist, unpacked-sdist testing, reverse-dependent
migration rehearsals, and two-compiler CI. Fill in the implementation outcome after M4.

Milestone 0 outcome (2026-07-21): the untouched GHC 9.12.4 build and all 463 original tests
passed, the example baseline is 1,616 bytes with SHA-256
`908d4c96efe9b693aba1828bd8d4c9009ff2f5a38aa74f66f119f850ed10272f`, and the offender list
matched the plan. The permanent map/set characterization suites raise the total to 487 passing
examples and exposed the released set union/`valid` caveat without changing production code.

Milestone 1 outcome (2026-07-21): the public optics module, direct optics dependencies,
overloaded-label extension, wrapper optics instances, and optics documentation are gone. The
surviving indexed instances now use the classes re-exported by `Control.Lens`; the package
resolves at the new `lens ==5.3.6` lower bound and all 487 tests pass. Optics remains only as an
indirect dependency of `insert-ordered-containers`, which Milestones 2 and 3 remove.

Milestone 2 outcome (2026-07-21): the compat map wrapper now delegates exclusively to two
hidden, hash-verified modules vendored from `insert-ordered-containers-0.3.0`. The CPP-dependent
public type switch is gone; the wrapper still owns order-insensitive equality and object-shaped
JSON. The complete pre-format upstream diff contained only the authorized provenance/module
renames, indexed-class import move, and removal of optics, Aeson, deepseq, Apply, and Bind code.
All 487 tests pass unchanged.

Milestone 3 outcome (2026-07-21): the public insertion-ordered set is now exposed from this
package as `Data.HashSet.InsOrd.Compat`; all five internal/test importers use it, every
non-optics upstream instance remains, and `deepseq` is direct. `insert-ordered-containers` is
absent from both dependency stanzas. The pre-format upstream diff contained only the authorized
provenance/module/internal-import changes and optics removal, and all 487 tests pass unchanged.

Milestone 4 outcome (2026-07-21): the resolved plan reports `offenders: []`; version 5.0.0,
release notes, a focused migration guide, exact upstream licensing, and ADR 0001 are in place.
The lens and insertion-order REPL checks pass, the example is byte-identical to M0, and all 487
tests pass under both GHC 9.12.4 and GHC 9.14.1. Haddocks, Cabal package checks, and a cleanly
unpacked source distribution all build successfully. Mori still reports the same three reverse
dependents, and all three pass their OpenAPI-focused migration rehearsals against the local
candidate stack. The implementation is locally complete; publication remains deliberately
blocked until GitHub Actions is green for both compilers on the final pushed commit.


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

**Relevant ADR.** This repository had no `docs/adr/` directory when the plan began. Completion
created `docs/adr/0001-use-lens-and-own-ordered-containers.md`, which records the durable
lens-only API, vendored-container ownership and provenance, licensing requirement, compatibility
policy, and intentionally preserved set-union behavior distilled from this plan.

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

**A subtlety that makes M1 easy but must be handled explicitly in M2.** In
`src/Data/HashMap/Strict/InsOrd/Compat.hs`, the block labelled `-- indexed-traversals` defines
`Optics.FunctorWithIndex`, `Optics.FoldableWithIndex` and `Optics.TraversableWithIndex`
instances. Those capabilities are not optics-specific and must be kept. Change their qualifier
to `Lens.` so they follow the classes exported by `Control.Lens`.
The newly required `lens-5.3.6` re-exports these classes from `indexed-traversable`. Sourcing
them through `Control.Lens` keeps that transitive package out of this package's direct imports.
Only the block labelled `-- Optics`
(the `Optics.Index`/`Optics.IxValue` type instances and the `Optics.Ixed`/`Optics.At`
instances) is genuinely optics-specific and gets deleted.

The upstream `0.3.0` map source imports these three classes directly from
`Data.Functor.WithIndex`, `Data.Foldable.WithIndex`, and `Data.Traversable.WithIndex`, which
would require `openapi-hs` to declare `indexed-traversable` directly. During M2, delete those
three direct imports and add
`FunctorWithIndex(..)`, `FoldableWithIndex(..)`, and `TraversableWithIndex(..)` to the existing
explicit `Control.Lens` import instead. This is an intentional compatibility import change;
the instance method bodies remain identical.

**What `openapi-hs` actually uses from `insert-ordered-containers`.** Only two modules, and
only through narrow doors:

`Data.HashMap.Strict.InsOrd` is imported by exactly one file — `src/Data/HashMap/Strict/InsOrd/Compat.hs`
— which re-exports a curated fifty-function surface under its own `newtype`. Because the
`newtype`'s data constructor and its `unCompatInsOrdHashMap` field are **not** exported, no
downstream user can obtain an upstream `InsOrdHashMap` from `openapi-hs`, and swapping the
underlying implementation is therefore invisible to them.

`Data.HashSet.InsOrd` is currently imported directly by four files:
`src/Data/OpenApi/Internal.hs` (for the type `InsOrdHashSet`, used in the fields
`_openApiTags`, `_serverVariableEnum` and `_operationTags`, and in an `OpenApiMonoid`
instance), `src/Data/OpenApi/Internal/AesonUtils.hs` (one `AesonDefaultValue` instance),
`src/Data/OpenApi/Operation.hs` (two calls to `InsOrdHS.fromList`), and
`test/Data/OpenApiSpec.hs` (two calls to `InsOrdHS.fromList`). Unlike the map, the set type is
used *unwrapped* and appears in the public record types, so replacing it is a source-breaking
change for downstream code that constructs tags. M0 adds
`test/Data/HashSet/InsOrdSpec.hs` as a fifth importer; M3 must repoint that characterization
spec along with the original four.

Nothing in this repository imports `Data.HashMap.InsOrd.Internal` directly, but both upstream
modules do: it holds a 41-line free-applicative helper called `SortedAp` used to run an
`Applicative` traversal in insertion order.

**Upstream source you will copy from.** The three files come from
the Hackage release `insert-ordered-containers-0.3.0`. Hackage lists `0.3.0` as the latest
release as of 2026-07-21. The source is identical to
`https://github.com/erikd/insert-ordered-containers` at tag `v0.3.0` (commit
`d4a5c25e19081560b00655f2ffef796189a1e833`). The files are
`src/Data/HashMap/Strict/InsOrd.hs` (660 lines),
`src/Data/HashSet/InsOrd.hs` (335 lines) and `src/Data/HashMap/InsOrd/Internal.hs` (41 lines).
The package is BSD-3-Clause, authored by Oleg Grenrus and maintained by Erik de Castro Lopo;
the complete license notice must ship with this repository. Obtain the immutable released
source with:

```bash
cabal get insert-ordered-containers-0.3.0 --destdir="$IOC_AUDIT_DIR"
shasum -a 256 \
  "$IOC_AUDIT_DIR/insert-ordered-containers-0.3.0/src/Data/HashMap/InsOrd/Internal.hs" \
  "$IOC_AUDIT_DIR/insert-ordered-containers-0.3.0/src/Data/HashMap/Strict/InsOrd.hs" \
  "$IOC_AUDIT_DIR/insert-ordered-containers-0.3.0/src/Data/HashSet/InsOrd.hs"
```

The expected hashes, in the same order, are:

```text
aa7dddd0d4c62d7dbecda0a2a37b3188ab4642cfbfe9ebf798d4145bd7060579
59f14017ecba215b9264a25c8d2aa5575bd313ba66b4e02bfb320c6d518e419f
2c0d1e5e65ed18f9b541821917ec67411532e163240dce14f65840f11d637e14
```

Set `IOC_AUDIT_DIR` to a fresh temporary directory first with
`IOC_AUDIT_DIR="$(mktemp -d -t openapi-ioc.XXXXXX)"`. Do not continue if a hash differs.

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

**Existing coverage and why it is insufficient by itself.** The baseline suite contains 463
passing Hspec examples and QuickCheck properties, and the example executable exercises a broad
OpenAPI document. Direct calls to the compat map in tests, however, are mostly `fromList`,
`keys`, and `lookup`; the public mutation, combination, traversal, lens, and invariant behavior
is not systematically tested. The upstream `0.3.0` package ships useful operation-model and
regression properties for the map. M0 adapts those ideas to Hspec/QuickCheck and adds equivalent
set coverage before any implementation changes, so the same tests establish both the old and
new behavior.

**Known downstream coupling.** Run
`mori registry dependents shinzui/openapi-hs --packages` whenever the plan is resumed. At the
time of this revision Mori reports `shinzui/servant-openapi-hs`,
`shinzui/relay-pagination`, and `shinzui/kansoku`. The first two contain direct imports of
`Data.HashMap.Strict.InsOrd`; their Cabal files also constrain
`insert-ordered-containers <0.3` and `openapi-hs <5`. They must change those imports and type
signatures to `Data.HashMap.Strict.InsOrd.Compat`, remove the obsolete direct ordered-container
dependency where it is no longer otherwise used, and relax their openapi bounds before they can
consume `5.0.0`. `kansoku` consumes OpenAPI through both packages and is the final integration
check.

The known edits are narrow and compile-checked. In `servant-openapi-hs`, change the two imports
in `src/Servant/OpenApi/Internal.hs` to the compat module; its uses of `InsOrdHashMap`,
`fromList`, `unionWith`, `insert`, and `insertWith` are all present in the wrapper. Remove the
library's `insert-ordered-containers` dependency and change the `openapi-hs` bounds in every
component from `<5` to `<6`. In `relay-pagination`, change the direct ordered-map imports in
`relay-pagination-servant/test/Main.hs` and
`examples/members-server/src/Example/OpenApi.hs` to the compat module, remove the corresponding
test/example ordered-container dependencies, and update both `openapi-hs` and
`servant-openapi-hs` bounds for their compatible v5 releases. In `kansoku`, update the exact
constraints in `cabal.project` only after the two provider packages build together, then run
the OpenAPI tests in `kansoku-core/test/Kansoku/OpenApiSpec.hs` and the API package tests. Use
Mori again at execution time because these paths and bounds may have advanced.

After making those temporary migration edits, run
`cabal test spec --test-show-details=direct` from the `servant-openapi-hs` root; run
`cabal test relay-pagination-servant-test members-server-test --test-show-details=direct` from
the `relay-pagination` root; and run
`cabal test kansoku-core-test --test-show-details=direct --test-options='--match Kansoku.Api.OpenApi.kansokuOpenApi'`
from the `kansoku` root. Also build the `kansoku-openapi` executable so the document generator
is typechecked against the candidate stack. If a repository's current component names differ,
obtain them from its `.cabal` files, update this plan, and record the exact successful command.


## Plan of Work

The work splits into five milestones numbered 0 through 4. Milestone 0 captures the baseline
and adds characterization tests while the released dependency is still in place. Milestone 1
removes the optics *API surface* and the direct optics dependencies; it is self-contained and
already delivers most of the user-visible change. Milestones 2 and 3 vendor the two
`insert-ordered-containers` modules that stand between us and an optics-free build plan, one
module at a time so each step compiles and runs the same contract tests on its own. Milestone 4
proves the outcome, verifies the source distribution and license payload, rehearses known
downstream migrations, and prepares the `5.0.0` release.

### Milestone 0 — Baseline

Before changing production code, confirm the tree builds and tests green, record what the build
plan looks like today, and then add ordered-container contract tests that run against the
released dependency. This exists so that if something fails after vendoring you know whether
the new implementation changed established behavior. At the end of this milestone production
behavior is unchanged; the working tree contains only new tests and plan evidence, and you have
the "before" `offenders:` list.

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

Add `test/Data/HashMap/Strict/InsOrd/CompatSpec.hs` and
`test/Data/HashSet/InsOrdSpec.hs`, and list them under the test suite's `other-modules` in
`openapi-hs.cabal`. Add `deepseq` to the test suite's `build-depends` for the instance smoke
tests. These tests become the executable compatibility boundary for the vendoring work.

The map spec imports `Data.HashMap.Strict.InsOrd.Compat` and defines a small recursive operation
model over `Word8` keys with constructors for `empty`, `singleton`, `fromList`, `insert`,
`delete`, `alter`, `union`, `difference`, `intersection`, and `filter`. For arbitrary operation
trees, compare `toHashMap` with the equivalent `Data.HashMap.Strict` evaluation and require
`valid`. Add focused examples for last-duplicate placement in `fromList`, left-biased union and
its output order, `mapKeys` collisions, `insertWith`, `unionWithKey`, `mapMaybeWithKey`,
`foldrWithKey`/`traverseWithKey` insertion order, `ix`/`at`, `show`/`read`, order-insensitive
compat equality, object-shaped Aeson encoding in insertion order, JSON round-trip semantics,
and the upstream issue-10 repeated-union overflow case. The expected JSON bytes for
`fromList [("b", 1), ("a", 2)]` are `{"b":1,"a":2}`.
For an exact duplicate example,
`fromList [("a",1),("b",2),("a",3)]` must produce
`[("b",2),("a",3)]`: the last value wins and reinsertion moves the key to the end. Union is
left-biased and keeps left order before right-only keys, so union of
`[("a",1),("b",2)]` with `[("b",9),("c",3)]` produces
`[("a",1),("b",2),("c",3)]`. For `mapKeys` collisions, compare the result with
`Data.HashMap.Strict.fromList` over the same transformed pairs and require `valid`; do not assert
which collided value wins because that depends on unordered hash-map iteration rather than the
ordered-map contract.

The set spec initially imports `Data.HashSet.InsOrd` from the released dependency. Define an
operation model for `empty`, `singleton`, `fromList`, `insert`, `delete`, `union`, `difference`,
`intersection`, `map`, and `filter`; compare membership with `Data.HashSet`, and test stable
`toList` order, duplicate insertion, union bias/order, JSON array order and
semantic round-trip, `ix`/`at`/`contains`, `show`/`read`, and forcing through both `NFData` and
`NFData1`. Require `valid` for every generated operation tree that contains no union. Separately
characterize the released union index-bound caveat: `union (singleton "a") (singleton "b")`
has correct membership and order but `valid == False`, while normalization through
`fromHashSet . toHashSet` restores `valid`. For JSON round-trips compare `toList` and membership
rather than raw set `Eq`, because
the released set equality observes internal insertion indices that decoding may compact after
deletion; preserve and document that existing caveat instead of accidentally declaring a new
contract. At the `toList` level, `fromList ["a","b","a"]` must match
`fromList ["b","a"]`, proving that reinsertion moves an existing member to the end. Require
left-biased union to keep all left-side members in their current order followed by right-only
members.

In M3 change only this test module's import to `Data.HashSet.InsOrd.Compat`; all expectations
must remain unchanged.

Run the full suite after adding the tests and commit this milestone separately. The tests must
pass against the released implementation before they are accepted as proof about the vendored
one.

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
`OverloadedLabels` from `default-extensions` (currently line 93). Change the `lens` dependency
from `>=4.16.1 && <5.4` to `>=5.3.6 && <5.4`. Hackage `5.3.6` is the current release and the
first declared lower bound in this package that is explicitly tested with GHC 9.14.1.

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

Delete `src/Data/OpenApi/Optics.hs` with `apply_patch`.

In `src/Data/HashMap/Strict/InsOrd/Compat.hs`, make three changes. Delete the import line
`import qualified Optics.Core         as Optics`. In the block headed `-- indexed-traversals`,
change the three instance heads from `Optics.FunctorWithIndex`, `Optics.FoldableWithIndex` and
`Optics.TraversableWithIndex` to `Lens.FunctorWithIndex`, `Lens.FoldableWithIndex` and
`Lens.TraversableWithIndex` — the module already has `import qualified Control.Lens as Lens`,
and as explained in Context and Orientation these are the indexed classes appropriate to the
selected lens version. Then delete the entire block headed `-- Optics`, which is the two type
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
reports zero failures, and
`rg -n "optics" src test examples openapi-hs.cabal -g '*.hs' -g '*.cabal'`
returns nothing (the historical CHANGELOG entry at `CHANGELOG.md:124` and the `docs/plans/`
files legitimately still mention optics and are out of scope). Also run
`cabal build all --dry-run --constraint='lens ==5.3.6'`; it must resolve, proving the new lower
bound rather than only an unconstrained latest build.

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
the `Control.DeepSeq` imports and the five `NFData`/`NFData1`/`NFData2` instances (on `P` and on
`InsOrdHashMap`). Delete the `Data.Functor.Apply` and `Data.Functor.Bind` imports and the
`Apply` and `Bind` instances. Delete the `qualified Data.Aeson as A` and
`qualified Data.Aeson.Types as A` imports and the whole `-- Aeson` section (the `ToJSON2`,
`ToJSON1`, `ToJSON`, `FromJSON1` and `FromJSON` instances) — the wrapper in
`src/Data/HashMap/Strict/InsOrd/Compat.hs` defines its own JSON instances on its `newtype` and
never reaches these. Change `import Data.HashMap.InsOrd.Internal` to
`import Data.HashMap.InsOrd.Compat.Internal`. Delete the three direct imports from
`Data.Functor.WithIndex`, `Data.Foldable.WithIndex`, and `Data.Traversable.WithIndex`, and add
their class names with methods to the existing explicit `Control.Lens` import. Keep everything
else, in particular: the `FunctorWithIndex`/`FoldableWithIndex`/`TraversableWithIndex` instance
method bodies, the whole `-- Lens` section with `ixImpl`, `hashMap` and
`unorderedTraversal`, and every exported function, because the wrapper delegates to about
fifty of them.

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

Before editing either copied file, verify the three source hashes recorded in Context and
Orientation. After editing, review the complete diff against the Hackage source and confirm
that every changed hunk is one of: the module rename, the internal import rename, the provenance
comment, the three indexed-class import moves into `Control.Lens`, or one of the explicitly
authorized instance/import deletions above. Do not accept algorithmic changes during vendoring.

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
`rg -n "Data\.HashMap\.Strict\.InsOrd(\s|$)" src test -g '*.hs'` should return nothing —
every reference now goes through the vendored `.Compat.Impl` module or the wrapper.

### Milestone 3 — Vendor the insertion-ordered hash set and drop the dependency

Scope: bring the upstream `InsOrdHashSet` implementation into this repository as one new
exposed module, repoint the five files that import `Data.HashSet.InsOrd` after M0, and remove
`insert-ordered-containers` from both `build-depends` stanzas.

At the end of this milestone the package has no dependency on `insert-ordered-containers` at
all.

Create `src/Data/HashSet/InsOrd/Compat.hs` as a copy of the upstream `src/Data/HashSet/InsOrd.hs`
(335 lines), with the module header renamed to `Data.HashSet.InsOrd.Compat`, the vendoring and
licence Haddock comment, and only these deletions: the imports
`qualified Optics.At as Optics` and `qualified Optics.Core as Optics` and the whole section
headed `-- Optics` (type instances `Optics.Index`/`Optics.IxValue`, instances
`Optics.Ixed`/`Optics.At`/`Optics.Contains`). Change
`import Data.HashMap.InsOrd.Internal` to `import Data.HashMap.InsOrd.Compat.Internal` (the
module you created in M2). **Keep every non-optics instance**, including the `Control.DeepSeq`
imports and `NFData`/`NFData1`, the `Data.Aeson` import and `ToJSON`/`FromJSON`, the `lens`
`Ixed`/`At`/`Contains` instances, and the `hashSet` iso. Unlike the map implementation, the set
has no wrapper, appears directly in exported OpenAPI records, and is part of the downstream
typeclass API.

Add `Data.HashSet.InsOrd.Compat` to `exposed-modules` in `openapi-hs.cabal`. It must be exposed,
not an `other-module`, because `InsOrdHashSet` appears in the public record types and downstream
code needs `fromList` to build a tag set.

Repoint the five importers. In `src/Data/OpenApi/Internal.hs` change
`import Data.HashSet.InsOrd (InsOrdHashSet)` to
`import Data.HashSet.InsOrd.Compat (InsOrdHashSet)`. In
`src/Data/OpenApi/Internal/AesonUtils.hs` and `src/Data/OpenApi/Operation.hs` change
`import Data.HashSet.InsOrd qualified as InsOrdHS` to
`import Data.HashSet.InsOrd.Compat qualified as InsOrdHS`. In `test/Data/OpenApiSpec.hs` make
the same qualified-import change. In `test/Data/HashSet/InsOrdSpec.hs`, change the M0 import to
the compat module without changing any test body or expectation.

Remove `insert-ordered-containers >=0.2.3 && <0.4` from the library `build-depends` (currently
line 79) and the bare `insert-ordered-containers` entry from the test-suite `build-depends`
(currently line 117). Add `deepseq >=1.4.4 && <1.6` to the library `build-depends`; it is now a
direct dependency of the public set module. The test suite already gained a direct `deepseq`
dependency in M0.

Review the complete set diff against the hash-verified Hackage source. Apart from formatting,
only the module rename, internal import rename, provenance comment, optics imports, and optics
instance section may differ. Then change `test/Data/HashSet/InsOrdSpec.hs` to import
`Data.HashSet.InsOrd.Compat` and run the unchanged contract suite.

Acceptance for M3: `cabal build all` succeeds; `cabal test all --test-show-details=direct`
reports zero failures; and
`rg -n '(^|,\s*)insert-ordered-containers|import Data\.HashSet\.InsOrd(\s|$)' src test examples openapi-hs.cabal -g '*.hs' -g '*.cabal'`
returns nothing.

### Milestone 4 — Prove it, license it, release it

Scope: demonstrate that optics is gone from the resolved build plan, carry the complete
vendored-code license into the source distribution, document every source migration, validate
the package artifact rather than only the working tree, rehearse known downstream consumers,
bump the version to `5.0.0`, and run the formatter and full test suite one final time.

Run the `offenders:` script from Purpose / Big Picture. It must print `offenders: []`. This is
the headline acceptance criterion for the whole plan.

Create `LICENSES/insert-ordered-containers-BSD-3-Clause.txt` with `apply_patch`, reproducing the
upstream `LICENSE` file verbatim from the same hash-verified Hackage source. Its SHA-256 must be
`eef5ffdb683ddc4f93095f3a222f2d29b109c0e3dcb4dc46e1ed3b984e61391a`. Do not merge or
paraphrase it into the root license: its non-endorsement clause names Oleg Grenrus and other
contributors and therefore is not identical to this repository's clause. Add the notice file
to `extra-source-files` in `openapi-hs.cabal`, add Oleg Grenrus to the Cabal `copyright` field,
and add a short provenance paragraph to the root `LICENSE` naming the three derived modules and
pointing to the complete notice under `LICENSES/`.

Bump `version:` in `openapi-hs.cabal` from `4.1.0` to `5.0.0`.

Add a `5.0.0` section at the top of `CHANGELOG.md`, above the existing `4.1.0` heading, using
the same style as the entries already there (a `5.0.0` line, a line of dashes, then bullets).
It must state, as breaking changes: that `Data.OpenApi.Optics` and the `optics` accessors are
removed and users should switch to the `lens` accessors in `Data.OpenApi.Lens` (re-exported
from `Data.OpenApi`); that `openapi-hs` no longer depends on `optics-core`, `optics-th` or
`insert-ordered-containers`; and that code which imported `Data.HashSet.InsOrd` from
`insert-ordered-containers` to construct tag sets must now import
`Data.HashSet.InsOrd.Compat` from `openapi-hs`. It must also state that code which used
`Data.HashMap.Strict.InsOrd` for OpenAPI map fields must switch to
`Data.HashMap.Strict.InsOrd.Compat`. Mention that the insertion-ordered map and set
implementations are vendored from `insert-ordered-containers 0.3.0` under BSD-3-Clause and that
the `lens` lower bound is now `5.3.6` to match the supported compiler matrix.

Create `MIGRATION_4_TO_5.md` and list it under `extra-doc-files`. Give downstream users exact
before/after imports and expressions. Cover removal of `Data.OpenApi.Optics`, replacement of
optics `%` composition and `#field` labels with the re-exported `lens` accessors and `(.)`, and
the trailing-underscore names used for collisions such as `type_`, `default_`, `maximum_`, and
`minimum_`. Cover the two container migrations separately: code that imported
`Data.HashSet.InsOrd` to construct tags must import `Data.HashSet.InsOrd.Compat`, and code that
used `Data.HashMap.Strict.InsOrd` to construct any OpenAPI map field must import
`Data.HashMap.Strict.InsOrd.Compat`. Tell users to remove `optics-core`, `optics-th`, and
`insert-ordered-containers` only if their own code has no remaining independent use for them.
State that the set keeps its non-optics instances, including `NFData`/`NFData1`, and that the
compat map intentionally keeps order-insensitive equality and JSON-object encoding.
Also state the new `lens >=5.3.6 && <5.4` bound and explain that it is the release line tested
with GHC 9.12/9.14.

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

Then validate what will actually be uploaded:

```bash
cabal check
cabal haddock all
cabal sdist
```

Inspect the generated tarball under `dist-newstyle/sdist/`. It must contain all three vendored
modules, both new ordered-container specs, `MIGRATION_4_TO_5.md`, and
`LICENSES/insert-ordered-containers-BSD-3-Clause.txt`. Unpack that one tarball into a fresh
temporary directory and run `cabal build all` and `cabal test all --test-show-details=direct`
from the unpacked tree. This catches accidental reliance on unlisted working-tree files.

Finally, run `mori registry dependents shinzui/openapi-hs --packages` again so newly registered
consumers are not missed. In the registered `servant-openapi-hs` and `relay-pagination` source
trees, rehearse the documented import/type/bound changes against the local v5 checkout and run
their OpenAPI-focused tests; then run `kansoku`'s OpenAPI tests against those compatible local
packages. These rehearsals belong on temporary consumer worktrees or their own tracked plans,
not as unrecorded edits in this repository. Record exact commands and outcomes in this plan's
Surprises & Discoveries. Do not publish until the repository's GitHub Actions matrix is green
on both GHC 9.12.4 and GHC 9.14.1.

Acceptance for M4: `offenders: []`, characterization and full tests green, formatter clean,
Haddocks and the unpacked sdist build, the `example` executable produces the same bytes as at
M0, all known downstream migrations are green, and both supported-GHC CI jobs pass. Any
downstream compatibility blocker blocks the `5.0.0` publication.


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
# add the two characterization specs and register them as described in M0
cabal test all --test-show-details=direct
```

Expected, before any change:

```text
offenders: ['indexed-profunctors', 'insert-ordered-containers', 'optics-core', 'optics-extra', 'optics-th']
```

Commit the new tests with subject
`test(containers): characterize pre-vendoring behavior` and the active ExecPlan and Intention
trailers.

**M1 — remove the optics surface.**

```bash
# use apply_patch to delete src/Data/OpenApi/Optics.hs and edit openapi-hs.cabal,
# src/Data/OpenApi.hs, src/Data/HashMap/Strict/InsOrd/Compat.hs and README.md
# as described above
cabal build all
cabal test all --test-show-details=direct
cabal build all --dry-run --constraint='lens ==5.3.6'
rg -n "optics" src test examples openapi-hs.cabal -g '*.hs' -g '*.cabal'
```

The final `rg` must print nothing (exit status 1). Then commit:

```bash
git add -A
git commit -F - <<'MSG'
refactor!: remove the optics accessor surface

Delete Data.OpenApi.Optics and its re-export from Data.OpenApi, strip the
optics Ixed/At instances from the InsOrdHashMap compat wrapper, and drop
optics-core, optics-th and the OverloadedLabels default extension. Raise the
lens lower bound to 5.3.6, the release tested with the supported GHC matrix.

The FunctorWithIndex/FoldableWithIndex/TraversableWithIndex instances in the
compat wrapper are kept through the classes exported by Control.Lens.

BREAKING CHANGE: Data.OpenApi.Optics and the #label accessors are gone; use
the lens accessors in Data.OpenApi.Lens.

ExecPlan: docs/plans/9-drop-optics-dependencies-in-favor-of-lens.md
Intention: intention_01ky2t2vtcekm9mrttbtye8m13
MSG
```

**M2 — vendor the map.**

```bash
IOC_AUDIT_DIR="$(mktemp -d -t openapi-ioc.XXXXXX)"
cabal get insert-ordered-containers-0.3.0 --destdir="$IOC_AUDIT_DIR"
shasum -a 256 \
  "$IOC_AUDIT_DIR/insert-ordered-containers-0.3.0/src/Data/HashMap/InsOrd/Internal.hs" \
  "$IOC_AUDIT_DIR/insert-ordered-containers-0.3.0/src/Data/HashMap/Strict/InsOrd.hs" \
  "$IOC_AUDIT_DIR/insert-ordered-containers-0.3.0/src/Data/HashSet/InsOrd.hs"

# use apply_patch to add the two hash-verified source files at the repository
# paths from Milestone 2, apply the authorized renames/deletions, register them
# under `other-modules:`, and repoint the compat wrapper

cabal build all
cabal test all --test-show-details=direct
rg -n "Data\.HashMap\.Strict\.InsOrd(\s|$)" src test -g '*.hs'
```

The final `rg` must print nothing. Then commit with subject
`refactor: vendor the insertion-ordered hash map implementation` and the same two trailers.

**M3 — vendor the set and drop the dependency.**

```bash
# use apply_patch to add the hash-verified set source at the repository path
# from Milestone 3, apply only the authorized optics removal/renames, expose the
# module, repoint the importers, retain NFData/NFData1, remove the two
# insert-ordered-containers dependencies, and add the direct deepseq dependency

cabal build all
cabal test all --test-show-details=direct
rg -n '(^|,\s*)insert-ordered-containers|import Data\.HashSet\.InsOrd(\s|$)' \
  src test examples openapi-hs.cabal -g '*.hs' -g '*.cabal'
```

The final `rg` must print nothing. Then commit with subject
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

# add the verbatim upstream notice under LICENSES/, update Cabal packaging and
# copyright metadata, bump version: to 5.0.0, and write CHANGELOG/MIGRATION_4_TO_5.md
nix fmt          # or: fourmolu --mode inplace src test examples && cabal-fmt --inplace openapi-hs.cabal
cabal build all
cabal test all --test-show-details=direct
cabal run -v0 example > /tmp/example-after.json
diff /tmp/example-before.json /tmp/example-after.json
cabal check
cabal haddock all
cabal sdist
SDIST_AUDIT_DIR="$(mktemp -d -t openapi-sdist.XXXXXX)"
tar -tzf dist-newstyle/sdist/openapi-hs-5.0.0.tar.gz > "$SDIST_AUDIT_DIR/files.txt"
rg -n "(Compat/Impl|Compat/Internal|HashSet/InsOrd/Compat|CompatSpec|InsOrdSpec|MIGRATION_4_TO_5|insert-ordered-containers-BSD-3-Clause)" \
  "$SDIST_AUDIT_DIR/files.txt"
tar -xzf dist-newstyle/sdist/openapi-hs-5.0.0.tar.gz -C "$SDIST_AUDIT_DIR"
REPO_ROOT="$PWD"
cd "$SDIST_AUDIT_DIR/openapi-hs-5.0.0"
cabal build all
cabal test all --test-show-details=direct
cd "$REPO_ROOT"
mori registry dependents shinzui/openapi-hs --packages
```

Expected:

```text
offenders: []
The `diff` command prints no output.
```

Then commit with subject `chore(release): 5.0.0`.


## Validation and Acceptance

Acceptance is phrased as things you can observe, not as files that exist.

**The optics packages are gone from the build.** This is the primary outcome. Resolve the build
plan and inspect it as shown above; the script must print `offenders: []`. Note that
`indexed-traversable` and `indexed-traversable-instances` **will** still be present — those are
`lens`'s own dependencies and have nothing to do with `optics`. If you want a second,
independent confirmation, write `cabal build all -v2` output to a temporary log and run
`rg -i optics` on that file; it should find no dependency or compiler argument containing an
optics package name.

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

**The full and characterization suites pass at every boundary.**
`cabal test all --test-show-details=direct` must report zero failures at the end of every
milestone. The existing suite covers JSON round-tripping, schema generation, 3.1 core types,
top-level 3.1 features, migration helpers and validation. The two M0 specs separately cover the
ordered-container contract and must first pass against the released dependency, then pass
unchanged after M2/M3. The build-plan check, rather than a unit test, proves the absence of
optics.

**The vendored set retains its non-optics public instances.** The set characterization spec
must compile and force a set through `NFData` and `NFData1`, round-trip it through Aeson, and
exercise `ix`, `at`, and `contains` from `lens`. This prevents dependency cleanup from silently
shrinking the public typeclass API.

**The vendored source differs only where authorized.** Before edits, all source hashes must
match Context and Orientation. During M2 and M3, inspect complete diffs against that source.
Algorithm bodies for construction, mutation, combination, traversal, conversion, and `valid`
must be unchanged. Only module/import renames, provenance comments, formatting, and explicitly
listed instance/import deletions are accepted.

**The example executable's output is byte-identical.** `cabal run -v0 example` prints a complete
OpenAPI 3.1 document. Capture it at M0 and diff it at M4; `diff` must report no differences.
This is the strongest end-to-end signal that the vendored containers behave exactly like the
upstream ones, because that document exercises ordered maps of paths, operations, responses,
schemas and tag sets all at once.

**Formatting and hooks are clean.** After `nix fmt`, `git status` should show no unexpected
churn, and committing must not be rejected by the `treefmt` pre-commit hook.

**The distribution artifact is complete.** `cabal check` produces no package errors,
`cabal haddock all` succeeds, and the tarball from `cabal sdist` contains the three vendored
modules, both characterization specs, `MIGRATION_4_TO_5.md`, and the verbatim third-party
license. Building and testing an unpacked tarball in a fresh temporary directory must pass.

**Known consumers migrate successfully.** The latest Mori reverse-dependent list is recorded
at release time. `servant-openapi-hs` and `relay-pagination` compile and pass their
OpenAPI-focused tests after switching ordered-map imports to the compat module and accepting
`openapi-hs-5`; `kansoku` then passes its OpenAPI tests against those local candidates. A
consumer build failure blocks publication rather than being dismissed as an expected major
version break.

**Both declared compilers pass.** The GitHub Actions jobs for GHC 9.12.4 and 9.14.1 must both be
green on the final commit. A local GHC 9.12.4 run alone is not sufficient release evidence.


## Idempotence and Recovery

Every repository change in this plan is a source edit in Git. Before discarding anything,
inspect `git status --short` and `git diff` so user-owned work is never mistaken for this plan's
work. Restore only an explicitly identified plan-owned path with
`git restore --source=HEAD -- <path>` when recovery is actually desired. Never reset the whole
working tree. Commit at the end of each milestone precisely so each milestone has a narrow,
reviewable rollback point.

The commands are safe to re-run. `cabal build all` and `cabal test all` are idempotent.
`cabal build all --dry-run` rewrites `dist-newstyle/cache/plan.json` each time and changes
nothing else. The `python3` inspection script only reads that file.

Create a new temporary directory with `mktemp -d` whenever the Hackage source or sdist is
unpacked. `cabal get insert-ordered-containers-0.3.0 --destdir="$IOC_AUDIT_DIR"` is then safe to
rerun with a fresh value. Do not overwrite an existing source directory and do not proceed past
the hash check if any value differs.

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

The implementation itself touches no database or network service. Source acquisition uses a
fresh temporary directory, and downstream rehearsals must use detached temporary worktrees so
the registered consumer repositories' current working trees remain untouched. If the local
build cache is suspect, inspect its path and intentionally run `cabal clean`; this removes only
rebuildable Cabal artifacts, which must then be regenerated before continuing.


## Interfaces and Dependencies

**Dependencies removed.** From the `library` stanza of `openapi-hs.cabal`:
`optics-core >=0.2 && <0.5` and `optics-th >=0.2 && <0.5` (M1), and
`insert-ordered-containers >=0.2.3 && <0.4` (M3). From the `spec` test-suite stanza:
`insert-ordered-containers` (M3). Transitively this also removes `optics-extra` and
`indexed-profunctors` from the build plan.

**Dependency bound tightened.** `lens >=4.16.1 && <5.4` becomes
`lens >=5.3.6 && <5.4`. Hackage `lens-5.3.6` is the current release and explicitly supports
the GHC 9.12/9.14 compiler line declared by this package.

**Dependencies added.** `deepseq >=1.4.4 && <1.6` becomes a direct library dependency because
the public vendored set retains the upstream `NFData` and `NFData1` instances. The test suite
also lists `deepseq` directly for compile/runtime instance checks. Everything else the vendored
modules need is already direct: `base`, `hashable`, `unordered-containers`, `transformers` (for
`Control.Monad.Trans.State.Strict`), `lens` (for `At`, `Ixed`, `Index`, `IxValue`, `Iso`,
`Traversal`, `Contains`, and the version-appropriate indexed traversal classes exported by
`Control.Lens`), and `aeson` (needed by the vendored set). `indexed-traversable` is deliberately
not imported directly; newer lens versions re-export it and older supported lens versions own
their indexed classes. `semigroupoids` is not added because `Apply`/`Bind` are stripped only
from the hidden map implementation.

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
and `At`; the wrapper derives from or delegates through these capabilities.

`Data.HashSet.InsOrd.Compat` — file `src/Data/HashSet/InsOrd/Compat.hs`, listed under
`exposed-modules`. Vendored from `insert-ordered-containers 0.3.0` with only the optics
instances removed. Must export the type `InsOrdHashSet` and
`empty`, `singleton`, `null`, `size`, `member`, `insert`, `delete`, `union`, `map`, `difference`,
`intersection`, `filter`, `toList`, `fromList`, `toHashSet`, `fromHashSet`, `hashSet`, `valid`,
and must retain the instances `Eq`, `Show`, `Read`, `Semigroup`, `Monoid`, `Foldable`,
`Hashable`, `IsList`, `Data`, `NFData`, `NFData1`, `ToJSON`, `FromJSON`, `Ixed`, `At` and
`Contains`.

**Modules changed, and their public contracts.**

`Data.OpenApi` — the export list loses `module Data.OpenApi.Optics`. Everything else it exports
is unchanged.

`Data.HashMap.Strict.InsOrd.Compat` — its export list, the `newtype InsOrdHashMap` (still
abstract: neither the constructor nor `unCompatInsOrdHashMap` is exported) and every function
signature in the `insert-ordered-containers >=0.3` branch stay exactly as they are today. Only
the module it delegates to changes, plus the removal of its optics `Ixed`/`At` instances and
the re-qualification of its three indexed instances. This keeps M2 invisible to consumers
already using the compat module. Consumers that previously forced the `<0.3` CPP branch and
constructed OpenAPI fields with `Data.HashMap.Strict.InsOrd` must perform the documented v5
source migration to the compat module.

`Data.OpenApi.Internal`, `Data.OpenApi.Internal.AesonUtils`, `Data.OpenApi.Operation` — their
import of `Data.HashSet.InsOrd` becomes an import of `Data.HashSet.InsOrd.Compat`. No exported
type or function signature changes; `InsOrdHashSet` is still `InsOrdHashSet`, it just comes from
a module in this package now.

`Data.OpenApi.Lens` — untouched. It remains the single accessor module and is still re-exported
from `Data.OpenApi`.

**Tests and distribution metadata added.**
`test/Data/HashMap/Strict/InsOrd/CompatSpec.hs` and `test/Data/HashSet/InsOrdSpec.hs` are
permanent characterization suites. `MIGRATION_4_TO_5.md` documents source changes.
`LICENSES/insert-ordered-containers-BSD-3-Clause.txt` is the verbatim upstream notice and is
listed in the Cabal source-distribution metadata.


## Revision Note

2026-07-21: Validated the plan specifically for regression risk. Added pre/post
characterization tests for ordered maps and sets, retained every non-optics public set instance,
corrected the upstream `v0.3.0` commit and pinned released-source hashes, routed indexed classes
through `Control.Lens`, raised the stale lens lower bound to the GHC-9.14-tested `5.3.6`, made
the complete upstream license part of the checked sdist, documented both container source
migrations, and made unpacked-sdist, known reverse-dependent, and two-compiler CI checks release
gates. These changes address silent behavioral drift, avoidable API loss, packaging omissions,
and downstream integration failures discovered during the audit.

2026-07-21: During M0 implementation, revised the set characterization expectations after
proving that released `insert-ordered-containers-0.3.0` does not preserve `valid` across a
right-contributing union. The suite now preserves that observed behavior explicitly, requires
`valid` for union-free generated operations, and demonstrates normalization. Also recorded the
current Mori registry-schema mismatch while retaining its successful reverse-dependent result.

2026-07-21: During M3 implementation, narrowed the dependency-removal search to Cabal list
entries and Haskell import declarations. The original blanket text search necessarily matched
the required vendoring provenance comments and could not satisfy its own no-output acceptance
criterion after a correct implementation.

2026-07-21: Completed M4 locally. Added the release metadata, migration guide, exact third-party
notice, and ADR; verified the optics-free plan, byte-identical example, Haddocks, checked and
unpacked sdist, all three reverse-dependent migrations, and all 487 tests on both supported
compilers. Recorded `--jobs=1` as the reliable Relay rehearsal command after its two test suites
hung when Cabal ran them concurrently. Left the final-commit GitHub Actions matrix explicitly
unchecked because publishing that commit is outside this implementation run; both CI jobs remain
mandatory before Hackage publication.
