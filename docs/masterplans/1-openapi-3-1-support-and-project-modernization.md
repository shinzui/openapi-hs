---
id: 1
slug: openapi-3-1-support-and-project-modernization
title: "OpenAPI 3.1 Support and Project Modernization"
kind: master-plan
created_at: 2026-06-11T03:47:39Z
---

# OpenAPI 3.1 Support and Project Modernization

This MasterPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Vision & Scope

This repository is a fork of `openapi3` (currently version 3.2.5), a Haskell library for
decoding, encoding, and manipulating OpenAPI specification documents. The upstream project
is barely maintained and supports only OpenAPI 3.0.x. This initiative turns the fork into a
modern, OpenAPI 3.1-capable library published under a new name.

After the entire initiative is complete:

- The library is named **`openapi-hs`** (renamed from `openapi3`), published as version
  **4.0.0**, with a synopsis and description that say "OpenAPI 3.1 data model". The Haskell
  module namespace stays `Data.OpenApi.*` — only the package identity changes, so downstream
  code that imports `Data.OpenApi` keeps working after a dependency-name swap.
- The build is **Cabal-only on GHC 9.12+**. `stack.yaml` is gone. The custom `Setup.hs` /
  `cabal-doctest` machinery is gone (build-type reverts to `Simple`). `cabal-version` is
  bumped to `3.0` or later. The `tested-with` list drops every GHC below 9.12 and keeps
  9.12.x and 9.14.x. `cabal build all` and `cabal test all` succeed on GHC 9.12.4 (the
  version the Nix dev shell pins via `ghc9124`).
- The data model represents **OpenAPI 3.1 / JSON Schema 2020-12**, not 3.0. A user can decode
  a 3.1 document containing `type: ["string", "null"]`, numeric `exclusiveMaximum`,
  `prefixItems`, `const`, `if`/`then`/`else`, `$defs`, `webhooks`, `Info.summary`, and
  `License.identifier`, manipulate it through lenses/optics, and re-encode it losslessly.
- A user holding a **3.0 document** can run provided migration helpers (operating on raw
  `Data.Aeson.Value`s) to convert it into a 3.1-shaped `Value` that then decodes into the new
  `Schema` type. There is a `MIGRATION_3.0_TO_3.1.md` guide.
- **Schema validation** (`Data.OpenApi.Schema.Validation`) understands the new 3.1 keywords:
  type arrays, `prefixItems`, `contains`/`minContains`/`maxContains`, `if`/`then`/`else`, and
  `const`.

**Strategy decision (carried from `OPENAPI31_MIGRATION_PLAN.md`):** this is a **breaking
change** to 3.1-only types ("Strategy A"). The data types represent 3.1 only; 3.0 documents
are not decodable directly. Several 3.1 changes make a 3.0 document *unrepresentable* in the
same types — `nullable` is removed, `exclusiveMaximum`/`exclusiveMinimum` change from `Bool`
to `Scientific`, and tuple `items` arrays are removed in favour of `prefixItems`. Keeping both
representations live was considered and rejected (see Decision Log).

**Explicitly out of scope:** keeping 3.0 round-tripping on the live types; a parallel
`Data.OpenApi30` module hierarchy; version-polymorphic `Schema (v :: OpenApiVersion)` types;
publishing to Hackage (the plans prepare metadata but do not run `cabal upload`); renaming the
`Data.OpenApi.*` module namespace (the user chose a package-name-only rename).


## Decomposition Strategy

The initiative splits along three themes — toolchain modernization, project rename, and the
OpenAPI 3.1 data-model migration — which decompose into seven child ExecPlans grouped into
four implementation waves (phases). The guiding principle is **functional concern with
independent verifiability**: each plan produces a behavior you can demonstrate on its own.

The 3.1 migration is the bulk of the work and is itself decomposed by *where it touches the
type system*, because the JSON serialization machinery (`generics-sop` + the custom Aeson
layer in `src/Data/OpenApi/Internal/AesonUtils.hs`) is tightly coupled to the `Schema` record
shape. The migration plan (`OPENAPI31_MIGRATION_PLAN.md`, at the repo root) explicitly warns
in its §4.0 that "the instances cannot be edited in isolation" — so we did **not** split
"types" and "serialization" into separate plans. Instead, each 3.1 plan owns *both* the type
change and its serialization round-trip. The split is:

- **EP-3 (core breaking changes)** owns the changes that force a recompile of the whole tree:
  the `type`-array representation, numeric exclusive bounds, removing `nullable`, simplifying
  `OpenApiItems`, and the version constants. Nothing else in 3.1 can land until the `Schema`
  record and its derived lenses compile in their new shape, so EP-3 is the hard foundation.
- **EP-4 (JSON Schema fields + reference keywords)** owns the additive JSON Schema 2020-12
  fields (`prefixItems`, `const`, conditionals, `contains`, `unevaluated*`, content keywords)
  **and** the genuinely hard sub-problem the migration plan flags: `$`-prefixed keys (`$id`,
  `$ref`, `$defs`, `$anchor`, `$dynamicRef`, `$dynamicAnchor`) do not derive from the default
  prefix-stripping rule, and `$ref`-with-siblings plus boolean-valued schemas break existing
  assumptions. This plan includes a design spike for those before the bulk field additions.
- **EP-5 (top-level objects)** owns the non-`Schema` additions: `webhooks` on `OpenApi`,
  `summary` on `Info`, `identifier` on `License`, and `$ref` on `PathItem`. These are separate
  records, independently verifiable, and only loosely coupled to the `Schema` work — but they
  reuse the `$`-key serialization helper that EP-4 builds.
- **EP-6 (validation)** owns `Data.OpenApi.Schema.Validation` updates for the new keywords. It
  must wait for the fields to exist (EP-3 + EP-4).
- **EP-7 (migration helpers, tests, release)** owns the `Value`-layer 3.0→3.1 migration
  helpers, the comprehensive 3.1 test suite, the migration guide, and the 4.0.0 version bump.

The two non-3.1 streams are independent of the migration content:

- **EP-1 (build modernization)** is the foundation wave. It does not touch OpenAPI logic, but
  every later plan benefits from building on the single supported toolchain, and EP-7's release
  metadata assumes the modern `.cabal`. We sequence it first.
- **EP-2 (rename)** is mechanical and touches package metadata only. It shares the `.cabal`
  file with EP-1 and EP-7 (an integration point), so it runs right after EP-1 to avoid
  three-way churn on that file.

Alternatives considered and rejected: a single mega-ExecPlan (rejected — far more than five
milestones and more than ten files across unrelated concerns); splitting types and
serialization into separate plans (rejected — §4.0 of the migration plan shows they must move
together); a parallel 3.0/3.1 module hierarchy or version-polymorphic types (rejected by the
migration plan itself; see Decision Log). See the Decision Log for the full record.


## Exec-Plan Registry

| # | Title | Path | Hard Deps | Soft Deps | Status |
|---|-------|------|-----------|-----------|--------|
| 1 | Modernize Build Toolchain to Cabal and GHC 9.12 | docs/plans/1-modernize-build-toolchain-to-cabal-and-ghc-9-12.md | None | None | Complete |
| 2 | Rename Package to openapi-hs | docs/plans/2-rename-package-to-openapi-hs.md | None | EP-1 | Complete |
| 3 | OpenAPI 3.1 Core Schema Type Changes | docs/plans/3-openapi-3-1-core-schema-type-changes.md | None | EP-1 | Complete |
| 4 | OpenAPI 3.1 JSON Schema Fields and Reference Keywords | docs/plans/4-openapi-3-1-json-schema-fields-and-reference-keywords.md | EP-3 | EP-1 | Complete |
| 5 | OpenAPI 3.1 Top-Level Object Features | docs/plans/5-openapi-3-1-top-level-object-features.md | EP-3 | EP-4 | Complete |
| 6 | OpenAPI 3.1 Schema Validation | docs/plans/6-openapi-3-1-schema-validation.md | EP-3, EP-4 | None | Complete |
| 7 | OpenAPI 3.1 Migration Helpers, Tests, and Release | docs/plans/7-openapi-3-1-migration-helpers-tests-and-release.md | EP-3, EP-4, EP-5 | EP-2, EP-6 | Complete |

