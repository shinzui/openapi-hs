---
id: 6
slug: openapi-3-1-schema-validation
title: "OpenAPI 3.1 Schema Validation"
kind: exec-plan
created_at: 2026-06-11T03:47:52Z
master_plan: "docs/masterplans/1-openapi-3-1-support-and-project-modernization.md"
---

# OpenAPI 3.1 Schema Validation

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

This repository is `openapi3` (a fork being modernized toward the name `openapi-hs`), a Haskell
library that decodes, encodes, manipulates, **and validates** OpenAPI specification documents.
"Validation" here means a single specific capability: given a `Schema` (a description of the
shape JSON data should take) and a concrete JSON `Value`, the library tells you whether that
value conforms to that schema, returning a list of human-readable error strings (an empty list
means "valid"). That capability lives in the function
`validateJSON :: Definitions Schema -> Schema -> Value -> [ValidationError]` and its siblings in
`src/Data/OpenApi/Schema/Validation.hs` (the public module) and
`src/Data/OpenApi/Internal/Schema/Validation.hs` (the engine).

OpenAPI 3.1 adopts the JSON Schema 2020-12 vocabulary, which adds and changes several keywords
that control validation. Today the engine validates only the OpenAPI 3.0 keyword set. This plan
teaches the engine the 3.1 keyword semantics so that, after the change, a user can do things they
cannot do now:

First, a user can validate a value against a schema whose `type` is an **array** of type names,
for example `{"type":["string","null"]}` ("a string, or JSON `null`"). The string `"hi"` passes;
JSON `null` passes; the number `3` fails. Today the engine assumes `type` is a single type and
cannot express "matches any of these types".

Second, a user can validate against the **numeric** `exclusiveMaximum` / `exclusiveMinimum`
keywords. In 3.1 these are numbers carrying a strict bound (value must be strictly less than /
greater than the number), and they are **independent** of `maximum` / `minimum` (which mean
"≤" / "≥"). A schema may legally carry both `maximum` and `exclusiveMaximum`. Today the engine
reads `exclusiveMaximum` as a boolean modifier on `maximum`, which is the 3.0 meaning and no
longer compiles once the field type changes.

Third, a user can validate arrays against **`prefixItems`** (tuple validation: the *i*-th array
element must match the *i*-th prefix schema) together with `items` (now a single schema or the
boolean `false`, which forbids any element beyond the prefix). The classic example
`{"prefixItems":[{"type":"string"},{"type":"number"}],"items":false}` accepts `["a",1]` and
rejects `["a",1,true]` (extra item) and `[1,"a"]` (wrong element types).

Fourth, a user can validate **`contains`** / **`minContains`** / **`maxContains`** (at least
`minContains`, at most `maxContains`, array elements must match the `contains` schema),
**`if`/`then`/`else`** conditional validation, and **`const`** (the value must equal a fixed JSON
value exactly).

Fifth, the plan makes an honest, documented decision about **`unevaluatedProperties`** and
**`unevaluatedItems`**, the two hardest 3.1 keywords. Their correct semantics depend on which
properties/items were already "evaluated" by adjacent keywords (`properties`, `prefixItems`,
`allOf`, `if`/`then`/`else`, …). Implementing that faithfully requires threading annotation
results through the whole validation walk — a redesign out of proportion to this plan. The plan
therefore implements a **best-effort, clearly-documented** version and records the limitation,
rather than pretending to do nothing or pretending to be complete.

You can see all of this working by running `nix develop -c cabal test all` from the repository
root and observing the new validation tests in
`test/Data/OpenApi/Schema/ValidationSpec.hs` pass: each new keyword has a test where a conforming
value yields `[]` (no errors) and a non-conforming value yields a non-empty error list.

This is **EP-6** in the master plan
`docs/masterplans/1-openapi-3-1-support-and-project-modernization.md`. It implements the
migration plan's Milestone 5 / Phase 5.1 ("update Schema validation") from
`OPENAPI31_MIGRATION_PLAN.md` at the repository root. EP-6 **hard-depends on EP-3**
(`docs/plans/3-openapi-3-1-core-schema-type-changes.md`, which introduces `OpenApiTypeValue`,
numeric exclusive bounds, and `OpenApiItemsBoolean`) and **on EP-4**
(`docs/plans/4-openapi-3-1-json-schema-fields-and-reference-keywords.md`, which adds the
`Schema` fields `_schemaPrefixItems`, `_schemaConst`, `_schemaIf`/`_schemaThen`/`_schemaElse`,
`_schemaContains`, `_schemaMinContains`, `_schemaMaxContains`, `_schemaUnevaluatedProperties`,
`_schemaUnevaluatedItems`). EP-6 **consumes** the final `Schema` shape read-only: it adds
validation logic and tests and must **not** change the `Schema` record, the lenses, the optics,
or the JSON instances. See the precondition check in Concrete Steps; if a field this plan needs
is missing, EP-3 or EP-4 is incomplete and must be finished first.


## Progress

This checklist is the authoritative current state. Update it at every stopping point; split a
partially done item into a done half and a remaining half rather than leaving it ambiguous.

- [x] M1 (2026-06-10): `schemaTypes` + the `validateSchemaType`/`validateParamSchemaType`/`showType` "matches-any" rewrite and the independent numeric `validateNumber` were **already landed by EP-3**. EP-6 verified the semantics (type arrays as union, `OpenApiNull` ↔ `null`, exclusive bounds independent) and added behavior tests.
- [x] M1 (2026-06-10): tests for type arrays (`"hi"`/`null` pass, `3` fails) and exclusive bounds (`50` passes, `0`/`100` fail).
- [x] M2 (2026-06-10): `prefixItems` positional validation in `validateArray` (legacy whole-array `items` check guarded to run only when `prefixItems` is absent; trailing elements governed by `items`/`OpenApiItemsBoolean False`).
- [x] M2 (2026-06-10): `contains`/`minContains`/`maxContains` counting (via `runValidation` per element, `minContains` default 1, `maxContains` optional).
- [x] M2 (2026-06-10): tests for `prefixItems`+`items:false` and `contains`+`minContains`/`maxContains`.
- [x] M3 (2026-06-10): `validateConditional` (`if` is a non-failing switch via `runValidation`) and `validateConst` (exact `Value` equality), both wired into `validateWithSchema`.
- [x] M3 (2026-06-10): tests for `if`/`then` (scalar form — see Surprises) and `const`.
- [x] M4 (2026-06-10): best-effort `validateUnevaluated` (local-only `unevaluatedProperties`/`unevaluatedItems`) with the documented `TODO(annotations)` limitation; tests for the local cases.
- [x] All milestones (2026-06-10): `cabal build all` + `cabal test all` green — 441 examples, 0 failures, 5 pending.


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence (test output is ideal).

- Discovery (planning, 2026-06-10): The engine has **two** type-checking entry points that both
  pattern-match `sch ^. type_` against single `OpenApiType` constructors:
  `validateSchemaType` (`src/Data/OpenApi/Internal/Schema/Validation.hs:469-501`) and
  `validateParamSchemaType` (`:503-516`), plus `showType` (`:518-525`). All three break the
  moment EP-3 changes `_schemaType` to `Maybe OpenApiTypeValue`. EP-3's own plan already
  rewrites these (see `docs/plans/3-openapi-3-1-core-schema-type-changes.md`, Milestone 1
  step 8, which introduces a `schemaTypes` normalizer). If EP-3 has already landed that rewrite,
  EP-6's M1 type-array work is *verification plus tests* rather than fresh code — confirm by
  reading the current `validateSchemaType` before editing. This plan is written to be correct
  whether or not EP-3 pre-did the read-site rewrite.

- Discovery (planning, 2026-06-10): `validateNumber`
  (`src/Data/OpenApi/Internal/Schema/Validation.hs:306-321`) currently reads
  `Just True == sch ^. exclusiveMaximum` / `exclusiveMinimum` — i.e. it treats the exclusive
  bounds as *booleans that modify* `maximum` / `minimum`. EP-3 changes those fields to
  `Maybe Scientific`, so `Just True ==` will not even type-check. EP-3's Milestone 2 step 5
  already specifies the rewrite to independent numeric checks; EP-6 owns making sure the final
  shape is correct and tested. Again, this plan is written to land the correct behavior whether
  or not EP-3 pre-did it.

- Discovery (planning, 2026-06-10): `validateArray`
  (`src/Data/OpenApi/Internal/Schema/Validation.hs:340-362`) pattern-matches the *old*
  `OpenApiItemsArray` constructor (line 352) for tuple validation. EP-3 removes that constructor
  (tuples move to `prefixItems`) and replaces it with `OpenApiItemsBoolean`. So `validateArray`
  must already have been adjusted by EP-3 (its Milestone 3 step 9 rewrites that branch to
  `OpenApiItemsBoolean b -> when (not b && not (Vector.null xs)) (invalid …)`). EP-6 builds
  `prefixItems` and `contains` validation *on top of* that EP-3-adjusted `validateArray`.

