---
id: 4
slug: openapi-3-1-json-schema-fields-and-reference-keywords
title: "OpenAPI 3.1 JSON Schema Fields and Reference Keywords"
kind: exec-plan
created_at: 2026-06-11T03:47:52Z
master_plan: "docs/masterplans/1-openapi-3-1-support-and-project-modernization.md"
---

# OpenAPI 3.1 JSON Schema Fields and Reference Keywords

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

This library, `openapi3` (in this fork being modernized toward the name `openapi-hs`), is a
Haskell library that decodes, encodes, and manipulates OpenAPI specification documents. An
OpenAPI document is a JSON (or YAML) description of an HTTP API. The most important part of
such a document is the `Schema` object, which describes the shape of request and response
data. Up to now the library models the OpenAPI 3.0 dialect of `Schema`. OpenAPI 3.1 adopts
the JSON Schema 2020-12 vocabulary, which adds many new schema keywords and a family of
identification keywords whose JSON names begin with a dollar sign (`$id`, `$ref`, `$defs`,
`$anchor`, `$dynamicRef`, `$dynamicAnchor`).

After this change, a user can take a JSON document such as
`{"prefixItems":[{"type":"string"},{"type":"number"}],"items":false}` or
`{"if":{...},"then":{...}}` or `{"const":42}` or `{"$id":"https://x/y","$defs":{...}}`, decode
it into the Haskell `Schema` value with `Data.Aeson.decode`, read or modify any of the new
fields through a lens (in `src/Data/OpenApi/Lens.hs`) or an optic (in
`src/Data/OpenApi/Optics.hs`), and re-encode it with `Data.Aeson.encode` so that the original
JSON keys — including the `$`-prefixed ones — come back unchanged. Concretely, the user can
write `decode "{\"const\":42}" :: Maybe Schema` and get `Just (mempty { _schemaConst = Just
(Number 42) })`, and `encode` of that value yields `{"const":42}` again. None of these
keywords can round-trip today; after this plan they all can.

A second, less visible but equally important outcome: this plan builds the **one reusable
mechanism** the whole codebase will use to emit and parse JSON keys that begin with `$`. The
library's normal serialization machinery derives a JSON key from a Haskell field name by
stripping a record prefix and lower-casing the first letter (so `_schemaPrefixItems` becomes
`"prefixItems"`). That rule physically cannot produce a key that starts with `$`, because a
Haskell record field cannot start with `$`. This plan introduces a helper that injects and
reads `$`-prefixed keys, places it in an importable module, and documents its name and
signature so that a later plan (EP-5, which adds `$ref` to the `PathItem` object and a
`webhooks` map) reuses it instead of re-inventing it. This is Integration Point IP-3 in the
master plan (`docs/masterplans/1-openapi-3-1-support-and-project-modernization.md`).


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented here,
even if it requires splitting a partially completed task into two ("done" vs. "remaining").
This section must always reflect the actual current state of the work.

- [ ] M0 spike: decide whether `$ref`-with-siblings decodes to `Inline (Schema { _schemaRef = Just ... })` or stays at the `Referenced` layer, and record the audit of every `Inline`/`Ref` pattern-match site.
- [ ] M0 spike: decide the boolean-schema representation (extend `Referenced`/`Schema` boolean decoding, OR a dedicated `BoolOr` sum) and record its blast radius.
- [ ] M0 spike: design and place the canonical `$`-prefixed-key serialization helper; record its name, signature, and module (Integration Point IP-3).
- [ ] M1: append the non-`$` JSON Schema fields to `Schema` (`const`, `prefixItems`, `contains`, `minContains`, `maxContains`, `if`/`then`/`else`, `dependentSchemas`, `dependentRequired`, `unevaluatedProperties`, `unevaluatedItems`, `propertyNames`, `contentEncoding`, `contentMediaType`, `contentSchema`, `examples`).
- [ ] M1: add an `AesonDefaultValue` instance for every new field type that lacks one; add `{-# DEPRECATED _schemaExample ... #-}`.
- [ ] M1: confirm derived lenses (`src/Data/OpenApi/Lens.hs`) and optics (`src/Data/OpenApi/Optics.hs`) exist for every M1 field; build passes.
- [ ] M1: round-trip tests for every M1 keyword pass.
- [ ] M2: append the `$`-prefixed fields (`_schemaId`, `_schemaAnchor`, `_schemaDefs`, `_schemaRef`, `_schemaDynamicRef`, `_schemaDynamicAnchor`) and wire them through the M0 helper.
- [ ] M2: round-trip tests prove each `$`-prefixed JSON key survives `decode . encode` with the literal `$` key.
- [ ] Whole plan: `nix develop -c cabal build all` and `nix develop -c cabal test all` succeed.


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

The library has **two different `SwaggerAesonOptions` for `Schema`** and they disagree. The
`ToJSON Schema` instance (`src/Data/OpenApi/Internal.hs:1336-1338`) is written by hand as:

```haskell
instance ToJSON Schema where
  toJSON = sopSwaggerGenericToJSONWithOpts $
      mkSwaggerAesonOptions "schema" & saoSubObject ?~ "items"
```

— it uses `saoSubObject ?~ "items"`. But the `HasSwaggerAesonOptions Schema` instance
(`src/Data/OpenApi/Internal.hs:1627-1628`), which `FromJSON Schema` reads via
`sopSwaggerGenericParseJSON`, says:

```haskell
instance HasSwaggerAesonOptions Schema where
  swaggerAesonOptions _ = mkSwaggerAesonOptions "schema" & saoSubObject ?~ "paramSchema"
```

— it uses `saoSubObject ?~ "paramSchema"`. The current `Schema` record (lines 619-665) has
**no** field named `_schemaParamSchema`, so on the parse side the `paramSchema` sub-object
splice never matches any field and is effectively a no-op; the `items` key is instead read by
the ordinary field path because `_schemaItems` maps to `"items"`. The implementer must not
assume the two option sets are interchangeable. This is documented here so the next contributor
does not "fix" one to match the other and accidentally change behavior. (EP-3 already touches
this area to handle `OpenApiItemsBoolean`; see the dependency note below.)

The Aeson-compat layer used throughout (`src/Data/OpenApi/Aeson/Compat.hs`) abstracts over the
`aeson` version: with modern `aeson`, JSON object keys are `Data.Aeson.Key` and
`stringToKey :: String -> Key = Key.fromString`, `keyToText :: Key -> Text`,
`objectToList :: KeyMap v -> [(Key, v)]`, `lookupKey :: Text -> KeyMap v -> Maybe v`,
`deleteKey :: Key -> KeyMap v -> KeyMap v`. A `$`-prefixed key is a perfectly legal `Key`
(`Key.fromString "$ref"`); nothing prevents constructing it — the only obstacle is that the
*generic field-name → key* rule cannot emit it. That is exactly why the M0 helper injects such
keys outside that rule.

(Further surprises to be recorded during implementation.)


## Decision Log

