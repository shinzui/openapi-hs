---
id: 7
slug: openapi-3-1-migration-helpers-tests-and-release
title: "OpenAPI 3.1 Migration Helpers, Tests, and Release"
kind: exec-plan
created_at: 2026-06-11T03:47:52Z
master_plan: "docs/masterplans/1-openapi-3-1-support-and-project-modernization.md"
---

# OpenAPI 3.1 Migration Helpers, Tests, and Release

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

This repository is a fork of the Haskell library originally published on Hackage as
`openapi3`: a library for decoding (parsing), encoding (serializing), and manipulating
OpenAPI specification documents. "OpenAPI" is the format formerly known as Swagger that
describes HTTP APIs in JSON or YAML. The fork is being upgraded from supporting OpenAPI
version 3.0 to supporting OpenAPI version 3.1, which adopts the JSON Schema 2020-12 dialect
and changes several keywords in incompatible ways. That upgrade is split across several
coordinated plans (see "Context and Orientation"); this plan is the **last** one — EP-7 in
the master plan — and it covers three distinct concerns that close out the upgrade.

After this plan is complete, three new user-visible capabilities exist:

First, a user who is holding an OpenAPI **3.0** document (which the new 3.1-only data types
can no longer parse directly) can call a small set of **migration helper functions** that
rewrite the *raw parsed JSON* (a `Data.Aeson.Value`) into a 3.1-shaped JSON value, which then
decodes cleanly into the new `Schema` type. Concretely, a user can take
`{"type": "string", "nullable": true}` (legal 3.0, illegal 3.1) and get back
`{"type": ["string", "null"]}` (legal 3.1), then `decode` it into a `Schema`. This is the
only supported bridge from 3.0 to 3.1 under the project's chosen strategy ("Strategy A",
explained below), because the 3.1 types deliberately cannot represent 3.0-only constructs.

Second, the library gains a **comprehensive automated test suite** for the 3.1 features that
the earlier plans added: type arrays (`type: ["string","null"]`), numeric exclusive bounds
(`exclusiveMaximum: 100` as a number rather than a boolean), tuple validation via
`prefixItems` with `items: false`, conditional schemas (`if`/`then`/`else`/`const`),
`webhooks`, the JSON Schema identification keywords (`$defs`/`$id`/`$ref`), `Info.summary`,
and `License.identifier`. These tests run under the existing `hspec` test framework and
include property-based round-trip checks (encode then decode returns the original value) plus
dedicated tests for the migration helpers above.

Third, the package is **prepared for a 4.0.0 release**: the version is bumped to `4.0.0`, the
`synopsis` and `description` are reworded to say "OpenAPI 3.1 data model", the top-level
module documentation in `src/Data/OpenApi.hs` is updated, a `CHANGELOG.md` entry summarizing
every breaking change is added, a hand-written `MIGRATION_3.0_TO_3.1.md` guide is created at
the repository root, and the `README.md` is reworded for 3.1. This plan does **not** publish
to Hackage (it does not run `cabal upload`); it only prepares the release artifacts.

You can see all three working by running, from the repository root,
`nix develop -c cabal test all`: every test suite (including the new 3.1 and migration specs)
passes green. You can see the migration helper concretely with a GHCi snippet shown in
"Validation and Acceptance". You can see the release prep with
`grep 'version:' openapi-hs.cabal` showing `4.0.0` and `nix develop -c cabal check` reporting
no errors.


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented here,
even if it requires splitting a partially completed task into two ("done" vs. "remaining").
This section must always reflect the actual current state of the work.

Milestone 1 — Value-layer migration helpers:

- [x] Created `src/Data/OpenApi/Migration.hs` exposing `migrate30To31`, `migrate30NullableValue`, `migrate30ExclusiveBoundsValue`, `migrate30ItemsArrayValue`, `migrate30SchemaValue` (2026-06-10).
- [x] nullable rewrite (`nullable:true` → add `"null"` to `type`; `nullable:false` → drop `"nullable"`).
- [x] exclusive-bounds rewrite (boolean → numeric, dropping `maximum` when `exclusiveMaximum:true`).
- [x] tuple-`items` rewrite (`items:[...]` → `prefixItems:[...]` + `items:false`).
- [x] recursive document walk `migrate30To31` (applies the per-object rewrite to every nested object).
- [x] `{-# DEPRECATED #-}` pragma on all five helpers.
- [x] Registered `Data.OpenApi.Migration` in the library `exposed-modules`.

Milestone 2 — comprehensive 3.1 test suite:

- [x] Feature coverage: the per-feature specs the plan enumerated (type arrays, exclusive bounds, prefixItems, conditionals, `const`, `$defs`/`$id`/`$ref`, webhooks, Info/License) were **already authored by EP-3/EP-4/EP-5/EP-6** as `CoreTypes31Spec`, `Schema31Spec`, `TopLevel31Spec`, and `Validation31Spec`. EP-7 reuses those rather than duplicating them (see Surprises).
- [x] Added `test/Data/OpenApi/MigrationSpec.hs` (3.0→3.1 helper tests, incl. a nested-recursion case).
- [x] Added `test/Data/OpenApi/Schema/RoundtripSpec.hs` with `prop_schema31_roundtrip` over a bounded fragment generator (no `Arbitrary Schema` exists — see Surprises).
- [x] Registered both new modules in the test-suite `other-modules`; IP-5 audit clean (only `test/Spec.hs`, the `hspec-discover` driver, is unlisted — it is `main-is`).

Milestone 3 — documentation + release:

- [x] Updated `src/Data/OpenApi.hs` module header to "OpenAPI 3.1 data model" (+ pointer to `Data.OpenApi.Migration`).
- [x] Created `MIGRATION_3.0_TO_3.1.md` at the repository root.
- [x] Set `version: 4.0.0`, `synopsis: OpenAPI 3.1 data model`, and the 3.1 `description` (IP-1).
- [x] Added a `4.0.0` entry to `CHANGELOG.md` under "Unreleased".
- [x] Updated `README.md` to 3.1 wording.
- [x] `cabal test all` (448 examples, 0 failures, 5 pending), `cabal check` ("No errors or warnings"), `cabal sdist` (wrote `openapi-hs-4.0.0.tar.gz`). Moved `CHANGELOG.md`/`README.md` to `extra-doc-files` to clear the one `cabal check` warning.


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

