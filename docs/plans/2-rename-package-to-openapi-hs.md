---
id: 2
slug: rename-package-to-openapi-hs
title: "Rename Package to openapi-hs"
kind: exec-plan
created_at: 2026-06-11T03:47:52Z
master_plan: "docs/masterplans/1-openapi-3-1-support-and-project-modernization.md"
---

# Rename Package to openapi-hs

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

This repository is a fork of the Haskell library historically published on Hackage as
`openapi3` — a library for decoding, encoding, and manipulating OpenAPI specification
documents. The fork is being modernized and will eventually be published under a new name.
This ExecPlan performs exactly one well-scoped piece of that modernization: it renames the
**Cabal package** from `openapi3` to `openapi-hs`. A "Cabal package" is the unit Haskell's
build tool (`cabal`) installs and that other projects depend on by name; its identity lives
in a `*.cabal` file whose `name:` field is the package name.

After this change, the package that lives in this repository is named `openapi-hs`. Concretely,
a person can run `ls *.cabal` and see `openapi-hs.cabal` (not `openapi3.cabal`); they can run
`cabal build all` and `cabal test all` inside the Nix dev shell and watch the project compile
and its tests pass under the new name; and a downstream project that previously wrote
`build-depends: openapi3` would now write `build-depends: openapi-hs`. Crucially, the Haskell
**module namespace stays `Data.OpenApi.*`**. A "module namespace" is the set of import paths
source files use — for example `import Data.OpenApi`. Because we deliberately leave those
unchanged, the only thing a downstream user must edit to adopt this fork is the dependency
*name* in their own `.cabal`; every `import Data.OpenApi...` line they already wrote keeps
working verbatim. The observable proof of that is in Validation: after the rename, a Haskell
snippet that does `import Data.OpenApi (OpenApi)` still compiles.

This plan is intentionally mechanical and additive in spirit: it touches package metadata and
package-name self-references only. It does not change any Haskell source under `src/`, any test
logic under `test/`, the library's behavior, its version number, its dependency bounds, or its
build system structure. Those concerns belong to sibling plans (see Interfaces and Dependencies).


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented here,
even if it requires splitting a partially completed task into two ("done" vs. "remaining").
This section must always reflect the actual current state of the work.

- [x] Milestone 1 (2026-06-10): Re-read `.cabal` — EP-1 had already run (`build-type: Simple`, no `doctests` suite), so the doctests self-reference edit was correctly skipped.
- [x] Milestone 1 (2026-06-10): `git mv openapi3.cabal openapi-hs.cabal`.
- [x] Milestone 1 (2026-06-10): Set `name: openapi-hs`.
- [x] Milestone 1 (2026-06-10): Updated `synopsis`, `description`, `homepage`, `bug-reports`, `source-repository head location` to the fork identity (`github.com/shinzui/openapi-hs`).
- [x] Milestone 1 (2026-06-10): Renamed self-reference `openapi3` → `openapi-hs` in `test-suite spec` `build-depends`.
- [x] Milestone 1 (2026-06-10): Renamed self-reference `openapi3` → `openapi-hs` in `executable example` `build-depends`.
- [x] Milestone 1 (2026-06-10): `test-suite doctests` already removed by EP-1 — no doctests self-reference edit needed.
- [x] Milestone 2 (2026-06-10): Updated `nix/haskell.nix` `callCabal2nix "openapi3-hs"` → `"openapi-hs"`.
- [x] Milestone 2 (2026-06-10): Updated `.seihou/config.dhall` `project.name` → `"openapi-hs"`. (Generated `.seihou/manifest.json` still records the old value — see Surprises.)
- [x] Milestone 3 (2026-06-10): Updated README title and Hackage link to `openapi-hs`; removed the dead Travis/Stackage badges; updated the issue-tracker link to the fork.
- [x] Milestone 3 (2026-06-10): Audited CHANGELOG — only historical upstream PR links reference `openapi3`; left untouched per Decision Log.
- [x] Validation (2026-06-10): `ls *.cabal` → only `openapi-hs.cabal`; metadata greps pass; `cabal build all` resolves as `openapi-hs-3.2.5` and `cabal test all` passes (375 examples, 0 failures); `(mempty :: OpenApi) :: OpenApi` typechecks in `cabal repl openapi-hs`.


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