Record every decision made while working on the plan. The first four entries are **seeded** by
the design analysis below; the implementer confirms or revises them during the M0 spike and
must leave the final wording here.

- Decision: `$ref`-with-siblings decodes by keeping the `Referenced` layer for the *pure*
  reference case and storing a sibling-bearing `$ref` in the new `_schemaRef :: Maybe Text`
  field of an `Inline` schema.
  Rationale: In OpenAPI 3.0 a JSON object with a `$ref` key is *only* a reference — any
  sibling keys are ignored — and the library models that with `referencedParseJSON`
  (`src/Data/OpenApi/Internal.hs:1564-1575`): if the object has a `$ref` whose value matches
  the expected `#/components/schemas/…` prefix it becomes `Ref (Reference suffix)`, otherwise
  `Inline`. JSON Schema 2020-12 (OpenAPI 3.1) allows `$ref` to appear *alongside* sibling
  keywords, and the two are evaluated together. Reworking every `Referenced`-consuming site to
  carry siblings would be a very large blast radius (see audit below). Instead we keep the
  existing `Referenced` two-constructor shape unchanged, and represent a sibling-bearing
  reference as `Inline (Schema { _schemaRef = Just "<the $ref string>", ...siblings... })`.
  `referencedParseJSON` keeps producing `Ref` **only** when `$ref` is the *sole* meaningful key
  and its value matches the component prefix; when other schema keys are present it falls to the
  `Inline` branch, and the inline `Schema` parse picks up `$ref` into `_schemaRef`. This means
  no existing `Ref`/`Inline` match site changes its meaning; the new behavior is purely additive.
  Date: 2026-06-10

- Decision: Boolean schemas are represented by **extending decoding so a JSON boolean maps to a
  canonical always-true / always-false `Schema`** (option (i) from the migration plan), not by a
  new `BoolOr` sum (option (ii)).
  Rationale: In JSON Schema 2020-12 a bare `true` or `false` is a valid schema in *any* schema
  position (`additionalProperties`, `items`, `unevaluatedItems`, members of `prefixItems`,
  `properties` values, `contains`, `if`/`then`/`else`, etc.). EP-3's `OpenApiItemsBoolean`
  (added in `docs/plans/3-openapi-3-1-core-schema-type-changes.md`) only covers the `items`
  case. Introducing a `BoolOr (Referenced Schema)` sum would force *every* affected field type
  to change and would ripple a new constructor through validation, the schema generator, and the
  optics — a large, type-level blast radius. Extending `Referenced Schema` *decoding* instead
  keeps every field's type unchanged: a JSON `true` decodes to the empty `Inline mempty`
  (always-true: the empty schema accepts everything) and a JSON `false` decodes to
  `Inline (mempty { _schemaNot = Just (Inline mempty) })` (always-false: `not: {}` rejects
  everything). The matching `ToJSON` direction re-emits those two canonical shapes as `true` /
  `false` only where round-trip fidelity is required; the safe and complete default is to emit
  them as the explicit object forms (`{}` and `{"not":{}}`), which are semantically identical
  and still valid 3.1. **EP-4 implements the read direction for the fields it owns** (the new
  `Referenced Schema` / `AdditionalProperties`-typed fields) and leaves `items` to EP-3's
  `OpenApiItemsBoolean`. Encoding a bare `true`/`false` literal is a fidelity nicety, not a
  correctness requirement; if it is not implemented, the round-trip of a bare boolean still
  produces a semantically equivalent object and the test suite asserts on that object form.
  Date: 2026-06-10

- Decision: The canonical `$`-prefixed-key mechanism is a **post-processing pass on the
  generated `Value`**, implemented as two exported helpers in
  `src/Data/OpenApi/Internal/AesonUtils.hs`: `dollarKeysToJSON` (inject) and
  `dollarKeysParseJSON` (extract). EP-5 imports these; it does not duplicate them. This is
  Integration Point IP-3.
  Rationale: The generic machinery (`sopSwaggerGenericToJSON*` /
  `sopSwaggerGenericParseJSON`) cannot emit or read a key beginning with `$` because the
  field-name→key rule strips the record prefix and lower-cases (it cannot prepend `$`). The two
  candidate techniques are (a) `saoAdditionalPairs`-style injection (constant pairs only — but
  `$`-key *values* are not constant, they depend on the `Schema`), and (b) a post-pass that
  rewrites the produced `Value`/`Object`. Because the `$`-key values are field-dependent, only
  (b) fits, so we add a thin wrapper around the existing generic `toJSON`/`parseJSON` that moves
  the relevant fields to/from their `$`-prefixed keys. Placing them in `AesonUtils` (already the
  home of `mkSwaggerAesonOptions`, `saoSubObject`, `saoAdditionalPairs`) keeps all serialization
  plumbing in one importable module.
  Date: 2026-06-10

- Decision: `_schemaExample` (singular) is **retained** and marked
  `{-# DEPRECATED _schemaExample "Use _schemaExamples (JSON Schema 'examples') in OpenAPI 3.1" #-}`.
  Rationale: OpenAPI 3.1 deprecates the singular `example` in favor of the JSON Schema
  `examples` array but does not remove it. Because the field stays on the type, the pragma is
  valid (unlike `_schemaNullable`, which EP-3 *removes* and therefore cannot deprecate). The new
  `_schemaExamples :: Maybe [Value]` carries the 3.1 `examples` array independently.
  Date: 2026-06-10


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose.

(To be filled during and after implementation.)


## Context and Orientation

This section assumes you know nothing about this repository. Read it fully before editing.

The repository root is `/Users/shinzui/Keikaku/hub/haskell/openapi3`. It is a Haskell library
built with Cabal inside a Nix dev shell. You build with `nix develop -c cabal build all` and
test with `nix develop -c cabal test all`, both run from the repository root. (If you are not
using Nix, plain `cabal build all` / `cabal test all` work too, provided a GHC 9.12.x toolchain
is on `PATH`.)

The data model lives in **`src/Data/OpenApi/Internal.hs`**, a large single module that declares
every OpenAPI data type and its hand-written or generically-derived JSON instances. The type
central to this plan is `Schema` (record declaration at `src/Data/OpenApi/Internal.hs:619-665`).
Each field is named with a `_schema` prefix, e.g. `_schemaType`, `_schemaItems`,
`_schemaExample`. A *field* here is one named component of the Haskell record; a *keyword* is
the JSON key it serializes to (e.g. the field `_schemaPrefixItems` serializes to the JSON
keyword `"prefixItems"`).

Several supporting types you will touch or reference:

- `Referenced a` (`src/Data/OpenApi/Internal.hs:952-955`) is the library's "either a JSON
  reference or an inline value" type: `data Referenced a = Ref Reference | Inline a`. A
  `Reference` (`Internal.hs:949`) wraps a `Text` (the `$ref` target). Many `Schema` fields are
  typed `Referenced Schema`, meaning "a sub-schema that may be given inline or by `$ref`".