- **No `Arbitrary Schema` instance exists (2026-06-10).** The plan (and the master plan's IP
  notes) assumed EP-3/EP-4 would update an `Arbitrary Schema` instance that `prop_schema31_roundtrip`
  could use. In fact the tree has **no** `Arbitrary Schema` — the existing property tests generate
  arbitrary *values* via `ToSchema`-derived schemas, not arbitrary `Schema` records. Authoring a
  full recursive `Arbitrary` for the ~50-field `Schema` (with `Referenced Schema` recursion needing
  careful sizing) is large and risky. Instead `RoundtripSpec` uses a **bounded fragment generator**:
  it picks a random subset of independent single-field setters (type arrays, exclusive bounds,
  `prefixItems`, `const`, `contains`, `if`/`then`, `examples`, `$id`/`$ref`, `unevaluatedItems`, …)
  and asserts `decode (encode s) === Just s`. The property "exists and runs" and exercises random
  combinations of the new fields without a full instance. (Cross-plan note: a real `Arbitrary Schema`
  remains future work if exhaustive property coverage is wanted.)

- **The per-feature specs the plan listed were already written by earlier plans (2026-06-10).**
  EP-3 added `Data.OpenApi.Schema.CoreTypes31Spec` (type arrays, numeric exclusive bounds, boolean
  items, `detectVersion`); EP-4 added `Data.OpenApi.Schema31Spec` (`prefixItems`, `const`,
  conditionals, `contains`, `examples`, `$defs`/`$id`/`$ref`, boolean sub-schemas); EP-5 added
  `Data.OpenApi.TopLevel31Spec` (`webhooks`, `Info.summary`, `License.identifier`, `PathItem.$ref`);
  EP-6 added `Data.OpenApi.Schema.Validation31Spec`. EP-7 therefore did **not** create the separate
  `TypeArraySpec`/`ExclusiveBoundsSpec`/`PrefixItemsSpec`/`ConditionalSpec`/`IdentificationSpec`/
  `WebhooksSpec`/`InfoLicenseSpec` modules the plan enumerated — that coverage already exists, and
  duplicating it would only add churn. EP-7's genuinely new test modules are `MigrationSpec` and
  `RoundtripSpec`.

- **`cabal check` flagged a doc-placement warning (2026-06-10).** With `cabal-version: 3.0`,
  `cabal check` warned that `CHANGELOG.md` belongs in `extra-doc-files`, not `extra-source-files`.
  Moved `README.md`/`CHANGELOG.md` (and the new `MIGRATION_3.0_TO_3.1.md`) to `extra-doc-files`,
  leaving only `examples/*.hs` in `extra-source-files`; `cabal check` is now clean.


## Decision Log

Record every decision made while working on the plan.

- Decision: Perform 3.0→3.1 migration at the raw `Data.Aeson.Value` layer, not on the 3.1
  `Schema` type.
  Rationale: Under Strategy A (the project-wide decision recorded in the master plan), the
  3.1 `Schema` type has no `_schemaNullable` field, numeric-only exclusive bounds, and no
  `OpenApiItemsArray` constructor — so a migration function cannot even mention the 3.0-only
  shapes if it operates on the typed value. Rewriting the parsed JSON before it is decoded is
  the only representation in which the 3.0 constructs still exist.
  Date: 2026-06-10

- Decision: Put the helpers in a dedicated, exposed module `Data.OpenApi.Migration` rather
  than inside `Data.OpenApi.Internal`.
  Rationale: The helpers are part of the public bridge for downstream users and should be
  importable and documented; placing them in `Internal` would hide them from the public API
  and from the migration guide's code examples.
  Date: 2026-06-10

- Decision: Release as version `4.0.0`.
  Rationale: The upgrade is a breaking change (removed `nullable`, exclusive-bounds type
  change, removed tuple `items`, package rename). Semantic versioning requires a major bump;
  `4.0.0` follows the prior `3.x` line. This matches the master plan and
  `OPENAPI31_MIGRATION_PLAN.md`.
  Date: 2026-06-10

- Decision: Apply `{-# DEPRECATED #-}` to the migration *helper functions*, not to any data
  constructor.
  Rationale: `{-# DEPRECATED #-}` on an identifier that no longer exists does not compile, and
  the removed 3.0 fields/constructors (`_schemaNullable`, `OpenApiItemsArray`) no longer
  exist. Deprecating the helpers signals that 3.0 input support is transitional without
  breaking compilation.
  Date: 2026-06-10

- Decision: Release-prep only; do not run `cabal upload`.
  Rationale: The master plan explicitly scopes Hackage publishing out. This plan prepares
  metadata and artifacts so a maintainer can publish later, but performing the upload is a
  separate, deliberate human action.
  Date: 2026-06-10


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose.

**Completed 2026-06-10.** All three EP-7 capabilities exist:

- `Data.OpenApi.Migration` rewrites raw 3.0 JSON into 3.1 shape
  (`migrate30To31` + the three single-concern helpers + `migrate30SchemaValue`), all deprecated
  to flag transitional 3.0 input. Verified end-to-end:
  `decode (encode (migrate30To31 {"type":"string","nullable":true}))` yields a `Schema` with
  `_schemaType = OpenApiTypeArray [OpenApiString, OpenApiNull]`.
- A comprehensive 3.1 test surface: the feature specs from EP-3..EP-6 plus EP-7's `MigrationSpec`
  and `RoundtripSpec` (`prop_schema31_roundtrip`). `cabal test all` → 448 examples, 0 failures,
  5 pending.
- Release prep: `version: 4.0.0`, `synopsis: OpenAPI 3.1 data model`, updated module header,
  README, a `4.0.0` CHANGELOG entry, and `MIGRATION_3.0_TO_3.1.md`. `cabal check` is clean and
  `cabal sdist` writes `openapi-hs-4.0.0.tar.gz`. No `cabal upload` (release-prep only, per scope).

**Gaps / future work:**
- No real `Arbitrary Schema`; the round-trip property uses a bounded fragment generator
  (Surprises). A full instance would broaden property coverage.
- The migration `version`-string is not rewritten by the helpers (a 3.0 doc's `"openapi":"3.0.x"`
  would still fail the 3.1 version bounds); callers should set `"openapi":"3.1.0"` after migrating,
  or the helper could be extended. Documented as a pitfall direction in the guide.
- Outstanding from EP-4 (tracked in the MasterPlan): generic tuple `ToSchema` still uses the
  `anyOf`-`items` stub rather than `prefixItems`; the 5 pending tuple generator props remain.


## Context and Orientation

This plan assumes the reader knows nothing about this repository. Read this section before
touching any file.

**What the library does.** It is a Haskell library, built with Cabal, whose modules live
under `src/Data/OpenApi/`. The central data type is `Schema`, defined in
`src/Data/OpenApi/Internal.hs`. A `Schema` models a JSON Schema object. The library can turn a
`Schema` into JSON (`encode`/`toJSON`) and parse JSON back into a `Schema`
(`decode`/`fromJSON`). It also has a top-level `OpenApi` type modelling a whole API document,
with sub-records `Info`, `License`, `PathItem`, and others, also in
`src/Data/OpenApi/Internal.hs`. The public façade module is `src/Data/OpenApi.hs`, which
re-exports the user-facing names and carries the package's top-level documentation.