- Discovery (M1 implementation, 2026-06-10): **EP-3 pre-landed all of M1.** The `schemaTypes`
  normalizer, the "matches-any" `validateSchemaType`/`validateParamSchemaType`, and the
  independent-numeric `validateNumber` already existed (committed by EP-3). M1 became
  verification + tests, exactly as the plan's Discovery notes anticipated.

- Discovery (M3/M4 implementation, 2026-06-10): **this engine's `validateObject` is strict, and it
  does not validate `not`.** Two consequences for the tests:
  (1) The plan's object-based `if country=USA then postal_code` test fails because `validateObject`
  rejects any property not listed in `properties` when `additionalProperties` is absent
  (`"property … is found in JSON value, but it is not mentioned in Swagger schema"`). Rewrote the
  `if/then` test to a **scalar** form ("if the value is a string, then it must be `const "yes"`")
  which exercises the if/then switch without tripping object strictness or the no-op pattern checker.
  (2) The plan's `unevaluatedItems` test used an always-false `{not:{}}` sub-schema, but the engine
  never validated `not` (a pre-existing 3.0-era gap, out of EP-6 scope), so `{not:{}}` accepts
  everything. Rewrote the test's `unevaluatedItems` schema to `{type:string}` so a trailing non-string
  element is genuinely rejected. Implementing `not`/`anyOf` validation is noted as future work but
  is outside EP-6's keyword list.

- Discovery (test placement, 2026-06-10): the EP-6 tests went into a **new** module
  `test/Data/OpenApi/Schema/Validation31Spec.hs` (registered in the cabal test-suite) rather than
  extending `ValidationSpec` as the Decision Log planned. Reason: the new tests need
  `OverloadedStrings`/`OverloadedLists`, and turning those on module-wide in `ValidationSpec` broke
  its existing literals' defaulting (`toJSON "red"` became ambiguous). A separate module with its own
  pragmas is cleaner and avoids touching the existing suite.

(Add further entries here as implementation proceeds.)


## Decision Log

Record every decision made while working on the plan.

- Decision: Treat `exclusiveMaximum` and `exclusiveMinimum` as **independent** numeric keywords,
  validated separately from `maximum` / `minimum`, per migration plan §1.1.2 coexistence note.
  Rationale: In JSON Schema 2020-12 / OpenAPI 3.1, `exclusiveMaximum` is a number meaning "value
  must be strictly less than this", `maximum` is a number meaning "value must be ≤ this", and a
  schema may legally carry both. The 3.0 reading (a boolean modifying `maximum`) no longer
  applies and no longer compiles once EP-3 changes the field type to `Maybe Scientific`. So the
  engine performs, for a numeric value `n`: a non-strict `maximum` check (`n > m → fail`), a
  strict `exclusiveMaximum` check (`n >= e → fail`), and the symmetric pair for the minimum
  side, each fired only when its keyword is present.
  Date: 2026-06-10

- Decision: Validate a `type` array as **"matches any"** — a value is valid against
  `OpenApiTypeArray ts` if it matches *at least one* primitive type in `ts`; against
  `OpenApiTypeSingle t` if it matches `t`; and against an absent `type` by falling back to the
  value's natural JSON shape (the pre-existing behavior). `OpenApiNull` matches JSON `null`.
  Rationale: JSON Schema 2020-12 defines `type: [..]` as a union — the instance is valid if its
  JSON type is any of the listed names. "Matches any" is the standard semantics and is the
  minimal change to the existing single-type dispatch.
  Date: 2026-06-10

- Decision (the central scoping decision): For `unevaluatedProperties` and `unevaluatedItems`,
  implement a **best-effort** version with a clearly documented limitation, **not** the full
  annotation-tracking semantics, and **not** a silent no-op.
  Rationale: The faithful semantics of these two keywords require, before evaluating them,
  knowing exactly which object properties and which array items were already "successfully
  evaluated" by *adjacent and in-place applicator* keywords — `properties`, `patternProperties`,
  `additionalProperties`, `prefixItems`, `items`, `contains`, **and** the sub-schemas reached
  through `allOf`, `anyOf`, `oneOf`, `if`/`then`/`else`, and `$ref`. JSON Schema calls these
  results "annotations", and a conforming implementation must collect them across the whole
  sub-schema tree and only then let `unevaluated*` apply to whatever was left unevaluated. This
  library's validation engine (the `Validation` profunctor in
  `src/Data/OpenApi/Internal/Schema/Validation.hs`) returns only a pass/fail plus error strings
  (`data Result a = Failed [ValidationError] | Passed a`); it does **not** thread an annotation
  set through the walk. Retrofitting annotation collection is a substantial redesign of the
  monad and every `validate*` function — far larger than the rest of EP-6 combined, and not
  required by the master plan's EP-6 line ("Validate type arrays, `prefixItems`,
  `contains`/`minContains`/`maxContains`, `if`/`then`/`else`, `const`" — note `unevaluated*` is
  absent from that line). We therefore scope EP-6 to implement type arrays, exclusive bounds,
  `prefixItems`, `contains*`, `if`/`then`/`else`, and `const` **fully**, and to implement a
  **best-effort** `unevaluated*`: we evaluate `unevaluatedProperties` against only the properties
  that the *current schema's own* `properties` / `additionalProperties` did not cover, and
  `unevaluatedItems` against only the items beyond the current schema's own `prefixItems` length
  (i.e. we treat "evaluated" as "evaluated by *this* schema object's local array/object
  applicators", ignoring properties/items evaluated through `allOf`/`if`/`$ref`). When a schema
  uses `unevaluated*` together with those cross-schema applicators, the best-effort result may be
  **stricter** than the spec (it may report an item/property as unevaluated that a fully
  conformant validator would consider evaluated). This limitation is documented in a Haddock
  comment on the new functions and in this Decision Log. The recommendation carried to the
  master plan is: **best-effort/deferred** — ship the local-only approximation, leave a
  `TODO(annotations)` marker, and treat full annotation-aware `unevaluated*` as future work.
  Date: 2026-06-10

- Decision: Add the new tests to the existing `test/Data/OpenApi/Schema/ValidationSpec.hs` module
  rather than creating a new spec module.
  Rationale: `ValidationSpec` is already registered in the test-suite `other-modules` of
  `openapi3.cabal` (the `test-suite spec` stanza) and is the established home for validation
  tests; extending it avoids a new cabal registration and matches the master plan's Integration
  Point IP-5 expectation with the least churn. The new tests use `validateJSON` directly against
  hand-built `Schema` values, the same `Data.OpenApi.Internal`/lens style the engine itself uses.
  Date: 2026-06-10


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose.

**Completed 2026-06-10.** The validation engine now understands the 3.1 keyword set:

- Type arrays validate as a union (`["string","null"]` accepts a string and `null`, rejects a
  number) and numeric exclusive bounds are independent strict checks (both pre-landed by EP-3,
  verified + tested here).
- `prefixItems` validates positionally with `items`/`items:false` governing trailing elements;
  `contains`/`minContains`/`maxContains` count matches.
- `if`/`then`/`else` switches sub-schemas without `if` itself failing; `const` enforces exact
  `Value` equality.
- `unevaluatedProperties`/`unevaluatedItems` are best-effort (local-only) with a documented
  `TODO(annotations)` limitation.

`cabal build all` + `cabal test all`: 441 examples, 0 failures, 5 pending. IP-2 honoured (no
`Schema`/lens/optic/JSON-instance changes — engine + tests only).

**Gaps / future work:**
- `unevaluated*` ignores cross-schema evaluation through `allOf`/`anyOf`/`oneOf`/`if`/`$ref`
  (annotation tracking), so it can be stricter than a fully-conformant validator. Documented in
  the function Haddock and the Decision Log.
- The engine still does not validate `not` or `anyOf` (pre-existing gaps, outside EP-6's keyword
  list) — noted in Surprises as future work.


## Context and Orientation

You are working in a Haskell library. Assume no prior knowledge of it. Build with
`nix develop -c cabal build all` and test with `nix develop -c cabal test all`, both run from the
repository root `/Users/shinzui/Keikaku/hub/haskell/openapi3`. (Plain `cabal` works too if a
GHC 9.12.x toolchain is on `PATH`.)

The files that matter for EP-6, by full path:

`src/Data/OpenApi/Internal/Schema/Validation.hs` is the **validation engine** and the primary
file you edit. Read it in full before editing. Its design, in plain language:

- A *validation* is a value of type `Validation s a`, which is a function
  `Config -> s -> Result a` where `s` is "the schema currently in focus" and
  `Result a = Failed [ValidationError] | Passed a`. `ValidationError` is just `String`. The
  `Applicative`/`Alternative`/`Monad` instances accumulate errors: `Failed xs <*> Failed ys =
  Failed (xs <> ys)` (collect both), and `<|>` is "first success wins, else the second" — that is
  how `oneOf` and "matches any type" are expressed.
- `withSchema :: (s -> Validation s a) -> Validation s a` gives you the schema in focus.
  `withConfig` gives you the `Config` (which holds `configDefinitions :: Definitions Schema`,
  the named-schema table used to resolve `$ref`, and the pattern checker).
- `check :: Lens' s (Maybe a) -> (a -> Validation s ()) -> Validation s ()` runs a checker only
  when an optional schema field is present (if the field is `Nothing`, it is vacuously valid).
  `checkMissing missing l g` is the same but runs `missing` when the field is absent. These two
  combinators are how every keyword is validated: `check maximum_ $ \m -> …`,
  `check items $ \case …`, and so on. You will add `check const_ …`, `check prefixItems …`,
  `check contains …`, `check if_ …`, `check unevaluatedItems …`, etc. — using the **lenses that
  EP-4 generated** for the new fields.
- `validateWithSchemaRef :: Referenced Schema -> Value -> Validation s ()` validates a value
  against a possibly-`$ref`'d sub-schema: `Ref ref` is resolved through `configDefinitions`;
  `Inline s` validates against `s` directly. This is the building block for every keyword whose
  value is a sub-schema (`prefixItems`, `contains`, `if`, `then`, `else`, `unevaluatedItems`,
  `propertyNames`, …).
- `validateWithSchema :: Value -> Validation Schema ()` is the top-level walk for a value against
  the focused schema. Today it is exactly:

  ```haskell
  validateWithSchema val = do
    validateSchemaType val
    validateEnum val
  ```

  `validateSchemaType` dispatches on `oneOf` / `allOf` and then on `(type, value-shape)` to one
  of `validateNumber` / `validateString` / `validateArray` / `validateObject` / `validateInteger`.
  **You will append new keyword checks to `validateWithSchema`** (for the keywords that are not
  tied to a specific value shape — `const`, `if`/`then`/`else`) and **extend the shape-specific
  validators** (`validateArray` for `prefixItems`/`contains*`/`unevaluatedItems`, `validateObject`
  for `unevaluatedProperties`).
- `validateNumber` (`:306-321`) validates `maximum`/`minimum`/`multipleOf` and (today) the
  boolean exclusive bounds. `validateArray` (`:340-362`) validates
  `maxItems`/`minItems`/`items`/`uniqueItems`. `validateObject` (`:364-414`) validates
  `discriminator`/`maxProperties`/`minProperties`/`required`/`properties`/`additionalProperties`.
  `validateEnum` (`:416-420`) validates `enum`. `validateSchemaType` (`:469-501`) is the type
  dispatcher; `validateParamSchemaType` (`:503-516`) is the parameter-schema variant; `showType`
  (`:518-525`) renders the "expected JSON value of type …" message.

`src/Data/OpenApi/Schema/Validation.hs` is the **public wrapper**: it re-exports
`validateJSON`, `validateJSONWithPatternChecker`, `validateToJSON`, etc. from the engine module.
You do not need to change it unless you want to export a new helper; EP-6 adds no new public
function, only new behavior inside existing ones, so this file is left as-is.

`src/Data/OpenApi/Lens.hs` provides the lenses the engine uses (`maximum_`, `minimum_`, `items`,
`enum_`, `type_`, `properties`, `required`, `additionalProperties`, `oneOf`, `allOf`, …). EP-4
**already generated** lenses for the new fields via `makeLensesWith swaggerFieldRules ''Schema`:
`prefixItems`, `const_` (the lens for `_schemaConst`; note the trailing underscore convention the
library uses for lens names that would otherwise clash with a Prelude name — verify the actual
generated name, see below), `contains`, `minContains`, `maxContains`, `if_`, `then_`, `else_`,
`unevaluatedProperties`, `unevaluatedItems`. **You consume these; you do not author them.**

`src/Data/OpenApi/Schema/Generator.hs` is the property-based **generator** (generate a value from
a schema, then validate it). It is read-only context for EP-6; do not change it. Note that it
matches `OpenApiItemsArray` (line 68) — EP-3 will have already rewritten that branch to the
`OpenApiItemsBoolean` shape, so by the time EP-6 runs, `Generator.hs` compiles. EP-6 does not
extend the generator to emit the new keywords (that would be valuable future work, but is out of
EP-6 scope).

`test/Data/OpenApi/Schema/ValidationSpec.hs` is the **test module** you extend. Read it before
editing. Its conventions: it uses `hspec` (`describe`/`it`/`prop`), the helpers
`shouldValidate :: (ToJSON a, ToSchema a) => Proxy a -> a -> Bool`
(`validateToJSON x == []`) and
`shouldNotValidate :: ToSchema a => (a -> Value) -> a -> Bool`
(`not . null . validateJSON defs sch . f`). The module is auto-discovered by `hspec-discover`
(`test/Spec.hs` is just `{-# OPTIONS_GHC -F -pgmF hspec-discover #-}`) **and** is listed in
`openapi3.cabal`'s `test-suite spec` `other-modules` (so no cabal edit is needed when you add
tests to it; a cabal edit *would* be needed only if you added a brand-new `*Spec.hs` module). EP-6
adds **example-based** tests that build a `Schema` directly and call `validateJSON mempty schema
value`, asserting the returned `[ValidationError]` is `[]` (pass) or non-empty (fail). This is the
most direct way to test a single keyword: it does not require a `ToSchema` instance.