- `AdditionalProperties` (`src/Data/OpenApi/Internal.hs:962-965`) is
  `AdditionalPropertiesAllowed Bool | AdditionalPropertiesSchema (Referenced Schema)` — it
  models `additionalProperties`, which may be a boolean or a schema. The 3.1
  `unevaluatedProperties` keyword has the same shape, so this plan reuses `AdditionalProperties`
  for `_schemaUnevaluatedProperties`.
- `OpenApiItems` (`src/Data/OpenApi/Internal.hs:586-589`) models the `items` keyword. **EP-3**
  (the plan this one hard-depends on) changes it from `OpenApiItemsObject | OpenApiItemsArray`
  to `OpenApiItemsObject | OpenApiItemsBoolean Bool`. Do not change `OpenApiItems` in this plan;
  consume EP-3's shape.
- `InsOrdHashMap Text v` (imported at `src/Data/OpenApi/Internal.hs:34-35` as
  `InsOrdHashMap`) is an insertion-ordered hash map used for JSON objects whose key order must
  be preserved (e.g. `properties`, `$defs`, `dependentSchemas`). It already has an
  `AesonDefaultValue` instance (`src/Data/OpenApi/Internal/AesonUtils.hs:75`).
- `Data.Aeson.Value` is the generic JSON value type; `Maybe Value` is used for free-form
  keywords like `const`, `default`, and members of `examples`.

The JSON serialization is **not** hand-written per field. It is derived by a custom
`generics-sop`-based layer in **`src/Data/OpenApi/Internal/AesonUtils.hs`**. The pieces you must
understand:

- `mkSwaggerAesonOptions "schema"` builds a `SwaggerAesonOptions` carrying the record prefix
  (`"schema"`), an optional list of additional constant pairs (`saoAdditionalPairs`), and an
  optional sub-object field name (`saoSubObject`).
- `sopSwaggerGenericToJSON'' ` (`AesonUtils.hs:138-167`) walks the record fields. For each
  field it computes the JSON key via `fieldNameModifier`: drop the leading underscore, drop the
  prefix length, then lower-case the leading run of capitals. So `_schemaPrefixItems` →
  (drop `_`) `schemaPrefixItems` → (drop `schema`) `PrefixItems` → (lower leading caps)
  `prefixItems`. **This rule cannot produce a `$`-prefixed key**, which is the entire reason M0
  exists.
- Fields equal to their `defaultValue` (from the `AesonDefaultValue` class,
  `AesonUtils.hs:66-75`) are *omitted* from output. For every field type, an `AesonDefaultValue`
  instance must exist so the generic walk type-checks and so `Nothing`/empty values are dropped.
  Existing instances cover `Text`, `Maybe a`, `[a]`, `Set`, `InsOrdHashSet`, and `InsOrdHashMap`
  (`AesonUtils.hs:70-75`). Every new field in this plan is wrapped in `Maybe`, so its type is
  `Maybe <something>` and is covered by `instance AesonDefaultValue (Maybe a)` — **except** that
  the generic constraint is on the *unwrapped element type as well in some derivations*; see the
  Plan of Work for the exact check you run, and add instances only if the build complains.
- `saoSubObject ?~ "items"` (used by `ToJSON Schema`) means: when the walk reaches the field
  whose modified name equals `"items"`, do not nest it; instead splice the *keys of the
  sub-object it produces* directly into the parent object. This is how `OpenApiItems`'s
  `{ "items": ... }` object gets flattened up.

The hand-written reference instances are `referencedToJSON`
(`src/Data/OpenApi/Internal.hs:1416-1418`) and `referencedParseJSON`
(`src/Data/OpenApi/Internal.hs:1564-1575`). `ToJSON (Referenced Schema)` and
`FromJSON (Referenced Schema)` use them with the prefix `"#/components/schemas/"`.

Lenses and optics are **derived by Template Haskell**, not written by hand:

- `src/Data/OpenApi/Lens.hs:32` is `makeLensesWith swaggerFieldRules ''Schema`. This generates
  one `Control.Lens` lens per record field automatically. Adding a field to the `Schema` record
  therefore *automatically* produces its lens — you do not hand-write lens definitions. Your job
  is only to confirm the build still derives them and to make sure no name collides.
- `src/Data/OpenApi/Optics.hs:121` is `makeFieldLabels ''Schema`. This generates one
  `optics`-style labelled optic per field. Same story: adding a record field produces its optic
  automatically.

The migration design document `OPENAPI31_MIGRATION_PLAN.md` (repository root) drives this work;
this plan implements its **Milestone 2** ("New Schema Features"), specifically §1.1.4 (the new
JSON Schema fields), the §1.1.4 design notes on `$ref`-with-siblings and boolean schemas, and
§4.0 (the generics-sop machinery and `$`-prefixed-key handling). The master plan
`docs/masterplans/1-openapi-3-1-support-and-project-modernization.md` defines this as **EP-4**;
it **hard-depends on EP-3** and soft-depends on EP-1.

**Dependency on EP-3 (`docs/plans/3-openapi-3-1-core-schema-type-changes.md`).** EP-3 reshapes
the foundation this plan builds on. At the time of writing, EP-3 is a skeleton (Not Started); do
not begin EP-4 implementation until EP-3 is complete. EP-3 will have:

- removed `_schemaNullable` from the `Schema` record;
- changed `_schemaType` from `Maybe OpenApiType` to `Maybe OpenApiTypeValue` (single type or
  array of types, with hand-written `ToJSON`/`FromJSON OpenApiTypeValue`);
- changed `_schemaExclusiveMaximum` and `_schemaExclusiveMinimum` from `Maybe Bool` to
  `Maybe Scientific`;
- changed `OpenApiItems` from `OpenApiItemsObject | OpenApiItemsArray` to
  `OpenApiItemsObject | OpenApiItemsBoolean Bool`, and reworked the `saoSubObject`/`items`
  serialization so a boolean `items` is emitted as the literal `"items": false` rather than
  being spliced as an object;
- removed the `FromJSON Schema` `nullaryCleanup` reliance on `OpenApiItemsArray []`
  (`src/Data/OpenApi/Internal.hs:1498-1506`) — confirm what EP-3 left there before you edit
  `FromJSON Schema`.

Because EP-3 may settle the final field *order* of the `Schema` record, **EP-4 appends its new
fields after EP-3's fields** and must not reorder anything EP-3 produced (master-plan Integration
Point IP-2). If you implement EP-4 against the pre-EP-3 tree for prototyping, rebase the field
additions onto EP-3's final record before merging.


## Plan of Work

The work is three milestones: a de-risking **spike (M0)** that produces three decisions and one
helper; the **additive non-`$` fields (M1)**; and the **`$`-prefixed fields (M2)** that consume
the helper. Each milestone ends with a green `nix develop -c cabal build all` and the relevant
round-trip tests passing.


### Milestone 0 — Spike: reconcile `$ref`, boolean schemas, and `$`-key serialization