Status values: Not Started, In Progress, Complete, Cancelled.
Hard Deps and Soft Deps reference other rows by their # prefix (e.g., EP-1, EP-3).


## Dependency Graph

The phases below define the implementation waves. Within a phase, plans can proceed in
parallel unless a hard dependency says otherwise.

**Phase 1 — Foundation (EP-1, then EP-2).** EP-1 (build modernization) has no dependencies and
goes first. It is not a *hard* dependency of the 3.1 work — the 3.1 code would still compile on
the old toolchain — but doing it first means everyone else builds on GHC 9.12 with `Simple`
build-type and no `stack`. EP-2 (rename) has a soft dependency on EP-1: both edit
`openapi3.cabal`, so running EP-2 immediately after EP-1 settles the toolchain avoids
re-resolving conflicts on that file. EP-2 carries no OpenAPI logic and could technically run at
any time.

**Phase 2 — 3.1 Core (EP-3).** EP-3 is the hard foundation of the migration. It changes the
shape of the `Schema` record (`src/Data/OpenApi/Internal.hs`), the derived lenses
(`src/Data/OpenApi/Lens.hs`, `src/Data/OpenApi/Optics.hs`), and the version bounds. Until the
tree compiles with the new `_schemaType :: Maybe OpenApiTypeValue`, numeric exclusive bounds,
no `_schemaNullable`, and the simplified `OpenApiItems`, no other 3.1 plan can add fields. EP-3
has a soft dependency on EP-1 (prefer the modern toolchain) but no hard dependency.

**Phase 3 — 3.1 Features (EP-4, then EP-5).** EP-4 hard-depends on EP-3: it adds fields to the
same `Schema` record EP-3 reshaped and extends the same Aeson machinery, and its `$`-key work
must reconcile with EP-3's hand-written `OpenApiTypeValue` instances. EP-5 hard-depends on EP-3
(it needs the new version constants and the `Referenced` plumbing) and soft-depends on EP-4
because `PathItem.$ref` and `webhooks` references reuse the `$`-prefixed-key serialization
helper EP-4 introduces; if EP-5 runs before EP-4, it must build a minimal version of that
helper itself and EP-4 later consolidates them (see Integration Points).

**Phase 4 — Validation & Release (EP-6, EP-7).** EP-6 hard-depends on EP-3 and EP-4 — it
validates keywords that only exist once those fields are present. EP-7 hard-depends on EP-3,
EP-4, and EP-5 (all 3.1 features must exist before the comprehensive test suite and migration
helpers can exercise them) and soft-depends on EP-2 (the release metadata names the package
`openapi-hs`) and EP-6 (validation behavior is worth covering in the final test pass, but EP-7
can ship without it). EP-7 performs the 4.0.0 version bump and CHANGELOG, so it goes last.

Parallelism summary: after EP-1, EP-2 and EP-3 can run concurrently (EP-2 is metadata-only,
EP-3 is the 3.1 foundation). After EP-3, EP-4 and EP-5 can run concurrently. EP-6 and EP-7
form the closing wave; EP-6 and EP-7 can overlap, with EP-7 absorbing EP-6's outcomes.


## Integration Points

**IP-1 — `openapi3.cabal` / `openapi-hs.cabal` (EP-1, EP-2, EP-7).** The Cabal package
description is touched by three plans. EP-1 owns its *structure*: `cabal-version`, `build-type`
(`Custom` → `Simple`), `tested-with`, the removal of the `custom-setup` stanza and the
`doctests` test-suite, and dependency bounds for GHC 9.12. EP-2 owns its *identity*: the
`name` field (`openapi3` → `openapi-hs`), the file rename (`openapi3.cabal` →
`openapi-hs.cabal`), `synopsis`, `description`, `homepage`, `bug-reports`, and
`source-repository`, plus every `openapi3` self-reference in `build-depends` of the test and
example stanzas. EP-7 owns the `version` field (→ `4.0.0`) and the final synopsis/description
wording ("OpenAPI 3.1 data model"). Rule: EP-1 lands structural changes first; EP-2 then
renames; EP-7 bumps the version last. Each plan must re-read the file before editing and must
not revert another plan's field. EP-2 must also update `nix/haskell.nix`
(`callCabal2nix "openapi3-hs"` → the new package name) and `.seihou/config.dhall`
(`project.name`).