`test/SpecCommon.hs` provides round-trip JSON helpers (`isSubJSON`, `(<=>)`); EP-6 does not need
them but they are available.

The data types you will reference (all from `Data.OpenApi.Internal`, re-exported by
`Data.OpenApi`):

- `Schema` — the record. After EP-3+EP-4 it carries `_schemaType :: Maybe OpenApiTypeValue`,
  `_schemaExclusiveMaximum :: Maybe Scientific`, `_schemaExclusiveMinimum :: Maybe Scientific`,
  `_schemaItems :: Maybe OpenApiItems`, `_schemaPrefixItems :: Maybe [Referenced Schema]`,
  `_schemaConst :: Maybe Value`, `_schemaContains :: Maybe (Referenced Schema)`,
  `_schemaMinContains :: Maybe Integer`, `_schemaMaxContains :: Maybe Integer`,
  `_schemaIf :: Maybe (Referenced Schema)`, `_schemaThen :: Maybe (Referenced Schema)`,
  `_schemaElse :: Maybe (Referenced Schema)`,
  `_schemaUnevaluatedProperties :: Maybe AdditionalProperties`,
  `_schemaUnevaluatedItems :: Maybe (Referenced Schema)`. `Schema` has `Monoid`/`Semigroup`
  instances, so `mempty` is a valid empty schema and `mempty { _schemaConst = Just … }` builds a
  minimal one.
- `OpenApiTypeValue = OpenApiTypeSingle OpenApiType | OpenApiTypeArray [OpenApiType]` (from EP-3).
- `OpenApiType` — the seven primitives `OpenApiString`, `OpenApiNumber`, `OpenApiInteger`,
  `OpenApiBoolean`, `OpenApiArray`, `OpenApiObject`, `OpenApiNull`.
- `OpenApiItems = OpenApiItemsObject (Referenced Schema) | OpenApiItemsBoolean Bool` (from EP-3).
- `Referenced a = Ref Reference | Inline a`; `AdditionalProperties =
  AdditionalPropertiesAllowed Bool | AdditionalPropertiesSchema (Referenced Schema)`.
- `Value` (from `Data.Aeson`) — JSON values; `Number`, `String`, `Bool`, `Array` (a
  `Data.Vector.Vector Value`), `Object`, `Null`. `Value` has an `Eq` instance, which is exactly
  what `const` validation needs.


## Plan of Work

The work is four milestones, each independently buildable and testable, each adding validation
for a coherent group of keywords plus its passing/failing tests. Do them in order. For each
keyword the relevant pieces below name (a) the JSON Schema 2020-12 semantics in plain language,
(b) the exact function in `src/Data/OpenApi/Internal/Schema/Validation.hs` to extend and the
branch to add, and (c) the test to add in `test/Data/OpenApi/Schema/ValidationSpec.hs`.

A note on lens names: the library generates lenses with `makeLensesWith swaggerFieldRules`, which
strips the `_schema` prefix and lower-cases. For most fields the lens is the obvious name
(`prefixItems`, `contains`, `minContains`, `maxContains`, `unevaluatedItems`,
`unevaluatedProperties`). For fields whose stripped name collides with a `Prelude`/`base`
identifier the library appends an underscore (it already does this for `maximum_`, `minimum_`,
`enum_`, `type_`). So expect `const_` (since `const` is in `Prelude`) and check whether `if_`,
`then_`, `else_` are generated with or without the underscore — `if`/`then`/`else` are reserved
*keywords*, so the field `_schemaIf` cannot generate a lens literally named `if`; EP-4's lens
derivation will have produced `if_`/`then_`/`else_` (verify the exact spelling once EP-4 lands by
`grep -n 'if_\|then_\|else_\|const_' src/Data/OpenApi/Lens.hs` or by `:t` in `cabal repl`). The
plan below writes `const_`, `if_`, `then_`, `else_`; if the real names differ, substitute them and
record it in Surprises.


