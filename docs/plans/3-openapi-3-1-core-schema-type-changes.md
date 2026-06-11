---
id: 3
slug: openapi-3-1-core-schema-type-changes
title: "OpenAPI 3.1 Core Schema Type Changes"
kind: exec-plan
created_at: 2026-06-11T03:47:52Z
master_plan: "docs/masterplans/1-openapi-3-1-support-and-project-modernization.md"
---

# OpenAPI 3.1 Core Schema Type Changes

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

This repository is `openapi3`, a Haskell library that decodes, encodes, and manipulates
OpenAPI specification documents. It currently models **OpenAPI 3.0**. OpenAPI **3.1** adopts
JSON Schema 2020-12, which changes the shape of the core `Schema` type in ways that are
incompatible with 3.0. This plan performs the *breaking core type changes* that every other
3.1 feature depends on. After this plan, the whole source tree compiles in its new 3.1 shape,
and four concrete, user-visible behaviors work that did not before:

First, a user can build a `Schema` whose JSON `type` is an **array** of type names — for
example `type: ["string", "null"]` for "a string that may also be null" — and encode/decode it
losslessly. In 3.0 this was impossible; `type` could only be a single string.

Second, the `exclusiveMaximum` and `exclusiveMinimum` keywords are now **numbers**, not
booleans. In 3.0, `{"maximum": 100, "exclusiveMaximum": true}` meant "strictly less than 100".
In 3.1, `{"exclusiveMaximum": 100}` carries the bound directly. A user can build and round-trip
`{"exclusiveMinimum": 0, "exclusiveMaximum": 100}`.

Third, the 3.0-only `nullable: true` keyword is **gone**. There is no `nullable` keyword in
JSON Schema 2020-12; nullability is expressed with `type: [..., "null"]`. A user can no longer
accidentally emit an invalid-for-3.1 `nullable` key, because the field no longer exists on the
type.

Fourth, the `items` keyword can now be a single schema **or a boolean** (`items: false` means
"no additional array items are allowed"), and it can **no longer** be an array of schemas
(tuple validation moves to `prefixItems`, which a later plan adds). A user can build and
round-trip `{"items": false}`.

You can see all four working by running the test suite added in this plan (Milestone 1–3) and
observing the round-trip properties pass. The single most important acceptance check is: a
`Schema` with its type field set to `OpenApiTypeArray [OpenApiString, OpenApiNull]` encodes to
exactly `{"type":["string","null"]}` and decodes back to the same value.

This is **EP-3** in the master plan `docs/masterplans/1-openapi-3-1-support-and-project-modernization.md`.
It is the hard foundation: until the `Schema` record and its derived lenses/optics compile in
the new shape, no other 3.1 work (additive JSON Schema fields, top-level objects, validation,
migration) can land. It has a *soft* dependency on EP-1 (build modernization) — the code would
compile on the old toolchain too — but you should prefer the modern Nix dev shell described in
Concrete Steps.


## Strategy (read this before touching anything)

This plan follows **Strategy A** from the migration plan `OPENAPI31_MIGRATION_PLAN.md` at the
repo root: the data types represent **3.1 only**. A 3.0 document is *not* directly decodable
after this change, because three of the changes make a 3.0 document unrepresentable on the same
type — `nullable` is removed, exclusive bounds change from `Bool` to `Scientific`, and tuple
`items` arrays are removed. Converting a 3.0 document is the job of a *separate* later plan
(EP-7) that rewrites the raw JSON `Value` *before* decoding; this plan deliberately adds **no**
migration helper and **no** deprecation pragmas on removed identifiers (you cannot deprecate a
field that no longer exists).

"Round-trip" throughout this plan means: for a value `s`, `decode (encode s) == Just s` (and the
reverse where a canonical JSON form exists). "Lossless" means the same.


## Progress

This checklist is the authoritative current state. Update it at every stopping point; split a
partially done item into a done half and a remaining half rather than leaving it ambiguous.

- [x] M1 (2026-06-10): Introduced `OpenApiTypeValue` (single | array) with hand-written `ToJSON`/`FromJSON` + `SwaggerMonoid`.
- [x] M1 (2026-06-10): Changed `_schemaType :: Maybe OpenApiType` → `Maybe OpenApiTypeValue` (Internal.hs); exported `OpenApiTypeValue(..)`/`singleType` from `Data.OpenApi`.
- [x] M1 (2026-06-10): Used explicit `OpenApiTypeSingle` at all ~50 `type_ ?~` set-sites (src + tests, via perl normalization preserving spacing) and `singleType` at read-sites; added `schemaTypes` normalizer in Validation.
- [x] M1 (2026-06-10): Updated `HasType NamedSchema` (Lens.hs) and `#type` (Optics.hs) to `Maybe OpenApiTypeValue`.
- [x] M1 (2026-06-10): Round-trip verified in repl: `{"type":["string","null"]}` encodes/round-trips; single type stays `{"type":"string"}`. Full suite green (375 examples, 0 failures).
- [x] M2 (2026-06-10): Changed `_schemaExclusiveMaximum`/`_schemaExclusiveMinimum` to `Maybe Scientific` (Internal.hs).
- [x] M2 (2026-06-10): Updated `HasExclusiveMaximum`/`HasExclusiveMinimum` (Lens.hs) and the `#exclusiveMaximum`/`#exclusiveMinimum` optics (Optics.hs) to `Maybe Scientific`.
- [x] M2 (2026-06-10): Natural `ToParamSchema` drops the `exclusiveMinimum ?~ False` (>= 0 is just `minimum: 0`); `validateNumber` rewritten so exclusive bounds are independent numeric keywords and maximum/minimum are non-strict (migration plan §1.1.2). `Maybe Scientific` is covered by `AesonDefaultValue (Maybe a)`, no new instance.
- [x] M2 (2026-06-10): Verified `{"exclusiveMinimum":0,"exclusiveMaximum":100}` round-trips; full suite green (375 examples, 0 failures).
- [x] M3 (2026-06-10): Removed `_schemaNullable` from `Schema`; grep confirms no `nullable`/`HasNullable` references remain.
- [x] M3 (2026-06-10): Simplified `OpenApiItems` to `OpenApiItemsObject | OpenApiItemsBoolean`.
- [x] M3 (2026-06-10): Rewrote `ToJSON OpenApiItems` (boolean emits `object ["items" .= b]`), removed the `FromJSON Schema` nullary cleanup, rewrote `FromJSON OpenApiItems` (Bool|Object). The `saoSubObject ?~ "items"` splice needed **no** change — it lifts the single `"items"` key from the wrapper object for both cases (verified empirically).
- [x] M3 (2026-06-10): Fixed all `OpenApiItemsArray` sites (tuple machinery, Generator, Validation, Lens `_OpenApiItemsBoolean`, Optics). Tuple derivation collapses to an `anyOf` `items` element (see Surprises/Decision Log) with `minItems`/`maxItems` = N; ISPair golden updated.
- [x] M3 (2026-06-10): `{"items":false}`/`{"items":true}` and homogeneous-array round-trips verified; full suite green (375 examples, 0 failures, 5 pending tuple-generator cases deferred to EP-4).
- [x] M4 (2026-06-10): Version bounds `lowerOpenApiSpecVersion = [3,1,0]`, `upperOpenApiSpecVersion = [3,1,1]`; also bumped the `Monoid`/`AesonDefaultValue` defaults to `[3,1,0]` (else `mempty :: OpenApi` would fall outside the new range and fail to round-trip). Added `OpenApiMajorVersion`/`detectVersion`, exported from `Data.OpenApi`. Updated version test fixtures (3.0.0/3.0.3 → 3.1.0; out-of-range error message) and stale `"openapi": "3.0.0"` Haddock examples. Added `test/Data/OpenApi/Schema/CoreTypes31Spec.hs` (registered in the cabal test-suite).
- [x] M4 (2026-06-10): `cabal build all` (incl. the `example` exe) and `cabal test all` are green across the whole tree (383 examples, 0 failures, 5 pending).


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence (test output is ideal).