**IP-2 — `src/Data/OpenApi/Internal.hs` `Schema` record + `OpenApiItems` (EP-3, EP-4, EP-5,
EP-6, EP-7).** The `Schema` data type (around `Internal.hs:619`) and `OpenApiItems`
(`Internal.hs:586`) are the central shared artifact. EP-3 **defines** the new shape: it
introduces `OpenApiTypeValue`, changes `_schemaType`, `_schemaExclusiveMaximum`,
`_schemaExclusiveMinimum`, removes `_schemaNullable`, and replaces `OpenApiItemsArray` with
`OpenApiItemsBoolean`. EP-4 **extends** it with the additive JSON Schema fields and the
`$`-keyword fields, appending to the record. EP-5 does *not* touch `Schema` (it touches
`OpenApi`, `Info`, `License`, `PathItem`). EP-6 and EP-7 **consume** the final shape (read-only
for the type; they add validation and tests). Rule: field *additions* append to the end of the
record to minimise merge friction; EP-4 must rebase onto EP-3's final field order. Every plan
that adds a `Schema` field must also add the matching lens in `src/Data/OpenApi/Lens.hs`, the
optic in `src/Data/OpenApi/Optics.hs`, and ensure an `AesonDefaultValue` exists for the field
type (see IP-3).

**IP-3 — Aeson serialization machinery `src/Data/OpenApi/Internal/AesonUtils.hs` (EP-3, EP-4,
EP-5).** `mkSwaggerAesonOptions`, `saoSubObject`, `saoAdditionalPairs`, the
`sopSwaggerGeneric*` functions, and the `AesonDefaultValue` class are shared. EP-3 reworks the
`saoSubObject ?~ "items"` handling because `OpenApiItems` can now be a bare boolean (not an
object whose keys splice up). EP-4 **defines** the reusable mechanism for emitting/parsing
`$`-prefixed keys (`$id`, `$ref`, `$defs`, `$anchor`, `$dynamicRef`, `$dynamicAnchor`) — either
via `saoAdditionalPairs`-style post-processing or a dedicated pass. EP-5 **consumes** that same
mechanism for `PathItem.$ref` and the `webhooks` `Referenced PathItem` map. Rule: EP-4 owns the
canonical `$`-key helper and its location; EP-5 imports it rather than duplicating. If EP-5 is
implemented before EP-4 it builds a minimal local helper and leaves a `TODO(EP-4)` marker;
EP-4 then consolidates and removes the duplicate.

**IP-4 — `OpenApiType` and `OpenApiNull` (EP-3, EP-7).** `OpenApiNull` already exists as an
`OpenApiType` constructor (`Internal.hs:597`). EP-3's `OpenApiTypeValue` wraps `OpenApiType`
(single or array). EP-7's migration helper `migrate30NullableValue` produces
`type: ["string", "null"]`, which decodes into `OpenApiTypeArray [OpenApiString, OpenApiNull]`.
Rule: EP-3 must keep `OpenApiNull` and make `OpenApiTypeArray` round-trip it; EP-7's helper
relies on that decoding.

**IP-5 — Test support module `test/SpecCommon.hs` and the test-suite stanza (EP-3, EP-4, EP-5,
EP-6, EP-7).** The shared round-trip helpers in `test/SpecCommon.hs` (`isSubJSON`, JSON
equality combinators) and the `other-modules` list in the test-suite stanza of the `.cabal`
are touched whenever a plan adds a new spec module. Rule: each plan that adds a `*Spec.hs`
module registers it in the `.cabal` test-suite `other-modules`; EP-7 does the final audit that
every new spec module is listed and that `hspec-discover` picks them up.