### Milestone 1 — Type arrays and numeric exclusive bounds

Scope: make the type dispatcher accept `type` arrays ("matches any") and make the numeric
validator treat `exclusiveMaximum`/`exclusiveMinimum` as independent strict numeric bounds. Much
of the *mechanical* rewrite here is owned by EP-3 (because the field-type changes break
compilation); EP-6 ensures the **semantics** are correct and adds the validation-behavior tests.
What exists after M1: validating `"hi"` and `null` against `{"type":["string","null"]}` returns
`[]`, validating `3` against it returns a non-empty error; validating `50` against
`{"exclusiveMinimum":0,"exclusiveMaximum":100}` returns `[]`, while `0` and `100` each return a
non-empty error. Commands: `nix develop -c cabal build all` then `nix develop -c cabal test all`.

**Type arrays — semantics.** In JSON Schema 2020-12, `type` may be a single type name
(`"string"`) or an array of names (`["string","null"]`). For an array, the instance is valid (as
far as `type` is concerned) if its JSON type matches **any** name in the array. `"null"` matches
the JSON literal `null`. A single name behaves as a one-element array. An absent `type` imposes no
type constraint (the value is then validated by whatever keywords are present, dispatched by the
value's natural shape — the engine's existing `(Nothing, <shape>)` fallback rows).

**Type arrays — function and branch.** Extend `validateSchemaType` (and its parameter-schema twin
`validateParamSchemaType`, plus `showType`) in
`src/Data/OpenApi/Internal/Schema/Validation.hs`. Add a normalizer near the top of the file:

```haskell
-- | The list of primitive types a schema's @type@ permits. An absent @type@
--   yields the empty list, signalling "no type constraint" so callers fall
--   back to validating by the value's natural JSON shape. A single type yields
--   a singleton; a @type@ array yields its element list.
schemaTypes :: Schema -> [OpenApiType]
schemaTypes sch = case sch ^. type_ of
  Nothing                    -> []
  Just (OpenApiTypeSingle t) -> [t]
  Just (OpenApiTypeArray ts) -> ts
```

Then rewrite the `_ ->` (non-`oneOf`/`allOf`) tail of `validateSchemaType` so that, instead of
matching `(sch ^. type_, val)` against single-constructor rows, it validates the value against the
schema's permitted types with "matches any" semantics. Concretely:

```haskell
    _ ->
      case schemaTypes sch of
        []  -> validateByShape val                 -- no type keyword: dispatch on value shape
        tys ->
          -- "matches any": pass if the value validates under at least one listed type.
          -- Each per-type validation either Passes () or Fails; <|> keeps the first Pass.
          let attempts = map (\t -> validateAsType t val) tys
          in case attempts of
               [] -> validateByShape val
               _  -> foldr1 (<|>) attempts
                       <|> invalid ("expected JSON value of one of types "
                                     ++ show tys ++ " but got " ++ showValueType val)
```

where `validateAsType :: OpenApiType -> Value -> Validation Schema ()` is the per-type body
factored out of the existing single-type rows (each row's right-hand side: `OpenApiNull`+`Null`
→ `valid`; `OpenApiBoolean`+`Bool _` → `valid`; `OpenApiInteger`+`Number n` → `validateInteger n`;
`OpenApiNumber`+`Number n` → `validateNumber n`; `OpenApiString`+`String s` → `validateString s`;
`OpenApiArray`+`Array xs` → `validateArray xs`; `OpenApiObject`+`Object o` → `validateObject o`;
any other `(type, value)` pairing → `invalid "expected …"`), and `validateByShape` is the existing
`(Nothing, <shape>)` fallback. `showValueType` is `showType` specialized to render the value's
actual JSON type for the error message. **If EP-3 already landed a `schemaTypes`-based rewrite of
these functions (per its Milestone 1 step 8), this milestone's type-array code is already present:
verify it implements "matches any" and that `OpenApiNull` matches `Null`, then just add the tests
below.** The crucial behavioral requirement EP-6 owns: a `type` array must validate as a union,
and `OpenApiNull` ↔ `null`.

**Numeric exclusive bounds — semantics.** In 3.1, `maximum` (number) means "value ≤ this";
`exclusiveMaximum` (number) means "value < this"; `minimum` means "≥"; `exclusiveMinimum` means
">". They are **independent**: a schema may carry both `maximum` and `exclusiveMaximum`, and each
is checked on its own. (In 3.0, `exclusiveMaximum` was a boolean toggling `maximum` from "≤" to
"<"; that meaning is gone.)

**Numeric exclusive bounds — function and branch.** Rewrite `validateNumber` in
`src/Data/OpenApi/Internal/Schema/Validation.hs` (currently `:306-321`). Remove the
`exMax`/`exMin` boolean reads. Keep the existing `maximum_`/`minimum_`/`multipleOf` checks as
non-strict, and add two **independent** strict checks via `check`:

```haskell
validateNumber :: Scientific -> Validation Schema ()
validateNumber n = withSchema $ \_sch -> do
  check maximum_ $ \m ->
    when (n > m) $
      invalid ("value " ++ show n ++ " exceeds maximum (should be <=" ++ show m ++ ")")

  check minimum_ $ \m ->
    when (n < m) $
      invalid ("value " ++ show n ++ " falls below minimum (should be >=" ++ show m ++ ")")

  check exclusiveMaximum $ \e ->
    when (n >= e) $
      invalid ("value " ++ show n ++ " is not below exclusive maximum (should be <" ++ show e ++ ")")

  check exclusiveMinimum $ \e ->
    when (n <= e) $
      invalid ("value " ++ show n ++ " is not above exclusive minimum (should be >" ++ show e ++ ")")

  check multipleOf $ \k ->
    when (not (isInteger (n / k))) $
      invalid ("expected a multiple of " ++ show k ++ " but got " ++ show n)
```

After EP-3, `exclusiveMaximum`/`exclusiveMinimum` are lenses onto `Maybe Scientific`, so `check
exclusiveMaximum $ \e -> …` type-checks with `e :: Scientific`. (If EP-3 has already produced this
exact body, verify it and proceed to the tests.)

**M1 tests.** Add to `test/Data/OpenApi/Schema/ValidationSpec.hs` a new `describe "OpenAPI 3.1
keywords"` block (see Validation and Acceptance for the full code). For type arrays: a schema
`mempty { _schemaType = Just (OpenApiTypeArray [OpenApiString, OpenApiNull]) }`; assert
`validateJSON mempty s (String "hi") == []`, `validateJSON mempty s Null == []`, and
`not (null (validateJSON mempty s (Number 3)))`. For exclusive bounds: a schema
`mempty { _schemaExclusiveMinimum = Just 0, _schemaExclusiveMaximum = Just 100,
_schemaType = Just (OpenApiTypeSingle OpenApiNumber) }`; assert `validateJSON mempty s (Number 50)
== []`, and that both `Number 0` and `Number 100` yield a non-empty error list.


### Milestone 2 — `prefixItems` and `contains` / `minContains` / `maxContains`

Scope: extend `validateArray` with positional `prefixItems` validation and `contains` counting.
What exists after M2: validating `["a",1]` against
`{"prefixItems":[{"type":"string"},{"type":"number"}],"items":false}` returns `[]`, while
`["a",1,true]` (extra item with `items:false`) and `[1,"a"]` (wrong element types) return
non-empty errors; validating `[1,2,3]` against `{"contains":{"type":"integer"},"minContains":2}`
returns `[]`, while `["a"]` (zero matches, below `minContains`) returns a non-empty error.
Commands: build then test.

**`prefixItems` — semantics.** `prefixItems` is an array of sub-schemas used for *tuple*
validation: the element at index *i* of the instance array must validate against
`prefixItems[i]`, for each *i* less than both the array length and the `prefixItems` length.
Indices at or beyond `length prefixItems` are then governed by `items`: if `items` is a schema,
every such trailing element must validate against it; if `items` is the boolean `false`
(`OpenApiItemsBoolean False`), **no** trailing elements are allowed (the array must be no longer
than the prefix). `items:true` (`OpenApiItemsBoolean True`) allows any trailing elements.
(`prefixItems` shorter than the array, with no `items`, leaves the trailing elements
unconstrained.)

**`prefixItems` — function and branch.** Extend `validateArray`
(`src/Data/OpenApi/Internal/Schema/Validation.hs:340-362`). After the `maxItems`/`minItems`
checks and **before or alongside** the existing `items` check, add a `check prefixItems` block:

```haskell
  check prefixItems $ \prefixSchemas -> do
    -- Validate each leading element positionally against its prefix schema.
    let prefixLen = length prefixSchemas
        indexed   = zip prefixSchemas (Vector.toList xs)
    sequenceA_ [ validateWithSchemaRef ps x | (ps, x) <- indexed ]
    -- Elements beyond the prefix are governed by `items`.
    withSchema $ \sch -> case sch ^. items of
      Just (OpenApiItemsBoolean False)
        | len > prefixLen ->
            invalid ("array has " ++ show (len - prefixLen)
                      ++ " item(s) beyond prefixItems but items:false forbids them")
      Just (OpenApiItemsObject itemSchema) ->
        traverse_ (validateWithSchemaRef itemSchema)
                  (drop prefixLen (Vector.toList xs))
      _ -> valid   -- items:true or items absent: trailing elements unconstrained here
```

This requires that the existing `check items $ \case …` block **not** also re-validate the
prefix elements against a single `items` schema when `prefixItems` is present. The cleanest
arrangement: guard the existing `items` check so it only runs the "every element against the
single `items` schema" behavior when `prefixItems` is **absent** (because when `prefixItems` is
present, `items` applies only to the *trailing* elements, handled in the block above). Implement
that as: read `sch ^. prefixItems`; if it is `Just _`, skip the legacy whole-array `items` check
(the prefix block already handled `items` for trailing elements); if it is `Nothing`, keep the
existing `items` behavior (`OpenApiItemsObject` validates every element; `OpenApiItemsBoolean
False` forbids any element in a non-empty array — this is EP-3's adjusted branch). Note for the
novice: `len` and `Vector.toList xs` are already in scope in `validateArray` (`len =
Vector.length xs`).

**`contains` / `minContains` / `maxContains` — semantics.** `contains` is a single sub-schema; an
array is valid iff the **count** of elements that validate against `contains` is at least
`minContains` (default 1) and at most `maxContains` (default: unbounded). `minContains: 0` makes
`contains` vacuously satisfiable (an empty array passes). These only constrain the *count*; they
do not require *which* elements match.

**`contains` — function and branch.** Add a `check contains` block to `validateArray`:

```haskell
  check contains $ \containsSchema -> withSchema $ \sch -> do
    -- Count how many elements validate against the contains schema.
    let matches = length
          [ () | x <- Vector.toList xs
               , case runValidationAgainst containsSchema x of
                   []  -> True
                   _   -> False ]
        minC = fromMaybe 1 (fmap fromInteger (sch ^. minContains))
        maxC = fmap fromInteger (sch ^. maxContains)
    when (matches < minC) $
      invalid ("array must contain at least " ++ show minC
                ++ " element(s) matching the `contains` schema, but only "
                ++ show matches ++ " do")
    for_ maxC $ \hi ->
      when (matches > hi) $
        invalid ("array must contain at most " ++ show hi
                  ++ " element(s) matching the `contains` schema, but " ++ show matches
                  ++ " do")
```

`runValidationAgainst :: Referenced Schema -> Value -> [ValidationError]` is a small local helper
that runs `validateWithSchemaRef` against a single value and extracts the error list, used purely
to *count* matches without aborting the whole validation:

```haskell
runValidationAgainst :: Referenced Schema -> Value -> Validation s [ValidationError]
runValidationAgainst ref x = withConfig $ \cfg -> withSchema $ \_s ->
  case runValidation (validateWithSchemaRef ref x) cfg (error "unused schema focus") of
    Failed es -> pure es
    Passed _  -> pure []
```

Because `validateWithSchemaRef` re-focuses the schema for the sub-schema (`sub sch …` / resolves
the `Ref`), the outer schema focus is not read — but to be safe and avoid a partial `error`, the
implementer should instead thread the *current* schema as the focus: write the counting loop
inside a `withSchema $ \sch -> …` and pass `sch` as the focus to `runValidation`. The exact, safe
form to use:

```haskell
  check contains $ \containsSchema -> withConfig $ \cfg -> withSchema $ \sch -> do
    let matchesElem x =
          case runValidation (validateWithSchemaRef containsSchema x) cfg sch of
            Failed _ -> False
            Passed _ -> True
        matches = length (filter matchesElem (Vector.toList xs))
        minC = maybe 1 fromInteger (sch ^. minContains)
        maxC = fmap fromInteger (sch ^. maxContains)
    when (matches < minC) $ invalid ("array must contain at least " ++ show minC
       ++ " matching element(s), found " ++ show matches)
    for_ maxC $ \hi -> when (matches > hi) $
      invalid ("array must contain at most " ++ show hi
        ++ " matching element(s), found " ++ show matches)
```

This is preferred over the `runValidationAgainst` helper above; use this in-line form. (`for_` is
already imported as `Data.Foldable.for_`; `fromMaybe`/`maybe` and `runValidation` are in scope.)

**M2 tests.** Add `prefixItems`+`items:false` tests: schema
`mempty { _schemaPrefixItems = Just [ Inline (mempty { _schemaType = Just (OpenApiTypeSingle
OpenApiString) }), Inline (mempty { _schemaType = Just (OpenApiTypeSingle OpenApiNumber) }) ],
_schemaItems = Just (OpenApiItemsBoolean False), _schemaType = Just (OpenApiTypeSingle
OpenApiArray) }`. Passing value: `Array ["a", Number 1]` → `[]`. Failing values:
`Array ["a", Number 1, Bool True]` (extra item) → non-empty; `Array [Number 1, "a"]` (wrong
types) → non-empty. Add `contains` tests: schema
`mempty { _schemaContains = Just (Inline (mempty { _schemaType = Just (OpenApiTypeSingle
OpenApiInteger) })), _schemaMinContains = Just 2, _schemaType = Just (OpenApiTypeSingle
OpenApiArray) }`. Passing: `Array [Number 1, Number 2, String "x"]` (two integers) → `[]`.
Failing: `Array [String "x"]` (zero integers, below `minContains` 2) → non-empty. See Validation
and Acceptance for exact code.


### Milestone 3 — `if`/`then`/`else` and `const`

Scope: add conditional validation and `const`. These are not array- or object-specific, so they
hook into `validateWithSchema` (the top-level walk). What exists after M3: validating
`{"country":"USA","postal_code":"20500"}` against the country/postal_code conditional returns
`[]`, while `{"country":"USA","postal_code":"abc"}` returns a non-empty error; validating
`Number 42` against `{"const":42}` returns `[]`, while `Number 43` returns a non-empty error.
Commands: build then test.

**`if`/`then`/`else` — semantics.** Evaluate the instance against the `if` sub-schema. If it
validates against `if`, the instance must **also** validate against `then` (when `then` is
present); if it does **not** validate against `if`, the instance must validate against `else`
(when `else` is present). The result of the `if` check itself **never** causes failure — `if` is
only a switch selecting `then` or `else`. If `then`/`else` is absent for the taken branch, that
branch imposes no constraint.

**`if`/`then`/`else` — function and branch.** Add to `validateWithSchema`
(`src/Data/OpenApi/Internal/Schema/Validation.hs:295-298`) a new check after `validateEnum`:

```haskell
validateWithSchema val = do
  validateSchemaType val
  validateEnum val
  validateConst val          -- M3, const
  validateConditional val    -- M3, if/then/else
  validateUnevaluated val     -- M4 (added later)
```

and define `validateConditional`:

```haskell
-- | if/then/else. The result of validating against `if` is a switch only:
--   if it passes, `then` must pass; otherwise `else` must pass. The `if`
--   check itself never contributes an error.
validateConditional :: Value -> Validation Schema ()
validateConditional val = check if_ $ \ifSchema -> withConfig $ \cfg -> withSchema $ \sch ->
  let ifPasses = case runValidation (validateWithSchemaRef ifSchema val) cfg sch of
                   Failed _ -> False
                   Passed _ -> True
  in if ifPasses
       then maybe valid (\t -> validateWithSchemaRef t val) (sch ^. then_)
       else maybe valid (\e -> validateWithSchemaRef e val) (sch ^. else_)
```

The `check if_` wrapper means the whole block is skipped when there is no `if` keyword.

**`const` — semantics.** The instance must equal the schema's `const` value **exactly**, by JSON
value equality (same type and same contents). `const: 42` accepts only the number `42`;
`const: "USA"` accepts only the string `"USA"`; `const: {"a":1}` accepts only that exact object.

**`const` — function and branch.** Add `validateConst` (called from `validateWithSchema` above):

```haskell
-- | const: the instance must equal the schema's `const` value exactly.
validateConst :: Value -> Validation Schema ()
validateConst val = check const_ $ \expected ->
  when (val /= expected) $
    invalid ("value " ++ show val ++ " does not equal const " ++ show expected)
```

`Value`'s `Eq` instance gives exact JSON equality, which is precisely `const` semantics.

**M3 tests.** Conditional: build the country/postal_code schema (migration plan §6.1):

```haskell
let ifS   = Inline (mempty { _schemaType = Just (OpenApiTypeSingle OpenApiObject)
                           , _schemaProperties =
                               [ ("country", Inline (mempty { _schemaConst = Just (String "USA") })) ] })
    thenS = Inline (mempty { _schemaType = Just (OpenApiTypeSingle OpenApiObject)
                           , _schemaProperties =
                               [ ("postal_code", Inline (mempty { _schemaType = Just (OpenApiTypeSingle OpenApiString)
                                                                , _schemaPattern = Just "^[0-9]{5}$" })) ] })
    condSchema = mempty { _schemaType = Just (OpenApiTypeSingle OpenApiObject)
                        , _schemaIf = Just ifS, _schemaThen = Just thenS }
```

Passing value: object `{"country":"USA","postal_code":"20500"}` → `[]` (note: pattern checking is
off by default; see the note below). Failing value: object `{"country":"USA","postal_code":"abc"}`
→ non-empty (only when a pattern checker is supplied; otherwise the failing case must rely on a
non-pattern constraint). **Important caveat for the test author:** `validateJSON` uses a no-op
pattern checker (`\_ _ -> True`), so a `pattern` mismatch alone will *not* produce an error. To
test the conditional reliably without depending on regex support, use a `then` branch whose
constraint is type-based, e.g. require `postal_code` to be a *number* (`_schemaType = Just
(OpenApiTypeSingle OpenApiNumber)`), and supply a *string* postal_code in the failing case; or use
`validateJSONWithPatternChecker` with a real checker. The plan's test (Validation and Acceptance)
uses the type-based variant so it is deterministic. `const` tests: schema
`mempty { _schemaConst = Just (Number 42) }`; `validateJSON mempty s (Number 42) == []`;
`not (null (validateJSON mempty s (Number 43)))`.


### Milestone 4 — Best-effort `unevaluatedProperties` / `unevaluatedItems`

Scope: implement the *best-effort* approximation decided in the Decision Log, with a clear Haddock
limitation note, plus tests for the cases it covers. What exists after M4: validating an object
against a schema that declares `properties: {a: …}` and `unevaluatedProperties: false` rejects an
object carrying an extra property `b` (because `b` was not evaluated by the local `properties`),
and accepts an object carrying only `a`; validating an array against `prefixItems: [string,number]`
+ `unevaluatedItems: false` rejects a third element and accepts a two-element array. The
limitation (cross-schema evaluation through `allOf`/`if`/`$ref` is not tracked) is documented.
Commands: build then test.

**Semantics (full, for reference) and the best-effort approximation.** In JSON Schema 2020-12,
`unevaluatedProperties` applies to object properties **not** "successfully evaluated" by any
`properties`, `patternProperties`, `additionalProperties`, **or** any in-place applicator
(`allOf`, `anyOf`, `oneOf`, `if`/`then`/`else`, `$ref`, `$dynamicRef`) that evaluated that
property; similarly `unevaluatedItems` applies to array items beyond those evaluated by
`prefixItems`/`items`/`contains` and in-place applicators. Faithfully computing the
"evaluated" set requires collecting annotations across the whole sub-schema tree, which this
engine does not do (see Decision Log). The **best-effort** approximation EP-6 ships treats
"evaluated" as **"evaluated by the current schema object's own local applicators"**:

- For `unevaluatedProperties`: the evaluated properties are the keys present in the current
  schema's `properties` map (plus, if `additionalProperties` is a schema or `true`, *all* keys —
  in which case `unevaluatedProperties` has nothing left to apply to). The unevaluated keys are
  the object's keys minus the `properties` keys. Apply the `unevaluatedProperties` constraint
  (`AdditionalPropertiesAllowed False` → those leftover keys are forbidden;
  `AdditionalPropertiesAllowed True` → allowed; `AdditionalPropertiesSchema s` → each leftover
  value must validate against `s`) to exactly those leftover keys.
