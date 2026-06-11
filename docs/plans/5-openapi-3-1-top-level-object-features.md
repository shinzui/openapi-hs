---
id: 5
slug: openapi-3-1-top-level-object-features
title: "OpenAPI 3.1 Top-Level Object Features"
kind: exec-plan
created_at: 2026-06-11T03:47:52Z
master_plan: "docs/masterplans/1-openapi-3-1-support-and-project-modernization.md"
---

# OpenAPI 3.1 Top-Level Object Features

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

This repository is `openapi3`, a Haskell library that decodes, encodes, and manipulates
OpenAPI specification documents. It currently models OpenAPI 3.0 only. OpenAPI 3.1 added
four document-level features that this library cannot yet represent, so a 3.1 document that
uses any of them either fails to decode or silently loses data when re-encoded. This plan
adds those four features to the four record types that own them:

1. **`webhooks` on the root `OpenApi` object** — a map of named, out-of-band operations the
   API may *send* to the consumer (as opposed to `paths`, which are operations the consumer
   *calls*). In 3.1 a value in this map may be either a Path Item Object or a Reference
   Object, so the Haskell type is `InsOrdHashMap Text (Referenced PathItem)`.
2. **`summary` on the `Info` object** — a short, one-line summary of the API, sitting beside
   the existing longer `description`.
3. **`identifier` on the `License` object** — an [SPDX](https://spdx.org/licenses/) license
   expression (for example `"MIT"` or `"Apache-2.0"`). The 3.1 spec says `identifier` and the
   existing `url` are **mutually exclusive** (a license is identified *either* by SPDX id
   *or* by URL, never both).
4. **`$ref` on the `PathItem` object** — a JSON Reference (for example
   `"#/components/pathItems/Foo"`) that pulls in an externally-defined path item, optionally
   overriding it with the already-existing `summary` and `description` fields. The JSON key
   is the literal string `$ref`, which begins with a dollar sign.

After this change a user can take a 3.1 document such as the one below, decode it into the
library's types, read or modify the new fields through lenses or optics, and re-encode it
**losslessly** — the re-encoded JSON contains the same `webhooks`, `summary`, `identifier`,
and `$ref` keys it started with.

```json
{
  "openapi": "3.1.0",
  "info": { "title": "Pets", "summary": "A pet store API", "version": "1.0.0" },
  "webhooks": {
    "newPet": {
      "post": {
        "requestBody": { "description": "Information about a new pet in the system" },
        "responses": { "200": { "description": "Return a 200 status to indicate ok" } }
      }
    }
  }
}
```

How you will *see it working*: the test suite (`cabal test all`) gains round-trip checks
that decode each of the four fragments above, re-encode them, and assert the JSON is
unchanged — in particular that the `$ref` key comes back out spelled `"$ref"` and not
`"ref"`. These tests fail before the change (the fields do not exist) and pass after.

Term definitions used throughout this plan, in plain language:

- **Round-trip**: take a Haskell value, encode it to JSON, decode that JSON back to a Haskell
  value, and get the original value back (`decode (encode x) == Just x`); or the reverse,
  starting from JSON. We treat both directions as "round-trip".
- **`Referenced a`**: a small sum type already defined in this repo
  (`src/Data/OpenApi/Internal.hs`, around line 952) with two cases: `Ref Reference` (a
  pointer like `{"$ref": "#/components/..."}`) and `Inline a` (the value written out in
  place). `webhooks` values use `Referenced PathItem`.
- **`InsOrdHashMap k v`**: an insertion-ordered hash map from the `insert-ordered-containers`
  package, re-exported here as `Data.HashMap.Strict.InsOrd.Compat`. The library uses it for
  every JSON-object-shaped field so that key order is preserved across a round-trip.
- **`$`-prefixed key**: a JSON object key whose first character is a dollar sign, such as
  `$ref`. These matter because the library's automatic field-name-to-JSON-key derivation
  (described in "Context and Orientation" below) cannot produce them — it strips a record
  prefix and lower-cases, which can never emit a leading `$`. They need explicit handling.


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented here,
even if it requires splitting a partially completed task into two ("done" vs. "remaining").
This section must always reflect the actual current state of the work.

- [ ] M1: Add `_infoSummary :: Maybe Text` to `Info`; lens via `makeFields`; optic; update
      `Info` test example/JSON; round-trip an `Info` carrying `summary`.
- [ ] M1: Add `_licenseIdentifier :: Maybe Text` to `License`; fix the `IsString License`
      instance; lens via `makeFields`; optic; update `License` test example/JSON; round-trip
      `{"name":"...","identifier":"MIT"}`.
- [ ] M1: Decide and document `License.identifier`-vs-`url` mutual exclusivity (document-only
      for this plan; see Decision Log).
- [ ] M2: Add `_openApiWebhooks :: InsOrdHashMap Text (Referenced PathItem)` to `OpenApi`;
      add `ToJSON`/`FromJSON (Referenced PathItem)`; lens via `makeFields`; optic; round-trip
      the `{"webhooks":{"newPet":{"post":{...}}}}` fragment.
- [ ] M3: Add `_pathItemRef :: Maybe Text` to `PathItem`; lens via `makeLensesWith
      swaggerFieldRules`; optic; implement `$ref`-key emit/parse (reuse EP-4 helper if present,
      else local fallback + `TODO(EP-4)`); round-trip a `PathItem` with `$ref` + `summary`.
- [ ] Final: `nix develop -c cabal build all` and `nix develop -c cabal test all` both pass;
      no compile warnings introduced for the new fields; update master-plan EP-5 rows.


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

(None yet.)


## Decision Log

Record every decision made while working on the plan.

- Decision: Webhooks values are typed `Referenced PathItem`, not bare `PathItem`.
  Rationale: The OpenAPI 3.1.0 fixed-fields table defines `webhooks` as
  `Map[string, Path Item Object | Reference Object]`. Using bare `PathItem` would make the
  reference case (`{"newPet": {"$ref": "#/components/pathItems/..."}}`) unrepresentable.
  `src/Data/OpenApi/Internal.hs` already supplies the `Referenced` sum and the
  `referencedToJSON`/`referencedParseJSON` plumbing, so this is the natural fit.
  Date: 2026-06-10

- Decision: `PathItem.$ref` reuses EP-4's canonical `$`-prefixed-key serialization helper
  (Integration Point IP-3 in the master plan). If EP-4 has not landed when this plan is
  implemented, build a minimal local helper inside `src/Data/OpenApi/Internal.hs` and mark it
  `-- TODO(EP-4): replace with the shared $-key helper`. EP-4 then consolidates.
  Rationale: Both EP-4's `Schema` `$`-keywords (`$id`, `$ref`, `$defs`, `$anchor`,
  `$dynamicRef`, `$dynamicAnchor`) and EP-5's `PathItem.$ref` hit the identical problem: the
  default prefix-stripping rule in `mkSwaggerAesonOptions` cannot emit a leading `$`.
  Centralizing avoids two divergent implementations. As of this writing
  (`docs/plans/4-openapi-3-1-json-schema-fields-and-reference-keywords.md` is a skeleton, not
  implemented), the local-fallback path applies.
  Date: 2026-06-10