Scope: produce three written decisions (already seeded in the Decision Log above — confirm or
revise them) and one working, exported serialization helper, *before* touching the `Schema`
record in bulk. At the end of M0 the repository still compiles and behaves exactly as before
(the helper is added but not yet wired into any field), and the Decision Log entries are final.
Run `nix develop -c cabal build all` to confirm no regression.

**Spike step (a): the `$ref`-with-siblings audit and decision.** Enumerate every site that
pattern-matches the `Referenced` constructors `Ref` and `Inline`, so the decision's blast radius
is on record. From the repository root run:

```bash
grep -rn 'Inline\|\bRef \|\bRef(\|Referenced' src/
```

The constructor-match sites that matter (the ones that *destructure* a `Referenced`, as opposed
to merely constructing one) are concentrated in:

- `src/Data/OpenApi/Internal.hs` — `referencedToJSON` (1416-1418), `referencedParseJSON`
  (1564-1575), the `swaggerMappend` for `Referenced` (1159-1160), and `IsString` (957-958).
- `src/Data/OpenApi/Internal/Schema/Validation.hs` — `validateWithSchemaRef`
  (around 291-292): `validateWithSchemaRef (Ref ref) … / (Inline s) …`.
- `src/Data/OpenApi/Operation.hs`, `src/Data/OpenApi/Internal/Schema.hs`,
  `src/Data/OpenApi/Internal/ParamSchema.hs`, `src/Data/OpenApi/Schema/Generator.hs`,
  `src/Data/OpenApi/Schema.hs`, `src/Data/OpenApi/Optics.hs` — construction sites and a few
  matches; verify with the grep.

The decision (seeded above): keep `Referenced` exactly as-is; represent a sibling-bearing
reference as `Inline (Schema { _schemaRef = Just … })`. The consequence to verify during the
audit is that **none** of the destructuring sites assume "if it parsed as `Inline` then it has
no `$ref`". They do not today, because `_schemaRef` does not exist yet; after M2 adds it, an
`Inline` schema may legally carry `_schemaRef`. Validation (`validateWithSchemaRef`) treats an
`Inline s` by validating against `s` directly (line 292); EP-6 owns making that follow
`_schemaRef`, so for EP-4 the only requirement is round-trip fidelity, not reference resolution.
Write the confirmed decision and the audit result (the file:line list) into the Decision Log and
Surprises sections.

**Spike step (b): the boolean-schema decision.** The seeded decision is to *extend decoding* so
a JSON boolean in a `Referenced Schema` (or `AdditionalProperties`) position maps to a canonical
schema: `true → Inline mempty`, `false → Inline (mempty { _schemaNot = Just (Inline mempty) })`.
The blast radius to record: this only touches the `FromJSON (Referenced Schema)` path
(`referencedParseJSON`, `src/Data/OpenApi/Internal.hs:1564-1575`) and the `FromJSON
AdditionalProperties` path (`src/Data/OpenApi/Internal.hs:1589-1591`, which already accepts
`Bool`). For `referencedParseJSON`, add a `Bool` case to the `Value` match so that a bare
boolean does not hit the `referencedParseJSON _ _ = fail "…not an object"` clause (line 1575).
Concretely the new clause is:

```haskell
referencedParseJSON :: FromJSON a => Text -> Value -> JSON.Parser (Referenced a)
referencedParseJSON _ (Bool True)  = Inline <$> parseJSON (Object mempty)
referencedParseJSON _ (Bool False) = Inline <$> parseJSON (object [ "not" .= object [] ])
referencedParseJSON prefix js@(Object o) = …  -- unchanged existing body
referencedParseJSON _ _ = fail "referenceParseJSON: not an object"
```

This relies on `FromJSON a` being able to parse the empty object and a `{"not":{}}` object —
which `FromJSON Schema` can. Because the type variable `a` is constrained `FromJSON a`, the
helper stays general; the only instances that exercise the boolean clauses are the `Schema`
ones. Record in the Decision Log that EP-4 implements the *read* direction (decode) for these
boolean schemas; emitting a bare `true`/`false` literal on the write side is an optional fidelity
improvement and is **not** required for correctness (the object forms `{}` / `{"not":{}}` are
semantically identical valid 3.1). EP-3 already owns the `items: false` boolean literal case via
`OpenApiItemsBoolean`.

**Spike step (c): build the `$`-key serialization helper (Integration Point IP-3).** Add two
exported functions to `src/Data/OpenApi/Internal/AesonUtils.hs`. They post-process the generic
`Value`: on the way out they *move* a set of ordinary keys to their `$`-prefixed spellings; on
the way in they *move* the `$`-prefixed keys back to the ordinary spellings the generic parser
expects. The mechanism is a simple key-rename pass over the top-level `Object`.

Add to the module's export list (`AesonUtils.hs:1-15`):

```haskell
    -- * Dollar-prefixed keys (JSON Schema 2020-12: $id, $ref, $defs, …)
    dollarKeyRenames,
    applyKeyRenamesToJSON,
    applyKeyRenamesParseJSON,
```

and define, near the other helpers:

```haskell
-- | A rename table: (plainKey, dollarKey) pairs. The plain key is what the
-- generic field-name rule produces from a record field; the dollar key is what
-- must appear in JSON. Example: ("id", "$id"), ("ref", "$ref").
type KeyRenameTable = [(Text, Text)]

-- | Rewrite a generated 'Value': for each (plain, dollar) pair, if the object
-- has the plain key, move its value to the dollar key. Non-object values are
-- returned unchanged. Idempotent if applied once per direction.
applyKeyRenamesToJSON :: KeyRenameTable -> Value -> Value
applyKeyRenamesToJSON renames (Object o) =
    Object (foldl' renameOne o renames)
  where
    renameOne obj (plain, dollar) =
      case lookupKey plain obj of
        Nothing -> obj
        Just v  -> insertKey dollar v (deleteKey (stringToKey plain) obj)
applyKeyRenamesToJSON _ v = v

-- | The inverse: move each dollar key back to its plain key before the generic
-- parser runs. Used inside a withObject in the FromJSON instance.
applyKeyRenamesParseJSON :: KeyRenameTable -> Object -> Object
applyKeyRenamesParseJSON renames o = foldl' renameOne o renames
  where
    renameOne obj (plain, dollar) =
      case lookupKey dollar obj of
        Nothing -> obj
        Just v  -> insertKey plain v (deleteKey (stringToKey dollar) obj)
```

You will need `insertKey` in the compat layer. Check `src/Data/OpenApi/Aeson/Compat.hs`
(`stringToKey`, `lookupKey`, `deleteKey`, `objectToList` exist; verify whether an `insertKey`
exists and, if not, add `insertKey :: Text -> v -> KeyMap v -> KeyMap v = KeyMap.insert .
Key.fromText` in the modern branch and the matching `HashMap.insert` in the legacy branch). Add
the import `import Data.Foldable (foldl')` (or use `Data.List.foldl'`) to `AesonUtils.hs`.

The single canonical rename table for `Schema` (constant; lives next to the `Schema` instances
in `src/Data/OpenApi/Internal.hs`, built once) is:

```haskell
schemaDollarKeyRenames :: [(Text, Text)]
schemaDollarKeyRenames =
  [ ("id", "$id")
  , ("anchor", "$anchor")
  , ("defs", "$defs")
  , ("ref", "$ref")
  , ("dynamicRef", "$dynamicRef")
  , ("dynamicAnchor", "$dynamicAnchor")
  ]
```

These plain keys (`id`, `anchor`, `defs`, `ref`, `dynamicRef`, `dynamicAnchor`) are exactly what
the generic rule produces from the M2 fields `_schemaId`, `_schemaAnchor`, `_schemaDefs`,
`_schemaRef`, `_schemaDynamicRef`, `_schemaDynamicAnchor` (e.g. `_schemaDynamicRef` → drop `_`
→ `schemaDynamicRef` → drop `schema` → `DynamicRef` → lower leading caps → `dynamicRef`). Note
there is no collision risk: the OpenAPI `Schema` object has no plain (non-`$`) `id`, `ref`,
`defs`, `anchor`, `dynamicRef`, or `dynamicAnchor` keyword, so moving `"ref"` → `"$ref"` cannot
clobber a legitimate plain `ref`.

At the end of M0 the helper compiles and is exported but unused; `nix develop -c cabal build
all` passes. Acceptance for M0: the three Decision Log entries are finalized with the audit
file:line list recorded, and `applyKeyRenamesToJSON` / `applyKeyRenamesParseJSON` build.


### Milestone 1 — Additive non-`$` JSON Schema 2020-12 fields

Scope: append the seventeen non-`$` fields to the `Schema` record, give each an
`AesonDefaultValue` if the build needs one, deprecate `_schemaExample`, and prove each new
keyword round-trips. At the end of M1, `decode`/`encode` handles `prefixItems`, `const`,
`contains`/`minContains`/`maxContains`, `if`/`then`/`else`, `dependentSchemas`,
`dependentRequired`, `unevaluatedProperties`, `unevaluatedItems`, `propertyNames`,
`contentEncoding`, `contentMediaType`, `contentSchema`, and `examples`. Commands:
`nix develop -c cabal build all` then `nix develop -c cabal test all`.

**Edit 1 — append fields to the `Schema` record** (`src/Data/OpenApi/Internal.hs`, after the
last EP-3 field, currently around line 664, just before the closing `}` and `deriving`). Insert:

```haskell
  -- JSON Schema 2020-12 additions (OpenAPI 3.1) — EP-4
  , _schemaConst :: Maybe Value
  , _schemaPrefixItems :: Maybe [Referenced Schema]
  , _schemaContains :: Maybe (Referenced Schema)
  , _schemaMinContains :: Maybe Integer
  , _schemaMaxContains :: Maybe Integer
  , _schemaIf :: Maybe (Referenced Schema)
  , _schemaThen :: Maybe (Referenced Schema)
  , _schemaElse :: Maybe (Referenced Schema)
  , _schemaDependentSchemas :: Maybe (InsOrdHashMap Text (Referenced Schema))
  , _schemaDependentRequired :: Maybe (InsOrdHashMap Text [Text])
  , _schemaUnevaluatedProperties :: Maybe AdditionalProperties
  , _schemaUnevaluatedItems :: Maybe (Referenced Schema)
  , _schemaPropertyNames :: Maybe (Referenced Schema)
  , _schemaContentEncoding :: Maybe Text
  , _schemaContentMediaType :: Maybe Text
  , _schemaContentSchema :: Maybe (Referenced Schema)
  , _schemaExamples :: Maybe [Value]
```

A note on the JSON keys for `if`/`then`/`else`: the field names are `_schemaIf`, `_schemaThen`,
`_schemaElse`. The generic rule produces `_schemaIf` → `If` → `if`, `_schemaThen` → `then`,
`_schemaElse` → `else`. These are *not* `$`-prefixed, so they derive normally and need no helper.
(`if`/`then`/`else` are reserved words in Haskell only as *expressions*; as record field-name
*suffixes* `If`/`Then`/`Else` they are ordinary identifiers — `_schemaIf` is a perfectly legal
field name.) Confirm after building that the emitted keys are exactly `"if"`, `"then"`, `"else"`.

**Edit 2 — deprecate `_schemaExample`.** Immediately above the `Schema` record (or directly
after the `data Schema = Schema` line, GHC accepts a top-level `DEPRECATED` pragma naming the
field selector), add:

```haskell
{-# DEPRECATED _schemaExample "Use _schemaExamples (JSON Schema 'examples') in OpenAPI 3.1" #-}
```

This is valid because `_schemaExample` (singular, `Internal.hs:637`) is *retained*. Building will
now emit a deprecation warning anywhere `_schemaExample` is used inside the library; expect to
see warnings in `FromJSON Schema`'s `nullaryCleanup` (line 1503) and possibly in the schema
generator. EP-3 may already have rewritten `nullaryCleanup`; if a warning appears on a library
internal use, suppress it locally with `{-# OPTIONS_GHC -Wno-deprecations #-}` at the top of the
specific module *only if* the build is configured `-Werror` (check `openapi3.cabal`'s
`ghc-options`). Do not silence the warning globally — downstream users should still see it.

**Edit 3 — `AesonDefaultValue` instances.** Every new field is `Maybe <T>`, and
`instance AesonDefaultValue (Maybe a)` (`AesonUtils.hs:71`) already covers `Maybe`-typed fields,
so in principle no new instance is required. However, the generic derivation constraint
`All2 AesonDefaultValue (Code a)` is on the *field types as they appear in the record*. Since
every added field is `Maybe …`, the constraint resolves to `AesonDefaultValue (Maybe …)` which
exists. **Build first; only add instances if GHC reports a missing `AesonDefaultValue`
instance.** The plausible gap is `AesonDefaultValue Integer` and `AesonDefaultValue Value` and
`AesonDefaultValue AdditionalProperties` — but again, only the `Maybe`-wrapped forms appear, so
they should not be needed. If the compiler does demand one (for example because some other
derivation unwraps the `Maybe`), add the minimal instance next to the others in
`AesonUtils.hs:70-75`, defaulting to `Nothing`:

```haskell
instance AesonDefaultValue Value
instance AesonDefaultValue Integer
instance AesonDefaultValue Scientific
instance AesonDefaultValue AdditionalProperties
```