## Progress

Aggregate milestone-level progress across all child plans. Updated as each child plan's
milestones complete.

- [x] EP-1: Remove `stack.yaml`; build with `cabal build all` on GHC 9.12.4 (2026-06-10)
- [x] EP-1: Switch build-type `Custom` → `Simple`; remove `custom-setup` and `doctests` suite; bump `cabal-version` (2026-06-10)
- [x] EP-1: Trim `tested-with` to GHC 9.12.x/9.14.x; update dependency bounds; refresh CI workflow (2026-06-10)
- [x] EP-2: Rename `.cabal` to `openapi-hs.cabal`, set `name: openapi-hs`, update metadata and self-references (2026-06-10)
- [x] EP-2: Update `nix/haskell.nix` and `.seihou/config.dhall` to the new package name; `cabal build all` passes (2026-06-10)
- [x] EP-3: Introduce `OpenApiTypeValue`; change `_schemaType`; hand-written JSON instances round-trip type arrays (2026-06-10)
- [x] EP-3: Change exclusive bounds to `Scientific`; remove `_schemaNullable`; simplify `OpenApiItems` to object|boolean (2026-06-10)
- [x] EP-3: Update version constants to 3.1.x; fix all lenses/optics/compile errors; existing tests updated/pass (2026-06-10)
- [x] EP-4: Spike + decide `$ref`-with-siblings and boolean-schema representation; build the `$`-key serialization helper (2026-06-10)
- [x] EP-4: Add JSON Schema fields (`prefixItems`, `const`, conditionals, `contains*`, `unevaluated*`, content*, `examples`) (2026-06-10)
- [x] EP-4: Add `$id`/`$anchor`/`$defs`/`$ref`/`$dynamicRef`/`$dynamicAnchor`; round-trip all new fields (2026-06-10)
- [x] EP-5: Add `webhooks` to `OpenApi`; `summary` to `Info`; `identifier` to `License`; `$ref` to `PathItem` (2026-06-10)
- [x] EP-5: Round-trip top-level features; reuse EP-4's `$`-key helper (2026-06-10)
- [x] EP-6: Validate type arrays, `prefixItems`, `contains`/`minContains`/`maxContains`, `if`/`then`/`else`, `const` (2026-06-10)
- [x] EP-7: Implement `Value`-layer 3.0→3.1 migration helpers; migration tests pass (2026-06-10)
- [x] EP-7: Comprehensive 3.1 test suite; `MIGRATION_3.0_TO_3.1.md`; bump to 4.0.0; CHANGELOG; module docs (2026-06-10)


## Surprises & Discoveries

Cross-plan insights, dependency changes, and scope adjustments discovered during
implementation.

- **Discovery (EP-1 implementation, 2026-06-10): `cabal-version: 3.0` forces an SPDX `license`
  identifier (affects IP-1).** Bumping `cabal-version` to `3.0` made Cabal reject the legacy
  `license: BSD3` at parse time (`Unknown SPDX license identifier: 'BSD3' Do you mean
  BSD-3-Clause?`). EP-1 changed it to `license: BSD-3-Clause`. Consequence for IP-1: EP-2
  (identity) and EP-7 (version/synopsis) both re-edit `openapi3.cabal`/`openapi-hs.cabal` — they
  must **keep** the SPDX `BSD-3-Clause` value and not revert it to `BSD3`. Recorded here because
  the shared-`.cabal` integration point spans those plans.

- **Discovery (EP-1 implementation, 2026-06-10): dev-shell cabal is 3.16.1.0.** Higher than the
  EP-1 plan's example transcript (3.12.1.0); acceptance only required ≥ 3.12. No action needed,
  but later plans' transcripts may likewise differ from any hand-written expectation.