- Decision: `License.identifier`-vs-`url` mutual exclusivity is **documented, not enforced**
  in this plan. The field is added and round-trips; a Haddock note records that the spec
  treats the two as mutually exclusive, and a non-fatal validation hook is left to EP-6 / EP-7
  if desired.
  Rationale: This plan's milestones are about *representability and round-tripping* the new
  fields. Enforcing exclusivity at decode time (failing on documents that set both) would (a)
  reject documents that other tools accept leniently and (b) belong with the broader
  validation work in EP-6. Round-trip is the acceptance bar here; enforcement is a separable,
  later concern. Recording the constraint in Haddock keeps users informed without changing
  decode behavior.
  Date: 2026-06-10


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose.

(To be filled during and after implementation.)


## Context and Orientation

Everything in this plan happens inside one library, `openapi3`, whose source lives under
`src/Data/OpenApi/`. You do not need to understand the whole library — only the handful of
files and mechanisms named here. Read this section fully before editing; the serialization
machinery is unusual and editing it blind will produce wrong JSON keys.

**The four record types you will edit** all live in
`src/Data/OpenApi/Internal.hs`:

- `OpenApi` (around line 58) — the document root. Fields are prefixed `_openApi*`. Its JSON
  is produced through the generic machinery described below. You will add `_openApiWebhooks`.
- `Info` (around line 106) — API metadata. Fields are prefixed `_info*`. Note: its JSON is
  **not** produced through the generic machinery; it uses `genericToJSON (jsonPrefix "Info")`
  / `genericParseJSON (jsonPrefix "Info")` (lines ~1176 and ~1231), a *different*, simpler
  path. You will add `_infoSummary`.
- `License` (around line 141) — license metadata. Fields prefixed `_license*`. Also uses the
  simple `jsonPrefix "License"` path (lines ~1182, ~1237). It has an `IsString License`
  instance (line ~149) you must update. You will add `_licenseIdentifier`.
- `PathItem` (around line 207) — operations on one path. Fields prefixed `_pathItem*`.
  **`_pathItemSummary` (line ~209) and `_pathItemDescription` (line ~213) already exist** —
  do **not** re-add them. The only new field is `_pathItemRef`. Its JSON *is* produced
  through the generic machinery. You will add `_pathItemRef`.

**The two serialization paths.** There are two distinct ways records turn into JSON in this
file, and you must know which a given type uses:

- *Simple path* (`Info`, `License`): a stock Aeson generic instance configured by
  `jsonPrefix "Foo"` (defined in `src/Data/OpenApi/Internal/Utils.hs`, line ~51). It drops
  the leading underscore, strips the record prefix (`Info`/`License`), lower-cases the first
  letter, and sets `omitNothingFields = True` (so a `Nothing` field emits no key). For these
  types, a new `Maybe Text` field named `_infoSummary` automatically becomes the key
  `"summary"`, omitted when `Nothing`. **No instance edit is needed for `Info.summary` or
  `License.identifier` beyond adding the record field** — the generic instance picks it up.
- *Generic-SOP path* (`OpenApi`, `PathItem`): a custom layer in
  `src/Data/OpenApi/Internal/AesonUtils.hs` driven by `generics-sop`. `OpenApi`'s
  `ToJSON`/`FromJSON` call `sopSwaggerGenericToJSON`/`sopSwaggerGenericParseJSON`; the
  key-naming options come from `HasSwaggerAesonOptions OpenApi` (line ~1631,
  `mkSwaggerAesonOptions "swagger"`). `PathItem` likewise uses
  `mkSwaggerAesonOptions "pathItem"` (line ~1615). This layer strips the record prefix and
  lower-cases the first letter exactly like the simple path, and **also** omits a field when
  its value equals a per-type "default" supplied by the `AesonDefaultValue` class. For a
  `Maybe` field the default is `Just Nothing` (so `Nothing` is omitted); for an
  `InsOrdHashMap` field the default is the empty map (so an empty map is omitted). This is why
  `_openApiWebhooks` works automatically *once* an `AesonDefaultValue` instance exists for its
  field type — and it already does: `instance AesonDefaultValue (InsOrd.InsOrdHashMap k v)`
  is defined in `AesonUtils.hs` (line ~75).

**Why `$ref` is special.** Both serialization paths derive the JSON key by *stripping a
prefix and lower-casing the first character*. There is no rule in either path that can emit a
leading `$`. So `_pathItemRef` would, by default, serialize to the key `"ref"` — which is
wrong; the spec key is `"$ref"`. This is the same obstacle EP-4 faces for the `Schema`
`$`-keywords. The master plan's Integration Point IP-3 assigns the *canonical* helper for
emitting/parsing `$`-prefixed keys to EP-4, and has EP-5 reuse it. Because EP-4 is not yet
implemented, this plan provides a **minimal local helper** (post-processing the generated
`Value`) and marks it `TODO(EP-4)` for later consolidation. See Milestone 3 for the exact
mechanism.