(The bare `instance … where` uses the class's default `defaultValue = Nothing`, meaning "no
default → omitted only when the surrounding `Maybe` is `Nothing`".) Record in Surprises which, if
any, were actually required.

**Edit 4 — `FromJSON Schema` / `ToJSON Schema` sanity.** The `Schema` JSON instances stay
generic. `ToJSON Schema` (`Internal.hs:1336-1338`) and `FromJSON Schema`
(`Internal.hs:1498-1506`) need **no per-field change** for M1 because every new field flows
through `sopSwaggerGenericToJSON`/`sopSwaggerGenericParseJSON` with the correct derived key. Two
things to verify, not change: (1) the `saoSubObject ?~ "items"` splice still only fires for the
`items` field (none of the new fields modify to `"items"`); (2) EP-3's `nullaryCleanup` no longer
references the removed `OpenApiItemsArray` (if it still does after EP-3, that is an EP-3 bug to
flag, not fix here).

**Edit 5 — boolean schema read support (from M0 step (b)).** Apply the `referencedParseJSON`
boolean clauses designed in M0 so that `prefixItems`/`contains`/`if`/`then`/`else`/`contentSchema`
/`unevaluatedItems`/`propertyNames` members given as bare `true`/`false` decode rather than fail.
`unevaluatedProperties :: Maybe AdditionalProperties` already accepts `Bool` via
`FromJSON AdditionalProperties` (line 1590).

**Edit 6 — lenses and optics.** No hand edits are needed: `makeLensesWith swaggerFieldRules
''Schema` (`src/Data/OpenApi/Lens.hs:32`) and `makeFieldLabels ''Schema`
(`src/Data/OpenApi/Optics.hs:121`) regenerate one lens/optic per field automatically when the
record gains fields. After building, confirm the lenses exist by name in GHCi or by a test that
references `Data.OpenApi.Lens.schemaConst` and `Data.OpenApi.Optics`'s `#const`-style label.
(Master-plan IP-2 requires "a lens + an optic per new field"; here they are derived, so the
requirement is satisfied by the TH splices — your obligation is to *verify*, not author.)

Acceptance for M1: `nix develop -c cabal build all` succeeds with only the expected
`_schemaExample` deprecation notices; the M1 round-trip tests (see Validation) pass.


### Milestone 2 — The `$`-prefixed identification/reference fields

Scope: append the six `$`-keyword fields and wire the `Schema` JSON instances through the M0
helper so each `$`-prefixed JSON key emits and parses correctly. At the end of M2,
`{"$id":"https://x","$ref":"#/$defs/A"}` round-trips with the literal `$` keys intact, and
`{"$defs":{"A":{"type":"string"}}}` round-trips. Commands: `nix develop -c cabal build all` then
`nix develop -c cabal test all`.

**Edit 1 — append the `$`-keyword fields** to the `Schema` record, after the M1 fields:

```haskell
  -- JSON Schema 2020-12 identification / reference keywords ($-prefixed) — EP-4
  , _schemaId :: Maybe Text                                         -- $id
  , _schemaAnchor :: Maybe Text                                     -- $anchor
  , _schemaDefs :: Maybe (InsOrdHashMap Text (Referenced Schema))   -- $defs
  , _schemaRef :: Maybe Text                                        -- $ref (siblings allowed; see Decision Log)
  , _schemaDynamicRef :: Maybe Text                                 -- $dynamicRef
  , _schemaDynamicAnchor :: Maybe Text                              -- $dynamicAnchor
```

These derive to the *plain* keys `id`, `anchor`, `defs`, `ref`, `dynamicRef`, `dynamicAnchor`
under the generic rule — which is exactly what the M0 rename table maps to/from the `$` forms.

**Edit 2 — wire `ToJSON Schema` through the rename pass.** Change the `ToJSON Schema` instance
(`src/Data/OpenApi/Internal.hs:1336-1338`) to post-process the generic `Value`:

```haskell
instance ToJSON Schema where
  toJSON = applyKeyRenamesToJSON schemaDollarKeyRenames
         . sopSwaggerGenericToJSONWithOpts
             (mkSwaggerAesonOptions "schema" & saoSubObject ?~ "items")
```

Import `applyKeyRenamesToJSON` from `Data.OpenApi.Internal.AesonUtils` (already imported module;
add the name to the import list at `src/Data/OpenApi/Internal.hs:40-41`). Define
`schemaDollarKeyRenames` (the table from M0 step (c)) near the instance.

If `Schema` also defines `toEncoding` anywhere, note that `applyKeyRenamesToJSON` operates on a
materialized `Value`; the simplest correct approach is to *not* provide a hand-rolled
`toEncoding` for `Schema` (let aeson derive it from `toJSON`), so the rename pass always runs.
Confirm `Schema` has no separate `toEncoding` that bypasses `toJSON` (the current instance at
1336-1338 only defines `toJSON`).

**Edit 3 — wire `FromJSON Schema` through the inverse pass.** Change `FromJSON Schema`
(`src/Data/OpenApi/Internal.hs:1498-1506`) so that before the generic parse it renames the `$`
keys back to plain keys:

```haskell
instance FromJSON Schema where
  parseJSON = withObject "Schema" $ \o ->
      fmap nullaryCleanup
        (sopSwaggerGenericParseJSON
           (Object (applyKeyRenamesParseJSON schemaDollarKeyRenames o)))
    where nullaryCleanup = …  -- EP-3's final cleanup, unchanged
```

`applyKeyRenamesParseJSON` moves `"$ref"`→`"ref"`, `"$id"`→`"id"`, etc., so the generic field
parser sees the plain keys its rule expects. Import `applyKeyRenamesParseJSON`. Keep whatever
`nullaryCleanup` EP-3 left (if EP-3 removed it entirely, drop the `fmap nullaryCleanup`).

Important interaction with `referencedParseJSON`: a `Schema` sub-value given as `{"$ref": …}`
alone is decoded by `FromJSON (Referenced Schema)` → `referencedParseJSON`
(`Internal.hs:1564-1575`), which intercepts `$ref` and yields `Ref` (the pure-reference case) —
this path does **not** go through `FromJSON Schema`, so it is unaffected by the rename pass. The
rename pass only matters when a `$ref` (or `$id`, `$defs`, …) appears as a key *inside an inline
`Schema` object* that is being parsed as a `Schema`. That is precisely the 3.1 "siblings"
scenario, and it lands in the `Inline <$> parseJSON js` branch of `referencedParseJSON`
(line 1568), which calls `FromJSON Schema`, which now reads `$ref` into `_schemaRef`. This is the
behavior the Decision Log entry on `$ref`-with-siblings specifies; verify it with the
`{"$id":"…","$ref":"#/…"}` round-trip test.

**Edit 4 — lenses/optics for the new fields.** Same as M1 Edit 6: derived automatically by the
TH splices in `Lens.hs:32` and `Optics.hs:121`. Verify the lenses `schemaId`, `schemaRef`,
`schemaDefs`, `schemaAnchor`, `schemaDynamicRef`, `schemaDynamicAnchor` exist after building.

Acceptance for M2: the `$`-prefixed round-trip tests (see Validation) pass, each producing the
literal `$`-prefixed JSON key.


## Concrete Steps

All commands run from the repository root `/Users/shinzui/Keikaku/hub/haskell/openapi3`.

Confirm EP-3 is complete before starting (the `Schema` record must already have
`_schemaType :: Maybe OpenApiTypeValue`, `Scientific` exclusive bounds, no `_schemaNullable`,
and `OpenApiItems = OpenApiItemsObject | OpenApiItemsBoolean Bool`):

```bash
grep -n '_schemaType ::' src/Data/OpenApi/Internal.hs
grep -n 'OpenApiItemsBoolean\|OpenApiItemsArray' src/Data/OpenApi/Internal.hs
grep -n '_schemaNullable' src/Data/OpenApi/Internal.hs   # expect: no output
```

Expected: the first shows `_schemaType :: Maybe OpenApiTypeValue`; the second shows
`OpenApiItemsBoolean` and *no* `OpenApiItemsArray`; the third prints nothing. If any check fails,
EP-3 is not done — stop and finish EP-3 first.

M0 — add the helper and confirm no regression:

```bash
# After editing src/Data/OpenApi/Internal/AesonUtils.hs (and Aeson/Compat.hs if insertKey is missing)
nix develop -c cabal build all
```

Expected tail:

```text
Building library for openapi3-3.2.5..
…
Linking … (or "Up to date")
```

M1 — add fields, deprecation, build:

```bash
nix develop -c cabal build all 2>&1 | tee /tmp/ep4-m1-build.log
grep -i 'deprecat\|error' /tmp/ep4-m1-build.log
```

Expected: zero lines containing `error`; the only `deprecat` lines refer to `_schemaExample`.

M1/M2 — run the test suite:

```bash
nix develop -c cabal test all 2>&1 | tee /tmp/ep4-test.log
tail -n 20 /tmp/ep4-test.log
```

Expected tail (numbers illustrative):

```text
Finished in 0.0123 seconds
NNN examples, 0 failures
Test suite openapi3-test: PASS
```


## Validation and Acceptance

Acceptance is behavioral: each new keyword survives `decode . encode` and produces the correct
JSON key (especially the `$`-prefixed ones). Add a new spec module
`test/Data/OpenApi/Schema31Spec.hs` and register it in the test-suite `other-modules` of the
`.cabal` file (master-plan IP-5). Use the existing round-trip combinator `(<=>)` from
`test/SpecCommon.hs` (`test/SpecCommon.hs:11-22`), which asserts `toJSON x == js`,
`fromJSON js == Success x`, and three encode/decode round-trips. The module is discovered by
`hspec-discover` because its name ends in `Spec` and it exports `spec :: Spec`.

The required cases (drawn from `OPENAPI31_MIGRATION_PLAN.md` §6.1; type-array is EP-3's, not
repeated here):

`prefixItems` with boolean `items` — JSON, Haskell value, and expected encoded text:

```json
{"prefixItems":[{"type":"string"},{"type":"number"}],"items":false}
```

```haskell
mempty
  { _schemaPrefixItems =
      Just [ Inline (mempty { _schemaType = Just (OpenApiTypeSingle OpenApiString) })
           , Inline (mempty { _schemaType = Just (OpenApiTypeSingle OpenApiNumber) }) ]
  , _schemaItems = Just (OpenApiItemsBoolean False)
  }
```

```text
{"items":false,"prefixItems":[{"type":"string"},{"type":"number"}]}
```

(Key order in the emitted text is whatever the generic walk produces; `(<=>)` compares JSON
values structurally for the round-trip assertions, and the `toJSON x == js` assertion compares
`Value`s, which are order-insensitive for objects. The `items:false` literal is EP-3's
`OpenApiItemsBoolean` machinery; this test confirms it composes with `prefixItems`.)

`if`/`then` conditional:

```json
{"if":{"const":"USA"},"then":{"type":"string"}}
```

```haskell
mempty
  { _schemaIf   = Just (Inline (mempty { _schemaConst = Just (String "USA") }))
  , _schemaThen = Just (Inline (mempty { _schemaType  = Just (OpenApiTypeSingle OpenApiString) }))
  }
```

Expected: `decode . encode` returns the same value, and the emitted object has keys `"if"` and
`"then"` exactly (no `$`, no mangling).

`const`:

```json
{"const":42}
```

```haskell
mempty { _schemaConst = Just (Number 42) }
```

Expected encoded text: `{"const":42}`.

`contains` with `minContains`:

```json
{"contains":{"type":"integer"},"minContains":1}
```

```haskell
mempty
  { _schemaContains    = Just (Inline (mempty { _schemaType = Just (OpenApiTypeSingle OpenApiInteger) }))
  , _schemaMinContains = Just 1
  }
```

`$defs` (a `$`-prefixed key, M2):

```json
{"$defs":{"A":{"type":"string"}}}
```

```haskell
mempty
  { _schemaDefs =
      Just (InsOrdHashMap.fromList
             [ ("A", Inline (mempty { _schemaType = Just (OpenApiTypeSingle OpenApiString) })) ]) }
```

Expected: the emitted object's key is literally `"$defs"` (assert
`toJSON x == object ["$defs" .= …]`); `decode (encode x) == Just x`.