- For `unevaluatedItems`: the evaluated items are the first `length prefixItems` elements (plus,
  if `items` is a schema or `true`, *all* elements). The unevaluated items are the elements beyond
  the prefix. Apply the constraint to exactly those.

**Function and branch.** Add `validateUnevaluated` (called from `validateWithSchema` in M3's edit)
that dispatches on the value shape:

```haskell
-- | Best-effort unevaluatedProperties / unevaluatedItems.
--
-- LIMITATION (documented, intentional): "evaluated" is approximated as
-- "evaluated by THIS schema object's own local `properties`/`additionalProperties`
-- (for objects) or `prefixItems`/`items` (for arrays)". Properties or items that a
-- full JSON Schema 2020-12 validator would consider evaluated via in-place
-- applicators (`allOf`/`anyOf`/`oneOf`/`if`/`then`/`else`/`$ref`) are NOT counted
-- here, so this check can be STRICTER than the spec when those applicators are
-- combined with `unevaluated*`. Full annotation-aware evaluation is future work
-- (TODO(annotations)).
validateUnevaluated :: Value -> Validation Schema ()
validateUnevaluated (Object o) = check unevaluatedProperties $ \ap -> withSchema $ \sch ->
  let propKeys      = InsOrdHashMap.keys (sch ^. properties)
      addlCoversAll = case sch ^. additionalProperties of
                        Just (AdditionalPropertiesAllowed True) -> True
                        Just (AdditionalPropertiesSchema _)     -> True
                        _                                       -> False
      leftover = [ (k, v) | (keyToText -> k, v) <- objectToList o
                          , not addlCoversAll
                          , k `notElem` propKeys ]
  in for_ leftover $ \(k, v) -> case ap of
       AdditionalPropertiesAllowed True  -> valid
       AdditionalPropertiesAllowed False ->
         invalid ("unevaluatedProperties=false but property " ++ show k ++ " was not evaluated")
       AdditionalPropertiesSchema s      -> validateWithSchemaRef s v
validateUnevaluated (Array xs) = check unevaluatedItems $ \uSchema -> withSchema $ \sch ->
  let prefixLen      = maybe 0 length (sch ^. prefixItems)
      itemsCoversAll = case sch ^. items of
                         Just (OpenApiItemsObject _)      -> True
                         Just (OpenApiItemsBoolean True)  -> True
                         _                                -> False
      leftover = if itemsCoversAll then [] else drop prefixLen (Vector.toList xs)
  in traverse_ (validateWithSchemaRef uSchema) leftover
validateUnevaluated _ = valid
```

(Adjust the `objectToList`/`keyToText` usage to match how `validateObject` already iterates the
object — those helpers are imported at the top of the engine module. `InsOrdHashMap.keys` comes
from the `InsOrdHashMap` import already present.)

**M4 tests.** Object case: schema
`mempty { _schemaType = Just (OpenApiTypeSingle OpenApiObject), _schemaProperties = [ ("a", Inline
(mempty { _schemaType = Just (OpenApiTypeSingle OpenApiString) })) ], _schemaUnevaluatedProperties
= Just (AdditionalPropertiesAllowed False) }`. Passing: object `{"a":"x"}` → `[]`. Failing: object
`{"a":"x","b":"y"}` → non-empty (`b` unevaluated). Array case: schema
`mempty { _schemaType = Just (OpenApiTypeSingle OpenApiArray), _schemaPrefixItems = Just [ Inline
(mempty { _schemaType = Just (OpenApiTypeSingle OpenApiString) }), Inline (mempty { _schemaType =
Just (OpenApiTypeSingle OpenApiNumber) }) ], _schemaUnevaluatedItems = Just (Inline (mempty {
_schemaNot = Just (Inline mempty) })) }` (an always-false unevaluated schema). Passing:
`Array ["a", Number 1]` → `[]`. Failing: `Array ["a", Number 1, Bool True]` → non-empty (the third
item is unevaluated and must satisfy the always-false schema). Document in the test description
that these are best-effort cases (single-schema, no `allOf`/`$ref` interaction). See Validation and
Acceptance.


## Concrete Steps

All commands run from the repository root `/Users/shinzui/Keikaku/hub/haskell/openapi3`.

**Precondition check — confirm EP-3 and EP-4 are complete.** EP-6 consumes the fields they add.
Run:

```bash
grep -n '_schemaType ::' src/Data/OpenApi/Internal.hs
grep -n '_schemaExclusiveMaximum ::' src/Data/OpenApi/Internal.hs
grep -n 'OpenApiItemsBoolean' src/Data/OpenApi/Internal.hs
grep -n '_schemaPrefixItems\|_schemaConst\|_schemaContains\|_schemaIf\|_schemaUnevaluated' src/Data/OpenApi/Internal.hs
```

Expected: `_schemaType :: Maybe OpenApiTypeValue`; `_schemaExclusiveMaximum :: Maybe Scientific`;
`OpenApiItemsBoolean` present (and **no** `OpenApiItemsArray` — `grep -n 'OpenApiItemsArray'
src/Data/OpenApi/Internal.hs` prints nothing); and the EP-4 fields (`_schemaPrefixItems`,
`_schemaConst`, `_schemaContains`, `_schemaMinContains`, `_schemaMaxContains`, `_schemaIf`,
`_schemaThen`, `_schemaElse`, `_schemaUnevaluatedProperties`, `_schemaUnevaluatedItems`) all
present. **If any check fails, EP-3 or EP-4 is incomplete — stop and finish them first** (they are
hard dependencies; EP-6 cannot validate fields that do not exist).

Confirm the generated lens names you will use:

```bash
grep -n 'const_\|prefixItems\|contains\|minContains\|maxContains\|if_\|then_\|else_\|unevaluated\|exclusiveMaximum\|exclusiveMinimum' src/Data/OpenApi/Lens.hs
```

Expected: lenses for each field exist (note the exact spelling of `const_`/`if_`/`then_`/`else_`;
substitute the real names into the edits if they differ, and record any difference in Surprises).

Enter the dev shell (pins GHC 9.12.4, provides `cabal`):

```bash
nix develop
```

Build and test (or prefix each with `nix develop -c`):

```bash
cabal build all
cabal test all
```

Expected on success (abridged):

```text
Building library for openapi3-3.2.5..
...
Test suite openapi3-test: RUNNING...
...
NNN examples, 0 failures
Test suite openapi3-test: PASS
```

A throwaway GHCi session is useful to sanity-check a single keyword while implementing:

```bash
cabal repl lib:openapi3
```

```haskell
import Data.Aeson (Value(..))
import Data.OpenApi
import Data.OpenApi.Internal
import Data.OpenApi.Schema.Validation (validateJSON)
let s = mempty { _schemaType = Just (OpenApiTypeArray [OpenApiString, OpenApiNull]) } :: Schema
validateJSON mempty s (String "hi")   -- expect: []
validateJSON mempty s Null            -- expect: []
validateJSON mempty s (Number 3)      -- expect: a non-empty [String]
```

Update this section with the actual observed output as you go.


## Validation and Acceptance

Validation is by example-based tests added to `test/Data/OpenApi/Schema/ValidationSpec.hs` plus
the full existing suite still passing. The engine returns `[ValidationError]` (a list of
`String`); **empty means valid**, non-empty means invalid. Each keyword gets a passing value
(asserts `== []`) and a failing value (asserts `not . null`). Add this block to `spec` in
`ValidationSpec.hs` (it needs the imports `Data.OpenApi.Internal` for the constructors,
`Data.OpenApi.Schema.Validation (validateJSON)`, and `Data.Aeson (Value(..))`; add them to the
existing import list — `Data.Aeson` is already imported, and `validateJSON` is reachable through
`Data.OpenApi` re-exports, but import it explicitly to be safe):

```haskell
  describe "OpenAPI 3.1 keyword validation" $ do

    -- M1: type arrays (matches-any; OpenApiNull matches JSON null)
    it "type [string,null] accepts a string and null, rejects a number" $ do
      let s = mempty { _schemaType = Just (OpenApiTypeArray [OpenApiString, OpenApiNull]) }
      validateJSON mempty s (String "hi")     `shouldBe` []
      validateJSON mempty s Null              `shouldBe` []
      validateJSON mempty s (Number 3)        `shouldNotBe` []

    -- M1: numeric exclusive bounds (independent of maximum/minimum)
    it "exclusiveMinimum 0 / exclusiveMaximum 100 accept 50, reject 0 and 100" $ do
      let s = mempty { _schemaType = Just (OpenApiTypeSingle OpenApiNumber)
                     , _schemaExclusiveMinimum = Just 0
                     , _schemaExclusiveMaximum = Just 100 }
      validateJSON mempty s (Number 50)       `shouldBe` []
      validateJSON mempty s (Number 0)        `shouldNotBe` []
      validateJSON mempty s (Number 100)      `shouldNotBe` []

    -- M2: prefixItems + items:false (tuple)
    it "prefixItems [string,number] + items:false validates [\"a\",1], rejects extras/wrong types" $ do
      let s = mempty
            { _schemaType = Just (OpenApiTypeSingle OpenApiArray)
            , _schemaPrefixItems =
                Just [ Inline (mempty { _schemaType = Just (OpenApiTypeSingle OpenApiString) })
                     , Inline (mempty { _schemaType = Just (OpenApiTypeSingle OpenApiNumber) }) ]
            , _schemaItems = Just (OpenApiItemsBoolean False) }
      validateJSON mempty s (Array [String "a", Number 1])              `shouldBe` []
      validateJSON mempty s (Array [String "a", Number 1, Bool True])   `shouldNotBe` []
      validateJSON mempty s (Array [Number 1, String "a"])              `shouldNotBe` []

    -- M2: contains + minContains
    it "contains integer + minContains 2 accepts two integers, rejects fewer" $ do
      let s = mempty
            { _schemaType = Just (OpenApiTypeSingle OpenApiArray)
            , _schemaContains =
                Just (Inline (mempty { _schemaType = Just (OpenApiTypeSingle OpenApiInteger) }))
            , _schemaMinContains = Just 2 }
      validateJSON mempty s (Array [Number 1, Number 2, String "x"])    `shouldBe` []
      validateJSON mempty s (Array [String "x"])                        `shouldNotBe` []

    -- M2: maxContains
    it "contains integer + maxContains 1 rejects two integers" $ do
      let s = mempty
            { _schemaType = Just (OpenApiTypeSingle OpenApiArray)
            , _schemaContains =
                Just (Inline (mempty { _schemaType = Just (OpenApiTypeSingle OpenApiInteger) }))
            , _schemaMaxContains = Just 1 }
      validateJSON mempty s (Array [Number 1, String "x"])              `shouldBe` []
      validateJSON mempty s (Array [Number 1, Number 2])                `shouldNotBe` []

    -- M3: if/then (type-based so it does not depend on the pattern checker)
    it "if country=USA then postal_code is a number" $ do
      let ifS = Inline (mempty
            { _schemaType = Just (OpenApiTypeSingle OpenApiObject)
            , _schemaProperties =
                [ ("country", Inline (mempty { _schemaConst = Just (String "USA") })) ] })
          thenS = Inline (mempty
            { _schemaType = Just (OpenApiTypeSingle OpenApiObject)
            , _schemaProperties =
                [ ("postal_code", Inline (mempty { _schemaType = Just (OpenApiTypeSingle OpenApiNumber) })) ] })
          s = mempty { _schemaType = Just (OpenApiTypeSingle OpenApiObject)
                     , _schemaIf = Just ifS, _schemaThen = Just thenS }
      validateJSON mempty s (object [ "country" .= ("USA" :: String), "postal_code" .= (20500 :: Int) ]) `shouldBe` []
      validateJSON mempty s (object [ "country" .= ("USA" :: String), "postal_code" .= ("abc" :: String) ]) `shouldNotBe` []
      -- if-branch not taken: a non-USA country imposes no postal_code constraint
      validateJSON mempty s (object [ "country" .= ("CA" :: String), "postal_code" .= ("abc" :: String) ]) `shouldBe` []

    -- M3: const
    it "const 42 accepts 42, rejects 43" $ do
      let s = mempty { _schemaConst = Just (Number 42) }
      validateJSON mempty s (Number 42)       `shouldBe` []
      validateJSON mempty s (Number 43)       `shouldNotBe` []

    -- M4: best-effort unevaluatedProperties (local-only)
    it "unevaluatedProperties:false rejects a property not in properties" $ do
      let s = mempty
            { _schemaType = Just (OpenApiTypeSingle OpenApiObject)
            , _schemaProperties =
                [ ("a", Inline (mempty { _schemaType = Just (OpenApiTypeSingle OpenApiString) })) ]
            , _schemaUnevaluatedProperties = Just (AdditionalPropertiesAllowed False) }
      validateJSON mempty s (object [ "a" .= ("x" :: String) ])                       `shouldBe` []
      validateJSON mempty s (object [ "a" .= ("x" :: String), "b" .= ("y" :: String) ]) `shouldNotBe` []

    -- M4: best-effort unevaluatedItems (local-only)
    it "unevaluatedItems:false-ish rejects an item beyond prefixItems" $ do
      let s = mempty
            { _schemaType = Just (OpenApiTypeSingle OpenApiArray)
            , _schemaPrefixItems =
                Just [ Inline (mempty { _schemaType = Just (OpenApiTypeSingle OpenApiString) })
                     , Inline (mempty { _schemaType = Just (OpenApiTypeSingle OpenApiNumber) }) ]
            , _schemaUnevaluatedItems = Just (Inline (mempty { _schemaNot = Just (Inline mempty) })) }
      validateJSON mempty s (Array [String "a", Number 1])              `shouldBe` []
      validateJSON mempty s (Array [String "a", Number 1, Bool True])   `shouldNotBe` []
```

Notes for the test author. `shouldNotBe []` requires `Data.List` ordering-free comparison only on
`[String]`, which `shouldNotBe` from hspec handles. The `object`/`(.=)`/`Array`/`Number`/`String`
constructors come from `Data.Aeson`, already imported in `ValidationSpec.hs`; the numeric literals
in `Array [Number 1, …]` rely on `Number`'s `Num`/`fromInteger`. The schema-construction record
syntax (`mempty { _schemaType = … }`) needs `Data.OpenApi.Internal` in scope (the field selectors);
add `import Data.OpenApi.Internal` to the module imports. `InsOrdHashMap`-typed
`_schemaProperties` accepts a list literal via `OverloadedLists` (the library already uses it in
the generator) — if the test module lacks `OverloadedLists`, either add the pragma at the top of
`ValidationSpec.hs` or build the map with `InsOrdHashMap.fromList [...]`; prefer the explicit
`fromList` to avoid adding a pragma. Substitute the real lens/field names if EP-4's derivation
differs from the spellings used here.

The behavioral proof beyond compilation:

- A `type` array validates as a union and `null` is accepted for `["string","null"]` (impossible
  before EP-6 — the engine assumed a single type).
- `exclusiveMaximum`/`exclusiveMinimum` carry strict numeric bounds independent of
  `maximum`/`minimum` (before: a boolean modifier, now a number).
- `prefixItems`+`items:false` validates a tuple and forbids extra elements; `contains`+
  `minContains`/`maxContains` count matching elements.
- `if`/`then`/`else` switches between sub-schemas without the `if` failing; `const` enforces exact
  equality.
- `unevaluated*` rejects locally-unevaluated leftovers (best-effort, documented).

Run the targeted suite and read the summary:

```bash
nix develop -c cabal test all 2>&1 | tail -n 20
```

Interpret: every `it` block prints with a checkmark and the run ends `0 failures`. If a numeric
literal like `Number 1` is ambiguous, annotate it (`Number 1 :: Value` is already fixed by the
list element type). If an assertion fails because the failing case actually returned `[]`, re-read
the corresponding `validate*` edit — the most common mistake is letting the legacy whole-array
`items` check run alongside `prefixItems` (guard it to run only when `prefixItems` is absent).


## Idempotence and Recovery

Every edit in this plan is to source files under version control; nothing is destructive to data.
Re-running `nix develop -c cabal build all` / `cabal test all` is idempotent and safe to repeat.

The milestones are ordered so each is a clean commit boundary; if a milestone leaves the tree
non-compiling and you must retreat, `git stash` or `git checkout -- src/Data/OpenApi/Internal/Schema/Validation.hs
test/Data/OpenApi/Schema/ValidationSpec.hs` restores the last good state. Because EP-6 touches only
the validation engine and the validation test module, the blast radius of a mistake is contained to
those two files (plus, only if you choose to export a new helper, the public wrapper
`src/Data/OpenApi/Schema/Validation.hs`).

The highest-risk edit is the `validateArray` reshuffle in M2 (interleaving `prefixItems` with the
legacy `items` check). If it proves fiddly, a safe intermediate is to implement `prefixItems` as a
*separate* check that does not touch the existing `items` block, and only forbid trailing elements
when `items == Just (OpenApiItemsBoolean False)` — accept temporary double-validation of trailing
elements (once by the legacy `items` block, once by the prefix block) since double-validating a
*passing* element is harmless (both `Passed`), and only the failing/extra-element cases matter for
the tests. Record in the Decision Log if you take this path. The M4 `unevaluated*` work is
intentionally best-effort; if even the local approximation proves troublesome, the documented
fallback is to implement only `unevaluatedItems` (simpler — a positional drop) and leave
`unevaluatedProperties` as `valid` with a `TODO(annotations)` and a Surprises note, since the
master plan's EP-6 line does not require `unevaluated*` at all.

To verify no leftover reference to removed constructors after EP-3 (a precondition, not EP-6's
job, but worth confirming the engine is consistent): `grep -n 'OpenApiItemsArray' src/Data/OpenApi/Internal/Schema/Validation.hs`
must print nothing.

Do not `git commit` as part of executing this plan; leave the working tree for review.


## Interfaces and Dependencies

Libraries and modules used (all already dependencies; EP-6 introduces none): `Data.Aeson`
(`Value`, `object`, `(.=)`, the `Value` `Eq` instance for `const`), `Data.Vector` (array
elements; `Vector.toList`, `Vector.length`, `Vector.null`), `Data.Scientific` (`Scientific`,
`isInteger` for numeric checks), `Data.Foldable` (`for_`, `traverse_`, `sequenceA_`),
`Data.HashMap.Strict.InsOrd.Compat` (`InsOrdHashMap` for `properties`/`keys`),
`Control.Lens` (the `check`/`withSchema` machinery and the field lenses), `hspec`/`QuickCheck`
for tests. The `Data.OpenApi.Aeson.Compat` helpers `keyToText`/`objectToList`/`lookupKey` are
already imported by the engine module and reused for the object iteration in `unevaluated*`.

Functions/branches that must exist at the end of each milestone, all in
`src/Data/OpenApi/Internal/Schema/Validation.hs` unless stated:

After **M1**: `schemaTypes :: Schema -> [OpenApiType]`; `validateSchemaType` /
`validateParamSchemaType` / `showType` rewritten for "matches any" type arrays with `OpenApiNull`
↔ JSON `null`; `validateNumber` rewritten so `exclusiveMaximum`/`exclusiveMinimum` are independent
strict numeric checks (`Maybe Scientific`) alongside the non-strict `maximum`/`minimum`. (These
may have been pre-landed by EP-3; EP-6 owns their correctness + tests.)

After **M2**: `validateArray` extended with a `check prefixItems` block (positional validation +
trailing-element handling via `items`/`OpenApiItemsBoolean`) and a `check contains` block
(`minContains` default 1, `maxContains` optional, counting matches without aborting).

After **M3**: `validateWithSchema` calls `validateConst` and `validateConditional`;
`validateConst :: Value -> Validation Schema ()` (exact `Value` equality against `_schemaConst`);
`validateConditional :: Value -> Validation Schema ()` (`if` is a non-failing switch selecting
`then`/`else`).

After **M4**: `validateWithSchema` also calls
`validateUnevaluated :: Value -> Validation Schema ()`, implementing the best-effort, locally-scoped
`unevaluatedProperties` (objects) and `unevaluatedItems` (arrays), with the documented limitation
Haddock comment and a `TODO(annotations)` marker.

Integration points honored (from the master plan
`docs/masterplans/1-openapi-3-1-support-and-project-modernization.md`):

- IP-2 (the shared `Schema`/`OpenApiItems` shape): EP-6 **consumes** the final shape read-only. It
  adds **no** field, changes **no** lens/optic/JSON instance, and reorders nothing. It depends on
  EP-3's `OpenApiTypeValue`/`Scientific` bounds/`OpenApiItemsBoolean` and EP-4's `_schemaPrefixItems`,
  `_schemaConst`, `_schemaContains`, `_schemaMinContains`, `_schemaMaxContains`, `_schemaIf`,
  `_schemaThen`, `_schemaElse`, `_schemaUnevaluatedProperties`, `_schemaUnevaluatedItems` already
  existing (precondition check in Concrete Steps).
- IP-4 (`OpenApiType`/`OpenApiNull`): EP-6 relies on `OpenApiNull` matching JSON `null` in the
  type-array "matches any" logic (the M1 test asserts `null` validates against `["string","null"]`).
- IP-5 (test support / test-suite stanza): EP-6 adds its tests to the already-registered
  `Data.OpenApi.Schema.ValidationSpec` module, so no `openapi3.cabal` `other-modules` edit is
  required. If a future contributor splits the 3.1 validation tests into their own module, they
  must register it in the `test-suite spec` `other-modules` list per IP-5.


---

Revision note (2026-06-10): Initial full authoring of EP-6 from the skeleton, per
`.claude/skills/exec-plan/PLANS.md`. Grounded every keyword's semantics, the exact engine function
to extend, and the branch to add against a close reading of
`src/Data/OpenApi/Internal/Schema/Validation.hs` (the `Validation` profunctor, `check`/`withSchema`,
`validateWithSchema`, `validateNumber`, `validateArray`, `validateObject`, `validateSchemaType`),
the public wrapper `src/Data/OpenApi/Schema/Validation.hs`, and the existing test conventions in
`test/Data/OpenApi/Schema/ValidationSpec.hs`. Referenced EP-3
(`docs/plans/3-openapi-3-1-core-schema-type-changes.md`) and EP-4
(`docs/plans/4-openapi-3-1-json-schema-fields-and-reference-keywords.md`) by path as hard
dependencies that define the fields EP-6 validates, and recorded the precondition check. Seeded the
Decision Log per the brief: exclusive bounds as independent keywords; type arrays validated as
"matches any"; and the central scoping decision recommending a **best-effort/deferred**
`unevaluated*` with a clearly documented limitation (the engine returns only pass/fail and does not
thread annotation results, so full annotation-aware `unevaluated*` is out of scope and approximated
locally). Why: the plan must let a novice implement EP-6 end-to-end from this file plus the current
working tree and the outputs of EP-3 and EP-4, with no other context.
