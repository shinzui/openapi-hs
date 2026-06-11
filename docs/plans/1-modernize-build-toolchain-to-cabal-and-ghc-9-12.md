---
id: 1
slug: modernize-build-toolchain-to-cabal-and-ghc-9-12
title: "Modernize Build Toolchain to Cabal and GHC 9.12"
kind: exec-plan
created_at: 2026-06-11T03:47:52Z
master_plan: "docs/masterplans/1-openapi-3-1-support-and-project-modernization.md"
---

# Modernize Build Toolchain to Cabal and GHC 9.12

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

This repository is a fork of the Haskell library `openapi3` (a library for decoding,
encoding, and manipulating OpenAPI specification documents). Today the project carries two
parallel build systems and a complicated custom build process: it has a `stack.yaml` pinned
to an ancient snapshot (`resolver: lts-16.31`), and its Cabal package uses
`build-type: Custom` with a hand-written `Setup.hs` that wires in `cabal-doctest` to run a
separate `doctests` test-suite. It claims to support eleven different GHC compilers from
8.6.5 through 9.14.1. This breadth was useful upstream but is now pure drag: it forces old
dependency lower bounds, CPP shims, and a fragile custom build path that frequently breaks
on modern GHC.

After this change, a developer can clone the repo, run a single modern toolchain
(`cabal` with GHC 9.12.4, provided by the Nix dev shell), and build and test the whole
project with two commands and nothing else. Concretely, after this plan:

- `stack.yaml` no longer exists; the project is **Cabal-only**.
- `Setup.hs` no longer exists and the package uses `build-type: Simple` (the standard,
  zero-configuration Cabal build). The `custom-setup` stanza and its `cabal-doctest`
  dependency are gone.
- The `doctests` test-suite is removed (it depended on the custom Setup). The remaining
  `spec` test-suite — the real unit/property tests, discovered by `hspec-discover` — still
  runs and passes.
- `cabal-version` is `3.0` (modern Cabal grammar) and `tested-with` lists only
  `GHC ==9.12.4 || ==9.14.1`.
- Dependency lower bounds that existed only to satisfy GHCs older than 9.12 are modernized,
  while upper bounds stay permissive enough for 9.12.4 and 9.14.1.
- CI builds and tests on GHC 9.12.4 and 9.14.1 only.

You can see it working by running, from the repository root:

```bash
nix develop -c cabal build all
nix develop -c cabal test all
```

Both succeed; the second runs the `spec` suite (not doctests) to completion. `ghc --version`
inside the dev shell reports `9.12.4`.

This plan is **EP-1** of the master plan
`docs/masterplans/1-openapi-3-1-support-and-project-modernization.md`. EP-1 is the
foundation wave: it modernizes the build and toolchain only. It contains **no OpenAPI 3.1
logic** and **no package rename**. Those are later plans (EP-2 renames the package to
`openapi-hs`; EP-7 bumps the version to `4.0.0`). This plan deliberately leaves the `.cabal`
`name` field as `openapi3` and the `version` field as `3.2.5` untouched — see the Decision
Log and Interfaces sections for why, so the next plans are not confused into thinking EP-1
forgot to rename or bump.


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented here,
even if it requires splitting a partially completed task into two ("done" vs. "remaining").
This section must always reflect the actual current state of the work.

- [x] Milestone 1 — Verify baseline (2026-06-10): `ghc --version` → 9.12.4, `cabal --version`
      → 3.16.1.0 (≥ 3.12). Baseline build state not separately recorded; proceeded straight to
      edits since the dev shell toolchain was confirmed correct.
- [x] Milestone 2 — Remove Stack (2026-06-10): deleted `stack.yaml`.
- [x] Milestone 3 — Drop the custom Setup (2026-06-10): `build-type: Custom` → `Simple`,
      removed the `custom-setup` stanza, deleted `Setup.hs`.
- [x] Milestone 4 — Remove the doctests suite (2026-06-10): removed the `test-suite doctests`
      stanza from `openapi3.cabal`, deleted `test/doctests.hs`.
- [x] Milestone 5 — Modernize Cabal metadata (2026-06-10): `cabal-version: 3.0`; `tested-with`
      trimmed to `GHC ==9.12.4 || ==9.14.1`. Also changed `license: BSD3` → `BSD-3-Clause`
      (SPDX), forced by the `cabal-version: 3.0` grammar — see Surprises & Discoveries.
- [x] Milestone 6 — Modernize dependency bounds (2026-06-10): collapsed the dual aeson branch
      to `aeson >=2.0.1.0 && <2.3`, dropped the stale GHC-7.8 `cookie` comment; other bounds
      left permissive (already cover 9.12/9.14). No solver conflicts.
- [x] Milestone 7 — Build and test clean (2026-06-10): `cabal clean && cabal build all` and
      `cabal test all` both succeed; the `spec` suite passes with `375 examples, 0 failures`,
      and only the `spec` suite runs (no `doctests`).