- **Discovery (EP-3 implementation, 2026-06-10): the EP-3 tuple stub uses `anyOf`, and EP-4
  must un-pend 5 generator tests.** EP-3 collapsed tuple `ToSchema` derivation to a single
  `items` object whose element is the **`anyOf`** of the member schemas (not `oneOf` — an
  integer matches both `Integer` and `Number`, which `oneOf` would reject). Because positional
  type info is lost, `validateFromJSON` round-trips for heterogeneous tuples cannot hold, so
  five `GeneratorSpec` props — `(IntMap String)`, `(Int,String)`, `(Int,String,Double)`,
  `(Int,String,Double,[Int])`, `(Int,String,Double,[Int],Int)` — are `xprop` (pending) with
  `TODO(EP-4)`. **EP-4's `prefixItems` milestone must:** (a) switch `appendItem` and the two
  `sketch*` array helpers in `src/Data/OpenApi/Internal/Schema.hs` from the `anyOf`-`items`
  collapse to true `prefixItems`; (b) update the `ISPair` golden
  (`test/Data/OpenApi/CommonTestTypes.hs`, currently the `anyOf` form); and (c) restore those
  five props from `xprop` to `prop`. This concretises the next discovery's tuple note.
  **STATUS (after EP-4, 2026-06-10): still OUTSTANDING.** EP-4 added the `prefixItems` *field*
  but did not rewire generic tuple `ToSchema` derivation to use it, nor un-pend the five props.
  The field now exists to support the switch; close this before/with the EP-7 release (or as a
  dedicated follow-up). Tracked here so it is not lost.

- **Discovery (EP-3 implementation, 2026-06-10): default OpenAPI version had to move to 3.1.0.**
  Beyond the version *bounds*, EP-3 bumped the `Monoid OpenApiSpecVersion` `mempty` and the
  `AesonDefaultValue Version` default to `[3,1,0]`. Otherwise `mempty :: OpenApi` serialises
  `"openapi":"3.0.0"`, which is now outside the valid `[3.1.0, 3.1.1]` range and fails to
  decode — breaking round-trip of the empty document. EP-7's release/test work should assume the
  default emitted version is `3.1.0`.

- **Discovery (during plan authoring, 2026-06-10): EP-3 and EP-4 are coupled through generic
  tuple `ToSchema` derivation.** The generic `ToSchema` instances in
  `src/Data/OpenApi/Internal/Schema.hs` derive a Haskell tuple (e.g. `(String, Int)`) into a
  schema whose `items` is the removed `OpenApiItemsArray [...]`. EP-3 removes
  `OpenApiItemsArray`, but the correct 3.1 replacement — `prefixItems` — is not added until
  EP-4. Consequence: EP-3 ships a *temporary* fallback (collapse tuple derivation to a
  homogeneous `items`, or `error`/`pending` the `ISPair` tuple test) with a `TODO(EP-4)`
  marker, and **EP-4 must explicitly restore proper tuple `ToSchema` via `prefixItems`** as
  part of its `prefixItems` milestone. This tightens the EP-3 → EP-4 hard dependency: EP-4 is
  not merely additive, it also *completes* a behavior EP-3 had to stub. Both child plans
  already carry the matching `TODO(EP-4)` notes; do not consider the tuple story done until
  EP-4 lands.

- **Discovery (during plan authoring, 2026-06-10): the `$`-prefixed-key serialization helper is
  centralized in EP-4 (IP-3), and EP-5 carries a stop-gap.** EP-4 defines
  `applyKeyRenamesToJSON` / `applyKeyRenamesParseJSON` (in
  `src/Data/OpenApi/Internal/AesonUtils.hs`) driven by a constant rename table
  (`schemaDollarKeyRenames`, placed next to the `Schema` instances in
  `src/Data/OpenApi/Internal.hs`). EP-5 needs the same mechanism for `PathItem.$ref` and
  `webhooks` but, because it may run before EP-4 completes, ships a minimal local `renameKey`
  helper marked `TODO(EP-4)`. When both are done, EP-5's `renameKey` must be replaced by EP-4's
  shared helper and the `TODO(EP-4)` removed — this is the consolidation step of IP-3.
  **RESOLVED (2026-06-10): EP-4 landed before EP-5, so EP-5 never shipped the stop-gap.**
  `PathItem.$ref` consumes EP-4's `applyKeyRenamesToJSON`/`applyKeyRenamesParseJSON` directly
  (table `pathItemDollarKeyRenames = [("ref","$ref")]`); no `renameKey`/`TODO(EP-4)` was ever
  introduced. `webhooks` values are `Referenced PathItem` and round-trip through the existing
  `referencedToJSON`/`referencedParseJSON` (their `$ref` is handled by those, not the rename
  pass). IP-3 is fully consolidated.