`$id` with sibling `$ref` (the spike's headline case, M2):

```json
{"$id":"https://example/s","$ref":"#/$defs/A"}
```

```haskell
mempty { _schemaId = Just "https://example/s", _schemaRef = Just "#/$defs/A" }
```

Expected: this decodes into an **`Inline`** schema carrying both `_schemaId` and `_schemaRef`
(it does *not* collapse to `Ref`, because the object has sibling keys and the `$ref` value does
not match the `#/components/schemas/` component prefix that `referencedParseJSON` strips). The
emitted object has both literal `$`-prefixed keys. Write this as a direct
`decode`/`encode`/`toJSON` assertion rather than `(<=>)` if you want to assert the `Inline`
wrapper explicitly:

```haskell
it "$id + sibling $ref stays Inline and round-trips" $ do
  let s = mempty { _schemaId = Just "https://example/s", _schemaRef = Just "#/$defs/A" }
  toJSON s `shouldBe` object [ "$id" .= ("https://example/s" :: Text)
                             , "$ref" .= ("#/$defs/A" :: Text) ]
  (decode (encode s) :: Maybe Schema) `shouldBe` Just s
  -- As a sub-schema, it parses to Inline (not Ref):
  (decode (encode s) :: Maybe (Referenced Schema)) `shouldBe` Just (Inline s)
```

Bare boolean sub-schema (the boolean-schema decision, read direction):

```json
{"contains":true,"unevaluatedItems":false}
```

```haskell
mempty
  { _schemaContains        = Just (Inline mempty)
  , _schemaUnevaluatedItems = Just (Inline (mempty { _schemaNot = Just (Inline mempty) }))
  }
```

Expected: decoding the JSON above produces this value (the `true` becomes the empty inline
schema; the `false` becomes `{"not":{}}`). The encode direction re-emits the object forms; assert
on those object forms, not on bare `true`/`false`, per the Decision Log.

Run the suite and read the summary:

```bash
nix develop -c cabal test all 2>&1 | tail -n 20
```

The change is effective beyond compilation when every case above shows `0 failures` and the
`$`-key cases specifically prove the literal `$id`/`$ref`/`$defs` keys appear in the encoded
output. As an extra manual check, in `nix develop -c cabal repl` you can evaluate
`encode (mempty { _schemaConst = Just (Number 42) } :: Schema)` and see `"{\"const\":42}"`, and
`encode (mempty { _schemaDefs = Just (InsOrdHashMap.fromList [("A", Inline mempty)]) } :: Schema)`
and see the `"$defs"` key.


## Idempotence and Recovery

Every edit in this plan is additive to the `Schema` record and the serialization layer; re-running
`nix develop -c cabal build all` and `nix develop -c cabal test all` is safe and repeatable. The
`applyKeyRenamesToJSON` / `applyKeyRenamesParseJSON` passes are idempotent in the sense that each
is applied exactly once per direction (once in `toJSON`, once in `FromJSON`); applying the *out*
rename twice would double-rename, so do not call it in both `toJSON` and a separate `toEncoding`
— rely on aeson deriving `toEncoding` from `toJSON` (M2 Edit 2 spells this out).

If a build fails because EP-3's final `Schema` field order differs from what you assumed,
re-open `src/Data/OpenApi/Internal.hs`, move your appended fields to the very end of the record
(after EP-3's last field), and rebuild; field order does not affect JSON because both directions
are keyed by name.

If `_schemaExample`'s deprecation pragma breaks a `-Werror` build on a *library-internal* use,
add a narrowly-scoped `{-# OPTIONS_GHC -Wno-deprecations #-}` only to the module that uses it
internally (likely `src/Data/OpenApi/Internal.hs` or the schema generator); never disable the
warning package-wide. To fully roll back M1/M2, `git checkout -- src/Data/OpenApi/Internal.hs
src/Data/OpenApi/Internal/AesonUtils.hs src/Data/OpenApi/Aeson/Compat.hs` and delete
`test/Data/OpenApi/Schema31Spec.hs`; the derived lenses/optics disappear automatically because
they come from the TH splices over the (reverted) record.

Do not `git commit` as part of executing this plan; leave the working tree for review.


## Interfaces and Dependencies

Libraries and modules used, and why: `Data.Aeson` (`Value`, `Object`, `object`, `(.=)`,
`withObject`) for JSON; `Generics.SOP` and this library's `Data.OpenApi.Internal.AesonUtils` for
the generic record serialization; `Data.OpenApi.Aeson.Compat` for version-agnostic key
operations (`stringToKey`, `lookupKey`, `deleteKey`, and the new `insertKey`);
`Data.HashMap.Strict.InsOrd.Compat` (`InsOrdHashMap`) for ordered maps (`$defs`,
`dependentSchemas`, `dependentRequired`); `Control.Lens` / `optics` via the existing TH splices
for accessors.

Types and signatures that must exist at the end of each milestone:

End of **M0** — in `src/Data/OpenApi/Internal/AesonUtils.hs`, exported:

```haskell
applyKeyRenamesToJSON   :: [(Text, Text)] -> Value  -> Value
applyKeyRenamesParseJSON :: [(Text, Text)] -> Object -> Object
```

and, in `src/Data/OpenApi/Aeson/Compat.hs` (if not already present), exported:

```haskell
insertKey :: Text -> v -> KeyMap v -> KeyMap v   -- modern aeson branch
-- and the corresponding HashMap.insert in the legacy branch
```

Three finalized Decision Log entries (the `$ref`-with-siblings representation, the
boolean-schema representation, and the `$`-key mechanism name+location).

End of **M1** — the `Schema` record (`src/Data/OpenApi/Internal.hs`) carries the seventeen new
fields listed in the Plan of Work, with types exactly as given (`Maybe Value`,
`Maybe [Referenced Schema]`, `Maybe (Referenced Schema)`, `Maybe Integer`,
`Maybe (InsOrdHashMap Text (Referenced Schema))`, `Maybe (InsOrdHashMap Text [Text])`,
`Maybe AdditionalProperties`, `Maybe Text`, `Maybe [Value]`); `_schemaExample` carries its
`{-# DEPRECATED #-}` pragma; derived lenses `schemaConst`, `schemaPrefixItems`, … exist in
`Data.OpenApi.Lens` and matching optics in `Data.OpenApi.Optics`.

End of **M2** — the `Schema` record carries the six `$`-keyword fields (`_schemaId`,
`_schemaAnchor`, `_schemaDefs`, `_schemaRef`, `_schemaDynamicRef`, `_schemaDynamicAnchor`);
`ToJSON Schema` and `FromJSON Schema` route through `applyKeyRenamesToJSON` /
`applyKeyRenamesParseJSON` with the constant table `schemaDollarKeyRenames`;
`referencedParseJSON` accepts bare `Bool` values; the derived lenses/optics for the six fields
exist.

Integration Point IP-3 (master plan): EP-4 **owns** the canonical `$`-key serialization helper.
Its canonical names are `applyKeyRenamesToJSON` and `applyKeyRenamesParseJSON`, its location is
`src/Data/OpenApi/Internal/AesonUtils.hs`, and the `Schema` rename table is
`schemaDollarKeyRenames` (in `src/Data/OpenApi/Internal.hs`). EP-5 (top-level objects:
`PathItem.$ref`, `webhooks`) must **import** `applyKeyRenamesToJSON` /
`applyKeyRenamesParseJSON` from `Data.OpenApi.Internal.AesonUtils` and supply its own small
rename table (e.g. `[("ref", "$ref")]` for `PathItem`) rather than duplicating the mechanism.
Integration Point IP-2 (master plan): EP-4 only **appends** to the `Schema` record EP-3 defined,
never reorders EP-3's fields, and provides a lens (derived), an optic (derived), and an
`AesonDefaultValue` (existing `Maybe` instance, plus any the build demands) for every new field.


---

Revision note (2026-06-10): Initial full authoring of EP-4 from the skeleton. Filled every
section per `.claude/skills/exec-plan/PLANS.md`. Seeded four Decision Log entries (the
`$ref`-with-siblings representation as `Inline` + `_schemaRef`; boolean-schema representation by
extending decode to canonical `{}`/`{"not":{}}` schemas; the `$`-key mechanism as the exported
post-processing pass `applyKeyRenamesToJSON` / `applyKeyRenamesParseJSON` in
`src/Data/OpenApi/Internal/AesonUtils.hs`; and the `_schemaExample` deprecation). Recorded the
discovered `ToJSON`/`FromJSON` `saoSubObject` mismatch (`"items"` vs the stale `"paramSchema"`)
in Surprises so a future contributor does not "fix" it blindly. Grounded every file:line citation
against the current tree (`Schema` record 619-665, `Referenced` 952-955, `AdditionalProperties`
962-965, `OpenApiItems` 586-589, `ToJSON Schema` 1336-1338, `FromJSON Schema` 1498-1506,
`referencedParseJSON` 1564-1575, the generic machinery in `AesonUtils.hs`, the TH lens/optic
splices at `Lens.hs:32` and `Optics.hs:121`). Why: the plan must let a novice implement EP-4
end-to-end from this file plus the current working tree and EP-3's output, with no other context.