- [x] Milestone 8 — Update CI (2026-06-10): replaced `.github/workflows/haskell-ci.yml` with a
      hand-written GitHub Actions workflow (GHC 9.12.4 + 9.14.1); deleted `cabal.haskell-ci`.
- [x] Final (2026-06-10) — Living sections updated; master plan's EP-1 checkboxes satisfied.


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

- **`cabal-version: 3.0` requires an SPDX `license` identifier (2026-06-10).** After bumping
  `cabal-version` from `>=1.10` to `3.0`, the first `cabal build all` failed to *parse* the
  `.cabal` file:

  ```text
  openapi3.cabal:15:26: error:
  unexpected Unknown SPDX license identifier: 'BSD3' Do you mean BSD-3-Clause?
     15 | license:             BSD3
  ```

  Cabal 3.0+ validates `license:` as an SPDX expression, and the legacy Cabal license name
  `BSD3` is not valid SPDX. Fix: changed `license: BSD3` → `license: BSD-3-Clause`. This is a
  structural consequence of the grammar bump and therefore within EP-1's ownership of the
  `.cabal` *structure* (it is not the `name`/`version`/identity fields owned by EP-2/EP-7).
  The plan did not anticipate this; the `license` edit was added to Milestone 5.

- **`cabal --version` is 3.16.1.0, well above the ≥ 3.12 floor (2026-06-10).** The dev shell
  ships a newer cabal-install than the plan's example transcript (3.12.1.0); acceptance only
  required ≥ 3.12, so this is fine. The `version:` grep in the Step 9 block also matches the
  `cabal-version:` line (both contain `version:`); the `name`/`version` package fields are
  unchanged (`openapi3` / `3.2.5`) as intended.


## Decision Log

Record every decision made while working on the plan.

- Decision: Switch `build-type: Custom` → `Simple` and drop `cabal-doctest` entirely.
  Rationale: The custom Setup exists only to run the `doctests` test-suite via
  `Distribution.Extra.Doctest.defaultMainWithDoctests "doctests"` (see `Setup.hs`). The
  `cabal-doctest` approach is fragile on modern GHC/Cabal and a frequent source of build
  breakage; `build-type: Simple` is the standard zero-configuration path. The doctest text in
  module Haddock comments stays in the source as documentation — we only stop *running* it
  through the custom-Setup harness. If a future contributor wants executable doctests back,
  the modern replacement is the standalone `cabal-docspec` tool run as a separate CI step (no
  custom Setup required); that is recorded as an optional follow-up, not part of this plan.
  Date: 2026-06-10

- Decision: Target only GHC 9.12.4 and 9.14.1; drop 8.6.5 through 9.10.3.
  Rationale: The master plan calls for "GHC 9.12+". The Nix dev shell
  (`nix/haskell.nix`) already pins `pkgs.haskell.packages."ghc9124"` (GHC 9.12.4). Keeping
  9.14.1 preserves the newest compiler the current `tested-with` already lists. Narrowing to
  two compilers lets us delete old dependency-bound branches and shrink CI.
  Date: 2026-06-10

- Decision: Set `cabal-version: 3.0` (rather than `3.4` or higher).
  Rationale: `3.0` already provides the modern features we rely on (common stanzas, modern
  field grammar, `Simple` build-type with no quirks) and is supported by every Cabal that
  ships with GHC 9.12/9.14, as well as older `cabal-install` a contributor might have on their
  system. `3.4`/`3.6` add features (e.g. richer `tested-with` set syntax, `import` from named
  package descriptions) we do not need here. Choosing the lowest version that does the job
  maximizes compatibility for downstream tooling that parses the `.cabal` file. The trade-off
  is purely that we forgo a few newer conveniences we are not using.
  Date: 2026-06-10

- Decision: Remove the existing `haskell-ci`-generated workflow and `cabal.haskell-ci`, and
  hand-write a small GitHub Actions workflow using `haskell-actions/setup`.
  Rationale: The current `.github/workflows/haskell-ci.yml` is generated by the `haskell-ci`
  tool from `cabal.haskell-ci`, whose constraint-sets (`aeson-1`, `insert-ordered-containers-0.2`)
  exist solely to exercise the *old* GHCs we are dropping. Regenerating is option (a); a
  hand-written workflow for just two GHCs is option (b). We choose (b): with only two
  supported compilers, a ~30-line workflow running `cabal build all` + `cabal test all` is
  simpler to read and maintain than the large generated matrix, and removes the `haskell-ci`
  tool from the maintenance surface. We document option (a) too, in case a maintainer prefers
  to keep `haskell-ci`.
  Date: 2026-06-10