**Lenses and optics.** Two parallel accessor systems are generated from the records:

- `src/Data/OpenApi/Lens.hs` uses `lens` Template Haskell. `OpenApi`, `Info`, and `License`
  are generated with `makeFields` (lines 19, 24, 26), which creates *classy* lenses: a class
  like `HasSummary s a` plus a method `summary`. Because these are generated directly from
  the record fields, **adding a record field automatically produces its lens** — you do not
  edit `Lens.hs` for `Info`/`License`/`OpenApi` unless a name collides (none of `summary`,
  `identifier`, `webhooks` currently exists as a field anywhere, so there is no collision).
  `PathItem` is generated with `makeLensesWith swaggerFieldRules ''PathItem` (line 27), which
  creates *plain* lenses named after the field minus its `_pathItem` prefix
  (`swaggerFieldRules` is in `src/Data/OpenApi/Internal/Utils.hs`, line ~25; it also renames
  some keyword-clashing fields, e.g. `type` → `type_`, but `ref` is not a clash). Adding
  `_pathItemRef` therefore generates a `ref` lens automatically. **You do not hand-write
  lenses; you only confirm the new ones appear.**
- `src/Data/OpenApi/Optics.hs` uses `optics` Template Haskell via `makeFieldLabels` for each
  type (`OpenApi` line 107, `Info` 113, `License` 115, `PathItem` 116). Like `makeFields`,
  `makeFieldLabels` reads the record fields, so the new optics (`#summary`, `#identifier`,
  `#webhooks`, `#ref`) are generated automatically once the record fields exist. **No edit to
  `Optics.hs` is required** beyond confirming compilation.

**`deriveGeneric` list.** Near line 973 of `Internal.hs` there is a block of
`deriveGeneric ''Foo` Template Haskell calls (`OpenApi` at 987, `PathItem` at 980). These
generate the `generics-sop` representation that the SOP serialization path consumes. They
read the record definition at splice time, so **adding fields to `OpenApi`/`PathItem` needs no
change to these lines** — but the lines must appear *after* the data declarations (they do).
`Info` and `License` are *not* in this list (they use the simple path), and that is fine.

**`Semigroup`/`Monoid` instances.** `OpenApi`, `Info`, `License`, and `PathItem` all derive
their `Monoid` via `genericMempty`/`genericMappend` (lines ~1004–1085). These are generic over
the record shape, so new fields are absorbed automatically: a new `Maybe` field's `mempty` is
`Nothing`, a new `InsOrdHashMap` field's `mempty` is the empty map. The existing test
examples build values with `mempty & lens .~ ...`, so they keep compiling — the new fields
just start out empty. The one exception is `License`'s hand-written `IsString` instance
(`fromString s = License (fromString s) Nothing`), which lists fields positionally and so
**must** be updated when a field is inserted.

**The tests** live in `test/Data/OpenApiSpec.hs`. The relevant example values are
`infoExample`/`infoExampleJSON` (around line 64), `licenseExample`/`licenseExampleJSON`
(around line 117), and the large petstore documents further down. The combinator `<=>`
(defined in `test/SpecCommon.hs`) asserts a Haskell value and a JSON value round-trip to each
other. You will extend the `Info` and `License` examples and add new round-trip cases for
`webhooks` and `PathItem.$ref`.

**Build and test commands.** The dev environment is a Nix flake; all build/test commands run
through `nix develop -c ...`. From the repo root
(`/Users/shinzui/Keikaku/hub/haskell/openapi3`):

```bash
nix develop -c cabal build all
nix develop -c cabal test all
```

**Read-only awareness (Integration Point IP-2).** This plan does **not** touch the `Schema`
record or `OpenApiItems`. Those belong to EP-3 (core) and EP-4 (JSON Schema fields). If you
find yourself editing `Schema`, stop — you are in the wrong plan.


## Plan of Work

The work splits into three milestones ordered by difficulty, each independently verifiable.
M1 adds two trivial `Maybe Text` fields on simple-path types. M2 adds the webhooks map on a
SOP-path type, exercising `Referenced PathItem`. M3 adds the `$ref` key, the only part that
needs custom `$`-key handling. Do them in order: M1 proves the simple path and the
lens/optic regeneration with the least risk; M2 proves the SOP path and the `Referenced`
plumbing; M3 layers the `$`-key handling on top of the now-proven SOP path.


### Milestone 1 — `Info.summary` and `License.identifier`

**Scope.** Add `_infoSummary :: Maybe Text` to `Info` and `_licenseIdentifier :: Maybe Text`
to `License`. Both ride the simple `jsonPrefix` serialization path, so no JSON-instance code
changes; the only hand-edit beyond the record fields is the positional `IsString License`
instance. Add coverage to the existing `Info`/`License` test examples and one focused
round-trip each.

**What will exist at the end.** A decoded `Info` retains a `summary` key and re-emits it; a
decoded `License` retains an `identifier` key and re-emits it. The lenses `summary`
(on `Info`) and `identifier` (on `License`), and the optics `#summary` / `#identifier`, exist
and compile.

**Edits.**

In `src/Data/OpenApi/Internal.hs`, inside `data Info` (around line 106), insert a `summary`
field immediately after `_infoTitle` so the field order matches the spec's presentation
(title, then summary, then description):

```haskell
data Info = Info
  { -- | The title of the API.
    _infoTitle :: Text

    -- | A short summary of the API. (OpenAPI 3.1)
  , _infoSummary :: Maybe Text

    -- | A short description of the API.
    -- [CommonMark syntax](https://spec.commonmark.org/) MAY be used for rich text representation.
  , _infoDescription :: Maybe Text
  -- ... remaining fields unchanged ...
  } deriving (Eq, Show, Generic, Data, Typeable)
```