**Strategy A, in plain terms.** OpenAPI 3.1 changed three things so that a 3.0 document can no
longer be represented by the same Haskell types: (1) it removed the `nullable: true` keyword
in favour of putting `"null"` into a `type` array, e.g. `type: ["string", "null"]`; (2) it
changed `exclusiveMaximum`/`exclusiveMinimum` from booleans that modify `maximum`/`minimum`
into independent numeric keywords; and (3) it removed the array form of `items` (used in 3.0
for fixed-length tuples) in favour of a new `prefixItems` array plus `items: false`. The
project chose "Strategy A": the Haskell types represent **only 3.1**. The field
`_schemaNullable` is **gone** from `Schema`; `_schemaExclusiveMaximum`/`_schemaExclusiveMinimum`
are now `Maybe Scientific` (numbers) instead of `Maybe Bool`; and the `OpenApiItems` type
dropped its `OpenApiItemsArray` constructor (tuple validation now lives in a new
`_schemaPrefixItems` field). These changes are delivered by the earlier plans (EP-3 and EP-4);
this plan **consumes** them. Because the 3.1 types cannot express 3.0-only shapes, a user with
a 3.0 document must first rewrite the *raw JSON* into a 3.1 shape — that is exactly what this
plan's migration helpers do.

**The companion plans this plan depends on.** These are checked into the repository; reference
them by path rather than reproducing them in full:

- `docs/masterplans/1-openapi-3-1-support-and-project-modernization.md` — the master plan.
  This plan is **EP-7** in its registry. EP-7 **hard-depends** on EP-3, EP-4, and EP-5
  (their type changes and fields must already exist before EP-7's tests and helpers can
  exercise them), and **soft-depends** on EP-2 (the package rename) and EP-6 (validation). The
  master plan's Integration Points **IP-1**, **IP-4**, and **IP-5** govern this plan and are
  restated below.
- `docs/plans/3-openapi-3-1-core-schema-type-changes.md` — EP-3, "OpenAPI 3.1 Core Schema Type
  Changes". It introduces `OpenApiTypeValue` (so `_schemaType :: Maybe OpenApiTypeValue` can be
  a single type or an array), changes exclusive bounds to `Scientific`, removes
  `_schemaNullable`, and reshapes `OpenApiItems` to object-or-boolean. EP-3 also updates the
  QuickCheck `Arbitrary Schema` instance to the new shape; EP-7's property test relies on that.
- `docs/plans/4-openapi-3-1-json-schema-fields-and-reference-keywords.md` — EP-4. It adds the
  additive JSON Schema 2020-12 fields (`_schemaConst`, `_schemaPrefixItems`, `_schemaIf`,
  `_schemaThen`, `_schemaElse`, `_schemaContains`, `_schemaMinContains`, `_schemaMaxContains`,
  `_schemaUnevaluatedProperties`, `_schemaUnevaluatedItems`, content keywords, `_schemaExamples`)
  and the `$`-prefixed reference keywords (`$id`, `$anchor`, `$defs`, `$ref`, `$dynamicRef`,
  `$dynamicAnchor`). EP-7's tests for `prefixItems`, conditionals, `const`, and `$defs`/`$id`/`$ref`
  exercise these fields.
- `docs/plans/5-openapi-3-1-top-level-object-features.md` — EP-5. It adds `webhooks` to
  `OpenApi`, `summary` to `Info`, `identifier` to `License`, and `$ref` to `PathItem`. EP-7's
  webhooks and Info/License tests exercise these.
- `docs/plans/6-openapi-3-1-schema-validation.md` — EP-6 (soft dependency). It updates schema
  validation for the new keywords. EP-7 can ship without it but should cover its behavior if
  present.

**The migration plan.** `OPENAPI31_MIGRATION_PLAN.md` at the repository root is the original
design note. This ExecPlan implements its §1.1.2 (exclusive-bounds rewrite), §1.1.3 (nullable
rewrite), §4.3 (tuple `items` → `prefixItems`), §5.2 (deprecating the migration helpers),
Phase 6 (testing), and Phase 7 (documentation, cabal metadata, 4.0.0 release).

**The aeson compatibility layer.** The library abstracts the differences between aeson 1.x and
2.x through `src/Data/OpenApi/Aeson/Compat.hs`. In aeson 2.x a JSON object is a
`Data.Aeson.KeyMap.KeyMap Value` keyed by `Data.Aeson.Key`; in aeson 1.x it is a
`HashMap Text Value`. `Data.OpenApi.Aeson.Compat` exposes helpers that work on both:
`deleteKey`, `objectToList`, `objectKeys`, `stringToKey`, `keyToString`, `keyToText`,
`lookupKey :: Text -> object -> Maybe v`, and `hasKey :: Text -> object -> Bool`. The
migration helpers must use these helpers (plus `KeyMap`/`HashMap` insert via the same CPP
pattern) so the code compiles on both aeson majors. Note that `Internal.hs` itself imports
`Data.Aeson hiding (Encoding)`, `qualified Data.Aeson.KeyMap as KeyMap`, and
`Data.OpenApi.Aeson.Compat (deleteKey)`; mirror that import style.

**Where things are in `Internal.hs` (post EP-3/EP-4/EP-5).** `OpenApiType` is a GADT-style
enum at `Internal.hs:591`, and crucially `OpenApiNull :: OpenApiType` already exists
(`Internal.hs:597`) — the nullable migration relies on this. `Schema` has `Semigroup`/`Monoid`
instances near `Internal.hs:1007` (`mempty = genericMempty`), so `mempty { _schemaType = ... }`
builds a `Schema` with only the named field set — the migration tests use this. The exact line
numbers shift once EP-3/EP-4/EP-5 land; locate identifiers by name, not by line number.

**The test harness.** `test/Spec.hs` contains the single line
`{-# OPTIONS_GHC -F -pgmF hspec-discover #-}`. This means `hspec-discover` (a build tool) scans
the `test/` directory at build time and automatically aggregates every module named `*Spec.hs`
whose top-level value is `spec :: Spec`. A new spec file is discovered automatically **only if**
it is also listed in the test-suite's `other-modules` in the `.cabal` (so the compiler builds
it) — that is Integration Point IP-5. `test/SpecCommon.hs` provides the round-trip combinator
`(<=>) :: (Eq a, Show a, ToJSON a, FromJSON a) => a -> Value -> Spec`, which asserts that a
Haskell value encodes to the given JSON, decodes back from it, and survives encode/decode
round trips. Existing specs `test/Data/OpenApiSpec.hs` and `test/Data/OpenApi/SchemaSpec.hs`
show the prevailing style: define expected `Schema`/`OpenApi` values and pair them with literal
JSON via `<=>` inside `describe`/`it` blocks.