- Decision: Leave `name: openapi3` and `version: 3.2.5` unchanged in `openapi3.cabal`.
  Rationale: Integration Point IP-1 of the master plan assigns the `name` field (and the file
  rename to `openapi-hs.cabal`) to EP-2, and the `version` bump to `4.0.0` to EP-7. EP-1 owns
  the file's *structure* only. Touching `name`/`version` here would create avoidable churn and
  conflicts with those later plans. This is recorded explicitly so the next contributor does
  not mistake the unchanged fields for an oversight.
  Date: 2026-06-10


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose.

**Completed 2026-06-10.** The project is now Cabal-only on a single modern toolchain, exactly
as the Purpose set out:

- `stack.yaml`, `Setup.hs`, `test/doctests.hs`, and `cabal.haskell-ci` are all deleted.
- `openapi3.cabal` declares `build-type: Simple`, `cabal-version: 3.0`, and
  `tested-with: GHC ==9.12.4 || ==9.14.1`; the `custom-setup` stanza and `test-suite doctests`
  are gone; the aeson bound is a single 2.x branch.
- `nix develop -c cabal build all` and `nix develop -c cabal test all` both succeed on GHC
  9.12.4; the `spec` suite passes (`375 examples, 0 failures`) and is the only suite that runs.
- CI is a hand-written GitHub Actions workflow over GHC 9.12.4 + 9.14.1.

**Gaps / deferred:** executable doctests are no longer run (only the example text remains in
Haddock comments); the documented modern replacement is `cabal-docspec` as a standalone CI
step, left as an optional follow-up. The GHC `-Wx-partial` warning in
`src/Data/OpenApi/Internal/Schema.hs:397` (`tail` on a list) predates this plan and was left
untouched — it is a `src/` concern outside EP-1's build-config scope.

**One deviation from the written plan:** the `license: BSD3 → BSD-3-Clause` edit was required
by the `cabal-version: 3.0` grammar and not foreseen in the plan (see Surprises). Everything
else landed as specified. Ownership boundary respected: `name` stays `openapi3` and `version`
stays `3.2.5` for EP-2 and EP-7; `nix/haskell.nix` and `.seihou/config.dhall` untouched.


## Context and Orientation

This section assumes you know nothing about this repository. Read it before editing anything.

The repository root is the directory that contains `openapi3.cabal`. All paths below are
relative to that root. The Haskell source lives under `src/` (modules `Data.OpenApi.*`); the
tests live under `test/`. None of the work in this plan touches `src/` — it is entirely about
build configuration, the toolchain, and CI.

The key files this plan reads or edits:

- `openapi3.cabal` — the Cabal **package description**: the file that tells the Haskell build
  tool (`cabal`) the package's name, version, dependencies, modules, and test-suites. This is
  the central file of this plan. Today its first line is `cabal-version: >=1.10` and it
  declares `build-type: Custom`.
- `Setup.hs` — a custom Cabal **Setup script**. With `build-type: Custom`, Cabal compiles and
  runs this file to drive the build instead of using its built-in logic. This one calls
  `Distribution.Extra.Doctest.defaultMainWithDoctests "doctests"`, which is the glue that lets
  the `doctests` test-suite find the library's modules. It exists only to support doctests.
- `cabal.project` — a small file telling `cabal` which packages are in this project. It
  currently reads `packages: .` and `tests: true`. We leave it as-is.
- `stack.yaml` — configuration for **Stack**, an alternative Haskell build tool. It pins
  `resolver: lts-16.31` (a 2020-era package snapshot) and lists `extra-deps`
  (`optics-core-0.3`, `optics-th-0.3`, `optics-extra-0.3`, `indexed-profunctors-0.1`,
  `insert-ordered-containers-0.2.3.1`). We delete this file; the project becomes Cabal-only.
- `cabal.haskell-ci` — input for the `haskell-ci` tool, which generates a GitHub Actions
  workflow. It declares `branches: master`, `allow-failures: >=9.14`, and several
  `constraint-set` blocks (`aeson-1`, `aeson-2`, `insert-ordered-containers-0.2`,
  `insert-ordered-containers-0.3`) — the `aeson-1` and `insert-ordered-containers-0.2` sets
  target old GHCs we are dropping. We delete this file.
- `.github/workflows/haskell-ci.yml` — the **CI workflow** generated from `cabal.haskell-ci`.
  GitHub runs it on push/PR. We replace it with a hand-written workflow for GHC 9.12.4 + 9.14.1.
- `test/doctests.hs` — the entry point of the `doctests` test-suite. It imports a generated
  module `Build_doctests` (produced only by the `cabal-doctest` custom Setup) and runs
  `Test.DocTest.doctest`. We delete this file.
- `test/Spec.hs` — the entry point of the `spec` test-suite. Its entire content is
  `{-# OPTIONS_GHC -F -pgmF hspec-discover #-}`, a GHC preprocessor pragma that makes
  `hspec-discover` scan the `test/` directory and assemble a test driver from every
  `*Spec.hs` module. **This suite stays and must keep passing.** We do not edit it.