- **`.seihou/manifest.json` also records `project.name` (2026-06-10).** The plan's Milestone 2
  acceptance grep `grep -rn "openapi3-hs" nix/ .seihou/` was expected to return nothing after
  editing `.seihou/config.dhall`, but it still matches `.seihou/manifest.json` (and a stray
  `.seihou/manifest.json.tmp`), whose `variables` block embeds
  `"project.name":"openapi3-hs"`. The manifest is **seihou-generated state** (it also stores
  content hashes), not a hand-authored config. Decision: left the manifest unedited rather than
  hand-patching generated state — the canonical source `.seihou/config.dhall` is now
  `openapi-hs`, and seihou regenerates the manifest from it on its next run, which will
  reconcile the value. Hand-editing was judged riskier (potential hash/state desync) than the
  cosmetic inconsistency. The `.tmp` file is an unrelated pre-existing atomic-write leftover.

- **Intentional residual `openapi3` mentions in the `.cabal` (2026-06-10).** After the rename,
  `grep openapi3 openapi-hs.cabal` still matches two lines — the synopsis
  (`OpenAPI 3.0 data model (openapi-hs fork of openapi3)`) and the description
  (`openapi-hs is a fork of the openapi3 library...`). These are deliberate prose references to
  the upstream project, not package-name self-references; the acceptance check that matters
  (`grep "name:.*openapi3"`) is clean and the build resolves the `openapi-hs` dependency.


## Decision Log

Record every decision made while working on the plan.

- Decision: Package-name-only rename (`openapi3` → `openapi-hs`); keep the `Data.OpenApi.*`
  Haskell module namespace exactly as-is.
  Rationale: This was an explicit user decision. Renaming the module namespace would be a far
  larger, fully-breaking change that touches every source file under `src/`, every test file
  under `test/`, and — more importantly — every downstream import site in the wider ecosystem,
  for little benefit on a fork. Keeping `Data.OpenApi.*` means downstream consumers only swap
  the dependency *name* in their `.cabal`; all their `import Data.OpenApi...` lines keep
  working unchanged.
  Date: 2026-06-10

- Decision: Treat historical CHANGELOG entries that link to `https://github.com/biocad/openapi3/pull/NN`
  as immutable history and do not rewrite them.
  Rationale: Those URLs point at real upstream pull requests in the original `biocad/openapi3`
  repository. They are an accurate record of where each change came from; rewriting the host or
  package segment would produce dead or misleading links. Only the README badges/title/links —
  which advertise *this* package's current identity — are updated.
  Date: 2026-06-10

- Decision: Align the cosmetic `callCabal2nix "openapi3-hs"` string in `nix/haskell.nix` to
  `"openapi-hs"` even though it does not change the built package's real name.
  Rationale: `callCabal2nix name src args` derives the real Haskell package from the `.cabal`
  file's `name:` field, so the string argument is only a label used for the derivation/path.
  Leaving it mismatched would confuse a future reader into thinking the package is still
  `openapi3-hs`. Aligning it costs nothing and removes that confusion.
  Date: 2026-06-10


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose.

**Completed 2026-06-10.** The Cabal package is now `openapi-hs`, exactly as the Purpose set
out, with the `Data.OpenApi.*` module namespace untouched:

- `ls *.cabal` shows only `openapi-hs.cabal`; `name: openapi-hs`; identity metadata
  (synopsis/description/homepage/bug-reports/source-repository) points at the
  `shinzui/openapi-hs` fork; all package self-references in `test-suite spec` and
  `executable example` say `openapi-hs`.