**The `.cabal` file and its name.** At the start of this initiative the package file is
`openapi3.cabal` with `name: openapi3` and `version: 3.2.5`. **EP-1** changed its structure
(`cabal-version`, `build-type` `Custom`→`Simple`, removed the `custom-setup` stanza and the
`doctests` test-suite, trimmed `tested-with`). **EP-2** renamed the file to `openapi-hs.cabal`
and set `name: openapi-hs`, and updated `synopsis`/`description`/`homepage`/`bug-reports`/
`source-repository` plus the `openapi3` self-references in the test and example
`build-depends`. **This plan (EP-7) re-reads whatever `.cabal` exists** and edits only the
`version` field and the final synopsis/description wording (IP-1). If you find `openapi3.cabal`
still present (because EP-1/EP-2 have not run yet in your working tree), edit that file in
place; do not rename it (that is EP-2's job) and do not change `name`, `build-type`,
`cabal-version`, or `tested-with` (those belong to EP-1/EP-2).


## Plan of Work

The work proceeds in three milestones, each independently verifiable. Milestone 1 (migration
helpers) is pure library code and can be compiled and unit-tested on its own. Milestone 2 (the
test suite) depends on Milestone 1's helpers for the migration specs and on the EP-3/EP-4/EP-5
fields for the feature specs. Milestone 3 (documentation and release) is metadata and prose; it
depends only on the prior two being green.

### Milestone 1 — Value-layer migration helpers

Scope: add a new exposed module `src/Data/OpenApi/Migration.hs` that rewrites a raw,
already-parsed 3.0 `Data.Aeson.Value` into a 3.1-shaped `Value`. At the end of this milestone,
a user can `import Data.OpenApi.Migration (migrate30To31)`, apply it to JSON parsed from a 3.0
document, and `decode` the result into the new 3.1 types. The module compiles on aeson 1.x and
2.x because it goes through `Data.OpenApi.Aeson.Compat`.

The module's public surface is exactly these functions. The top-level entry point recursively
walks a whole document; the three single-concern helpers do one rewrite each and are reused by
the walk and exercised directly by tests:

```haskell
module Data.OpenApi.Migration
  ( migrate30To31
  , migrate30NullableValue
  , migrate30ExclusiveBoundsValue
  , migrate30ItemsArrayValue
  , migrate30SchemaValue
  ) where
```

Define the three single-concern rewrites first. Each takes a `Value` and, when that value is a
JSON object, performs its one rewrite; for any non-object it returns the value unchanged. Use
the `Data.OpenApi.Aeson.Compat` helpers (`lookupKey`, `hasKey`, `deleteKey`) plus `KeyMap`
insert (guarded by the same CPP `MIN_VERSION_aeson(2,0,0)` pattern used in
`Data.OpenApi.Aeson.Compat`) so the code is aeson-version-agnostic. A small private helper
`overObject :: (Object -> Object) -> Value -> Value` that applies a function to the underlying
map of a JSON object and leaves everything else alone keeps the three rewrites tidy.

The nullable rewrite (migration plan §1.1.3): when the object has `"nullable": true`, delete
the `"nullable"` key and add `"null"` to the `"type"` key, turning a string `"string"` into the
array `["string", "null"]`, an existing single-element array `["string"]` into
`["string", "null"]`, and a longer array by appending `"null"` if not already present. If
`"type"` is absent, the result is `{"type": ["null"]}` after the nullable removal (a value that
is only null). When the object has `"nullable": false`, just delete `"nullable"`. When there is
no `"nullable"` key, return the object unchanged.

```haskell
-- | Rewrite a decoded 3.0 schema JSON object into a 3.1-shaped 'Value'.
-- @nullable:true@ removes the @nullable@ key and adds @"null"@ to the @type@ key
-- (@"string"@ becomes @["string","null"]@; @["string"]@ becomes @["string","null"]@).
-- @nullable:false@ just removes the @nullable@ key.
migrate30NullableValue :: Value -> Value
migrate30NullableValue = overObject $ \o ->
  case lookupKey "nullable" o of
    Just (Bool True)  -> insertKey "type" (addNull (lookupKey "type" o))
                           (deleteKey (stringToKey "nullable") o)
    Just (Bool False) -> deleteKey (stringToKey "nullable") o
    _                 -> o
  where
    -- "string"            -> ["string","null"]
    -- ["string", ...]     -> ["string", ..., "null"]  (only if "null" absent)
    -- Nothing (no type)   -> ["null"]
    addNull :: Maybe Value -> Value
    addNull = ...
```

The exclusive-bounds rewrite (migration plan §1.1.2): in 3.0, `exclusiveMaximum` is a boolean
that *modifies* `maximum`. In 3.1, `exclusiveMaximum` is itself a number and `maximum` is
independent. The rewrite handles each of the two keyword pairs independently. When
`"exclusiveMaximum": true` is present and `"maximum"` is a number, replace both with
`"exclusiveMaximum": <thatNumber>` (drop `"maximum"`). When `"exclusiveMaximum": false` is
present, drop the boolean `"exclusiveMaximum"` and keep `"maximum"` unchanged. If
`"exclusiveMaximum"` is already a number (already 3.1-shaped), leave it. The same logic applies
to `exclusiveMinimum`/`minimum`.

```haskell
-- | Rewrite 3.0 boolean exclusive bounds into 3.1 numeric ones.
-- @{"maximum":100,"exclusiveMaximum":true}@  -> @{"exclusiveMaximum":100}@ (drops maximum)
-- @{"maximum":100,"exclusiveMaximum":false}@ -> @{"maximum":100}@
-- Symmetric for minimum / exclusiveMinimum.
migrate30ExclusiveBoundsValue :: Value -> Value
migrate30ExclusiveBoundsValue = overObject (rewriteBound "maximum" "exclusiveMaximum"
                                          . rewriteBound "minimum" "exclusiveMinimum")
  where
    rewriteBound boundKey exclKey o = ...
```

The tuple-`items` rewrite (migration plan §4.3): in 3.0, `"items": [s1, s2, ...]` (an array)
meant tuple validation. In 3.1 that becomes `"prefixItems": [s1, s2, ...]` together with
`"items": false` (no additional items allowed). The rewrite fires only when `"items"` is a JSON
array; when `"items"` is an object (single-schema items) or already `false`/`true`, leave it.

```haskell
-- | Rewrite a 3.0 tuple @items@ array into 3.1 @prefixItems@ + @items:false@.
-- @{"items":[a,b]}@ -> @{"prefixItems":[a,b],"items":false}@
migrate30ItemsArrayValue :: Value -> Value
migrate30ItemsArrayValue = overObject $ \o ->
  case lookupKey "items" o of
    Just (Array xs) -> insertKey "items" (Bool False)
                         (insertKey "prefixItems" (Array xs)
                           (deleteKey (stringToKey "items") o))
    _               -> o
```

Compose the three into a single per-object rewrite, then provide the recursive whole-document
walk. `migrate30SchemaValue` applies all three rewrites to one object (order does not matter
because the three operate on disjoint keys: `nullable`/`type`, `maximum`/`exclusiveMaximum`/
`minimum`/`exclusiveMinimum`, and `items`/`prefixItems`). `migrate30To31` walks the entire
`Value` recursively — into every object value and every array element — applying
`migrate30SchemaValue` to each object it encounters, so that nested schemas (inside
`properties`, `prefixItems`, `$defs`, `allOf`, `additionalProperties`, request/response bodies,
and so on) are all migrated. Applying the per-object rewrite to *every* object is safe because
the rewrites are no-ops on objects that lack the trigger keys.

```haskell
-- | Apply all single-object 3.0->3.1 rewrites to one schema object.
migrate30SchemaValue :: Value -> Value
migrate30SchemaValue =
  migrate30NullableValue . migrate30ExclusiveBoundsValue . migrate30ItemsArrayValue

-- | Recursively rewrite a whole 3.0 document 'Value' into 3.1 shape, applying
-- the schema rewrites to every nested object.
migrate30To31 :: Value -> Value
migrate30To31 = go
  where
    go (Object o) = migrate30SchemaValue (Object (fmap go o))
    go (Array xs) = Array (fmap go xs)
    go v          = v
```

Finally, add the deprecation pragmas (migration plan §5.2). These attach to the *functions* (a
valid target), signalling that 3.0 input support is transitional:

```haskell
{-# DEPRECATED migrate30NullableValue, migrate30ExclusiveBoundsValue,
               migrate30ItemsArrayValue, migrate30SchemaValue, migrate30To31
      "3.0 input support is transitional; remove once all inputs are 3.1." #-}
```

Register the module in the library `exposed-modules` of the `.cabal` (add the line
`Data.OpenApi.Migration` next to `Data.OpenApi`). This is the only library-stanza change in
this plan.

Acceptance for Milestone 1: `nix develop -c cabal build all` compiles the new module, and the
GHCi snippet in "Validation and Acceptance" produces the expected 3.1-shaped `Value` and
decodes into the expected `Schema`.

### Milestone 2 — comprehensive 3.1 test suite

Scope: add new `*Spec.hs` modules under `test/Data/OpenApi/` covering every 3.1 feature plus
the migration helpers, register them all in the test-suite `other-modules`, and run the final
IP-5 audit confirming each is listed and discovered. At the end, `nix develop -c cabal test all`
runs all specs green.

Create the spec modules following the existing style in `test/Data/OpenApi/SchemaSpec.hs`: each
module declares `module ... where`, imports `Data.OpenApi`, `Test.Hspec`, `Data.Aeson`
(`object`, `(.=)`, `Value`), `SpecCommon ((<=>))`, and defines a top-level `spec :: Spec`. Pair
an expected Haskell value with literal JSON using `<=>` from `test/SpecCommon.hs`, which checks
encode, decode, and round-trip in one shot.

The modules and what each covers (each filename's module path must match the on-disk path so
`hspec-discover` and the compiler agree):

`test/Data/OpenApi/Schema/TypeArraySpec.hs` — type arrays. Assert that
`mempty { _schemaType = Just (OpenApiTypeArray [OpenApiString, OpenApiNull]) }` encodes to and
decodes from `{"type": ["string","null"]}`, and that the single form
`mempty { _schemaType = Just (OpenApiTypeSingle OpenApiString) }` round-trips
`{"type": "string"}`. (The constructors `OpenApiTypeValue`, `OpenApiTypeSingle`,
`OpenApiTypeArray` come from EP-3.)

`test/Data/OpenApi/Schema/ExclusiveBoundsSpec.hs` — numeric exclusive bounds. Assert
`mempty { _schemaExclusiveMinimum = Just 0, _schemaExclusiveMaximum = Just 100 }` round-trips
`{"exclusiveMinimum": 0, "exclusiveMaximum": 100}`, and that a schema carrying both `maximum`
and a numeric `exclusiveMaximum` round-trips (they are independent in 3.1). (`Scientific`
literals like `0`/`100` work via `Num`.)

`test/Data/OpenApi/Schema/PrefixItemsSpec.hs` — `prefixItems` plus `items: false`. Assert a
schema with `_schemaPrefixItems = Just [Inline strSchema, Inline numSchema]` and the
`items: false` representation round-trips
`{"prefixItems": [{"type":"string"},{"type":"number"}], "items": false}`. (`_schemaPrefixItems`
comes from EP-4; the `items:false` representation is EP-3's `OpenApiItemsBoolean False`.)

`test/Data/OpenApi/Schema/ConditionalSpec.hs` — `if`/`then`/`else`/`const`. Assert a schema
with `_schemaIf`/`_schemaThen`/`_schemaElse` set, and a separate schema with
`_schemaConst = Just (...)`, round-trip their JSON (e.g. `{"const": "USA"}` and the
country/postal-code example from the migration plan §6.1). (These fields come from EP-4.)

`test/Data/OpenApi/Schema/IdentificationSpec.hs` — `$defs`/`$id`/`$ref`. Assert that schemas
carrying `_schemaId = Just "..."`, `_schemaDefs = Just (...)`, and a `$ref`-bearing schema
round-trip the `$`-prefixed JSON keys correctly. (These keys and their serialization come from
EP-4's `$`-key helper; this spec is the regression check that the helper keeps them
round-tripping.)

`test/Data/OpenApi/WebhooksSpec.hs` — `webhooks`. Assert an `OpenApi` value with
`_openApiWebhooks` populated by a `Referenced PathItem` round-trips its
`{"webhooks": {"newPet": {"post": {...}}}}` JSON. (`_openApiWebhooks` comes from EP-5.)

`test/Data/OpenApi/InfoLicenseSpec.hs` — `Info.summary` and `License.identifier`. Assert an
`Info` with `_infoSummary = Just "..."` round-trips `{"summary": "...", ...}`, and a `License`
with `_licenseIdentifier = Just "MIT"` round-trips `{"name": "...", "identifier": "MIT"}`.
(Both fields come from EP-5.)

`test/Data/OpenApi/MigrationSpec.hs` — the migration helpers (migration plan §6.3). This module
imports `Data.OpenApi.Migration` and asserts the helpers' behavior, then decodes their output
into the 3.1 `Schema`:

```haskell
module Data.OpenApi.MigrationSpec where

import Data.Aeson (Value, decode, encode, object, (.=))
import Data.Text (Text)
import Test.Hspec
import Data.OpenApi
import Data.OpenApi.Migration (migrate30NullableValue,
                               migrate30ExclusiveBoundsValue,
                               migrate30ItemsArrayValue)

spec :: Spec
spec = describe "3.0 to 3.1 migration" $ do
  it "converts nullable:true to a type array" $ do
    let v30 = object [ "type" .= ("string" :: Text), "nullable" .= True ]
    (decode (encode (migrate30NullableValue v30)) :: Maybe Schema)
      `shouldBe`
      Just (mempty { _schemaType =
                       Just (OpenApiTypeArray [OpenApiString, OpenApiNull]) })

  it "drops nullable:false without touching type" $ do
    let v30 = object [ "type" .= ("string" :: Text), "nullable" .= False ]
    (decode (encode (migrate30NullableValue v30)) :: Maybe Schema)
      `shouldBe`
      Just (mempty { _schemaType = Just (OpenApiTypeSingle OpenApiString) })

  it "rewrites boolean exclusiveMaximum to a numeric bound" $ do
    let v30 = object [ "maximum" .= (100 :: Int), "exclusiveMaximum" .= True ]
    (decode (encode (migrate30ExclusiveBoundsValue v30)) :: Maybe Schema)
      `shouldBe`
      Just (mempty { _schemaExclusiveMaximum = Just 100 })

  it "rewrites a tuple items array into prefixItems + items:false" $ do
    let v30 = object [ "items" .=
                ([ object ["type" .= ("string" :: Text)]
                 , object ["type" .= ("number" :: Text)] ] :: [Value]) ]
    -- decodes into a Schema with prefixItems set and items:false
    (decode (encode (migrate30ItemsArrayValue v30)) :: Maybe Schema)
      `shouldSatisfy` ( /= Nothing )
```

The comment in the migration plan notes that `mempty` works because `Schema` has a `Monoid`
instance (`genericMempty`, near `Internal.hs:1007`) and `OpenApiNull` already exists as an
`OpenApiType` constructor (`Internal.hs:597`, Integration Point IP-4).

Add the property-based round-trip test. Place it in the migration/property spec or a small
`test/Data/OpenApi/Schema/RoundtripSpec.hs`. It states that any `Schema` survives encode then
decode:

```haskell
prop_schema31_roundtrip :: Schema -> Property
prop_schema31_roundtrip s = decode (encode s) === Just s
```

This depends on the QuickCheck `Arbitrary Schema` instance, which EP-3/EP-4 update to cover the
new fields. If, when you run this, the property fails on a field EP-3/EP-4 left out of
`Arbitrary` or out of the JSON instances, record it in Surprises & Discoveries and note it as a
cross-plan gap (it is then a defect in EP-3/EP-4, not in EP-7); the EP-7 deliverable is that the
property test *exists and runs*.

Register every new module in the test-suite `other-modules` (IP-5). After EP-2's rename the file
is `openapi-hs.cabal`; otherwise `openapi3.cabal`. The `other-modules` block must end up listing
the existing entries plus:

```cabal
    Data.OpenApi.Schema.TypeArraySpec
    Data.OpenApi.Schema.ExclusiveBoundsSpec
    Data.OpenApi.Schema.PrefixItemsSpec
    Data.OpenApi.Schema.ConditionalSpec
    Data.OpenApi.Schema.IdentificationSpec
    Data.OpenApi.Schema.RoundtripSpec
    Data.OpenApi.WebhooksSpec
    Data.OpenApi.InfoLicenseSpec
    Data.OpenApi.MigrationSpec
```

Final IP-5 audit: run `nix develop -c cabal test all` and confirm `hspec-discover` reports each
new spec running. Cross-check by listing every `*Spec.hs` under `test/` and verifying each
appears in `other-modules`:

```bash
diff <(cd test && find . -name '*Spec.hs' | sed 's#^\./##;s#\.hs$##;s#/#.#g' | sort) \
     <(grep -oE '[A-Za-z.]+Spec' openapi-hs.cabal | sort -u)
```

An empty diff means every on-disk spec is registered. (Use `openapi3.cabal` if EP-2 has not run.)

Acceptance for Milestone 2: `nix develop -c cabal test all` passes all suites including the new
specs; the audit diff is empty.

### Milestone 3 — documentation + release

Scope: update prose and metadata for the 4.0.0 release. At the end, the package metadata
declares 4.0.0 and "OpenAPI 3.1 data model", `cabal check` passes, the module docs and README
say 3.1, the CHANGELOG has a 4.0.0 entry, and `MIGRATION_3.0_TO_3.1.md` exists at the repository
root. No upload is performed.

Update `src/Data/OpenApi.hs` module haddock header. Replace the Swagger-era opening paragraph
with a statement that this is the OpenAPI 3.1 data model and that the library supports OpenAPI
Specification version 3.1.x (migration plan §7.1):

```haskell
-- |
-- Module:      Data.OpenApi
-- ...
--
-- OpenAPI 3.1 data model.
--
-- This library supports OpenAPI Specification version 3.1.x, decoding and
-- encoding 3.1 API specifications as well as manipulating them. The
-- specification is available at https://spec.openapis.org/oas/v3.1.0
```

Create `MIGRATION_3.0_TO_3.1.md` at the repository root. It is hand-written prose for downstream
users and must contain, in plain language: a breaking-changes summary (`nullable` removed in
favour of type arrays; `exclusiveMaximum`/`exclusiveMinimum` now numeric and independent of
`maximum`/`minimum`; tuple `items` arrays replaced by `prefixItems` + `items:false`; supported
version bounds moved to 3.1.x; the package renamed to `openapi-hs`); code-migration examples
using the helpers (showing `migrate30To31` applied to a parsed 3.0 document and then `decode`d,
plus the single-concern helpers); and common pitfalls (e.g. that a bare `nullable: true` with no
`type` becomes `type: ["null"]`; that `exclusiveMaximum: true` *drops* `maximum`; that the
helpers are deprecated on purpose to flag transitional 3.0 input).

Update the `.cabal` (IP-1 — EP-7 owns **only** `version` and the final synopsis/description
wording; do not touch `name`, `build-type`, `cabal-version`, or `tested-with`). Set:

```cabal
version:             4.0.0
synopsis:            OpenAPI 3.1 data model
description:
  This library is intended to be used for decoding and encoding OpenAPI 3.1 API
  specifications as well as manipulating them.
  .
  The OpenAPI 3.1 specification is available at https://spec.openapis.org/oas/v3.1.0
```

Re-read the file before editing to confirm the current `name` and structure (it may be
`openapi-hs.cabal` after EP-2 or still `openapi3.cabal`); change only the three pieces above.

Add a `4.0.0` entry to `CHANGELOG.md`. The file currently opens with an `Unreleased` heading
followed by `3.2.5`. Insert the `4.0.0` section between `Unreleased` and `3.2.5`, summarizing
every breaking change delivered across EP-1..EP-6 and the rename:

```text
Unreleased
----------

4.0.0
-----

- **Breaking:** the data model now represents OpenAPI 3.1 / JSON Schema 2020-12
  instead of 3.0. Supported spec versions are 3.1.x.
- **Breaking:** removed `nullable`; use `type: ["...","null"]` (`OpenApiTypeArray`).
- **Breaking:** `exclusiveMaximum`/`exclusiveMinimum` are now numeric (`Scientific`)
  and independent of `maximum`/`minimum`.
- **Breaking:** removed the tuple `items` array; use `prefixItems` + `items: false`.
- Added JSON Schema 2020-12 fields: `prefixItems`, `const`, `if`/`then`/`else`,
  `contains`/`minContains`/`maxContains`, `unevaluatedProperties`/`unevaluatedItems`,
  content keywords, `examples`, and `$id`/`$anchor`/`$defs`/`$ref`/`$dynamicRef`/`$dynamicAnchor`.
- Added top-level 3.1 features: `webhooks`, `Info.summary`, `License.identifier`,
  and `$ref` on `PathItem`.
- Added `Value`-layer 3.0->3.1 migration helpers in `Data.OpenApi.Migration`.
- Schema validation understands the new 3.1 keywords.
- **Build:** Cabal-only on GHC 9.12+/9.14; removed `stack.yaml` and the custom
  `Setup.hs`/`cabal-doctest` machinery.
- **Renamed** the package from `openapi3` to `openapi-hs` (module namespace
  `Data.OpenApi.*` unchanged).
```

Update `README.md` to 3.1 wording. EP-2 already handled the package *name* in the README; EP-7
updates the 3.1 *wording*: change "OpenAPI 3.0 data model" to "OpenAPI 3.1 data model", change
the sentence about decoding "OpenApi 3.0.3 specifications" to 3.1, and update the spec link from
`http://swagger.io/specification/` to `https://spec.openapis.org/oas/v3.1.0`.

Acceptance for Milestone 3: `grep 'version: *4.0.0'` on the `.cabal` matches;
`nix develop -c cabal check` reports no errors; `nix develop -c cabal sdist` builds a tarball
without complaint; `MIGRATION_3.0_TO_3.1.md` exists; the module header, README, and CHANGELOG
say 3.1/4.0.0.


## Concrete Steps

Run everything from the repository root `/Users/shinzui/Keikaku/hub/haskell/openapi3`. The
project builds inside the Nix dev shell; prefix Cabal commands with `nix develop -c`. If you are
already inside `nix develop`, drop the prefix.

First, confirm the current `.cabal` filename and name, so later edits target the right file:

```bash
ls *.cabal
grep -nE '^name:|^version:|^synopsis:' *.cabal
```

Expected, depending on whether EP-2 has run:

```text
openapi-hs.cabal           # after EP-2 (or openapi3.cabal before it)
name:                openapi-hs
version:             3.2.5
synopsis:            ...
```

Milestone 1: create `src/Data/OpenApi/Migration.hs` as designed above, then add
`Data.OpenApi.Migration` to the library `exposed-modules` (next to `Data.OpenApi`). Build:

```bash
nix develop -c cabal build all
```

Expected tail:

```text
[ N of M] Compiling Data.OpenApi.Migration ( src/Data/OpenApi/Migration.hs, ... )
Linking ...
```

Smoke-test the helper in GHCi:

```bash
nix develop -c cabal repl lib:openapi-hs
```

```haskell
λ> import Data.Aeson
λ> import Data.Text (Text)
λ> import Data.OpenApi.Migration
λ> migrate30NullableValue (object ["type" .= ("string"::Text), "nullable" .= True])
Object (fromList [("type",Array [String "string",String "null"])])
```

(The exact `show` formatting of the `Object` varies by aeson version; the load-bearing part is
that `nullable` is gone and `type` is the array `["string","null"]`.)

Milestone 2: create the spec modules under `test/Data/OpenApi/` and `test/Data/OpenApi/Schema/`,
register each in the test-suite `other-modules`, then:

```bash
nix develop -c cabal test all
```

Expected tail (suite names and counts illustrative):

```text
Data.OpenApi.MigrationSpec
  3.0 to 3.1 migration
    converts nullable:true to a type array          [✔]
    drops nullable:false without touching type      [✔]
    rewrites boolean exclusiveMaximum ...            [✔]
    rewrites a tuple items array ...                 [✔]
...
Finished in 0.0s
NNN examples, 0 failures
```

Run the IP-5 registration audit (empty diff is success):

```bash
CABAL=$(ls *.cabal)
diff <(cd test && find . -name '*Spec.hs' | sed 's#^\./##;s#\.hs$##;s#/#.#g' | sort) \
     <(grep -oE '[A-Za-z.]+Spec' "$CABAL" | sort -u)
```

Milestone 3: edit `src/Data/OpenApi.hs`, the `.cabal` `version`/`synopsis`/`description`,
`CHANGELOG.md`, `README.md`, and create `MIGRATION_3.0_TO_3.1.md`. Then:

```bash
grep -nE '^version:' *.cabal          # must show 4.0.0
nix develop -c cabal check
nix develop -c cabal sdist
nix develop -c cabal test all
```

Expected:

```text
version:             4.0.0
...
No errors or warnings could be found in the package.
...
Wrote tarball sdist to dist-newstyle/sdist/openapi-hs-4.0.0.tar.gz
...
NNN examples, 0 failures
```


## Validation and Acceptance

Acceptance is observable behavior, not just compilation.

Migration helper, end to end. In `nix develop -c cabal repl lib:openapi-hs`, this snippet must
produce the type-array schema:

```haskell
λ> :set -XOverloadedStrings
λ> import Data.Aeson (object, (.=), encode, decode)
λ> import Data.Text (Text)
λ> import Data.OpenApi
λ> import Data.OpenApi.Migration (migrate30NullableValue)
λ> decode (encode (migrate30NullableValue (object ["type" .= ("string"::Text), "nullable" .= True]))) :: Maybe Schema
```

Expected result:

```text
Just (Schema {_schemaType = Just (OpenApiTypeArray [OpenApiString,OpenApiNull]), ...})
```

Equivalently, the assertion baked into `test/Data/OpenApi/MigrationSpec.hs`:

```haskell
decode (encode (migrate30NullableValue v30)) :: Maybe Schema)
  `shouldBe`
  Just (mempty { _schemaType = Just (OpenApiTypeArray [OpenApiString, OpenApiNull]) })
```

Full test suite. From the repository root:

```bash
nix develop -c cabal test all
```

All suites — the existing specs plus the new `TypeArraySpec`, `ExclusiveBoundsSpec`,
`PrefixItemsSpec`, `ConditionalSpec`, `IdentificationSpec`, `RoundtripSpec`, `WebhooksSpec`,
`InfoLicenseSpec`, and `MigrationSpec` — report `0 failures`. The property test
`prop_schema31_roundtrip` passes its default 100 random `Schema` values.

Package metadata at 4.0.0. From the repository root:

```bash
grep -E '^version: *4\.0\.0' *.cabal
grep -E '^synopsis: *OpenAPI 3\.1 data model' *.cabal
nix develop -c cabal check
nix develop -c cabal sdist
```

`cabal check` prints `No errors or warnings could be found in the package.` and `cabal sdist`
writes `openapi-hs-4.0.0.tar.gz` (or `openapi3-4.0.0.tar.gz` if EP-2 has not run). No
`cabal upload` is run — release prep only.

Documentation present. `MIGRATION_3.0_TO_3.1.md` exists at the repository root and mentions
`nullable`, `exclusiveMaximum`, `prefixItems`, and `migrate30To31`; `src/Data/OpenApi.hs`'s
header says "OpenAPI 3.1 data model"; `CHANGELOG.md` has a `4.0.0` section; `README.md` says
3.1. Verify quickly:

```bash
test -f MIGRATION_3.0_TO_3.1.md && echo present
grep -q 'OpenAPI 3.1 data model' src/Data/OpenApi.hs && echo header-ok
grep -q '^4.0.0' CHANGELOG.md && echo changelog-ok
```


## Idempotence and Recovery

Every step is safe to repeat. Creating `src/Data/OpenApi/Migration.hs`,
`MIGRATION_3.0_TO_3.1.md`, and the spec modules is idempotent: re-running overwrites with the
same content. The `.cabal` edits set fixed values (`version: 4.0.0`, the synopsis, the
description), so applying them twice yields the same file; before editing, re-read the file to
confirm you are changing only `version`/`synopsis`/`description` and not reverting EP-1's
structural fields or EP-2's `name`/rename.

If `cabal build` or `cabal test` fails because an EP-3/EP-4/EP-5 field or constructor referenced
by a spec does not yet exist (those plans have not landed in your tree), that spec cannot be
written yet: note the missing dependency in Surprises & Discoveries, comment the affected
`it`/module out with a `TODO(EP-3/EP-4/EP-5)` marker so the rest of the suite stays green, and
revisit once the dependency lands. The migration helpers (Milestone 1) depend only on aeson and
the `Aeson.Compat` layer, so they can be built and tested even if some feature specs are blocked.

If the IP-5 audit diff is non-empty, it names either a spec on disk missing from
`other-modules` (add it) or an `other-modules` entry with no file (remove it or create the
file). Re-run the diff until empty.

`cabal sdist` writes into `dist-newstyle/` and never mutates source; deleting that directory and
re-running is safe. No step uploads anything.


## Interfaces and Dependencies

Libraries and modules used, and why: `Data.Aeson` (`Value`, `Object`, `Bool`, `Array`, `String`,
`object`, `(.=)`, `encode`, `decode`) for the raw-JSON rewrites and tests;
`Data.OpenApi.Aeson.Compat` (at `src/Data/OpenApi/Aeson/Compat.hs`) for aeson-version-agnostic
key operations (`deleteKey`, `lookupKey`, `hasKey`, `stringToKey`, `objectToList`) so the
migration module compiles on aeson 1.x and 2.x; `Data.OpenApi` for the public `Schema`,
`OpenApiType`, `OpenApiTypeValue`, `Info`, `License`, `OpenApi` types under test;
`Test.Hspec`/`Test.QuickCheck` and `SpecCommon` (`test/SpecCommon.hs`'s `<=>`) for the test
harness. The `hspec-discover` build tool aggregates the specs via `test/Spec.hs`.

Types and functions that must exist at the end of each milestone.

End of Milestone 1 — in the new module `Data.OpenApi.Migration`:

```haskell
migrate30To31                :: Value -> Value
migrate30NullableValue       :: Value -> Value
migrate30ExclusiveBoundsValue :: Value -> Value
migrate30ItemsArrayValue     :: Value -> Value
migrate30SchemaValue         :: Value -> Value
```

All five are exported and carry `{-# DEPRECATED #-}` pragmas. The library `.cabal`
`exposed-modules` lists `Data.OpenApi.Migration`.

End of Milestone 2 — these spec modules exist, each defining `spec :: Spec`, and each is listed
in the test-suite `other-modules`: `Data.OpenApi.Schema.TypeArraySpec`,
`Data.OpenApi.Schema.ExclusiveBoundsSpec`, `Data.OpenApi.Schema.PrefixItemsSpec`,
`Data.OpenApi.Schema.ConditionalSpec`, `Data.OpenApi.Schema.IdentificationSpec`,
`Data.OpenApi.Schema.RoundtripSpec`, `Data.OpenApi.WebhooksSpec`,
`Data.OpenApi.InfoLicenseSpec`, `Data.OpenApi.MigrationSpec`. The property
`prop_schema31_roundtrip :: Schema -> Property` exists and runs. This milestone depends on the
EP-3/EP-4/EP-5 fields and on EP-3's updated `Arbitrary Schema` (IP-4 for `OpenApiNull` in
`OpenApiTypeArray`).

End of Milestone 3 — the `.cabal` declares `version: 4.0.0`, `synopsis: OpenAPI 3.1 data model`,
and the 3.1 description; `src/Data/OpenApi.hs` header says "OpenAPI 3.1 data model";
`MIGRATION_3.0_TO_3.1.md` exists; `CHANGELOG.md` has a `4.0.0` entry; `README.md` says 3.1.
Integration Point IP-1 constrains EP-7 to the `version` field and final synopsis/description
wording only.


## Revision Notes

- 2026-06-10: Initial full authoring of the plan from the skeleton. Filled Purpose, Progress
  (three milestones as checklists), Decision Log (seeded with the five decisions: Value-layer
  migration, dedicated `Data.OpenApi.Migration` module, version 4.0.0, deprecating helpers not
  constructors, release-prep only), Context (Strategy A, companion plans by path, aeson Compat
  layer, test harness, `.cabal` naming under EP-1/EP-2), the three-milestone Plan of Work,
  Concrete Steps, Validation and Acceptance (GHCi transcript + test transcript + metadata
  checks), Idempotence and Recovery, and Interfaces and Dependencies. Grounded in
  `OPENAPI31_MIGRATION_PLAN.md` (§1.1.2, §1.1.3, §4.3, §5.2, Phase 6, Phase 7), the master plan
  (IP-1/IP-4/IP-5, EP-7 dependencies), and the actual repository files (`Internal.hs` aeson
  imports, `Aeson/Compat.hs` helper set, `test/Spec.hs` hspec-discover, `SpecCommon.hs` `<=>`,
  the current `.cabal` and `CHANGELOG.md`). Reason: convert the skeleton into a self-contained,
  novice-executable ExecPlan as required by `.claude/skills/exec-plan/PLANS.md`.