- `nix/haskell.nix` and `flake.nix` — the Nix configuration that provides the dev shell. We
  read these to know how to obtain the toolchain but do **not** edit them in this plan (EP-2
  later edits `nix/haskell.nix` for the rename).

Terms used in this plan, defined in plain language:

- **Cabal** — the standard Haskell build tool. `cabal build all` compiles every component;
  `cabal test all` runs every test-suite.
- **Stack** — a different Haskell build tool that pins a whole curated package set
  ("resolver"/"snapshot"). We are removing it.
- **`build-type`** — a field in the `.cabal` file that tells Cabal how to build the package.
  `Simple` means "use Cabal's built-in logic, no custom code". `Custom` means "compile and run
  `Setup.hs` to drive the build". We move from `Custom` to `Simple`.
- **`custom-setup` stanza** — the block in the `.cabal` file that lists the dependencies of
  `Setup.hs` (here: `base`, `Cabal`, `cabal-doctest`). It is only meaningful with
  `build-type: Custom`. We remove it.
- **doctests** — executable examples embedded in module documentation (Haddock) comments,
  run as tests by the `doctest`/`cabal-doctest` machinery. We stop running them; the example
  text remains in the source as documentation.
- **`hspec-discover`** — a tool that auto-collects Hspec test modules. Used by the `spec`
  suite, which we keep.
- **`tested-with`** — a `.cabal` field listing the GHC versions the maintainers test against.
  Informational; also read by `haskell-ci`.
- **Nix dev shell** — a reproducible development environment. Running `nix develop` from the
  repo root drops you into a shell where `cabal` and `ghc` are GHC 9.12.4, pinned by
  `nix/haskell.nix` (`pkgs.haskell.packages."ghc9124"`). The shell is also exposed as
  `devShells.default` and `devShells."ghc9124"`.

How the toolchain is obtained: every command in this plan is written to run inside the Nix
dev shell. You can either prefix each command with `nix develop -c` (run one command in the
shell) or run `nix develop` once to enter an interactive shell and then run the bare command.
If you already have a *system* `cabal` ≥ 3.12 and GHC 9.12.4 on your `PATH`, the same `cabal`
commands work without the `nix develop -c` prefix; the plan notes this where relevant.

Relationship to the master plan: the master plan's Integration Point **IP-1** states that
`openapi3.cabal` is shared by EP-1, EP-2, and EP-7, and that **EP-1 owns its structure**
(`cabal-version`, `build-type`, `tested-with`, removal of `custom-setup` and the `doctests`
suite, and dependency bounds), while EP-2 owns identity (`name`, file rename, synopsis,
homepage, self-references) and EP-7 owns the `version`. This plan stays strictly within EP-1's
ownership.


## Plan of Work

The work proceeds as eight small, independently verifiable milestones, in order. Each edits
configuration only — no Haskell source under `src/` changes. The guiding principle is to make
one coherent change at a time and confirm the project still builds before moving on, so a
failure is always attributable to the last step.

### Milestone 1 — Verify the baseline toolchain

Scope: confirm the environment before changing anything, so later failures are clearly caused
by our edits and not a broken setup. At the end of this milestone you will have confirmed the
dev shell provides GHC 9.12.4 and a modern `cabal`, and you will have recorded whether the
project currently builds (it may already build via the custom Setup, or may be failing — note
which). No files change.

Commands to run (from the repo root):

```bash
nix develop -c ghc --version
nix develop -c cabal --version
```

Acceptance: `ghc --version` prints `The Glorious Glasgow Haskell Compilation System,
version 9.12.4`; `cabal --version` prints a `cabal-install` version ≥ 3.12.

### Milestone 2 — Remove Stack

Scope: delete `stack.yaml`, making the project Cabal-only. At the end, `stack.yaml` does not
exist and Cabal still configures the project. Stack configuration is fully independent of
Cabal, so deleting it cannot affect the Cabal build; this milestone is the safest first edit.

Edit: delete the file `stack.yaml`.