- **Discovery (during plan authoring, 2026-06-10): stale `HasSwaggerAesonOptions Schema`
  option.** The `ToJSON Schema` instance uses `saoSubObject ?~ "items"`, but a separate
  `HasSwaggerAesonOptions Schema` instance references `"paramSchema"` — a no-op, since `Schema`
  has no such sub-field. EP-3 (which reworks the `items` sub-object handling) and EP-4 (which
  touches the same surface) must not "reconcile" these blindly; the `"paramSchema"` reference is
  dead and should be left alone or removed deliberately, not aligned to `"items"`.

- **Discovery (during plan authoring, 2026-06-10): `unevaluatedProperties`/`unevaluatedItems`
  are scoped to best-effort in EP-6.** Full JSON Schema 2020-12 `unevaluated*` semantics require
  threading annotation results from adjacent applicators (`allOf`, `if`/`then`, `properties`,
  `prefixItems`, `$ref`) through the validation walk, which the current engine
  (`src/Data/OpenApi/Internal/Schema/Validation.hs`) does not do (it returns only pass/fail).
  EP-6 therefore implements type-arrays, exclusive bounds, `prefixItems`, `contains*`,
  `if`/`then`/`else`, and `const` fully, but ships only a locally-scoped approximation of
  `unevaluated*` with a documented `TODO(annotations)` limitation. Full annotation-aware
  `unevaluated*` is explicitly out of scope for this initiative.


## Decision Log

- Decision: Adopt Strategy A — 3.1-only data types, breaking-change release 4.0.0.
  Rationale: Three 3.1 changes make 3.0 documents unrepresentable on the same types
  (`nullable` removed, exclusive bounds `Bool`→`Scientific`, tuple `items` removed). Keeping
  both representations live (Strategy B) produces a larger, confusing API and was rejected in
  `OPENAPI31_MIGRATION_PLAN.md`. 3.0 inputs are handled by `Value`-layer migration helpers
  (EP-7), not by storing 3.0 fields on the 3.1 type.
  Date: 2026-06-10

- Decision: Package-name-only rename (`openapi3` → `openapi-hs`); keep the `Data.OpenApi.*`
  module namespace.
  Rationale: User selected this scope. Renaming modules would be a much larger, fully-breaking
  change touching every source/test file and every downstream import site, with little benefit
  for a fork. Keeping `Data.OpenApi` means downstream code only swaps the dependency name.
  Date: 2026-06-10

- Decision: Target GHC 9.12.x and 9.14.x; drop 8.6 through 9.10.
  Rationale: User asked to "move to GHC 9.12+". The Nix dev shell already pins `ghc9124`
  (`nix/haskell.nix`). Keeping 9.14.x preserves the most recent compiler the current
  `tested-with` already lists. Dropping older GHCs lets us delete CPP shims and old
  dependency-bound branches.
  Date: 2026-06-10

- Decision: Decompose the 3.1 migration by type-system surface (core / schema-fields /
  top-level / validation / release) rather than by the migration plan's seven phases, and keep
  each plan's serialization changes inside the plan that owns the corresponding type change.
  Rationale: §4.0 of `OPENAPI31_MIGRATION_PLAN.md` shows the `generics-sop` + custom-Aeson
  machinery cannot be edited in isolation from the `Schema` record shape; splitting "types" and
  "serialization" into separate plans would create a circular hard dependency. Seven child
  plans is the documented maximum, so the work is grouped into four phases (waves).
  Date: 2026-06-10