- Discovery (planning, 2026-06-10): There are **two** `saoSubObject` settings for `Schema`, not
  one. `instance ToJSON Schema` (`src/Data/OpenApi/Internal.hs:1336-1338`) overrides the options
  with `saoSubObject ?~ "items"`, but `instance HasSwaggerAesonOptions Schema`
  (`Internal.hs:1627-1628`), which drives **decoding** via `sopSwaggerGenericParseJSON`, uses
  `saoSubObject ?~ "paramSchema"`. The migration plan's §4.0 only mentions `"items"`. Both must
  be understood when reworking the boolean-`items` case (see Plan of Work, Milestone 3).

- Discovery (planning, 2026-06-10): The compile-error surface from changing `_schemaType` is far
  larger than the type declaration. The `type_` lens is used at ~45 call sites across
  `src/Data/OpenApi/Internal/Schema.hs` (27 uses), `src/Data/OpenApi/Internal/ParamSchema.hs`
  (16), `src/Data/OpenApi/Internal/Schema/Validation.hs` (2 plus pattern matches), and
  `src/Data/OpenApi/Schema/Generator.hs` (2). Almost all do `type_ ?~ OpenApiString` (set a
  single `OpenApiType`) or match `sch ^. type_ == Just OpenApiString`. Changing the field type
  naively would break every one. The plan keeps these terse via a smart accessor (see "The
  `type_` ergonomics problem").

- Discovery (planning, 2026-06-10): Generic `ToSchema` derivation of **non-record product types**
  (tuples) emits `OpenApiItemsArray`. `nullarySchema`, `appendItem`, and the
  `OpenApiItemsArray [_]` guard in `src/Data/OpenApi/Internal/Schema.hs` (lines ~910, 941, 973)
  implement tuple validation, and the test type `ISPair` (`test/Data/OpenApi/CommonTestTypes.hs:469`)
  asserts the `"items":[...]` form. Removing `OpenApiItemsArray` breaks tuple derivation, not just
  parsing. This plan resolves it conservatively (see Milestone 3, "Tuple derivation under Strategy A").

- Discovery (M3 implementation, 2026-06-10): **tuple collapse must use `anyOf`, not `oneOf`.**
  The Decision Log planned a `oneOf` element schema for collapsed tuples, but `oneOf` means
  *exactly one* branch matches. Member types overlap — an integer like `0` matches both the
  `Integer` and `Number` (`OpenApiNumber`) branches — so `ValidationSpec`'s
  `prop_validate (0,"",0.0)` failed with "matches more than one of 'oneOf' schemas". Switched
  the collapse to `anyOf` ("each element is one of these types"), which both validates correctly
  and is the semantically right reading of a homogenised heterogeneous tuple. The `ISPair`
  golden uses `anyOf` accordingly. (Note: the current validator does not actively check `anyOf`,
  so an `anyOf`-only element schema is permissive — acceptable under EP-3; EP-4/EP-6 refine it.)

- Discovery (M3 implementation, 2026-06-10): **`Control.Lens.anyOf` clashes with the schema
  `anyOf` lens.** Unlike `oneOf`, `Control.Lens` exports a fold named `anyOf`. The file already
  did `import Control.Lens hiding (allOf)` for the same reason; extended it to
  `hiding (allOf, anyOf)`.

- Discovery (M3 implementation, 2026-06-10): **positional-tuple generator round-trips can't hold
  under EP-3.** `validateFromJSON` (GeneratorSpec) generates a value *from* a schema and parses
  it back into the type. Once a tuple's positional info collapses to a homogeneous `anyOf`
  `items` element, the generator can't know position 1 must be a `String`, so it may emit a
  position-wrong value that fails to parse. Five such props — `(IntMap String)`, `(Int,String)`,
  `(Int,String,Double)`, `(Int,String,Double,[Int])`, `(Int,String,Double,[Int],Int)` — were
  marked `xprop` (pending) with `TODO(EP-4)`; they will be restored once `prefixItems` exists.
  The `saoSubObject ?~ "items"` "key insight" from M3 step 4 held: no `AesonUtils` change needed.

(Add further entries here as implementation proceeds.)


## Decision Log

- Decision: Follow Strategy A — 3.1-only data types, breaking changes; no 3.0 round-tripping on
  the live types and no migration helper in this plan.
  Rationale: Carried from `OPENAPI31_MIGRATION_PLAN.md` and the master plan's Decision Log.
  Three 3.1 changes make 3.0 documents unrepresentable on the same types. Migration belongs at
  the raw-`Value` layer in EP-7.
  Date: 2026-06-10

- Decision: Serialize the boolean `items` case by **bypassing** `saoSubObject` — emit a literal
  `"items": true|false` pair from the hand-written `ToJSON OpenApiItems`, and special-case the
  `Schema` encoder so the `items` sub-object splice only applies when `items` is an object.
  Rationale: `saoSubObject ?~ "items"` splices the *keys* of an object value up into the parent
  `Schema` object. A boolean is not an object and has no keys to splice; the existing splice code
  in `src/Data/OpenApi/Internal/AesonUtils.hs` (`sopSwaggerGenericToJSON''`, the
  `Just name' == sub` branch, lines 150-153) explicitly `error`s on a non-object, non-null value.
  Emitting a plain key is the minimal, local change and keeps the generic machinery untouched for
  every other field. EP-4 will build the `$`-key helper on the same surface (Integration Point
  IP-3), so we keep the change small and well-documented.
  Date: 2026-06-10

- Decision: Keep `OpenApiType` and its `OpenApiNull` constructor intact; introduce
  `OpenApiTypeValue` as a wrapper (single | array) rather than re-modeling the type universe.
  Rationale: Integration Point IP-4 requires `OpenApiNull` to survive so that EP-7's
  `migrate30NullableValue` can produce `type: ["string","null"]` decoding to
  `OpenApiTypeArray [OpenApiString, OpenApiNull]`. Wrapping is minimal and preserves the existing
  `ToJSON`/`FromJSON OpenApiType` (which already serialize `OpenApiNull` ↔ `"null"`).
  Date: 2026-06-10

- Decision: Version bounds become `lowerOpenApiSpecVersion = [3,1,0]` and
  `upperOpenApiSpecVersion = [3,1,1]`. Add `data OpenApiMajorVersion = OpenApi30 | OpenApi31` and
  `detectVersion`.
  Rationale: From the migration plan §3.1/§3.2. `detectVersion` is for *routing* a read document
  to the right decoder (used by EP-7), **not** for storing two representations on one type.
  Date: 2026-06-10

- Decision: Tuple `ToSchema` derivation under Strategy A produces a single-schema `items` whose
  element schema is the `oneOf` of the tuple member schemas, and the `ISPair` test is updated to
  match the new 3.1 form (see Milestone 3). `prefixItems` (the correct 3.1 representation of a
  tuple) does not exist until EP-4; rather than block EP-3 on EP-4, we choose the conservative
  in-tree behavior and leave a `TODO(EP-4)` to switch tuple derivation to `prefixItems`.
  Rationale: EP-3 must compile and pass tests on its own. A tuple cannot keep emitting an `items`
  array (removed), and `prefixItems` is not yet available. Collapsing to a homogeneous `items`
  with a `oneOf` element keeps derivation total and round-trippable now; EP-4 upgrades it.
  Date: 2026-06-10

(Append new decisions here as they are made during implementation.)


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion. Compare the
result against the original purpose.

**Completed 2026-06-10.** All four headline 3.1 behaviors from the Purpose work, and the whole
tree compiles and tests in its new 3.1 shape:

- Type arrays: `{"type":["string","null"]}` decodes/round-trips; a single type still emits a
  bare string. (`OpenApiTypeValue`, IP-4 `OpenApiNull` preserved.)
- Numeric exclusive bounds: `{"exclusiveMinimum":0,"exclusiveMaximum":100}` round-trips;
  `validateNumber` treats them as independent strict keywords.
- `nullable` removed entirely (no field to emit it).
- `items` is object-or-boolean: `{"items":false}`/`{"items":true}` round-trip; tuple `items`
  arrays are gone.
- Version bounds are 3.1.0–3.1.1; `detectVersion`/`OpenApiMajorVersion` added for EP-7's router.

`cabal build all` + `cabal test all` green: 383 examples, 0 failures, 5 pending.

**Gaps / deferred to EP-4 (all marked `TODO(EP-4)`):**
- Tuple `ToSchema` derivation collapses to an `anyOf` `items` element (homogenised) instead of
  the proper positional `prefixItems`. Five positional-tuple generator round-trip props are
  `xprop` (pending) because the generator can't reconstruct positions from a homogenised schema.
  EP-4 must restore tuple derivation via `prefixItems` and un-pend these (this tightens the
  EP-3→EP-4 hard dependency — see the MasterPlan Surprises).
- The `oneOf`→`anyOf` correction (overlapping member types) is documented in Surprises; the
  validator does not yet actively check `anyOf` (permissive), which EP-6 can refine.

**Deviation from the written plan:** the plan only listed the version *bounds*; I also had to
bump the `Monoid`/`AesonDefaultValue` default version to 3.1.0 so `mempty :: OpenApi`
round-trips. The `saoSubObject` "key insight" held — no `AesonUtils.hs` change was needed.
Field order: `_schemaNullable` was removed but all other `Schema` fields kept their order, so
EP-4's appends stay clean (IP-2).


## Context and Orientation

You are working in a Haskell library. Assume no prior knowledge of it. The relevant files, by
full path, are:

`src/Data/OpenApi/Internal.hs` is the single big module that defines every data type
(`Schema`, `OpenApiType`, `OpenApiItems`, `OpenApi`, etc.), the JSON `ToJSON`/`FromJSON`
instances, the `Semigroup`/`Monoid` instances, and the version constants. It is ~1900 lines.
The anchors you care about:

- Version constants: `lowerOpenApiSpecVersion` and `upperOpenApiSpecVersion` at
  `Internal.hs:96-101` (currently `[3,0,0]` and `[3,0,3]`).
- `data OpenApiItems` at `Internal.hs:586-589` (currently `OpenApiItemsObject | OpenApiItemsArray`).
- `data OpenApiType` at `Internal.hs:591-599` (the seven JSON Schema primitive types, including
  `OpenApiNull` at line 597 — keep it).
- `data Schema` at `Internal.hs:619-665`. Fields of interest: `_schemaNullable :: Maybe Bool`
  (line 624, to be removed), `_schemaType :: Maybe OpenApiType` (line 650, to change),
  `_schemaItems :: Maybe OpenApiItems` (line 652), `_schemaExclusiveMaximum :: Maybe Bool`
  (line 654, to change), `_schemaExclusiveMinimum :: Maybe Bool` (line 656, to change). Note
  `_schemaMaximum`/`_schemaMinimum` are already `Maybe Scientific` (lines 653, 655) and **stay**.
- `deriveGeneric ''Schema` at `Internal.hs:986` (Template Haskell that builds the generics-sop
  representation the JSON machinery uses; you do not edit this line, but adding/removing fields
  changes what it generates).
- `instance Semigroup Schema` / `instance Monoid Schema` at `Internal.hs:1034-1038`. These are
  `genericMappend`/`genericMempty` — derived structurally over the record, so they automatically
  follow field changes **as long as** every field type has the monoidal/`SwaggerMonoid`
  plumbing it needs (see "The Monoid concern" below).
- `instance SwaggerMonoid OpenApiType` at `Internal.hs:1146-1148`.
- `instance ToJSON OpenApiType` (`Internal.hs:1170-1171`) and `instance FromJSON OpenApiType`
  (`Internal.hs:1225-1226`): both use `genericToJSON/genericParseJSON (jsonPrefix "Swagger")`,
  which maps `OpenApiString` ↔ `"string"`, `OpenApiNull` ↔ `"null"`, etc. **Keep these.**
- `instance ToJSON Schema` at `Internal.hs:1336-1338` (uses
  `mkSwaggerAesonOptions "schema" & saoSubObject ?~ "items"`).
- `instance ToJSON OpenApiItems` at `Internal.hs:1354-1361` (the `OpenApiItemsArray []` nullary
  special case and the array branch).
- `instance FromJSON Schema` at `Internal.hs:1498-1506` (the `nullaryCleanup` post-processing
  that references `OpenApiItemsArray []`).
- `instance FromJSON OpenApiItems` at `Internal.hs:1511-1516` (the `null obj -> OpenApiItemsArray []`
  and `Array _ -> OpenApiItemsArray` branches).
- `instance HasSwaggerAesonOptions Schema` at `Internal.hs:1627-1628` (drives decoding; uses
  `saoSubObject ?~ "paramSchema"`).
- `instance AesonDefaultValue OpenApiType` at `Internal.hs:1653`.

`src/Data/OpenApi/Internal/AesonUtils.hs` is the custom JSON layer. Key terms, in plain English:

- `mkSwaggerAesonOptions "schema"` builds options that strip the `_schema` field-name prefix and
  lower-case the first letter, so `_schemaPrefixItems` becomes the JSON key `"prefixItems"`.
- `saoSubObject ?~ "items"` (a lens setter) marks the JSON key `"items"` as a *sub-object splice*:
  when encoding, the value at that field is expected to be a JSON **object**, and its keys are
  lifted ("spliced") up into the parent object instead of nesting under `"items"`. The encoder
  code that does this is `sopSwaggerGenericToJSON''` (lines 145-167); the `Just name' == sub`
  branch at lines 150-153 handles it and **errors if the value is not an object or null**. The
  decoder counterpart is `sopSwaggerGenericParseJSON''` (lines 218-237), whose `Just name' == sub`
  branch (lines 223-225) parses the *whole outer object* into that field.
- `class AesonDefaultValue a` (lines 66-75) supplies a per-type "default" used to omit fields on
  encode and to default missing fields on decode. `Maybe a` defaults to `Just Nothing` (line 71),
  which is why optional fields just work. **Scientific has no instance and does not need one**: the
  `Schema` exclusive-bound fields are `Maybe Scientific`, and `Maybe a`'s instance covers them.

`src/Data/OpenApi/Lens.hs` generates lenses with `makeFields` (the `_schemaFoo` field gives a
`HasFoo` class and a `foo` lens). After the record changes, the relevant hand-written overlapping
instances are: `HasType NamedSchema (Maybe OpenApiType)` at line 92, `HasExclusiveMaximum s (Maybe Bool)`
at lines 114-116, `HasExclusiveMinimum s (Maybe Bool)` at lines 122-124, and the
`_OpenApiItemsArray`/`_OpenApiItemsObject` reviews at lines 57-75. The `nullable` lens is
generated by `makeFields ''Schema` and disappears automatically when the field is removed (no
hand-written `HasNullable` instance exists — confirm with grep).

`src/Data/OpenApi/Optics.hs` mirrors Lens.hs but for the `optics` library (`LabelOptic`
instances and `#field` labels). The relevant anchors: the `OpenApiItems` prisms at lines 145-168
(`_OpenApiItemsArray`, `_OpenApiItemsObject`), the `#type` optic for `NamedSchema` at lines ~196,
the `#exclusiveMaximum`/`#exclusiveMinimum` optics typed `Maybe Bool` (search for them), and the
`#items` optic at lines ~222.

`src/Data/OpenApi/Internal/Schema.hs` contains the generic `ToSchema` derivation. It uses the
`type_` and `items` lenses heavily (`type_ ?~ OpenApiArray`, `items ?~ OpenApiItemsObject ...`,
and the tuple machinery `nullarySchema`/`appendItem` at lines ~908-989).

`src/Data/OpenApi/Internal/ParamSchema.hs` contains `ToParamSchema` instances, also using
`type_ ?~ ...` widely and one `exclusiveMinimum ?~ False` at line 124 (which must change).

`src/Data/OpenApi/Internal/Schema/Validation.hs` validates JSON values against schemas. It reads
`sch ^. exclusiveMaximum`/`exclusiveMinimum` as booleans at lines 308-309, pattern-matches
`sch ^. type_` against `OpenApiType` constructors at lines 486-516, and matches
`OpenApiItemsArray` at line 352.

`src/Data/OpenApi/Schema/Generator.hs` generates example JSON `Value`s from a `Schema`. It reads
`schema ^. type_` and matches `OpenApiItemsArray` at line 68.

`test/Data/OpenApi/SchemaSpec.hs`, `test/Data/OpenApi/CommonTestTypes.hs`, and
`test/SpecCommon.hs` are the tests. `CommonTestTypes.hs` defines `ISPair` (a tuple,
line 469) whose expected JSON `ispairSchemaJSON` uses the `"items":[...]` tuple form (line 475);
`SchemaSpec.hs:70` asserts it. `SpecCommon.hs` provides round-trip helpers (`isSubJSON` and a
`(<=>)` JSON-equality combinator). These must be updated.

The build uses Nix. `flake.nix` and `nix/haskell.nix` pin GHC 9.12.4 (`ghc9124`) and build the
package via `callCabal2nix`. The dev shell gives you `cabal`.


## Plan of Work

The work is four milestones, each independently buildable and testable. Do them in order: M2 and
M3 assume M1's `OpenApiTypeValue` exists, and M4's green build assumes M1–M3 are complete. Commit
after each milestone.

Before any milestone, re-read the three sub-problems below; they cut across milestones.


### The `type_` ergonomics problem (cross-cutting, set up in M1)

Changing `_schemaType` from `Maybe OpenApiType` to `Maybe OpenApiTypeValue` would break ~45 call
sites that do `type_ ?~ OpenApiString` (set a single type) or `sch ^. type_ == Just OpenApiString`
(test a single type). Rewriting all of them to `type_ ?~ OpenApiTypeSingle OpenApiString` and
`sch ^. type_ == Just (OpenApiTypeSingle OpenApiString)` is noisy and error-prone.

Resolve this by adding a small, total helper layer in `src/Data/OpenApi/Internal.hs` next to the
`OpenApiTypeValue` definition, and using it at the call sites:

```haskell
-- | A single-type value: the common case. @toSingleType OpenApiString@ is
--   @OpenApiTypeSingle OpenApiString@.
pattern OpenApiTypeS :: OpenApiType -> OpenApiTypeValue
pattern OpenApiTypeS t = OpenApiTypeSingle t

-- | Extract a single type if the value is a single type (not an array).
singleType :: OpenApiTypeValue -> Maybe OpenApiType
singleType (OpenApiTypeSingle t) = Just t
singleType (OpenApiTypeArray _)  = Nothing
```

The most economical approach, chosen here, is a **bidirectional pattern synonym**:

```haskell
{-# LANGUAGE PatternSynonyms #-}
-- ...
pattern OpenApiTypeSingle' :: OpenApiType -> OpenApiTypeValue   -- illustrative; see below
```

Concretely: keep the data constructors `OpenApiTypeSingle`/`OpenApiTypeArray` as the canonical
representation, and rewrite the source call sites mechanically. For *setting*, replace
`type_ ?~ OpenApiString` with `type_ ?~ OpenApiTypeSingle OpenApiString` (a simple, total textual
change — there are ~43 of these and they are all `type_ ?~ <Constructor>`). For *reading* in
validation, replace the `case sch ^. type_ of Just OpenApiString -> ...` blocks with a normalized
view: introduce in `Validation.hs`

```haskell
-- | The list of primitive types a schema's @type@ permits (single → singleton,
--   array → the list, absent → empty so callers fall back to value-shape defaults).
schemaTypes :: Schema -> [OpenApiType]
schemaTypes sch = case sch ^. type_ of
  Nothing                       -> []
  Just (OpenApiTypeSingle t)    -> [t]
  Just (OpenApiTypeArray ts)    -> ts
```

and rewrite `validateSchemaType`/`validateParamSchemaType` to "the value matches if it matches
**any** permitted type, or if no type is given fall back to the value's natural shape". This both
fixes the compile error *and* implements the 3.1 semantics that a type array matches if the value
matches any member — a behavior EP-6 will extend, but which we must not break here.

Decision recorded: we use **explicit `OpenApiTypeSingle`** at the ~43 set-sites (mechanical) and a
`schemaTypes` normalizer at the read-sites, rather than a pattern synonym, because a bidirectional
pattern synonym over a two-constructor type is more obscure than the explicit constructor and the
set-sites are trivially find-and-replace. (If during implementation the noise proves excessive,
adding the `pattern OpenApiTypeS` synonym above is a safe, additive fallback — record it in the
Decision Log if you do.)


### The Monoid concern (cross-cutting)

`instance Monoid Schema` is `genericMempty`/`genericMappend` (`Internal.hs:1034-1038`), which
fold structurally over each field. For a `Maybe a` field, the generic combinator uses
`SwaggerMonoid`-style "last-wins under Maybe" semantics already in place. Changing
`_schemaExclusiveMaximum`/`Minimum` from `Maybe Bool` to `Maybe Scientific` is transparent: both
are `Maybe`-wrapped and need no `SwaggerMonoid` instance for the inner type. Changing
`_schemaType` to `Maybe OpenApiTypeValue` requires that `OpenApiTypeValue` participate where
`OpenApiType` did. The existing `instance SwaggerMonoid OpenApiType` (`Internal.hs:1146-1148`,
"last wins") is referenced only through the `Maybe` wrapper. Confirm during M1 whether the
generic `Schema` monoid needs a `SwaggerMonoid OpenApiTypeValue` instance; if the build complains
about a missing instance, add the analogous "last wins":

```haskell
instance SwaggerMonoid OpenApiTypeValue where
  swaggerMempty = OpenApiTypeSingle OpenApiString
  swaggerMappend _ y = y
```

Removing `_schemaNullable` simply drops a field from the generic fold — no monoid change needed.
Replacing `OpenApiItems`' array constructor with a boolean does not change `OpenApiItems`'
participation in the `Schema` monoid (the field is `Maybe OpenApiItems`, last-wins under `Maybe`).


### Milestone 1 — Type arrays (`OpenApiTypeValue`)

Scope: introduce `OpenApiTypeValue`, change `_schemaType`, hand-write its JSON instances, update
the `type_` lens/optic, mechanically fix the ~43 `type_ ?~ <Constructor>` set-sites and the
validation read-sites, and add the key round-trip test.

What exists after M1: the tree compiles; `_schemaType :: Maybe OpenApiTypeValue`; a `Schema` with
`_schemaType = Just (OpenApiTypeArray [OpenApiString, OpenApiNull])` encodes to
`{"type":["string","null"]}` and decodes back identically; a single type still encodes as a bare
string (`{"type":"string"}`), preserving 3.0-style output for the common case.

Edits:

1. In `src/Data/OpenApi/Internal.hs`, just **above** `data OpenApiType` (line 591), add:

   ```haskell
   -- | The value of a schema's @type@ keyword. In OpenAPI 3.1 / JSON Schema 2020-12,
   --   @type@ may be a single type (@"string"@) or an array of types (@["string","null"]@).
   data OpenApiTypeValue
     = OpenApiTypeSingle OpenApiType
     | OpenApiTypeArray [OpenApiType]
     deriving (Eq, Show, Generic, Data, Typeable)
   ```

2. Change `_schemaType :: Maybe OpenApiType` (line 650) to `_schemaType :: Maybe OpenApiTypeValue`.

3. Add hand-written JSON instances near the other `Schema`-related instances (place them right
   after `instance FromJSON OpenApiType` ends, around `Internal.hs:1227`):

   ```haskell
   instance ToJSON OpenApiTypeValue where
     toJSON (OpenApiTypeSingle t) = toJSON t      -- reuses ToJSON OpenApiType → a JSON string
     toJSON (OpenApiTypeArray ts) = toJSON ts      -- a JSON array of strings

   instance FromJSON OpenApiTypeValue where
     parseJSON v@(String _) = OpenApiTypeSingle <$> parseJSON v
     parseJSON v@(Array _)  = OpenApiTypeArray  <$> parseJSON v
     parseJSON _ = fail "type must be a string or an array of strings"
   ```

   These reuse the existing `ToJSON/FromJSON OpenApiType` (which already map constructors ↔
   `"string"`/`"null"`/etc.), so `OpenApiNull` round-trips inside an array automatically (IP-4).

4. If the build reports `Schema` needs `SwaggerMonoid OpenApiTypeValue`, add the "last wins"
   instance shown in "The Monoid concern" above.

5. In `src/Data/OpenApi/Lens.hs`, change the hand-written `HasType NamedSchema (Maybe OpenApiType)`
   instance (line 92) to `HasType NamedSchema (Maybe OpenApiTypeValue)`:

   ```haskell
   instance HasType NamedSchema (Maybe OpenApiTypeValue) where type_ = schema.type_
   ```

   The `makeFields ''Schema` call (earlier in the file) regenerates the `type_` lens on `Schema`
   itself with the new field type automatically.

6. In `src/Data/OpenApi/Optics.hs`, change the `#type` `LabelOptic` for `NamedSchema` (the block
   with `a ~ Maybe OpenApiType`, near line 196) to `a ~ Maybe OpenApiTypeValue`,
   `b ~ Maybe OpenApiTypeValue`.

7. Mechanically rewrite every `type_ ?~ <Constructor>` set-site across
   `src/Data/OpenApi/Internal/Schema.hs`, `src/Data/OpenApi/Internal/ParamSchema.hs`,
   `src/Data/OpenApi/Schema/Generator.hs`, and any in `src/Data/OpenApi.hs`, to
   `type_ ?~ OpenApiTypeSingle <Constructor>`. There are ~43. A guided search:
   `grep -rn "type_ ?~ OpenApi" src/`. Also the Generator's
   `schema & type_ ?~ inferredType` (Generator.hs:39) becomes
   `schema & type_ ?~ OpenApiTypeSingle inferredType`.

8. In `src/Data/OpenApi/Internal/Schema/Validation.hs`, add `schemaTypes` (see "The `type_`
   ergonomics problem") and rewrite the two `case sch ^. type_ of` blocks (`validateSchemaType`
   at lines ~486-501 and `validateParamSchemaType` at ~505-516) and `showType` (lines 518+) to use
   it. The semantics: if `schemaTypes sch` is non-empty, the value is valid if it matches **any**
   listed type; if empty, fall back to the existing "by value shape" defaults. Also fix any
   `sch ^. type_ == Just OpenApiObject`-style equality reads (e.g. `Internal/Schema.hs:1059`) to
   compare against `Just (OpenApiTypeSingle OpenApiObject)` or use `singleType`.

9. Add the round-trip test (see Validation and Acceptance for the exact code) asserting both the
   array form `{"type":["string","null"]}` and the single form `{"type":"string"}`.

Commands and acceptance: `nix develop -c cabal build all` succeeds; the new M1 test passes; the
existing schema tests still pass except any that will be touched in M3. Acceptance is the array
round-trip plus the single-type-still-a-bare-string behavior.


### Milestone 2 — Numeric exclusive bounds

Scope: change `_schemaExclusiveMaximum`/`_schemaExclusiveMinimum` to `Maybe Scientific`, fix the
lens/optic types, fix the two boolean usages, confirm round-trip.

What exists after M2: `{"exclusiveMinimum": 0, "exclusiveMaximum": 100}` round-trips; the fields
serialize as plain numbers via the generic machinery (the `Maybe Scientific` flows through exactly
like `_schemaMaximum`, which is already `Maybe Scientific`).

Edits:

1. In `src/Data/OpenApi/Internal.hs`, change lines 654 and 656 to
   `_schemaExclusiveMaximum :: Maybe Scientific` and `_schemaExclusiveMinimum :: Maybe Scientific`.

2. In `src/Data/OpenApi/Lens.hs`, change `HasExclusiveMaximum s (Maybe Bool)` (line 115) and
   `HasExclusiveMinimum s (Maybe Bool)` (line 123) to `(Maybe Scientific)`.

3. In `src/Data/OpenApi/Optics.hs`, change the `#exclusiveMaximum` and `#exclusiveMinimum`
   `LabelOptic` blocks (`a ~ Maybe Bool`) to `a ~ Maybe Scientific`, `b ~ Maybe Scientific`.

4. In `src/Data/OpenApi/Internal/ParamSchema.hs`, line 124 currently does
   `& exclusiveMinimum ?~ False`. In 3.1 a *numeric* `exclusiveMinimum` carries the bound. The
   surrounding instance is for a "non-negative integer"-style param (around lines 118-125): the
   3.0 form was `minimum: 0, exclusiveMinimum: True` meaning "> 0". Rewrite to the 3.1 numeric
   form `& exclusiveMinimum ?~ 0` and drop the now-redundant `& minimum_ ?~ ...` if present (read
   the exact lines first; preserve the intended bound). Record the exact before/after in the
   Decision Log.

5. In `src/Data/OpenApi/Internal/Schema/Validation.hs`, the `validateNumber` function (lines
   307-317) reads `Just True == sch ^. exclusiveMaximum`/`Minimum` (booleans). Under 3.1, the
   numeric `exclusiveMaximum`/`Minimum` are **independent** keywords from `maximum`/`minimum`.
   Rewrite to: a separate `check exclusiveMaximum $ \m -> when (n >= m) (invalid ...)` and likewise
   for minimum, *in addition to* the existing `maximum`/`minimum` checks (which stay non-strict
   `>`/`<`). This implements the migration plan §1.1.2 coexistence rule. Also fix
   `inferParamSchemaTypes` (lines 456-462): it uses `has (exclusiveMaximum._Just)` which is type
   agnostic and continues to work — confirm it still typechecks (it should).

6. Confirm `AesonDefaultValue`: `Maybe Scientific` is covered by the `instance AesonDefaultValue
   (Maybe a)` (AesonUtils.hs:71). No new instance is needed. There is no `AesonDefaultValue Bool`
   that was being relied on — the fields were always `Maybe`-wrapped.

Commands and acceptance: `nix develop -c cabal build all` succeeds; M2 round-trip test passes
(`{"exclusiveMinimum":0,"exclusiveMaximum":100}` decodes to a `Schema` with those `Scientific`
fields and re-encodes identically). Existing `ParamSchemaSpec` tests that asserted boolean
exclusive bounds must be updated to the numeric form — read `test/Data/OpenApi/ParamSchemaSpec.hs`
and `test/Data/OpenApi/CommonTestTypes.hs` and adjust expected JSON. (Planning grep found no
literal `exclusiveMinimum` in tests, so the affected assertions are whatever the
`Natural`/non-negative-integer param schema emits — locate via the failing test output.)


### Milestone 3 — Remove `nullable`, simplify `OpenApiItems`, rework `saoSubObject`

Scope: the largest milestone. Remove `_schemaNullable`; change `OpenApiItems` to
object-or-boolean; rewrite the four serialization touch-points; fix the tuple derivation
machinery and the `ISPair` test; add the `{"items":false}` and homogeneous-array round-trip tests.

What exists after M3: no `nullable` field anywhere; `OpenApiItems` is `OpenApiItemsObject |
OpenApiItemsBoolean`; `{"items":false}` and `{"items":true}` round-trip; a homogeneous array
schema `{"type":"array","items":{"type":"string"}}` round-trips; tuple `ToSchema` derivation
produces a valid 3.1 schema and the `ISPair` test asserts the new form.

Edits:

1. **Remove the field.** In `src/Data/OpenApi/Internal.hs`, delete `_schemaNullable :: Maybe Bool`
   (line 624). No deprecation pragma (the field is gone). `makeFields ''Schema` will stop
   generating the `nullable` lens automatically; confirm with
   `grep -rn "nullable\|Nullable" src/ test/` that nothing references it. (Planning grep showed it
   appears only in the field decl and the generated lens — no hand-written `HasNullable` instance.)

2. **Simplify `OpenApiItems`.** Replace lines 586-589 with:

   ```haskell
   -- | The @items@ keyword. In OpenAPI 3.1 / JSON Schema 2020-12, @items@ is a single
   --   schema or a boolean. (Tuple validation moved to @prefixItems@, added in a later plan;
   --   TODO(EP-4): re-introduce tuple support via @prefixItems@.)
   data OpenApiItems where
     OpenApiItemsObject  :: Referenced Schema -> OpenApiItems
     OpenApiItemsBoolean :: Bool              -> OpenApiItems   -- items: true | false
     deriving (Eq, Show, Typeable, Data)
   ```

   Update the comment block at lines 580-585 (which describes `OpenApiItemsArray` for tuples) to
   describe the new shape.

3. **Rework `ToJSON OpenApiItems`** (lines 1354-1361). Replace with:

   ```haskell
   instance ToJSON OpenApiItems where
     toJSON (OpenApiItemsObject x) = object [ "items" .= x ]
     toJSON (OpenApiItemsBoolean b) = object [ "items" .= b ]
   ```

   Delete the `OpenApiItemsArray []` nullary special case and its doctest comment (lines 1344-1361
   header). The boolean case emits a literal `"items": true|false` pair.

4. **Rework the `saoSubObject` splice for the boolean case.** This is the IP-3 surface. The
   `instance ToJSON Schema` (lines 1336-1338) currently splices the `items` sub-object up into the
   parent. With a boolean `items`, splicing must be bypassed. Two concrete sub-edits:

   - In `src/Data/OpenApi/Internal/AesonUtils.hs`, the splice branch in `sopSwaggerGenericToJSON''`
     (lines 150-153) does `case json of Object m -> splice; Null -> drop; _ -> error`. Extend it so
     that for the `items` sub-object, a non-object value (the boolean's `{"items": Bool b}` object
     produced by `ToJSON OpenApiItems`) is **not** spliced but re-emitted as the plain field. The
     minimal robust fix: change `ToJSON OpenApiItems` for the boolean case to still produce an
     **object** `{"items": Bool b}` (as written in step 3), and in the splice branch, when the
     spliced object contains exactly the key `"items"` whose value is a `Bool`, keep it as a normal
     pair. Because `ToJSON OpenApiItems` always wraps in an `object [ "items" .= ... ]`, the
     spliced-up keys are *already* `{"items": <value>}` — i.e. the splice lifts the single key
     `"items"` up, which is exactly what we want for **both** the object and boolean cases. **Key
     insight (verify during implementation):** the existing splice already lifts the `"items"` key
     from the wrapper object, so emitting `object ["items" .= b]` for the boolean case may *just
     work* without touching AesonUtils — the splice sees an `Object` (`{"items": false}`), lifts
     its keys, and the parent gets `"items": false`. Confirm by encoding `{"items":false}` and
     checking the output. If it works, **no AesonUtils change is needed**; if the splice mangles
     it, fall back to: drop `saoSubObject ?~ "items"` from `ToJSON Schema` and instead emit `items`
     as a normal field (remove the splice entirely, accept that the wrapper object nests — but then
     adjust so the JSON key is right). Record which path was taken in the Decision Log with the
     observed encoder output.

     Note the asymmetry surfaced in Surprises: `ToJSON Schema` uses `saoSubObject ?~ "items"` but
     `HasSwaggerAesonOptions Schema` (decoding) uses `saoSubObject ?~ "paramSchema"`. The decode
     path does **not** splice `items`; instead `FromJSON OpenApiItems` (step 6) parses the `items`
     key directly. So the decode side needs no `saoSubObject` change — only `FromJSON OpenApiItems`
     changes.

5. **Rewrite the `FromJSON Schema` nullary cleanup** (lines 1498-1506). It currently special-cases
   `_schemaItems s == Just (OpenApiItemsArray [])`. Since `OpenApiItemsArray` is gone, remove the
   whole `nullaryCleanup`:

   ```haskell
   instance FromJSON Schema where
     parseJSON = sopSwaggerGenericParseJSON
   ```

   (The nullary-tuple workaround existed only for the removed array case.)

6. **Rewrite `FromJSON OpenApiItems`** (lines 1511-1516):

   ```haskell
   instance FromJSON OpenApiItems where
     parseJSON (Bool b) = pure (OpenApiItemsBoolean b)
     parseJSON js@(Object _) = OpenApiItemsObject <$> parseJSON js
     parseJSON _ = fail "items must be a schema object or a boolean"
   ```

   Note: how `OpenApiItems` is reached during `Schema` decoding — `_schemaItems :: Maybe OpenApiItems`
   is a normal field (not spliced on decode, per the asymmetry above), so the parser receives the
   raw `items` JSON value (an object or a bool) directly. Verify by decoding `{"items":false}`.
   The old `null obj -> OpenApiItemsArray []` "nullary schema" branch is deleted (it existed for
   the tuple workaround).

7. **Fix tuple `ToSchema` derivation** in `src/Data/OpenApi/Internal/Schema.hs`. The functions
   `nullarySchema` (line ~908: `items ?~ OpenApiItemsArray []`), `appendItem` (lines 973-975), the
   `OpenApiItemsArray [_]` guard (line 941), and `withFieldSchema`'s `items %~ appendItem ref`
   (the unnamed-field/tuple branch) all rely on `OpenApiItemsArray`. Per the Decision Log, tuple
   derivation now collapses to a single-schema `items` whose element is the `oneOf` of the member
   schemas. Concretely:

   - Replace `appendItem` with an accumulator that, instead of building a list, builds a single
     `OpenApiItemsObject` whose schema is `mempty & oneOf %~ ...` accumulating member refs, OR —
     simpler and chosen here — change the unnamed-field branch in `withFieldSchema` so a product
     of N fields produces `type_ ?~ OpenApiTypeSingle OpenApiArray` and
     `items ?~ OpenApiItemsObject (Inline (mempty & oneOf ?~ memberRefs))` with `minItems`/`maxItems`
     both `N`. Leave a `TODO(EP-4)` comment: "switch to `prefixItems` for true tuple validation".
   - Remove `nullarySchema`'s `items ?~ OpenApiItemsArray []`; an empty tuple (zero fields) becomes
     `type_ ?~ OpenApiTypeSingle OpenApiArray & maxItems ?~ 0` with no `items` (or
     `items ?~ OpenApiItemsBoolean False` to mean "no items allowed" — choose `maxItems 0` to match
     the prior intent and avoid a behavioral surprise; record the choice).
   - Remove the `OpenApiItemsArray [_]` guard; with the new accumulator the single-field case is
     handled by the existing record/field logic.

   This is the most intricate edit; do it incrementally and lean on the `ISPair` test to confirm
   the emitted shape. Read lines 900-995 in full before editing.

8. **Fix `Generator.hs`** (line 68): remove the `OpenApiItemsArray refs -> ...` branch. With only
   `OpenApiItemsObject` and `OpenApiItemsBoolean`, the array case is `OpenApiItemsBoolean b ->`
   (for `b == True`, generate as if unconstrained array; for `False`, generate an empty array).
   Keep the `OpenApiItemsObject` branch as-is.

9. **Fix `Validation.hs`** (line 352): replace the `OpenApiItemsArray itemSchemas -> ...` branch in
   `validateArray` with `OpenApiItemsBoolean b -> when (not b && not (Vector.null xs)) (invalid ...)`
   (a `false` items with a non-empty array is invalid; `true` is always valid). Keep the
   `OpenApiItemsObject` branch.

10. **Fix `Lens.hs`** (lines 57-75): the `_OpenApiItemsArray` review references the removed
    constructor. Remove `_OpenApiItemsArray` entirely and add `_OpenApiItemsBoolean`:

    ```haskell
    _OpenApiItemsBoolean :: Review OpenApiItems Bool
    _OpenApiItemsBoolean = unto OpenApiItemsBoolean
    ```

    Keep `_OpenApiItemsObject`. Also remove the stale commented-out `OpenApiItemsPrimitive`
    references in the comments.

11. **Fix `Optics.hs`** (lines 145-168): remove the `"_OpenApiItemsArray"` `LabelOptic` instance;
    add a `"_OpenApiItemsBoolean"` review analogous to `"_OpenApiItemsObject"`.

12. **Fix the `ISPair` test.** In `test/Data/OpenApi/CommonTestTypes.hs`, update `ispairSchemaJSON`
    (line 475) from the `"items":[...]` tuple form to the new 3.1 form the derivation now produces
    (a `oneOf` element schema with `minItems`/`maxItems` of 2). Derive the exact expected JSON by
    encoding `toSchema (Proxy :: Proxy ISPair)` once the derivation is updated, then paste the
    canonical JSON. Adjust `SchemaSpec.hs:70` only if the test helper signature changes (it should
    not).

Commands and acceptance: `nix develop -c cabal build all` then `nix develop -c cabal test all`.
Acceptance: `{"items":false}` and `{"items":true}` round-trip; the homogeneous-array schema
round-trips; the `ISPair` test passes against its new expected JSON; no reference to `nullable` or
`OpenApiItemsArray` remains (`grep -rn "nullable\|OpenApiItemsArray" src/ test/` is empty).


### Milestone 4 — Version constants, `detectVersion`, green tree

Scope: bump version bounds, add the version-routing utility, and get a fully green build/test.

What exists after M4: `lowerOpenApiSpecVersion = makeVersion [3,1,0]`,
`upperOpenApiSpecVersion = makeVersion [3,1,1]`; `OpenApiMajorVersion`/`detectVersion` exist; the
whole tree builds and all tests pass.

Edits:

1. In `src/Data/OpenApi/Internal.hs`, change lines 97 and 101:

   ```haskell
   lowerOpenApiSpecVersion = makeVersion [3, 1, 0]
   upperOpenApiSpecVersion = makeVersion [3, 1, 1]
   ```

2. Add, near the version constants (so it is co-located with `OpenApiSpecVersion`):

   ```haskell
   -- | Coarse major version of an OpenAPI document, used to route a parsed document
   --   to the appropriate decoder. This is NOT stored on any type and does not keep
   --   two representations alive; it only tells a reader which migration path to take.
   data OpenApiMajorVersion = OpenApi30 | OpenApi31
     deriving (Eq, Show, Generic, Data, Typeable)

   detectVersion :: OpenApiSpecVersion -> OpenApiMajorVersion
   detectVersion v
     | versionBranch (getVersion v) >= [3, 1] = OpenApi31
     | otherwise                              = OpenApi30
   ```

   Check the actual accessor: `OpenApiSpecVersion` wraps a `Version` — read its definition near
   `Internal.hs` to find the field name (it may be `getVersion` or a record selector). Use
   `versionBranch` from `Data.Version` on the underlying `Version`. Export `OpenApiMajorVersion`,
   `detectVersion`, and (if not already) `OpenApiTypeValue(..)`, `OpenApiItemsBoolean` from the
   public modules — check `src/Data/OpenApi.hs`'s re-export list and add the new names.

3. Audit any version-bound check that referenced `[3,0,...]` (e.g. a `parseJSON OpenApiSpecVersion`
   or a test asserting the bounds). `grep -rn "3, 0, 3\|lowerOpenApiSpecVersion\|upperOpenApiSpecVersion" src/ test/`
   and update expectations. There is a test asserting parse failure outside bounds — update it to
   the new range if present.

4. Run the full suite. Fix any remaining compile or test failures uncovered only at this point
   (e.g. doctests embedded in Haddock comments that show old JSON — search for `nullable` and
   `exclusiveMaximum.*true` in comments and update them).

Commands and acceptance: `nix develop -c cabal build all` and `nix develop -c cabal test all` both
succeed with zero failures. This is the milestone that proves EP-3 done.


## Concrete Steps

All commands run from the repo root `/Users/shinzui/Keikaku/hub/haskell/openapi3`.

Enter the dev shell once (it pins GHC 9.12.4 and provides `cabal`):

```bash
nix develop
```

Inside the shell (or prefix each command with `nix develop -c`):

```bash
cabal build all
```

Expected on success (abridged):

```text
Building library for openapi3-3.2.5..
...
Linking ...
```

Run the tests:

```bash
cabal test all
```

Expected on success (abridged):

```text
Test suite openapi3-test: RUNNING...
...
Finished in N seconds
M examples, 0 failures
Test suite openapi3-test: PASS
```

Useful search commands while implementing:

```bash
grep -rn "type_ ?~ OpenApi" src/                 # the ~43 set-sites for M1 step 7
grep -rn "nullable\|Nullable" src/ test/          # confirm M3 step 1 leaves nothing
grep -rn "OpenApiItemsArray" src/ test/           # confirm M3 leaves nothing
grep -rn "exclusiveMa\(x\|n\)imum" src/ test/    # find M2 boolean usages
```

To inspect what the encoder produces for a value while validating the `saoSubObject` decision
(M3 step 4), use a throwaway GHCi session in the shell:

```bash
cabal repl lib:openapi3
```

```haskell
import Data.Aeson (encode)
import Data.OpenApi.Internal
encode (mempty { _schemaItems = Just (OpenApiItemsBoolean False) } :: Schema)
-- expect: "{\"items\":false}"
encode (mempty { _schemaType = Just (OpenApiTypeArray [OpenApiString, OpenApiNull]) } :: Schema)
-- expect: "{\"type\":[\"string\",\"null\"]}"
```

Update this section with the actual observed output as you go.


## Validation and Acceptance

Validation is by round-trip tests added to the test suite plus the full existing suite passing.
Create a new spec module `test/Data/OpenApi/Schema/CoreTypes31Spec.hs` (register it in the
`other-modules` of the test-suite stanza in `openapi3.cabal`, per Integration Point IP-5, and let
`hspec-discover` pick it up — match the naming/discovery convention the other `*Spec.hs` modules
use; read one of them first). Its contents implement the migration plan's `prop_schema31_roundtrip`
pattern plus the specific golden cases:

```haskell
{-# LANGUAGE OverloadedStrings #-}
module Data.OpenApi.Schema.CoreTypes31Spec where

import Data.Aeson (decode, encode, eitherDecode, Value)
import Data.Aeson.QQ.Simple (aesonQQ)
import Test.Hspec
import Data.OpenApi
import Data.OpenApi.Internal

spec :: Spec
spec = do
  describe "OpenAPI 3.1 core type changes" $ do

    it "type array {\"type\":[\"string\",\"null\"]} round-trips" $ do
      let s = mempty { _schemaType = Just (OpenApiTypeArray [OpenApiString, OpenApiNull]) }
      encode s `shouldBe` "{\"type\":[\"string\",\"null\"]}"
      (decode (encode s) :: Maybe Schema) `shouldBe` Just s

    it "single type still serializes as a bare string" $ do
      let s = mempty { _schemaType = Just (OpenApiTypeSingle OpenApiString) }
      encode s `shouldBe` "{\"type\":\"string\"}"
      (decode (encode s) :: Maybe Schema) `shouldBe` Just s

    it "numeric exclusive bounds round-trip" $ do
      let s = mempty { _schemaExclusiveMinimum = Just 0
                     , _schemaExclusiveMaximum = Just 100 }
      (decode (encode s) :: Maybe Schema) `shouldBe` Just s
      (decode "{\"exclusiveMinimum\":0,\"exclusiveMaximum\":100}" :: Maybe Schema)
        `shouldBe` Just s

    it "items:false round-trips" $ do
      let s = mempty { _schemaItems = Just (OpenApiItemsBoolean False) }
      encode s `shouldBe` "{\"items\":false}"
      (decode (encode s) :: Maybe Schema) `shouldBe` Just s

    it "items:true round-trips" $ do
      let s = mempty { _schemaItems = Just (OpenApiItemsBoolean True) }
      (decode (encode s) :: Maybe Schema) `shouldBe` Just s

    it "homogeneous array schema round-trips" $ do
      let s = mempty { _schemaType  = Just (OpenApiTypeSingle OpenApiArray)
                     , _schemaItems = Just (OpenApiItemsObject
                                       (Inline (mempty { _schemaType = Just (OpenApiTypeSingle OpenApiString) }))) }
      (decode (encode s) :: Maybe Schema) `shouldBe` Just s
```

Adjust the exact `encode` byte-for-byte expectations if aeson key ordering differs; the
authoritative assertion is the `decode (encode s) == Just s` round-trip. (If exact-bytes
assertions are brittle, compare decoded `Value`s instead, using `SpecCommon.hs`'s helpers.)

The behavioral proof beyond compilation:

- `{"type":["string","null"]}` is decodable and re-encodes identically (impossible before this
  plan — 3.0 `type` was a single string). This is the headline acceptance.
- `{"exclusiveMaximum":100}` carries a numeric bound (before: only `true`/`false`).
- `{"items":false}` is representable and round-trips (before: `items` could not be a boolean).
- Emitting a `nullable` key is now impossible: there is no field for it.

Run, for the targeted module then the whole suite:

```bash
nix develop -c cabal test all
```

Interpret: every `it` block prints with a checkmark and the run ends `0 failures`. If a golden
`encode` assertion fails on key order, switch that assertion to a `Value`-equality check and
re-run.


## Idempotence and Recovery

Every edit in this plan is to source files under version control; nothing is destructive to data.
The steps are safe to re-run: re-running `cabal build all`/`cabal test all` is idempotent.

If a milestone leaves the tree non-compiling and you need to retreat, the milestones are ordered
so each is a clean commit boundary — `git stash` or `git checkout -- <file>` restores the last
good state. Because M1 introduces `OpenApiTypeValue` and the `type_` rewrites together, do not
commit M1 half-done; if you must stop mid-M1, the tree will not compile, so leave a `WIP` commit
on a scratch branch rather than the working branch.

The single highest-risk edit is M3 step 7 (tuple derivation). If it proves too invasive, a safe
intermediate fallback that keeps the tree compiling is: make tuple derivation `error` with a clear
message "tuple ToSchema requires prefixItems (EP-4)" and mark the `ISPair` test `pending`. This
keeps EP-3's core type changes landed while deferring the tuple-derivation semantics to EP-4.
Record this fallback in the Decision Log if used, and add a `TODO(EP-4)`.

To verify no leftover references after M3, these greps must be empty:

```bash
grep -rn "OpenApiItemsArray" src/ test/
grep -rn "_schemaNullable\|HasNullable" src/ test/
```


## Interfaces and Dependencies

Libraries used (all already dependencies): `aeson` (JSON), `generics-sop` (the custom serializer),
`lens` and `optics-core` (the two lens/optic surfaces), `scientific` (the `Scientific` numeric
type for exclusive bounds), `insert-ordered-containers` (`InsOrdHashMap`), `hspec` and
`aeson-qq` for tests. No new dependency is introduced by this plan.

Types and signatures that must exist at the end of each milestone (full module paths):

After M1, in `Data.OpenApi.Internal`:

```haskell
data OpenApiTypeValue
  = OpenApiTypeSingle OpenApiType
  | OpenApiTypeArray [OpenApiType]
  deriving (Eq, Show, Generic, Data, Typeable)

instance ToJSON OpenApiTypeValue
instance FromJSON OpenApiTypeValue

-- _schemaType :: Maybe OpenApiTypeValue          (field on Schema)
```

and in `Data.OpenApi.Lens`: `instance HasType NamedSchema (Maybe OpenApiTypeValue)`; in
`Data.OpenApi.Optics`: the `#type` `LabelOptic` targeting `Maybe OpenApiTypeValue`. The `type_`
lens / `#type` optic on `Schema` itself are regenerated by `makeFields`/optics and target
`Maybe OpenApiTypeValue`.

After M2, in `Data.OpenApi.Internal`: `_schemaExclusiveMaximum :: Maybe Scientific` and
`_schemaExclusiveMinimum :: Maybe Scientific` on `Schema`; in `Data.OpenApi.Lens`:
`HasExclusiveMaximum s (Maybe Scientific)`, `HasExclusiveMinimum s (Maybe Scientific)`; in
`Data.OpenApi.Optics`: `#exclusiveMaximum`/`#exclusiveMinimum` optics targeting `Maybe Scientific`.

After M3, in `Data.OpenApi.Internal`:

```haskell
data OpenApiItems where
  OpenApiItemsObject  :: Referenced Schema -> OpenApiItems
  OpenApiItemsBoolean :: Bool              -> OpenApiItems
  deriving (Eq, Show, Typeable, Data)

instance ToJSON OpenApiItems
instance FromJSON OpenApiItems
-- Schema has NO _schemaNullable field.
```

and in `Data.OpenApi.Lens`/`Optics`: `_OpenApiItemsObject` and `_OpenApiItemsBoolean` reviews; no
`_OpenApiItemsArray`.

After M4, in `Data.OpenApi.Internal`:

```haskell
lowerOpenApiSpecVersion :: Version   -- makeVersion [3,1,0]
upperOpenApiSpecVersion :: Version   -- makeVersion [3,1,1]

data OpenApiMajorVersion = OpenApi30 | OpenApi31
  deriving (Eq, Show, Generic, Data, Typeable)

detectVersion :: OpenApiSpecVersion -> OpenApiMajorVersion
```

Integration points honored (from the master plan):

- IP-2 (the shared `Schema`/`OpenApiItems` shape): EP-3 *defines* the new shape. New fields in
  EP-4 will **append** to the end of the `Schema` record; this plan leaves the record's existing
  field order intact except for the `_schemaNullable` removal, so EP-4's appends are clean.
- IP-3 (the Aeson machinery): EP-3 reworks the boolean-`items` serialization. The chosen mechanism
  is documented in the Decision Log and M3 step 4 (bypass the splice for the boolean case / verify
  the existing splice already lifts the single `"items"` key). EP-4 builds its `$`-key helper on
  this same `AesonUtils` surface, so the change is kept minimal and well-described.
- IP-4 (`OpenApiType`/`OpenApiNull`): EP-3 keeps `OpenApiNull` and makes `OpenApiTypeArray`
  round-trip it; the M1 headline test proves `OpenApiTypeArray [OpenApiString, OpenApiNull]` ↔
  `["string","null"]`.


## Risks

The biggest risk this plan flags: **tuple `ToSchema` derivation** (M3 step 7). Removing
`OpenApiItemsArray` does not merely break a parser branch — it breaks generic derivation of
non-record product types (tuples), whose correct 3.1 representation is `prefixItems`, a field that
does not exist until EP-4. The conservative collapse-to-`oneOf`-`items` here changes the *emitted
schema shape* for tuples, which is a behavioral (not just mechanical) change and may surprise
downstream users who derive `ToSchema` for tuples. The documented fallback (error + pending test +
`TODO(EP-4)`) keeps EP-3 landable if the collapse proves too invasive; either way EP-4 should
revisit tuple derivation to use `prefixItems`. A secondary risk is the `saoSubObject` boolean-items
interaction (M3 step 4): the plan instructs verifying empirically whether the existing splice
already handles `{"items": false}` before editing `AesonUtils.hs`, to avoid a needless change to
the shared serializer that EP-4 also depends on.


## Revision Notes

- 2026-06-10 — Initial full authoring from the skeleton. Filled every section from a close reading
  of `OPENAPI31_MIGRATION_PLAN.md` (Milestone 1; Phases 1.1.1–1.1.3, 1.2, 3, and the items/exclusive
  /type-array parts of Phase 4), the master plan's Integration Points IP-2/IP-3/IP-4, and the
  source files (`Internal.hs`, `Internal/AesonUtils.hs`, `Lens.hs`, `Optics.hs`,
  `Internal/Schema.hs`, `Internal/ParamSchema.hs`, `Internal/Schema/Validation.hs`,
  `Schema/Generator.hs`, and the named test files). Reason for the larger-than-stated scope: the
  `type_` lens and `OpenApiItemsArray`/exclusive-bound usages reach ~45+ call sites across src/
  including the generic tuple-derivation machinery, all of which must change for the tree to
  compile; these are enumerated in the Surprises section with evidence so a novice can find them.