In the same file, inside `data License` (around line 141), insert `identifier` after
`_licenseName`, and add a Haddock note about the mutual-exclusivity-with-`url` constraint:

```haskell
data License = License
  { -- | The license name used for the API.
    _licenseName :: Text

    -- | An [SPDX](https://spdx.org/licenses/) license expression for the API,
    -- e.g. @"MIT"@ or @"Apache-2.0"@. (OpenAPI 3.1)
    --
    -- The OpenAPI 3.1 specification states that 'identifier' and '_licenseUrl'
    -- are mutually exclusive: a license is identified by /either/ an SPDX
    -- identifier /or/ a URL, never both. This library does not enforce that
    -- constraint at decode time (see EP-5 Decision Log); it round-trips
    -- whatever is present.
  , _licenseIdentifier :: Maybe Text

    -- | A URL to the license used for the API.
  , _licenseUrl :: Maybe URL
  } deriving (Eq, Show, Generic, Data, Typeable)
```

Update the `IsString License` instance (around line 149) to account for the new field, which
sits between `name` and `url`:

```haskell
instance IsString License where
  fromString s = License (fromString s) Nothing Nothing
```

That is the complete set of source edits for M1: because `Info` and `License` serialize
through `genericToJSON (jsonPrefix "Info")` / `(jsonPrefix "License")` with
`omitNothingFields = True`, the new `Maybe Text` fields automatically map to the keys
`"summary"` / `"identifier"` and are omitted when `Nothing`. The `makeFields` calls in
`Lens.hs` and the `makeFieldLabels` calls in `Optics.hs` regenerate the `summary`/`identifier`
accessors automatically. The `genericMempty`/`genericMappend` `Monoid` instances absorb the
new fields automatically.

**Test edits** in `test/Data/OpenApiSpec.hs`:

Extend `infoExample` to set a summary and add the key to `infoExampleJSON` so the existing
`<=>` round-trip continues to hold *and* now covers `summary`:

```haskell
infoExample :: Info
infoExample = mempty
  & title          .~ "Swagger Sample App"
  & summary        ?~ "A sample Swagger app"
  & description    ?~ "This is a sample server Petstore server."
  & termsOfService ?~ "http://swagger.io/terms/"
  & contact        ?~ contactExample
  & license        ?~ licenseExample
  & version        .~ "1.0.1"
```

```json
{
  "title": "Swagger Sample App",
  "summary": "A sample Swagger app",
  "description": "This is a sample server Petstore server.",
  "termsOfService": "http://swagger.io/terms/",
  "contact": { "name": "API Support", "url": "http://www.swagger.io/support", "email": "support@swagger.io" },
  "license": { "name": "Apache 2.0", "url": "http://www.apache.org/licenses/LICENSE-2.0.html" },
  "version": "1.0.1"
}
```

Add a focused `License` example that exercises `identifier` (do **not** change the existing
`licenseExample`, which carries `url`; SPDX and url are mutually exclusive, so keep them in
separate examples). Add a new describe block referencing it, mirroring the existing
`licenseExample <=> licenseExampleJSON` line near the top of `spec`:

```haskell
licenseIdentifierExample :: License
licenseIdentifierExample = "MIT"
  & identifier ?~ "MIT"

licenseIdentifierExampleJSON :: Value
licenseIdentifierExampleJSON = [aesonQQ|
{
  "name": "MIT",
  "identifier": "MIT"
}
|]
```

```haskell
-- inside `spec`, near the existing "License Object" line:
describe "License Object (SPDX identifier)" $ licenseIdentifierExample <=> licenseIdentifierExampleJSON
```

**Commands.**

```bash
nix develop -c cabal build all
nix develop -c cabal test all
```

**Acceptance.** `cabal build all` succeeds. `cabal test all` passes, including the updated
"Info Object" block (now carrying `summary`) and the new "License Object (SPDX identifier)"
block. Concretely: decoding `{"name":"MIT","identifier":"MIT"}` yields
`License "MIT" (Just "MIT") Nothing` and re-encoding yields back the same two keys (`name`,
`identifier`) with no `url` key.


### Milestone 2 — `OpenApi.webhooks`

**Scope.** Add `_openApiWebhooks :: InsOrdHashMap Text (Referenced PathItem)` to the `OpenApi`
root record, provide the `ToJSON`/`FromJSON` instances for `Referenced PathItem` (these do not
yet exist; the existing `Referenced` instances cover `Schema`, `Param`, `Response`, etc., but
not `PathItem`), and add a round-trip test for the `webhooks` fragment.

**What will exist at the end.** A 3.1 document containing a top-level `webhooks` map decodes
into `OpenApi` with that map populated, and re-encodes to the same `webhooks` JSON. The
optic `#webhooks` and lens `webhooks` exist.

**Edits.**

In `src/Data/OpenApi/Internal.hs`, inside `data OpenApi` (around line 58), insert the webhooks
field after `_openApiPaths` (mirroring the spec's ordering, where `webhooks` sits alongside
`paths`):

```haskell
    -- | The available paths and operations for the API.
  , _openApiPaths :: InsOrdHashMap FilePath PathItem

    -- | The incoming webhooks that MAY be received as part of this API,
    -- and that the API consumer MAY choose to implement. (OpenAPI 3.1)
    -- Each value is a Path Item Object or a Reference Object.
  , _openApiWebhooks :: InsOrdHashMap Text (Referenced PathItem)
  -- ... remaining fields unchanged ...
```

Add `ToJSON`/`FromJSON` instances for `Referenced PathItem`. The repo already defines the
generic helpers `referencedToJSON :: ToJSON a => Text -> Referenced a -> Value` (line ~1416)
and `referencedParseJSON :: FromJSON a => Text -> Value -> Parser (Referenced a)` (line ~1564),
and a column of one-line instances for the other referenced types (lines ~1420 and ~1577).
Append a `PathItem` line to each column. Per the OpenAPI 3.1 spec, path-item references live
under `#/components/pathItems/`, so use that prefix:

```haskell
-- alongside the other `instance ToJSON (Referenced X)` lines (~1420):
instance ToJSON (Referenced PathItem) where toJSON = referencedToJSON "#/components/pathItems/"
```

```haskell
-- alongside the other `instance FromJSON (Referenced X)` lines (~1577):
instance FromJSON (Referenced PathItem) where parseJSON = referencedParseJSON "#/components/pathItems/"
```

No change is needed to `OpenApi`'s own `ToJSON`/`FromJSON`: it uses the SOP path
(`sopSwaggerGenericToJSON` / `sopSwaggerGenericParseJSON`), which derives the key `"webhooks"`
from `_openApiWebhooks` automatically and omits the field when the map is empty (the
`AesonDefaultValue (InsOrdHashMap k v)` instance, defined in `AesonUtils.hs` line ~75, makes
the empty map the default-and-omitted value). The `deriveGeneric ''OpenApi` call (line ~987)
regenerates the SOP representation including the new field. `makeFields ''OpenApi` (Lens.hs)
and `makeFieldLabels ''OpenApi` (Optics.hs) regenerate `webhooks`/`#webhooks` automatically.
`genericMempty`/`genericMappend` absorb the new field (empty map default).

**Test edits** in `test/Data/OpenApiSpec.hs`. Add a self-contained round-trip for the
webhooks fragment from `OPENAPI31_MIGRATION_PLAN.md` §6.1 example 5. Build the expected
Haskell value with `mempty :: OpenApi` plus the `webhooks` lens, and assert it round-trips
against the JSON with `<=>`:

```haskell
webhooksExample :: OpenApi
webhooksExample = mempty
  & webhooks .~ IOHM.fromList
      [ ("newPet", Inline (mempty
          & post ?~ (mempty
              & requestBody ?~ Inline (mempty
                  & description ?~ "Information about a new pet in the system")
              & at 200 ?~ Inline (mempty
                  & description .~ "Return a 200 status to indicate ok"))))
      ]

webhooksExampleJSON :: Value
webhooksExampleJSON = [aesonQQ|
{
  "openapi": "3.0.0",
  "info": { "title": "", "version": "" },
  "paths": {},
  "components": {},
  "webhooks": {
    "newPet": {
      "post": {
        "requestBody": { "description": "Information about a new pet in the system", "content": {} },
        "responses": { "200": { "description": "Return a 200 status to indicate ok" } }
      }
    }
  }
}
|]
```

```haskell
-- inside `spec`:
describe "Webhooks Object (OpenAPI 3.1)" $ webhooksExample <=> webhooksExampleJSON
```

A note on the surrounding keys: the existing `OpenApi` round-trip helpers always emit
`openapi`, `info`, `paths`, and `components` (the latter two are forced non-empty / always
present by the existing instances — see the `ToJSON OpenApi` instance that injects an empty
`paths` object, line ~1321). The exact set of always-present keys may differ slightly in this
repo's current state; when implementing, first run the existing `OpenApi` round-trip tests to
observe the canonical empty-document shape, then mirror it in `webhooksExampleJSON` so the
comparison isolates the `webhooks` key. The `openapi` version string can be any value in the
currently-accepted range — at the time this plan is written the version bounds are still 3.0.x
(`lowerOpenApiSpecVersion`/`upperOpenApiSpecVersion` in `Internal.hs` ~96–101). EP-3 raises
those to 3.1.x; if EP-3 has landed, use `"3.1.0"` here, otherwise `"3.0.0"`. The `webhooks`
field itself is independent of the version string in this library's decoder, so either works
for the round-trip.

If you prefer to avoid coupling the test to the full empty-document key set, an equivalent and
simpler acceptance is a *Haskell-value* round-trip that does not pin the surrounding JSON:

```haskell
-- property-style, independent of the empty-document key shape:
it "round-trips webhooks through encode/decode" $
  decode (encode webhooksExample) `shouldBe` Just webhooksExample
```

Use whichever form is least brittle against the current `OpenApi` instance; the
`decode . encode` form is recommended because it does not depend on the exact set of
always-emitted keys.

**Imports.** `Inline` and `Referenced` come from `Data.OpenApi.Internal` (re-exported by
`Data.OpenApi`). The test already imports the lens accessors and `aesonQQ`. If `IOHM`
(`Data.HashMap.Strict.InsOrd`) is not already imported in the spec, add it; check the existing
import list first to avoid a duplicate.

**Commands.**

```bash
nix develop -c cabal build all
nix develop -c cabal test all
```

**Acceptance.** `decode (encode webhooksExample) == Just webhooksExample`. When encoded, the
document contains a `"webhooks"` object whose `"newPet"` value is an inline path item with a
`"post"` operation — proving `Referenced PathItem` serializes its `Inline` case as the bare
path item (not wrapped in `$ref`). A separate check decodes
`{"newPet": {"$ref": "#/components/pathItems/Foo"}}` into
`Inline (... )`? No — into `Ref (Reference "Foo")`, proving the reference case decodes through
`referencedParseJSON "#/components/pathItems/"`.


### Milestone 3 — `PathItem.$ref`

**Scope.** Add `_pathItemRef :: Maybe Text` to `PathItem` and make it serialize to / parse
from the `$`-prefixed JSON key `"$ref"`. This is the only milestone needing custom key
handling, because the generic machinery cannot emit a leading `$`.

**What will exist at the end.** A `PathItem` value with `_pathItemRef = Just
"#/components/pathItems/Foo"` encodes to JSON containing `"$ref":
"#/components/pathItems/Foo"` (not `"ref": ...`), and a JSON path item carrying `"$ref"`
decodes back into that field. The `ref` lens and `#ref` optic exist.

**Edits.**

In `src/Data/OpenApi/Internal.hs`, inside `data PathItem` (around line 207), insert the new
field at the **front** of the record (the spec lists `$ref` first), before the already-present
`_pathItemSummary`:

```haskell
data PathItem = PathItem
  { -- | A reference (@$ref@) to an externally-defined Path Item Object,
    -- whose definition replaces this one, with 'summary' and 'description'
    -- providing optional overrides. (OpenAPI 3.1)
    _pathItemRef :: Maybe Text

    -- | An optional, string summary, intended to apply to all operations in this path.
  , _pathItemSummary :: Maybe Text

    -- | An optional, string description ...
  , _pathItemDescription :: Maybe Text
  -- ... remaining fields unchanged ...
  } deriving (Eq, Show, Generic, Data, Typeable)
```

Adding the field regenerates the `ref` lens (via `makeLensesWith swaggerFieldRules ''PathItem`
in `Lens.hs`; `ref` is not a keyword clash, so `swaggerFieldNamer` leaves it as `ref`) and the
`#ref` optic (via `makeFieldLabels ''PathItem` in `Optics.hs`). `deriveGeneric ''PathItem`
(line ~980) regenerates the SOP representation. `genericMempty` makes the default `Nothing`.

**The `$ref` key problem and its fix.** `PathItem` serializes through the SOP path
(`instance ToJSON PathItem where toJSON = sopSwaggerGenericToJSON`, line ~1386, and
`instance FromJSON PathItem where parseJSON = sopSwaggerGenericParseJSON`, line ~1542). Left
alone, the SOP layer would derive the key `"ref"` from `_pathItemRef` (strip `_pathItem`
prefix → `Ref` → lower-case first letter → `ref`). We must intercept this so the key is
`"$ref"` on the way out and the parser reads `"$ref"` on the way in.

**Preferred mechanism (EP-4 helper, IP-3).** If
`docs/plans/4-openapi-3-1-json-schema-fields-and-reference-keywords.md` has been implemented,
it owns a canonical helper for `$`-prefixed keys. Open that plan and find the helper's name
and module (search its "Interfaces and Dependencies" section, and grep the source for the
function it introduces, e.g. `grep -rn 'dollarKey\|prefixedKey\|\$ref' src/Data/OpenApi/`).
Import and apply it for `PathItem.$ref` exactly as EP-4 documents, then skip the fallback
below.

**Fallback mechanism (EP-4 not yet landed — current situation).** As of this writing EP-4 is a
skeleton, so implement a minimal local helper by hand-writing `PathItem`'s `ToJSON`/`FromJSON`
as a thin wrapper around the generic ones that *renames* the `ref` key to/from `$ref`. Replace
the two existing one-line instances (lines ~1386 and ~1542) with:

```haskell
-- TODO(EP-4): replace this bespoke $ref handling with the shared $-prefixed-key
-- helper that EP-4 owns (master plan Integration Point IP-3). Until EP-4 lands,
-- we rename the generically-derived "ref" key to/from the spec key "$ref" here.
instance ToJSON PathItem where
  toJSON p = renameKey "ref" "$ref" (sopSwaggerGenericToJSON p)

instance FromJSON PathItem where
  parseJSON = sopSwaggerGenericParseJSON . renameKey "$ref" "ref"
```

where `renameKey` is a small local helper added near the other JSON helpers (for example just
below `referencedToJSON`, around line 1418). It operates on a `Data.Aeson.Value`, renaming a
single object key when present and leaving everything else untouched. Because this file already
conditionally imports `Data.Aeson.KeyMap` (guarded by `MIN_VERSION_aeson(2,0,0)` at line ~11)
and uses key helpers from `Data.OpenApi.Aeson.Compat` (`deleteKey` is already imported), use
those compat helpers so the code builds across the aeson versions this repo supports. A direct
implementation against `aeson >= 2`'s `KeyMap`:

```haskell
-- | Rename a single top-level object key from @old@ to @new@ if present.
-- Leaves non-objects and objects lacking @old@ unchanged. Local stop-gap;
-- see TODO(EP-4) above.
renameKey :: Text -> Text -> Value -> Value
renameKey oldK newK (Object o) =
  case KeyMap.lookup (Key.fromText oldK) o of
    Nothing -> Object o
    Just v  -> Object (KeyMap.insert (Key.fromText newK) v (KeyMap.delete (Key.fromText oldK) o))
renameKey _ _ v = v
```

This needs `import qualified Data.Aeson.Key as Key` (add it near the existing
`import qualified Data.Aeson.KeyMap as KeyMap`, under the same `MIN_VERSION_aeson(2,0,0)`
guard). If the repo must also build on `aeson < 2` (check the `.cabal` `build-depends`
bound for `aeson`; the master plan's EP-1 narrows the toolchain to GHC 9.12+, which ships
`aeson >= 2`, so on the modernized toolchain the `KeyMap` path is the only one needed), guard
the helper with CPP mirroring the existing `#if MIN_VERSION_aeson(2,0,0)` blocks and provide a
`HashMap`-based branch using `Data.OpenApi.Aeson.Compat`. Prefer to rely on EP-1 having landed
(aeson 2 only) to keep this stop-gap small; note the assumption in a `Surprises &
Discoveries` entry if you must add the CPP branch.

When the `FromJSON` parser runs, the incoming object key is `"$ref"`; `renameKey "$ref" "ref"`
turns it into `"ref"` *before* `sopSwaggerGenericParseJSON` runs, so the generic parser (which
expects the derived key `"ref"`) finds it. The field is a `Maybe Text` with default
`Just Nothing`, so a path item lacking `$ref` parses fine (no key, field stays `Nothing`) and
encodes without emitting `$ref`.