- Decision: Make EP-1 (build modernization) a soft, not hard, dependency of the 3.1 plans.
  Rationale: The 3.1 code would compile on the old toolchain too, so EP-1 does not *block*
  EP-3. But sequencing EP-1 first means all later work targets one toolchain (GHC 9.12,
  `Simple` build-type, no `stack`), which is simpler and matches the release in EP-7.
  Date: 2026-06-10

- Decision: EP-4 owns the canonical `$`-prefixed-key serialization helper; EP-5 consumes it.
  Rationale: Both the `Schema` `$`-keywords (EP-4) and `PathItem.$ref`/`webhooks` references
  (EP-5) hit the same problem — `$`-prefixed JSON keys do not derive from the default
  prefix-stripping rule in `mkSwaggerAesonOptions`. Centralising the helper in EP-4 avoids two
  divergent implementations (Integration Point IP-3).
  Date: 2026-06-10


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion. Compare
the result against the original vision.

**All seven child plans complete (2026-06-10).** The fork is now a modern, OpenAPI 3.1-capable
library matching the Vision:

- **Identity & build (EP-1, EP-2):** package renamed `openapi3` → **`openapi-hs`**, Cabal-only on
  GHC 9.12.4/9.14.1 (`build-type: Simple`, no `stack.yaml`/custom Setup/doctests), `cabal-version`
  3.0, SPDX license. The `Data.OpenApi.*` namespace is unchanged.
- **3.1 data model (EP-3, EP-4, EP-5):** type arrays (`OpenApiTypeValue`), numeric exclusive
  bounds, no `nullable`, object/boolean `items`, version 3.1.x; the full JSON Schema 2020-12 field
  set including the `$`-prefixed keywords (via the shared `applyKeyRenamesToJSON`/`ParseJSON`
  helper, IP-3); and the top-level features `webhooks`/`Info.summary`/`License.identifier`/
  `PathItem.$ref`. Everything round-trips losslessly.
- **Validation (EP-6):** the engine understands type arrays, numeric bounds, `prefixItems`,
  `contains*`, `if`/`then`/`else`, `const`, and a best-effort `unevaluated*`.
- **Migration & release (EP-7):** `Data.OpenApi.Migration` bridges 3.0→3.1 at the `Value` layer;
  version **4.0.0**, "OpenAPI 3.1 data model" synopsis, `MIGRATION_3.0_TO_3.1.md`, CHANGELOG, and
  updated module/README docs. `cabal check` clean; `cabal sdist` produces `openapi-hs-4.0.0.tar.gz`.

Final state: `cabal build all` + `cabal test all` green — **448 examples, 0 failures, 5 pending**.
The seven plans landed in 12 commits (EP-3 in 4, the rest 1–2 each), each milestone committed in a
working state with both `MasterPlan:`/`ExecPlan:` trailers.

**Outstanding follow-ups (tracked in Surprises, none blocking the release):**
1. Generic tuple `ToSchema` derivation still emits the EP-3 `anyOf`-`items` stub rather than
   `prefixItems`; 5 positional-tuple generator props are `xprop` (pending). The `prefixItems`
   field exists to support the switch — a clean follow-up.
2. No `Arbitrary Schema` instance; `prop_schema31_roundtrip` uses a bounded fragment generator.
3. `unevaluated*` is local-only (no cross-schema annotation tracking); `not`/`anyOf` are still
   unvalidated (pre-existing). All documented in-code with `TODO` markers.
4. Hackage publishing was explicitly out of scope (release artifacts prepared, not uploaded).

**Lessons:** the EP-3→EP-4 coupling (tuple derivation, `$`-key helper) and the EP-3-pre-landing of
EP-6's M1 played out as the Decomposition Strategy predicted — sequencing the hard `Schema`
foundation (EP-3) first let every later plan append/consume cleanly (IP-2). The biggest
deviations were all in the *serialization/TH* margins the plans had partially flagged: reserved-word
lens names (`if`/`then`/`else`/`id`/`const`/`contains`), `toEncoding` bypassing rename passes, and
strict `validateObject`/un-validated `not` shaping the test design.