Acceptance: `stack.yaml` is gone; `nix develop -c cabal build all` still proceeds to compile
(it may still rely on the custom Setup at this point — that's fine, we remove it next).

### Milestone 3 — Drop the custom Setup (build-type Simple)

Scope: convert the package to the standard `build-type: Simple` and remove the custom build
machinery. At the end, `openapi3.cabal` declares `build-type: Simple`, has no `custom-setup`
stanza, and `Setup.hs` no longer exists. Note that the `doctests` test-suite is still declared
at this point and will fail to build because `Build_doctests` is no longer generated — we
remove that suite in the very next milestone, so do not run `cabal test all` until Milestone 4
is done.

Edits to `openapi3.cabal`:

Change the `build-type` line from:

```cabal
build-type:          Custom
```

to:

```cabal
build-type:          Simple
```

Remove the entire `custom-setup` stanza (it spans these lines):

```cabal
custom-setup
  setup-depends:
    base < 5,
    Cabal < 4,
    cabal-doctest >=1.0.6 && <1.1
```

Then delete the file `Setup.hs`.

Acceptance: `openapi3.cabal` contains `build-type:          Simple` and no `custom-setup`
text; `Setup.hs` does not exist. (Full build verification waits until Milestone 4 has removed
the now-orphaned doctests suite.)

### Milestone 4 — Remove the doctests test-suite

Scope: remove the `doctests` test-suite, which depended on the custom Setup. At the end, the
`test-suite doctests` stanza is gone from `openapi3.cabal` and `test/doctests.hs` is deleted.
The `spec` test-suite (the real tests) is untouched.

Edits to `openapi3.cabal`: remove the entire `test-suite doctests` stanza:

```cabal
test-suite doctests
  -- See QuickCheck note in https://github.com/phadej/cabal-doctest#notes
  build-depends:    base, doctest, Glob, QuickCheck
  default-language: Haskell2010
  hs-source-dirs:   test
  main-is:          doctests.hs
  type:             exitcode-stdio-1.0
  build-depends:    base, openapi3
  ghc-options:      -Wno-unused-packages
```

Then delete the file `test/doctests.hs`.

Note: do **not** touch `test-suite spec` or `test/Spec.hs`. The line comment inside
`test-suite spec` that reads `-- We need aeson's toEncoding for doctests too` may be left as
harmless historical text; optionally tidy it, but it has no functional effect.

Acceptance: `openapi3.cabal` has no `test-suite doctests` text; `test/doctests.hs` does not
exist; `nix develop -c cabal build all` succeeds; `nix develop -c cabal test all` runs and
passes the `spec` suite only (see Validation for the expected transcript).

### Milestone 5 — Modernize Cabal metadata (cabal-version + tested-with)

Scope: modernize the package-description grammar and the supported-compiler list. At the end,
the first line of `openapi3.cabal` is `cabal-version: 3.0` and `tested-with` lists exactly
`GHC ==9.12.4 || ==9.14.1`.

Edits to `openapi3.cabal`:

Change the first line from:

```cabal
cabal-version:       >=1.10
```

to:

```cabal
cabal-version:       3.0
```

Replace the entire `tested-with` block:

```cabal
tested-with:
  GHC ==8.6.5
   || ==8.8.4
   || ==8.10.7
   || ==9.0.2
   || ==9.2.8
   || ==9.4.8
   || ==9.6.7
   || ==9.8.4
   || ==9.10.3
   || ==9.12.4
   || ==9.14.1
```

with:

```cabal
tested-with:
  GHC ==9.12.4 || ==9.14.1
```

Acceptance: the file begins with `cabal-version:       3.0`; `tested-with` names only 9.12.4
and 9.14.1; `nix develop -c cabal build all` still succeeds (the `cabal-version` change does
not alter semantics for the fields we use, but it does change how Cabal parses the file, so
re-running the build confirms the grammar is still valid).

### Milestone 6 — Modernize dependency bounds

Scope: simplify dependency bounds that existed only to satisfy GHCs older than 9.12, while
keeping upper bounds permissive enough for 9.12.4 and 9.14.1. The goal is "builds clean on
9.12.4", not an exhaustive bounds purge — be conservative.

The concrete, low-risk changes to the `library` `build-depends` in `openapi3.cabal`:

1. Collapse the dual `aeson` branch. The current line supports both aeson 1.x and aeson 2.x:

   ```cabal
   , aeson                     >=1.4.2.0  && <1.6 || >=2.0.1.0 && < 2.3
   ```

   The aeson-1 branch existed only for GHCs older than 9.2 (see `cabal.haskell-ci`'s
   `constraint-set aeson-1` which is gated `ghc: <9.2`). GHC 9.12/9.14 use aeson 2.x. Collapse
   to the aeson-2 branch only, keeping a permissive upper bound:

   ```cabal
   , aeson                     >=2.0.1.0  && <2.3
   ```

2. Remove the stale `cookie` comment about GHC 7.8. The comment

   ```cabal
   -- cookie 0.4.3 is needed by GHC 7.8 due to time>=1.4 constraint
   ```

   refers to a compiler we no longer support. Delete the comment line; keep the dependency
   line itself (`cookie >=0.4.3 && <0.6`) — the bound is still fine for 9.12/9.14.

3. Leave the remaining bounds as they are. They are already permissive enough for 9.12.4 and
   9.14.1: `base >=4.11.1.0 && <4.23`, `bytestring <0.13`, `containers <0.9`,
   `template-haskell <2.25`, `time <1.16`, `transformers <0.7`, `mtl <2.4`, `text <2.2`,
   `lens <5.4`, `vector <0.14`, etc. The upper bounds were already raised to cover GHC 9.14 in
   commit `8975c17` ("add support for 9.14"). We deliberately do **not** raise the `base`
   *lower* bound: although `base >=4.11.1.0` corresponds to GHC 8.4, lowering the floor does no
   harm and a conservative floor avoids accidentally excluding a valid build plan. The point of
   this milestone is to remove dead *branches* (the aeson-1 alternative) and dead *comments*,
   not to tighten floors.

   Apply the same one-line aeson collapse in the `test-suite spec` `build-depends` only if it
   lists an explicit aeson bound — it does not (the spec suite lists a bare `aeson` inheriting
   the library's constraint via the solver), so no change is needed there.

Acceptance: `nix develop -c cabal build all` succeeds and the solver chooses a single aeson
2.x; `nix develop -c cabal test all` passes. If the solver reports any bound conflict, record
it in Surprises & Discoveries and relax the specific upper bound that conflicts (and only
that one), then re-run.

### Milestone 7 — Full build and test (consolidated proof)

Scope: prove the end-to-end result after all `.cabal` and file edits. At the end, both build
and test commands succeed from a clean state.

Commands (from the repo root):

```bash
nix develop -c cabal clean
nix develop -c cabal build all
nix develop -c cabal test all
```

Acceptance: see Validation and Acceptance for the exact expected transcripts. The `spec`
suite runs to completion with `0 failures`; no `doctests` suite runs.

### Milestone 8 — Update CI

Scope: make CI match the modern, two-compiler reality. We choose option (b) from the master
plan: a hand-written GitHub Actions workflow. At the end, `.github/workflows/haskell-ci.yml`
is replaced by a small hand-written workflow and `cabal.haskell-ci` is deleted.

Replace the entire contents of `.github/workflows/haskell-ci.yml` with the following
hand-written workflow. It uses `haskell-actions/setup` (the maintained successor to
`actions/setup-haskell`) to install each GHC + a matching `cabal-install`, then runs
`cabal build all` and `cabal test all` across a matrix of GHC 9.12.4 and 9.14.1:

```yaml
name: CI

on:
  push:
    branches: [master]
  pull_request:
    branches: [master]

jobs:
  build:
    name: GHC ${{ matrix.ghc }}
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        ghc: ['9.12.4', '9.14.1']
    steps:
      - uses: actions/checkout@v4

      - name: Set up GHC ${{ matrix.ghc }}
        uses: haskell-actions/setup@v2
        id: setup
        with:
          ghc-version: ${{ matrix.ghc }}
          cabal-version: 'latest'

      - name: Configure
        run: cabal configure --enable-tests --enable-benchmarks

      - name: Freeze build plan
        run: cabal freeze

      - name: Cache build artifacts
        uses: actions/cache@v4
        with:
          path: |
            ${{ steps.setup.outputs.cabal-store }}
            dist-newstyle
          key: ${{ runner.os }}-ghc-${{ matrix.ghc }}-${{ hashFiles('cabal.project.freeze') }}
          restore-keys: ${{ runner.os }}-ghc-${{ matrix.ghc }}-

      - name: Build
        run: cabal build all

      - name: Test
        run: cabal test all --test-show-details=direct
```

Then delete the file `cabal.haskell-ci` (it is no longer consumed by anything once we stop
using `haskell-ci`).

Documented alternative — option (a), keep `haskell-ci`: instead of the above, you could keep
the generated workflow by editing `cabal.haskell-ci` to the new GHC set and regenerating.
That would mean: remove `allow-failures: >=9.14` (9.14 is now a first-class target),
remove the `constraint-set aeson-1` and `constraint-set insert-ordered-containers-0.2` blocks
(they target dropped GHCs), and then run `haskell-ci regenerate` (the tool reads the
`tested-with` field of `openapi3.cabal`, now `9.12.4 || 9.14.1`, to build the matrix). We do
**not** take this path because it keeps the `haskell-ci` tool as a maintenance dependency for
just two compilers; the hand-written workflow above is simpler. This alternative is recorded
only so a maintainer who prefers `haskell-ci` knows exactly what to change.

Acceptance: `.github/workflows/haskell-ci.yml` contains the hand-written workflow above;
`cabal.haskell-ci` does not exist. CI cannot be fully exercised locally, but the workflow YAML
is valid (it can be linted with `nix develop -c yamllint .github/workflows/haskell-ci.yml` if
`yamllint` is available, or simply inspected) and its `cabal build all` / `cabal test all`
commands are exactly the ones validated locally in Milestone 7.


## Concrete Steps

Run all commands from the repository root
(`/Users/shinzui/Keikaku/hub/haskell/openapi3` on the author's machine; on any clone it is the
directory containing `openapi3.cabal`). Commands assume the Nix dev shell; if you have a
system `cabal` ≥ 3.12 + GHC 9.12.4, drop the `nix develop -c` prefix.

Step 1 — baseline:

```bash
nix develop -c ghc --version
nix develop -c cabal --version
```

Expected:

```text
The Glorious Glasgow Haskell Compilation System, version 9.12.4
cabal-install version 3.12.1.0
compiled using version 3.12.1.0 of the Cabal library
```

(The exact `cabal-install` patch version may differ; any ≥ 3.12 is acceptable.)

Step 2 — remove Stack:

```bash
rm -f stack.yaml
```

Step 3 — edit `openapi3.cabal` (`build-type` and remove `custom-setup`) and delete `Setup.hs`:

```bash
rm -f Setup.hs
```

Apply the `openapi3.cabal` edits described in Milestone 3 (use the Edit tool, not `sed`).

Step 4 — remove the doctests suite and its driver:

```bash
rm -f test/doctests.hs
```

Apply the `openapi3.cabal` edit described in Milestone 4 (remove the `test-suite doctests`
stanza).

Step 5 — edit `openapi3.cabal` for `cabal-version` and `tested-with` (Milestone 5).

Step 6 — edit `openapi3.cabal` dependency bounds (Milestone 6).

Step 7 — clean build and test:

```bash
nix develop -c cabal clean
nix develop -c cabal build all
nix develop -c cabal test all
```

Step 8 — CI:

```bash
rm -f cabal.haskell-ci
```

Write the new `.github/workflows/haskell-ci.yml` (Milestone 8).

Step 9 — confirm the destructive deletions actually happened and the key fields are present:

```bash
test ! -e stack.yaml && echo "stack.yaml: removed"
test ! -e Setup.hs && echo "Setup.hs: removed"
test ! -e test/doctests.hs && echo "test/doctests.hs: removed"
test ! -e cabal.haskell-ci && echo "cabal.haskell-ci: removed"
grep -n "build-type:" openapi3.cabal
grep -n "cabal-version:" openapi3.cabal
grep -n "tested-with:" -A1 openapi3.cabal
grep -n "name:" openapi3.cabal | head -n1
grep -n "version:" openapi3.cabal | head -n1
```

Expected:

```text
stack.yaml: removed
Setup.hs: removed
test/doctests.hs: removed
cabal.haskell-ci: removed
20:build-type:          Simple
1:cabal-version:       3.0
25:tested-with:
26:  GHC ==9.12.4 || ==9.14.1
2:name:                openapi3
3:version:             3.2.5
```

(Line numbers will shift as edits land; the values are what matter. Note `name` is still
`openapi3` and `version` still `3.2.5` — that is intentional; EP-2 and EP-7 change them.)


## Validation and Acceptance

The change is "effective beyond compilation" in two observable ways: (1) the project builds
and its real test-suite passes under a single modern toolchain, and (2) the obsolete files and
machinery are provably gone.

Primary behavioral acceptance — run from the repo root:

```bash
nix develop -c cabal build all
```

Expected (abbreviated; module count and timings will vary):

```text
Resolving dependencies...
Build profile: -w ghc-9.12.4 -O1
In order, the following will be built (use -v for more details):
 - openapi3-3.2.5 (lib) (first run)
 - openapi3-3.2.5 (test:spec) (first run)
 - openapi3-3.2.5 (exe:example) (first run)
...
Linking ...
```

Then:

```bash
nix develop -c cabal test all
```

Expected — exactly one test-suite (`spec`) runs, no `doctests` suite appears, and it finishes
with zero failures:

```text
Build profile: -w ghc-9.12.4 -O1
...
Running 1 test suites...
Test suite spec: RUNNING...
Test suite spec: PASS
Test suite logged to:
.../openapi3-3.2.5/t/spec/test/openapi3-3.2.5-spec.log
1 of 1 test suites (1 of 1 test cases) passed.
```

If you want to see the per-example detail and confirm `0 failures`, run:

```bash
nix develop -c cabal test all --test-show-details=direct
```

Expected tail:

```text
Finished in N.NNNN seconds
NNN examples, 0 failures
```

The crucial observation is the phrase `Running 1 test suites...` (the `doctests` suite is
gone) together with `0 failures` (the `spec` suite still works).

Toolchain acceptance:

```bash
nix develop -c ghc --version
```

Expected:

```text
The Glorious Glasgow Haskell Compilation System, version 9.12.4
```

File-state acceptance (the obsolete machinery is gone and the new structure is present) — run
the Step 9 block from Concrete Steps. Success is all four `removed` lines printing and the
grep output showing `build-type:          Simple`, `cabal-version:       3.0`, and the trimmed
`tested-with`, while `name`/`version` remain `openapi3` / `3.2.5`.

Negative acceptance (prove the doctests path is truly gone): the following must produce **no**
matches:

```bash
grep -RIn "cabal-doctest\|defaultMainWithDoctests\|Build_doctests\|build-type:.*Custom\|custom-setup" \
  openapi3.cabal Setup.hs test/doctests.hs 2>/dev/null
```

Expected:

```text
(no output)
```

(`grep` prints nothing and the three files it was asked about either no longer exist — which
is the point — or contain none of those tokens.)


## Idempotence and Recovery

Every edit in this plan is safe to repeat. The file deletions use `rm -f`, which succeeds
whether or not the file is present, so re-running the Concrete Steps after a partial run does
no harm. The `.cabal` and workflow edits are exact-string replacements; if a string has
already been changed, re-applying the same change is a no-op (an editing tool will report the
old string is absent — that means the edit already landed, which is fine). `cabal clean`
followed by `cabal build all` always rebuilds from a clean slate, so a half-finished build
cannot leave stale artifacts that mask success or failure.

Because all changes are confined to build configuration and CI (no `src/` edits), the blast
radius is small and fully recoverable through version control. The repository is a git repo;
before starting, the working tree is clean except for unrelated files noted at plan creation
(`flake.lock`, `.seihou/config.dhall`, `OPENAPI31_MIGRATION_PLAN.md`). To recover from any
mistake, restore individual files from git:

```bash
git checkout -- openapi3.cabal
git checkout -- stack.yaml Setup.hs test/doctests.hs cabal.haskell-ci .github/workflows/haskell-ci.yml
```

(For files this plan deletes, `git checkout -- <path>` restores them from the last commit.)
Do not run `git checkout -- .` blindly, as it would also revert the unrelated
already-modified files. This plan does **not** commit anything; committing is left to the
operator after validation passes.

If `cabal build all` fails after Milestone 6 with a dependency-bound conflict, the recovery is
local and surgical: read the solver's reported conflict, relax only the single conflicting
upper bound in `openapi3.cabal`, record the change in Surprises & Discoveries with the solver
output, and re-run `cabal build all`. Do not broaden multiple bounds at once.


## Interfaces and Dependencies

This plan consumes existing tools and does not define new Haskell interfaces (no `src/`
changes, so no module signatures change). The relevant external pieces and why they are used:

- **`cabal` (cabal-install ≥ 3.12) and GHC 9.12.4** — the single supported toolchain, provided
  by the Nix dev shell (`nix/haskell.nix`, which pins `pkgs.haskell.packages."ghc9124"`).
  `cabal build all` and `cabal test all` are the canonical commands after this plan. The plan
  also works with an equivalent system toolchain.
- **`hspec-discover`** — the build tool that assembles the `spec` test driver. It is already a
  `build-tool-depends` of `test-suite spec` and is unchanged by this plan. The `spec` suite is
  the behavior we preserve.
- **`haskell-actions/setup@v2`** and **`actions/cache@v4`** — the GitHub Actions used by the
  new CI workflow to install GHC/Cabal and cache the build store. These are the maintained
  actions for Haskell CI; the workflow runs the same `cabal build all` / `cabal test all`
  validated locally.

Removed dependencies and tools (no longer part of the build after this plan):

- **`cabal-doctest`** (was a `custom-setup` `setup-depends`) — removed with the custom Setup.
- **`doctest`, `Glob`** (were `build-depends` of the deleted `doctests` suite) — removed.
- **Stack** — removed entirely; `stack.yaml` deleted.
- **`haskell-ci`** — removed as a maintenance tool; `cabal.haskell-ci` deleted, workflow
  hand-written.

State at the end of each milestone (the observable contract):

- After Milestone 2: `stack.yaml` absent; `cabal build all` still configures.
- After Milestone 4: `openapi3.cabal` has `build-type: Simple`, no `custom-setup`, no
  `test-suite doctests`; `Setup.hs` and `test/doctests.hs` absent; `cabal build all` and
  `cabal test all` succeed, with `spec` the only suite.
- After Milestone 6: `cabal-version: 3.0`; `tested-with` is `GHC ==9.12.4 || ==9.14.1`;
  the aeson dependency is the single 2.x branch; `cabal build all` / `cabal test all` succeed.
- After Milestone 8: `.github/workflows/haskell-ci.yml` is the hand-written workflow;
  `cabal.haskell-ci` absent.

Ownership boundary (master-plan Integration Point IP-1): this plan **must not** change the
`.cabal` `name` field (stays `openapi3` — EP-2 renames it to `openapi-hs` and renames the file)
nor the `version` field (stays `3.2.5` — EP-7 bumps it to `4.0.0`). It also does **not** edit
`nix/haskell.nix` or `.seihou/config.dhall` (EP-2 updates those for the rename). Keeping within
this boundary lets EP-2 and EP-7 apply their changes without conflicting with EP-1.