**A subtlety to verify, not assume.** `sopSwaggerGenericToJSON` omits a field whose value
equals its `AesonDefaultValue` default. For `Maybe Text` the default is `Just Nothing`, so
`_pathItemRef = Nothing` emits no `"ref"` key, and `renameKey "ref" "$ref"` is a no-op (the key
isn't there) — correct. When `_pathItemRef = Just "..."`, the generic layer emits
`"ref": "..."`, and `renameKey` rewrites it to `"$ref": "..."` — correct. Confirm both with the
tests below rather than trusting this paragraph.

**Test edits** in `test/Data/OpenApiSpec.hs`. Add a focused `PathItem` round-trip carrying
`$ref` and a `summary` override:

```haskell
pathItemRefExample :: PathItem
pathItemRefExample = mempty
  & ref     ?~ "#/components/pathItems/Foo"
  & summary ?~ "Shared path item"

pathItemRefExampleJSON :: Value
pathItemRefExampleJSON = [aesonQQ|
{
  "$ref": "#/components/pathItems/Foo",
  "summary": "Shared path item"
}
|]
```

```haskell
-- inside `spec`:
describe "PathItem Object ($ref, OpenAPI 3.1)" $ pathItemRefExample <=> pathItemRefExampleJSON
```

`ref` and `summary` are the lenses generated by `makeLensesWith swaggerFieldRules ''PathItem`.
If the spec module imports lenses qualified or via `Data.OpenApi`, the names are already in
scope (the existing `pathItem`-related examples use `summary` already).

**Commands.**

```bash
nix develop -c cabal build all
nix develop -c cabal test all
```

**Acceptance.** `encode pathItemRefExample` produces JSON whose keys are exactly `"$ref"` and
`"summary"` (the literal dollar-prefixed key, *not* `"ref"`). `decode` of
`pathItemRefExampleJSON` yields `pathItemRefExample`. The `<=>` round-trip passes in both
directions. Grep the encoded output in the test (or add an explicit assertion) to confirm the
substring `"$ref"` appears and `"ref"` (without `$`) does not.


## Concrete Steps

Run everything from the repo root,
`/Users/shinzui/Keikaku/hub/haskell/openapi3`. The shell prompt is omitted; each fenced block
is a command to run, followed by what you should see.

First, establish a clean baseline so you can tell which test failures are new:

```bash
nix develop -c cabal build all
```

Expected: the project compiles. If it does not compile *before* your changes, stop and
resolve the pre-existing breakage (or note in Surprises & Discoveries that EP-3/EP-4 are
mid-flight) before proceeding — this plan assumes a compiling tree.

```bash
nix develop -c cabal test all
```

Expected: the existing suite passes (a summary line such as
`N examples, 0 failures`). Record the example count so you can confirm your new cases were
added.

Then implement M1, M2, M3 in order, rebuilding and re-testing after each:

```bash
nix develop -c cabal build all && nix develop -c cabal test all
```

Expected after M1: build succeeds; the "Info Object" block now round-trips with a `summary`
key and a new "License Object (SPDX identifier)" block passes. Example count increases by at
least one.

Expected after M2: build succeeds; a "Webhooks Object (OpenAPI 3.1)" case passes
(`decode (encode webhooksExample) == Just webhooksExample`).

Expected after M3: build succeeds; a "PathItem Object ($ref, OpenAPI 3.1)" case passes, and the
encoded `PathItem` contains the literal key `"$ref"`.

To inspect the emitted JSON for the `$ref` key directly (sanity check outside the suite), use
GHCi:

```bash
nix develop -c cabal repl openapi3
```

```haskell
:set -XOverloadedStrings
import Data.OpenApi
import Data.Aeson (encode)
import Control.Lens ((&), (?~))
encode (mempty & ref ?~ "#/components/pathItems/Foo" :: PathItem)
```

Expected output contains `"$ref":"#/components/pathItems/Foo"` and does **not** contain a bare
`"ref":` key.


## Validation and Acceptance

Acceptance is behavioral and observable through the test suite plus the GHCi spot-check above.
Concretely, after all three milestones:

1. **`Info.summary` round-trips.** Decoding the updated `infoExampleJSON` (which now contains
   `"summary": "A sample Swagger app"`) yields an `Info` whose `summary` lens returns
   `Just "A sample Swagger app"`, and re-encoding reproduces the `"summary"` key. Observed via
   the "Info Object" `<=>` block.

2. **`License.identifier` round-trips and is `url`-free.** Decoding
   `{"name":"MIT","identifier":"MIT"}` yields `License "MIT" (Just "MIT") Nothing`; encoding it
   back emits exactly `name` and `identifier` and **no** `url`. Observed via the new
   "License Object (SPDX identifier)" `<=>` block. (Mutual exclusivity is documented, not
   enforced — a document setting both `identifier` and `url` still decodes; see Decision Log.)

3. **`OpenApi.webhooks` round-trips a `Referenced PathItem` map.** The fragment

   ```json
   { "webhooks": { "newPet": { "post": { "requestBody": { "description": "Information about a new pet in the system" }, "responses": { "200": { "description": "Return a 200 status to indicate ok" } } } } } }
   ```

   decodes into an `OpenApi` whose `webhooks` map has key `"newPet"` mapping to an
   `Inline PathItem` with a `post` operation, and `decode (encode doc) == Just doc`. A separate
   decode of `{"newPet": {"$ref": "#/components/pathItems/Foo"}}` yields
   `Ref (Reference "Foo")` for that entry, proving the reference branch. Observed via the
   "Webhooks Object (OpenAPI 3.1)" case.

4. **`PathItem.$ref` emits the dollar-prefixed key.** Encoding a `PathItem` with
   `_pathItemRef = Just "#/components/pathItems/Foo"` and `_pathItemSummary = Just "..."`
   yields JSON whose keys are `"$ref"` and `"summary"`; decoding that JSON returns the same
   value. The literal `"$ref"` substring is present and a bare `"ref"` key is absent. Observed
   via the "PathItem Object ($ref, OpenAPI 3.1)" `<=>` block and the GHCi spot-check.

The single overall gate:

```bash
nix develop -c cabal build all && nix develop -c cabal test all
```

must succeed with zero failures and a higher example count than the baseline recorded in
Concrete Steps. Beyond compilation, the four cases above prove the new fields carry data
through a full encode/decode cycle and emit the correct spec keys — especially the
dollar-prefixed `$ref`.


## Idempotence and Recovery

Every edit in this plan is additive and re-runnable. The record-field insertions, the
`Referenced PathItem` instances, the `IsString License` update, and the test additions can be
applied once; re-applying them is a no-op if the text already matches (use the exact snippets
above). If a build fails mid-way:

- **Duplicate-field or ambiguous-lens errors** usually mean a field name collides. None of
  `summary` (on `Info`), `identifier`, `webhooks`, or `ref` (on `PathItem`) currently exist as
  fields, so a collision means a prior milestone's edit was partially applied or another plan
  (EP-3/EP-4) added an overlapping name — grep `src/Data/OpenApi/` for the field and reconcile.
- **`IsString License` arity error** (`License` applied to the wrong number of arguments) means
  the `fromString` instance was not updated to the new three-field shape; apply the M1
  `IsString` edit.
- **`$ref` shows up as `"ref"` in test output** means the M3 `renameKey` wrapping is missing or
  the EP-4 helper was not actually applied; re-check that the `PathItem` `ToJSON`/`FromJSON`
  instances were replaced (not left as the original one-liners).
- **`AesonDefaultValue` / "no instance" errors for the webhooks field** are unexpected because
  the `InsOrdHashMap` instance already exists; if seen, confirm you did not change the field's
  type away from `InsOrdHashMap Text (Referenced PathItem)`.

To roll back, revert the touched files (`src/Data/OpenApi/Internal.hs`,
`test/Data/OpenApiSpec.hs`, and — only if you hand-edited them, which this plan does not
require — `src/Data/OpenApi/Lens.hs` / `src/Data/OpenApi/Optics.hs`) with `git checkout --`.
No data migrations or destructive operations are involved. Do **not** `git commit` as part of
executing this plan unless explicitly asked.


## Interfaces and Dependencies

All work is inside the existing `openapi3` library; no new package dependencies are
introduced. The libraries already in play and used here are `aeson` (JSON), `lens` and
`optics` (accessors), `generics-sop` (the SOP serialization layer), and
`insert-ordered-containers` (the `InsOrdHashMap` re-exported as
`Data.HashMap.Strict.InsOrd.Compat`).

Types, instances, and accessors that must exist at the end of each milestone, by full module
path:

**End of M1** (`src/Data/OpenApi/Internal.hs`):

```haskell
data Info    = Info    { _infoTitle :: Text, _infoSummary :: Maybe Text, ... }
data License = License { _licenseName :: Text, _licenseIdentifier :: Maybe Text, _licenseUrl :: Maybe URL }
instance IsString License  -- updated to 3-field positional constructor
```

with generated accessors `summary :: Lens' ... (Maybe Text)` and
`identifier :: Lens' ... (Maybe Text)` from `Data.OpenApi.Lens`, and optics `#summary` /
`#identifier` from `Data.OpenApi.Optics`.

**End of M2** (`src/Data/OpenApi/Internal.hs`):

```haskell
data OpenApi = OpenApi { ..., _openApiWebhooks :: InsOrdHashMap Text (Referenced PathItem), ... }
instance ToJSON   (Referenced PathItem)
instance FromJSON (Referenced PathItem)
```

with generated `webhooks` lens (`Data.OpenApi.Lens`) and `#webhooks` optic
(`Data.OpenApi.Optics`). The instances reuse the existing
`referencedToJSON`/`referencedParseJSON` helpers (same module) with the prefix
`"#/components/pathItems/"`.

**End of M3** (`src/Data/OpenApi/Internal.hs`):

```haskell
data PathItem = PathItem { _pathItemRef :: Maybe Text, _pathItemSummary :: Maybe Text, ... }
instance ToJSON   PathItem  -- wraps sopSwaggerGenericToJSON, renaming "ref" -> "$ref"
instance FromJSON PathItem  -- renames "$ref" -> "ref" before sopSwaggerGenericParseJSON
renameKey :: Text -> Text -> Value -> Value  -- local stop-gap, TODO(EP-4)
```

with generated `ref` lens (`Data.OpenApi.Lens`, via `makeLensesWith swaggerFieldRules`) and
`#ref` optic (`Data.OpenApi.Optics`). If
`docs/plans/4-openapi-3-1-json-schema-fields-and-reference-keywords.md` is implemented when M3
runs, replace `renameKey` and the bespoke instance wrappers with EP-4's shared `$`-key helper
(master plan Integration Point IP-3) and delete the `TODO(EP-4)` marker.

**Cross-plan dependencies.** This plan **hard-depends on EP-3**
(`docs/plans/3-openapi-3-1-core-schema-type-changes.md`) for the reshaped core and updated
version constants, and **soft-depends on EP-4**
(`docs/plans/4-openapi-3-1-json-schema-fields-and-reference-keywords.md`) for the canonical
`$`-key helper. It does **not** touch the `Schema` record or `OpenApiItems` (Integration Point
IP-2; those are owned by EP-3/EP-4). It is consumed downstream by EP-7
(`docs/plans/7-openapi-3-1-migration-helpers-tests-and-release.md`), which exercises these
fields in the comprehensive test suite.


## Revision Notes

- 2026-06-10: Initial full draft of EP-5 from the skeleton. Filled Purpose, Context, three
  milestones (M1 Info.summary + License.identifier, M2 OpenApi.webhooks, M3 PathItem.$ref),
  Concrete Steps, Validation, Idempotence, and Interfaces. Seeded the Decision Log with the
  three decisions called for by the master plan and EP-5 scope: `Referenced PathItem` (not bare)
  for webhooks; reuse of EP-4's `$`-key helper with a local `TODO(EP-4)` fallback because EP-4
  is currently a skeleton; and document-only (not enforced) handling of `License.identifier`
  vs `url` mutual exclusivity. Why: the master plan assigns EP-5 these four top-level fields and
  Integration Points IP-2 (no Schema edits) and IP-3 (reuse the `$`-key helper); this draft
  encodes those constraints so a novice can implement without reading the other plans.