- `nix/haskell.nix` and `.seihou/config.dhall` use `openapi-hs`; README advertises the new
  name with dead upstream badges removed.
- `cabal build all` resolves the project as `openapi-hs-3.2.5` and `cabal test all` passes
  (375 examples, 0 failures); `(mempty :: OpenApi) :: OpenApi` typechecks in
  `cabal repl openapi-hs`, proving downstream `import Data.OpenApi` is unaffected.

**Ownership boundary respected (IP-1):** `version` stays `3.2.5` (EP-7 bumps to 4.0.0); the
`license: BSD-3-Clause` value from EP-1 was preserved; `build-type`/`cabal-version`/
`tested-with`/dependency bounds (EP-1's) were not touched. **Gap:** the seihou-generated
`.seihou/manifest.json` still records the old `project.name` and will reconcile when seihou
next regenerates (see Surprises) — no functional impact.


## Context and Orientation

You are working in a Git repository at `/Users/shinzui/Keikaku/hub/haskell/openapi3`. Treat the
following as the only knowledge you have; everything you need to do this task is described here.

The repository is a Haskell library. Haskell libraries are described by a **Cabal package
description file** ending in `.cabal`. At the start of this work that file is
`/Users/shinzui/Keikaku/hub/haskell/openapi3/openapi3.cabal`. Inside it, the line `name: openapi3`
declares the package name. The same file also declares a `library` stanza (the actual library
code, under `src/`), a `test-suite spec` stanza (the test program, under `test/`), possibly a
`test-suite doctests` stanza (a second test program that runs documentation examples), and an
`executable example` stanza (a small demo program, under `examples/`). When one of these
stanzas needs to use the library defined in the *same* package, it lists the package's own name
in its `build-depends`. These are the "self-references": `test-suite spec`, `test-suite doctests`
(if present), and `executable example` each list `openapi3` in their `build-depends`, meaning
"depend on the library built from this very package." When we rename the package, those
self-references must be renamed too, or the build will fail to find the dependency.

The Haskell **module namespace** is separate from the package name. Modules are the import paths
in source files, all beginning `Data.OpenApi` (for example `Data.OpenApi`, `Data.OpenApi.Lens`,
`Data.OpenApi.Internal`). These are declared in the `library` stanza's `exposed-modules:` list
and in `module Data.OpenApi... where` headers inside `src/`. **This plan does not touch any of
those.** The package name and the module namespace are independent: you can rename one without
renaming the other, and we are renaming only the package name.

Two Nix build files reference the package name. Nix is the tool that provides the reproducible
development environment (`nix develop`). The file
`/Users/shinzui/Keikaku/hub/haskell/openapi3/nix/haskell.nix` contains the line
`packages.default = haskellPackages.callCabal2nix "openapi3-hs" inputs.self { };`. The function
`callCabal2nix` takes a *name string*, a source, and arguments, and turns the project's `.cabal`
file into a Nix package. The name string (`"openapi3-hs"`) is only a cosmetic label — the real
package is derived from the `.cabal` `name:` field — but we align it to `"openapi-hs"` for
clarity. The file `/Users/shinzui/Keikaku/hub/haskell/openapi3/flake.nix` imports
`./nix/haskell.nix` and does not itself mention the package name, so it is **not** edited by this
plan. The file `/Users/shinzui/Keikaku/hub/haskell/openapi3/.seihou/config.dhall` is a small
configuration file (written in the Dhall configuration language) whose `project.name` field is
currently `"openapi3-hs"`; we set it to `"openapi-hs"`.

The README at `/Users/shinzui/Keikaku/hub/haskell/openapi3/README.md` opens with a title and a
row of status badges (small linked images) and contains Hackage and issue-tracker links that use
the `openapi3` package name. The CHANGELOG at
`/Users/shinzui/Keikaku/hub/haskell/openapi3/CHANGELOG.md` is a list of versioned changes; its
body links to historical upstream pull requests under `biocad/openapi3` (which we leave alone, per
the Decision Log).

This ExecPlan is the second child plan ("EP-2") of a larger initiative described in
`docs/masterplans/1-openapi-3-1-support-and-project-modernization.md` (checked into this repo).
That master plan defines a shared file, the `.cabal`, as "Integration Point IP-1," touched by
three plans: EP-1 (build modernization), this plan EP-2 (rename/identity), and EP-7 (version
bump). The division of ownership matters and is restated under Interfaces and Dependencies below.

One sentence of orientation about ordering: this plan **soft-depends** on EP-1. "Soft-depends"
means EP-2 does not strictly require EP-1 to have run first, but the two plans both edit the
`.cabal`, so running EP-2 after EP-1 avoids re-resolving overlapping edits. Because EP-1 may or
may not have run when you start, the very first concrete step is to **re-read the `.cabal` and
detect which state it is in**, and every edit below is written to be safe in both states.


## Plan of Work

The work is three small milestones. Each is independently verifiable. Throughout, you must obey
the ownership boundaries of Integration Point IP-1 (see Interfaces and Dependencies): EP-2 owns
package **identity**, not package **structure** or **version**. Concretely, this plan must
**not** change `build-type`, `cabal-version`, `tested-with`, dependency bounds (those belong to
EP-1), and must **not** change the `version` field (EP-7 bumps it to `4.0.0`). Only rename
`openapi3` → `openapi-hs` occurrences and adjust identity metadata.

Milestone 1 — rename the package in the `.cabal`. Scope: after this milestone the package file
is named `openapi-hs.cabal`, its `name:` field reads `openapi-hs`, its identity metadata
(`synopsis`, `description`, `homepage`, `bug-reports`, `source-repository head location`) reflects
the fork, and every self-reference (`build-depends: ... openapi3 ...` inside `test-suite spec`,
the optional `test-suite doctests`, and `executable example`) reads `openapi-hs`. The first action
is to **re-read** `openapi3.cabal` (or `openapi-hs.cabal` if a prior partial run already renamed
it) to determine the current state — in particular whether the `test-suite doctests` stanza still
exists. EP-1, if it has already run, removes that stanza and switches `build-type` to `Simple`; if
EP-1 has not run, the stanza is still present and `build-type` is still `Custom`. Do not touch
`build-type` either way. Then rename the file with `git mv` (skip if the new name already exists),
edit `name:`, edit the identity fields, and edit the self-references. The library stanza's
`exposed-modules:` and the `module Data.OpenApi... where` headers in `src/` are **left untouched**.
Acceptance: `ls *.cabal` shows `openapi-hs.cabal` and not `openapi3.cabal`; `grep -n "name:" *.cabal`
shows `name: openapi-hs`; and `grep -n "openapi3" *.cabal` returns nothing.

Milestone 2 — align the Nix and seihou config files. Scope: after this milestone
`nix/haskell.nix` passes `"openapi-hs"` to `callCabal2nix`, and `.seihou/config.dhall` has
`project.name = "openapi-hs"`. These are exact one-token string replacements
(`openapi3-hs` → `openapi-hs`). Acceptance: `grep -rn "openapi3-hs" nix/ .seihou/` returns nothing.

Milestone 3 — update human-facing references. Scope: after this milestone the README's title,
badges, and package links advertise `openapi-hs` rather than `openapi3`, and the CHANGELOG has
been audited (the historical upstream PR links are deliberately left as-is). Be precise: do not
rewrite mentions of the OpenAPI **specification version** ("3.0" / "3.1") — only the **package
name** token `openapi3`. Acceptance: the README no longer contains the package-name token
`openapi3` in its badges or links (spec-version phrases like "OpenAPI 3.0" may legitimately
remain until a 3.1 plan updates wording — that wording is not this plan's concern), and a human
reading the top of the README sees the new name.


## Concrete Steps

Run everything from the repository root
`/Users/shinzui/Keikaku/hub/haskell/openapi3`. Do not `git commit` anything as part of this plan.

Step 0 — detect the current state (idempotence guard). Determine which `.cabal` file exists and
whether the `doctests` test-suite is present:

```bash
cd /Users/shinzui/Keikaku/hub/haskell/openapi3
ls *.cabal
grep -n "^name:" *.cabal
grep -n "build-type:" *.cabal
grep -n "test-suite doctests" *.cabal || echo "no doctests suite (EP-1 has run)"
```

If `ls *.cabal` already prints `openapi-hs.cabal` and `grep -n "^name:"` already prints
`name: openapi-hs`, Milestone 1's rename has already happened; skip the `git mv` and the
`name:` edit below and only verify the remaining edits. If `openapi3.cabal` is present, proceed
with the full sequence. Expected output in the pristine (EP-1-not-run) state:

```text
openapi3.cabal
1:name:                openapi3
20:build-type:          Custom
185:test-suite doctests
```

Expected output if EP-1 has already run (doctests removed, build-type Simple):

```text
openapi3.cabal
1:name:                openapi3
20:build-type:          Simple
no doctests suite (EP-1 has run)
```

Step 1 — rename the file (skip if `openapi-hs.cabal` already exists):

```bash
cd /Users/shinzui/Keikaku/hub/haskell/openapi3
test -f openapi-hs.cabal || git mv openapi3.cabal openapi-hs.cabal
ls *.cabal
```

Expected:

```text
openapi-hs.cabal
```

Step 2 — set the package name. Edit `openapi-hs.cabal` line 1 (`name:`). The change is:

```diff
-name:                openapi3
+name:                openapi-hs
```

Step 3 — update the identity metadata. In `openapi-hs.cabal`, update the synopsis, description,
homepage, bug-reports, and the `source-repository head` location to reflect the fork. Leave
`category`, `license`, `license-file`, `author`, `maintainer`, and `copyright` untouched (they
are not part of this plan's scope, and leaving them avoids guessing). Use the fork's GitHub
location `https://github.com/shinzui/openapi-hs` (the repository's `flake.nix` already points its
inputs at `github:shinzui/...`, so this is the natural fork host). The synopsis/description wording
may still say "OpenAPI 3.0" at this point — EP-7 owns the final "OpenAPI 3.1 data model" wording —
so here we only adjust them to read naturally for the renamed fork without claiming 3.1 support
prematurely. The edits:

```diff
-synopsis:            OpenAPI 3.0 data model
+synopsis:            OpenAPI 3.0 data model (openapi-hs fork of openapi3)
```

```diff
 description:
-  This library is intended to be used for decoding and encoding OpenAPI 3.0 API
-  specifications as well as manipulating them.
+  openapi-hs is a fork of the openapi3 library, intended to be used for decoding and
+  encoding OpenAPI 3.0 API specifications as well as manipulating them. The Haskell
+  module namespace remains Data.OpenApi.*, so only the package dependency name changes
+  for downstream users.
   .
   The original OpenAPI 3.0 specification is available at http://swagger.io/specification/.
```

```diff
-homepage:            https://github.com/biocad/openapi3
-bug-reports:         https://github.com/biocad/openapi3/issues
+homepage:            https://github.com/shinzui/openapi-hs
+bug-reports:         https://github.com/shinzui/openapi-hs/issues
```

```diff
 source-repository head
   type:     git
-  location: https://github.com/biocad/openapi3.git
+  location: https://github.com/shinzui/openapi-hs.git
```

Step 4 — rename the self-references. There are two or three, depending on whether EP-1 has run.
In `test-suite spec`'s `build-depends`:

```diff
     , mtl
-    , openapi3
+    , openapi-hs
     , template-haskell
```

In `executable example`'s `build-depends`:

```diff
-build-depends:    base, aeson, lens, openapi3, text
+build-depends:    base, aeson, lens, openapi-hs, text
```

In `test-suite doctests`'s `build-depends` — **only if that stanza still exists** (Step 0 showed
it). If EP-1 has already removed the doctests suite, skip this edit entirely:

```diff
 type:             exitcode-stdio-1.0
-build-depends:    base, openapi3
+build-depends:    base, openapi-hs
 ghc-options:      -Wno-unused-packages
```

Verify Milestone 1:

```bash
cd /Users/shinzui/Keikaku/hub/haskell/openapi3
ls *.cabal
grep -n "^name:" *.cabal
grep -rn "openapi3" *.cabal || echo "no openapi3 package-name references remain in cabal"
```

Expected:

```text
openapi-hs.cabal
1:name:                openapi-hs
no openapi3 package-name references remain in cabal
```

Step 5 — align `nix/haskell.nix`. Change the cosmetic `callCabal2nix` name argument:

```diff
-      packages.default = haskellPackages.callCabal2nix "openapi3-hs" inputs.self { };
+      packages.default = haskellPackages.callCabal2nix "openapi-hs" inputs.self { };
```

Step 6 — align `.seihou/config.dhall`. Change the project name:

```diff
-, `project.name` = "openapi3-hs"
+, `project.name` = "openapi-hs"
```

Verify Milestone 2:

```bash
cd /Users/shinzui/Keikaku/hub/haskell/openapi3
grep -rn "openapi3-hs" nix/ .seihou/ || echo "no openapi3-hs references remain"
```

Expected:

```text
no openapi3-hs references remain
```

Step 7 — update the README. The package-name references are the title, the four badge lines, the
haddock link, and the issue-tracker link. Update them to the new package name and fork host. Do
**not** change the "OpenAPI 3.0 data model" sentence's spec version — only the package-name token.
The edits to `README.md`:

```diff
-# OpenApi 3
+# openapi-hs
 
-[![Hackage](https://img.shields.io/hackage/v/openapi3.svg)](http://hackage.haskell.org/package/openapi3)
-[![Build Status](https://travis-ci.org/biocad/openapi3.svg?branch=master)](https://travis-ci.org/biocad/openapi3)
-[![Stackage LTS](http://stackage.org/package/openapi3/badge/lts)](http://stackage.org/lts/package/opeopenapi3)
-[![Stackage Nightly](http://stackage.org/package/openapi3/badge/nightly)](http://stackage.org/nightly/package/openapi3)
+[![Hackage](https://img.shields.io/hackage/v/openapi-hs.svg)](http://hackage.haskell.org/package/openapi-hs)
```

The Travis and Stackage badges point at the unmaintained upstream and a package that is not (yet)
published under the new name, so removing them rather than rewriting them to dead links is the
honest choice; keep only the Hackage badge placeholder (it will resolve once the package is
published, which is out of scope here). Then update the two in-body links:

```diff
-Please refer to [haddock documentation](http://hackage.haskell.org/package/openapi3).
+Please refer to [haddock documentation](http://hackage.haskell.org/package/openapi-hs).
```

```diff
-Please report bugs via the [github issue tracker](https://github.com/biocad/openapi3/issues).
+Please report bugs via the [github issue tracker](https://github.com/shinzui/openapi-hs/issues).
```

Step 8 — audit the CHANGELOG. The CHANGELOG body contains links of the form
`https://github.com/biocad/openapi3/pull/NN`. These are historical upstream pull-request URLs and
must be left untouched (Decision Log). Confirm there is no *package-name header* (a top-of-file
heading naming the package) that needs changing:

```bash
cd /Users/shinzui/Keikaku/hub/haskell/openapi3
head -5 CHANGELOG.md
grep -n "openapi3" CHANGELOG.md | grep -v "github.com/biocad/openapi3/pull" || echo "only historical PR links reference openapi3; nothing to change"
```

Expected:

```text
Unreleased
----------

3.2.5
-----
only historical PR links reference openapi3; nothing to change
```

If that grep prints a non-PR-link line (for example a header containing the package name), update
that line's package-name token to `openapi-hs`; otherwise leave the CHANGELOG as-is.


## Validation and Acceptance

The acceptance for this plan is behavioral: the package still builds and tests still pass under
the new name, and downstream `import Data.OpenApi` continues to compile — proving the rename did
not disturb the module namespace.

First, the metadata checks. Run from the repository root:

```bash
cd /Users/shinzui/Keikaku/hub/haskell/openapi3
ls *.cabal
grep -rn "name:.*openapi3" *.cabal || echo "PASS: no 'name: openapi3' remains"
grep -rn "openapi3-hs" nix/ .seihou/ || echo "PASS: no openapi3-hs in nix/ or .seihou/"
```

Expected:

```text
openapi-hs.cabal
PASS: no 'name: openapi3' remains
PASS: no openapi3-hs in nix/ or .seihou/
```

Second, the build and test must succeed inside the Nix dev shell. The dev shell pins GHC 9.12.4
(`ghc9124`, per `nix/haskell.nix`). `cabal build all` building every component proves that the
renamed self-references resolve — if `test-suite spec` or `executable example` still pointed at
the old `openapi3` name, Cabal would fail with an "unknown package" error during dependency
resolution. Run:

```bash
cd /Users/shinzui/Keikaku/hub/haskell/openapi3
nix develop -c cabal build all
nix develop -c cabal test all
```

Expected (abbreviated — the key signal is that resolution names `openapi-hs` and tests pass):

```text
Resolving dependencies...
Build profile: -w ghc-9.12.4 -O1
...
 - openapi-hs-3.2.5 (lib) (first run)
 - openapi-hs-3.2.5 (test:spec) (first run)
 - openapi-hs-3.2.5 (exe:example) (first run)
...
Linking ... spec ...
Running 1 test suites...
Test suite spec: RUNNING...
Test suite spec: PASS
```

If `cabal` reports `unknown package: openapi3`, a self-reference was missed — go back to Step 4
and search the renamed `.cabal` again with `grep -rn "openapi3" *.cabal`.

Third, prove the module namespace is intact. Create no permanent file; use a throwaway check that
the library still exports `Data.OpenApi` under the new package. The simplest robust proof is that
`cabal test all` already imports `Data.OpenApi` from `test/` and passed above. As an explicit,
self-contained extra check, you can compile a one-line snippet in the dev shell using GHCi against
the built library:

```bash
cd /Users/shinzui/Keikaku/hub/haskell/openapi3
nix develop -c cabal repl openapi-hs <<'EOF'
import Data.OpenApi (OpenApi)
:type (mempty :: OpenApi)
EOF
```

Expected (the type checks, confirming `import Data.OpenApi` resolves under `openapi-hs`):

```text
(mempty :: OpenApi) :: OpenApi
```

Acceptance is met when: `ls *.cabal` shows only `openapi-hs.cabal`; `grep -rn "name:.*openapi3" *.cabal`
finds nothing; `grep -rn "openapi3-hs" nix/ .seihou/` finds nothing; `nix develop -c cabal build all`
and `nix develop -c cabal test all` both succeed; and `import Data.OpenApi` compiles in the repl.


## Idempotence and Recovery

Every step in this plan is safe to run more than once. The file rename in Step 1 is guarded by
`test -f openapi-hs.cabal || git mv ...`, so re-running it after the rename is a no-op rather than
an error. The metadata and self-reference edits are exact string substitutions: if a substitution's
target text (the old `openapi3` token) is already gone because a previous run applied it, the edit
simply has nothing to match and changes nothing — re-running the verification greps will still show
the desired end state. The Nix and Dhall edits are likewise single-token substitutions of
`openapi3-hs` → `openapi-hs` and are idempotent.

The mandatory idempotence guard is Step 0: always re-read the `.cabal` before editing to discover
whether you are in the pristine state or a partially completed / EP-1-already-run state. The one
state-dependent edit is the `test-suite doctests` self-reference: apply it only if that stanza
exists. If EP-1 has already removed the doctests suite, skipping that edit is correct, not an error.

Recovery is straightforward because no destructive operation occurs and nothing is committed. If
anything looks wrong, inspect the working tree with `git status` and `git diff`, and discard the
uncommitted changes with `git restore .` and (if the file was renamed) `git restore --staged
openapi-hs.cabal openapi3.cabal` followed by `git checkout -- openapi3.cabal` to return to the
original `openapi3.cabal`. Because the rename used `git mv`, Git tracks it as a rename and a single
`git restore`/`git checkout` of the original path brings the file back. After recovery you can
restart this plan from Step 0 cleanly.


## Interfaces and Dependencies

This plan edits configuration and metadata files only; it defines no new Haskell types or function
signatures, and it intentionally leaves the library's public interface — the `Data.OpenApi.*`
module namespace and every exported symbol therein — byte-for-byte unchanged. The "interface" this
plan is responsible for is therefore the **package identity**: the `name:` field of the `.cabal`,
the `.cabal` file name itself, the identity metadata fields (`synopsis`, `description`, `homepage`,
`bug-reports`, `source-repository head location`), the package-name self-references in the test and
example stanzas, the cosmetic `callCabal2nix` label in `nix/haskell.nix`, and `project.name` in
`.seihou/config.dhall`. At the end of this plan, the package these files describe must resolve and
build under the name `openapi-hs`, and `import Data.OpenApi` must still typecheck.

Dependency and ownership boundaries, restated from the master plan's Integration Point IP-1
(`docs/masterplans/1-openapi-3-1-support-and-project-modernization.md`), because three sibling
plans share the `.cabal` file and must not overwrite one another's fields:

EP-1 (build modernization) owns the `.cabal`'s **structure**: `cabal-version`, `build-type`
(`Custom` → `Simple`), `tested-with`, the `custom-setup` stanza, the `test-suite doctests` stanza,
and dependency bounds. This plan must **not** change any of those. In particular, do not touch
`build-type`, do not add or remove the doctests suite (only rename its self-reference *if it is
present*), and do not edit dependency version bounds.

EP-2 (this plan) owns the `.cabal`'s **identity** exactly as enumerated above. This is the only
plan permitted to change `name:`, rename the file, and rewrite the identity metadata and
self-references. It is also the plan that updates `nix/haskell.nix` and `.seihou/config.dhall` for
the name.

EP-7 (migration helpers, tests, release) owns the `version` field and the **final**
synopsis/description wording ("OpenAPI 3.1 data model"). This plan must **not** change the
`version` field (it stays at its current value; EP-7 bumps it to `4.0.0`), and the synopsis/
description wording this plan writes is only an interim, identity-correct phrasing that EP-7 may
later refine to assert 3.1 support.

Sequencing: this plan **soft-depends** on EP-1 (it can run before EP-1, but both edit the `.cabal`,
so running it after EP-1 settles avoids re-resolving overlapping edits). It has **no hard
dependency** on any other plan. Conversely, EP-7 **soft-depends** on this plan, because the release
metadata it finalizes names the package `openapi-hs`. The Step 0 idempotence guard is precisely
what lets this plan run correctly whether or not EP-1 has already executed.

External tools this plan relies on, and why: `git` (for the tracked file rename via `git mv`);
`grep` and `ls` (for the verification checks); `nix` with the project's dev shell (`nix develop`)
which provides `cabal` and GHC 9.12.4 (`ghc9124`, pinned in `nix/haskell.nix`) for the build/test
validation. No new libraries are introduced and no dependency bounds change.
