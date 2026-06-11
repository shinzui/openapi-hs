# OpenAPI 3.1 Support Migration Plan

This document outlines the changes required to support OpenAPI 3.1 in the `openapi3` Haskell library.

## Executive Summary

OpenAPI 3.1 represents a significant evolution from 3.0, primarily through its adoption of JSON Schema 2020-12. This migration requires changes to core data types, serialization logic, and validation. The recommended approach is a **breaking change release** (version 4.0.0).

### Version Support Decision (read this first)

Several 3.1 changes make 3.0 documents **unrepresentable** in the same types: removing `nullable`, removing `OpenApiItemsArray` (tuple) validation, and changing `exclusiveMaximum`/`exclusiveMinimum` from `Bool` to `Scientific`. Two mutually exclusive strategies follow from this:

- **Strategy A — 3.1-only types (SELECTED).** The data types represent 3.1 only. A 3.0 document cannot be decoded directly; users migrate via provided helper functions that operate on *raw `Value`s* or on a separate legacy type. Clean API, no round-trip guarantee for 3.0.
- **Strategy B — version-aware types (NOT selected).** Keep both representations live (e.g. `nullable` *and* type arrays, `Bool` *and* `Scientific` exclusive bounds) and branch serialization on the detected version. Preserves 3.0 round-tripping at the cost of a larger, more confusing API.

**This plan assumes Strategy A throughout.** Wherever "migration" is mentioned, it means converting an already-parsed 3.0 `Value` (or legacy type) into a 3.1 `Schema` — *not* keeping 3.0 fields on the 3.1 type. The version-detection utility in Phase 3 is for **reading** a document and routing it to the right decoder, not for storing two representations on one type.

## Background

### Current State
- Library version: 3.2.4
- Supported OpenAPI versions: 3.0.0 - 3.0.3
- Version bounds defined in `src/Data/OpenApi/Internal.hs:110-115`

### OpenAPI 3.1 Key Changes
OpenAPI 3.1.0 was released in February 2021 with these major changes:
1. Full JSON Schema 2020-12 compatibility
2. Webhooks support
3. Path item `$ref` with summary/description override
4. Info object `summary` field
5. License object `identifier` field (SPDX)

---

## Phase 1: Core Type Changes

### 1.1 Schema Type Modifications

**File:** `src/Data/OpenApi/Internal.hs`

#### 1.1.1 Type Field (Breaking Change)

**Current (line 661):**
```haskell
_schemaType :: Maybe OpenApiType
```

**Required for 3.1:**
```haskell
_schemaType :: Maybe OpenApiTypeValue

-- New type to support type arrays
data OpenApiTypeValue
  = OpenApiTypeSingle OpenApiType
  | OpenApiTypeArray [OpenApiType]  -- e.g., ["string", "null"]
  deriving (Eq, Show, Generic, Data, Typeable)
```

**Rationale:** 3.1 allows `type` to be an array for union types (e.g., `type: ["string", "null"]`).

#### 1.1.2 Exclusive Bounds (Breaking Change)

**Current (lines 665-667):**
```haskell
_schemaExclusiveMaximum :: Maybe Bool
_schemaExclusiveMinimum :: Maybe Bool
```

**Required for 3.1:**
```haskell
_schemaExclusiveMaximum :: Maybe Scientific
_schemaExclusiveMinimum :: Maybe Scientific
```

**Rationale:** In JSON Schema 2020-12, `exclusiveMaximum` and `exclusiveMinimum` are numeric values, not boolean modifiers.

**Coexistence note:** `_schemaMaximum`/`_schemaMinimum` (`Internal.hs:664, 666`) stay as-is. In 3.0 the boolean `exclusiveMaximum` *modified* `maximum`; in 3.1 they are **independent** keywords — a schema may legally carry both `maximum` and (numeric) `exclusiveMaximum`. Migration of a 3.0 `{ "maximum": 100, "exclusiveMaximum": true }` must rewrite to `{ "exclusiveMaximum": 100 }` (dropping `maximum`); `{ "maximum": 100, "exclusiveMaximum": false }` becomes `{ "maximum": 100 }`. Validation (Phase 5) must treat the two keywords independently.

#### 1.1.3 Remove Nullable Field

**Current (line 635):**
```haskell
_schemaNullable :: Maybe Bool
```

**Required for 3.1:** Remove this field entirely (Strategy A). There is no `nullable` keyword in JSON Schema 2020-12.

**Rationale:** 3.1 uses `type: ["string", "null"]` instead of `nullable: true`. Keeping the field would let users produce invalid 3.1 documents.

> **Note:** Because the field is removed, there is **no** `{-# DEPRECATED _schemaNullable #-}` pragma — you cannot deprecate a field that no longer exists. (The earlier draft of this plan contradicted itself here; see Phase 5.2, which has been corrected.)

**Migration helper:** Conversion happens at the *raw `Value`* layer, before a 3.1 `Schema` exists — it cannot reference `_schemaNullable`, since the 3.1 type has no such field. The helper rewrites a decoded 3.0 JSON object:

```haskell
-- Operates on raw JSON parsed from a 3.0 document, producing a 3.1-shaped Value
-- that can then be decoded into the 3.1 'Schema'.
migrate30NullableValue :: Value -> Value
migrate30NullableValue (Object o)
  | KeyMap.lookup "nullable" o == Just (Bool True) =
      Object (KeyMap.delete "nullable" (addNullToTypeKey o))
  | otherwise = Object (KeyMap.delete "nullable" o)
migrate30NullableValue v = v

-- Rewrites "type": "string"  ->  "type": ["string", "null"]
--          "type": ["string"] -> "type": ["string", "null"]
addNullToTypeKey :: Object -> Object
addNullToTypeKey = ...  -- see Phase 4 for the type-array representation
```

#### 1.1.4 New JSON Schema Fields

Add the following fields to `Schema`:

```haskell
data Schema = Schema
  { -- ... existing fields ...

  -- JSON Schema 2020-12 additions
  , _schemaConst :: Maybe Value                           -- const keyword
  , _schemaPrefixItems :: Maybe [Referenced Schema]       -- tuple validation
  , _schemaContains :: Maybe (Referenced Schema)          -- array contains
  , _schemaMinContains :: Maybe Integer                   -- min contains count
  , _schemaMaxContains :: Maybe Integer                   -- max contains count
  , _schemaIf :: Maybe (Referenced Schema)                -- conditional: if
  , _schemaThen :: Maybe (Referenced Schema)              -- conditional: then
  , _schemaElse :: Maybe (Referenced Schema)              -- conditional: else
  , _schemaDependentSchemas :: Maybe (InsOrdHashMap Text (Referenced Schema))
  , _schemaDependentRequired :: Maybe (InsOrdHashMap Text [Text])
  , _schemaUnevaluatedProperties :: Maybe AdditionalProperties
  , _schemaUnevaluatedItems :: Maybe (Referenced Schema)
  , _schemaPropertyNames :: Maybe (Referenced Schema)     -- validate property names
  , _schemaContentEncoding :: Maybe Text                  -- e.g., "base64"
  , _schemaContentMediaType :: Maybe Text                 -- e.g., "image/png"
  , _schemaContentSchema :: Maybe (Referenced Schema)     -- schema for decoded content
  , _schemaExamples :: Maybe [Value]                      -- JSON Schema "examples" array (3.1)

  -- JSON Schema identification
  , _schemaId :: Maybe Text                               -- $id
  , _schemaAnchor :: Maybe Text                           -- $anchor
  , _schemaDefs :: Maybe (InsOrdHashMap Text (Referenced Schema))  -- $defs
  , _schemaRef :: Maybe Text                              -- $ref (see design note below)
  , _schemaDynamicRef :: Maybe Text                       -- $dynamicRef
  , _schemaDynamicAnchor :: Maybe Text                    -- $dynamicAnchor
  }
```

> **Spec-validated — `example` (singular) is retained but deprecated.** The existing `_schemaExample :: Maybe Value` (`Internal.hs:648`) stays for compatibility but OpenAPI 3.1 deprecates it in favor of the JSON Schema `examples` array. Mark it `{-# DEPRECATED _schemaExample "Use _schemaExamples (JSON Schema 'examples') in OpenAPI 3.1" #-}` — this is a *retained* field, so the pragma is valid here (unlike `_schemaNullable`, which is removed). ([migration guide](https://www.openapis.org/blog/2021/02/16/migrating-from-openapi-3-0-to-3-1-0))
>
> **Spec-validated — boolean schemas are broader than `items`.** In JSON Schema 2020-12 / OpenAPI 3.1, `true`/`false` is a valid schema in **any** schema position (`additionalProperties`, `items`, `unevaluatedItems`, members of `prefixItems`, `properties` values, `contains`, etc.), not just `items`. The §1.1 additions type many of these as `Referenced Schema`, which cannot represent a bare boolean. Two options: (a) extend `Referenced`/`Schema` decoding so a JSON boolean maps to an always-true/always-false `Schema` (e.g. `false` → a schema with `not: {}`); or (b) introduce a dedicated sum (`BoolOr (Referenced Schema)`) for the affected fields. The plan's `OpenApiItemsBoolean` (§1.2) only patches the `items` case and leaves the rest unable to round-trip `true`/`false`. Decide this alongside the `$ref` spike. ([spec.openapis.org/oas/v3.1.0](https://spec.openapis.org/oas/v3.1.0))

> **Design note — `$ref` is not a simple field.** The library already models references with `Referenced Schema` (`Ref` | `Inline`), which in 3.0 is mutually exclusive with any sibling keywords. JSON Schema 2020-12 changes this: `$ref` may appear **alongside** sibling keywords. Adding `_schemaRef :: Maybe Text` therefore introduces a *second* way to express a reference that can coexist with the existing `Referenced` wrapper, and the two must be reconciled:
> - Decide whether `$ref`-with-siblings decodes to `Inline (Schema { _schemaRef = Just ... })` or stays at the `Referenced` layer.
> - Audit every site that pattern-matches `Referenced` to ensure it accounts for inline schemas that *also* carry `_schemaRef`.
> - All five `$`-keys here (`$ref`, `$id`, `$anchor`, `$dynamicRef`, `$dynamicAnchor`) hit the §4.0 prefix-mapping problem.
>
> This is a genuine design task, not a field addition. It should get its own small spike before Milestone 2.

### 1.2 OpenApiItems Changes

**File:** `src/Data/OpenApi/Internal.hs` (lines 597-600)

**Current:**
```haskell
data OpenApiItems where
  OpenApiItemsObject :: Referenced Schema -> OpenApiItems
  OpenApiItemsArray  :: [Referenced Schema] -> OpenApiItems
```

**Required for 3.1:**
The `items` keyword in 3.1 can only be a single schema (or boolean). Tuple validation uses `prefixItems`.

```haskell
-- Simplified for 3.1
data OpenApiItems where
  OpenApiItemsObject :: Referenced Schema -> OpenApiItems
  OpenApiItemsBoolean :: Bool -> OpenApiItems  -- items: true/false
```

**Note:** `OpenApiItemsArray` should be removed as tuple validation moves to `_schemaPrefixItems`.

---

## Phase 2: Top-Level OpenAPI Object Changes

### 2.1 Webhooks Support

**File:** `src/Data/OpenApi/Internal.hs`

Add webhooks field to `OpenApi` type (around line 72):

```haskell
data OpenApi = OpenApi
  { _openApiInfo :: Info
  , _openApiServers :: [Server]
  , _openApiPaths :: InsOrdHashMap FilePath PathItem
  , _openApiWebhooks :: InsOrdHashMap Text (Referenced PathItem)  -- NEW
  , _openApiComponents :: Components
  , _openApiSecurity :: [SecurityRequirement]
  , _openApiTags :: InsOrdHashSet Tag
  , _openApiExternalDocs :: Maybe ExternalDocs
  , _openApiOpenapi :: OpenApiSpecVersion
  }
```

> **Spec-validated:** the OpenAPI 3.1.0 fixed-fields table defines `webhooks` as `Map[string, Path Item Object | Reference Object]` — hence `Referenced PathItem`, **not** bare `PathItem`. ([spec.openapis.org/oas/v3.1.0](https://spec.openapis.org/oas/v3.1.0))

### 2.2 Info Object Changes

Add `summary` field:

```haskell
data Info = Info
  { _infoTitle :: Text
  , _infoSummary :: Maybe Text      -- NEW: short summary
  , _infoDescription :: Maybe Text
  , _infoTermsOfService :: Maybe Text
  , _infoContact :: Maybe Contact
  , _infoLicense :: Maybe License
  , _infoVersion :: Text
  }
```

### 2.3 License Object Changes

Add SPDX identifier support:

```haskell
data License = License
  { _licenseName :: Text
  , _licenseIdentifier :: Maybe Text  -- NEW: SPDX identifier (mutually exclusive with url)
  , _licenseUrl :: Maybe URL
  }
```

### 2.4 PathItem Reference Enhancement

`_pathItemSummary` and `_pathItemDescription` **already exist** (`Internal.hs:223, 227`). The only new field is `_pathItemRef`:

```haskell
data PathItem = PathItem
  { _pathItemRef :: Maybe Text          -- NEW: $ref for external path item
  , _pathItemSummary :: Maybe Text      -- already present
  , _pathItemDescription :: Maybe Text  -- already present
  -- ... rest of fields
  }
```

**Serialization caveat:** `$ref` is a `$`-prefixed key — it will not derive from the default `mkSwaggerAesonOptions` prefix rule (see §4.0, point 1) and needs explicit handling.

---

## Phase 3: Version Constants and Validation

### 3.1 Update Version Bounds

**File:** `src/Data/OpenApi/Internal.hs` (lines 110-115)

```haskell
-- Option A: Support only 3.1.x
lowerOpenApiSpecVersion :: Version
lowerOpenApiSpecVersion = makeVersion [3, 1, 0]

upperOpenApiSpecVersion :: Version
upperOpenApiSpecVersion = makeVersion [3, 1, 1]  -- or latest patch

-- Option B: Support both 3.0.x and 3.1.x (more complex)
-- This requires version-aware serialization
```

### 3.2 Version Detection

Add version detection for conditional parsing:

```haskell
data OpenApiMajorVersion = OpenApi30 | OpenApi31
  deriving (Eq, Show)

detectVersion :: OpenApiSpecVersion -> OpenApiMajorVersion
detectVersion v
  | versionBranch v >= [3, 1] = OpenApi31
  | otherwise = OpenApi30
```

---

## Phase 4: JSON Serialization Changes

### 4.0 The generics-sop machinery (must read before editing instances)

The `Schema` JSON instances are **not** hand-written field-by-field. They are derived through `generics-sop` plus this library's custom Aeson layer:

- `deriveGeneric ''Schema` (Template Haskell) generates the SOP `Generic` representation.
- `instance ToJSON Schema` (`Internal.hs:1347–1349`) is:
  ```haskell
  instance ToJSON Schema where
    toJSON = sopSwaggerGenericToJSONWithOpts $
        mkSwaggerAesonOptions "schema" & saoSubObject ?~ "items"
  ```
- `instance FromJSON Schema` (`Internal.hs:1509`) uses `sopSwaggerGenericParseJSON`.
- Field names are mapped to JSON keys by `mkSwaggerAesonOptions "schema"`, which strips the `_schema` prefix and lower-cases the first letter (so `_schemaPrefixItems` → `"prefixItems"`).
- `saoSubObject ?~ "items"` is what splices the `OpenApiItems` sub-object's keys up into the parent `Schema` object instead of nesting them.

**Consequences for this migration — none of these are optional:**

1. **Every new `Schema` field flows through this machinery automatically** *only if* its name maps cleanly to the desired JSON key. Keys that begin with `$` (`$id`, `$anchor`, `$defs`, `$ref`, `$dynamicRef`, `$dynamicAnchor`) **cannot** be produced by the default prefix-stripping rule. These require either `saoAdditionalPairs`-style handling or a post-processing pass on the generated `Value`. Budget explicit work for each `$`-prefixed key — they will *not* "just derive."
2. **`AesonDefaultValue`** — adding fields requires the corresponding `AesonDefaultValue` instance/defaulting to be consistent, or `mempty`/round-trip behavior breaks.
3. **`saoSubObject ?~ "items"`** assumes `OpenApiItems` is an object-shaped sub-value. Changing `OpenApiItems` to allow a **boolean** (`items: false`) breaks this assumption — a boolean is not an object whose keys can be spliced. The sub-object handling needs rework (see §4.3).
4. **`OpenApiTypeValue`** gets a *hand-written* `ToJSON`/`FromJSON` (below); the field `_schemaType :: Maybe OpenApiTypeValue` then serializes through the generic machinery using that instance for the value.

Do not assume the instances can be edited in isolation. Treat `Internal/AesonUtils.hs` (`mkSwaggerAesonOptions`, `saoSubObject`, `saoAdditionalPairs`, `sopSwaggerGeneric*`) as part of the change surface.

### 4.1 Schema ToJSON/FromJSON

**File:** `src/Data/OpenApi/Internal.hs` (lines 1347, 1509)

The `Schema` instances themselves stay generic (`sopSwaggerGenericToJSONWithOpts` / `sopSwaggerGenericParseJSON`); there is **no** `filterNullableFor31` — `nullable` is gone from the type entirely (Strategy A), so there is nothing to filter. The custom work is the hand-written `OpenApiTypeValue` instances, plus the `$`-prefixed-key handling from §4.0.

#### Hand-written `OpenApiTypeValue` instances

```haskell
instance ToJSON OpenApiTypeValue where
  toJSON (OpenApiTypeSingle t) = toJSON t
  toJSON (OpenApiTypeArray ts) = toJSON ts

instance FromJSON OpenApiTypeValue where
  parseJSON v@(String _) = OpenApiTypeSingle <$> parseJSON v
  parseJSON v@(Array _)  = OpenApiTypeArray  <$> parseJSON v
  parseJSON _ = fail "type must be a string or an array of strings"
```

### 4.3 OpenApiItems boolean handling

Because `saoSubObject ?~ "items"` splices object keys, adding `OpenApiItemsBoolean Bool` (for `items: true|false`) requires special-casing: a boolean `items` must be emitted as the literal key `"items": false`, not spliced. Plan to either drop the sub-object trick for `items` and emit it as a plain key, or branch in the serialization so the boolean case bypasses `saoSubObject`. Removing `OpenApiItemsArray` also breaks the existing `FromJSON OpenApiItems` array branch (`Internal.hs:1526`) — under Strategy A this is intended, but reading any 3.0 `items: [...]` now fails and must be routed through the §1.1.3-style `Value` migration first.

### 4.2 Exclusive Bounds Serialization

Handle the numeric exclusive bounds:

```haskell
-- In Schema JSON instances, exclusiveMaximum/Minimum serialize as numbers
-- Example: { "exclusiveMaximum": 100 } instead of { "maximum": 100, "exclusiveMaximum": true }
```

---

## Phase 5: Validation Module Updates

### 5.1 Update Schema Validation

**File:** `src/Data/OpenApi/Schema/Validation.hs`

Update validation logic for:
- Type arrays (value matches if it matches any type in array)
- `prefixItems` validation for tuples
- `contains`, `minContains`, `maxContains` for arrays
- `if`/`then`/`else` conditional validation
- `unevaluatedProperties` and `unevaluatedItems`
- `const` keyword validation

### 5.2 Deprecation Warnings

Under Strategy A, `_schemaNullable` and `OpenApiItemsArray` are **removed**, not deprecated — a `{-# DEPRECATED #-}` pragma on a removed identifier does not compile. There is therefore nothing to deprecate on the `Schema`/`OpenApiItems` types themselves.

If gentler ergonomics are desired, deprecate the **migration helpers** (so they warn once 3.0 input is no longer expected) rather than the data constructors:

```haskell
{-# DEPRECATED migrate30NullableValue
      "3.0 input support is transitional; remove once all inputs are 3.1." #-}
```

---

## Phase 6: Testing

### 6.1 New Test Cases

**Directory:** `test/Data/OpenApi/`

Create comprehensive tests for:

1. **Type Arrays:**
   ```json
   { "type": ["string", "null"] }
   ```

2. **Numeric Exclusive Bounds:**
   ```json
   { "exclusiveMinimum": 0, "exclusiveMaximum": 100 }
   ```

3. **Tuple Validation:**
   ```json
   { "prefixItems": [{"type": "string"}, {"type": "number"}], "items": false }
   ```

4. **Conditional Schemas:**
   ```json
   { "if": {"properties": {"country": {"const": "USA"}}},
     "then": {"properties": {"postal_code": {"pattern": "^[0-9]{5}$"}}}}
   ```

5. **Webhooks:**
   ```json
   { "webhooks": { "newPet": { "post": { ... } } } }
   ```

### 6.2 Roundtrip Tests

Ensure all new constructs survive JSON encode/decode cycles:

```haskell
prop_schema31_roundtrip :: Schema -> Property
prop_schema31_roundtrip s =
  decode (encode s) === Just s
```

### 6.3 Migration Tests

Test conversion from 3.0 to 3.1 schemas:

Because migration happens at the `Value` layer (the 3.1 `Schema` has no `_schemaNullable` to set), the test exercises `migrate30NullableValue`, then decodes into the 3.1 `Schema`:

```haskell
spec :: Spec
spec = describe "3.0 to 3.1 migration" $ do
  it "converts nullable to type array" $ do
    -- raw 3.0 JSON
    let v30 = object [ "type" .= ("string" :: Text), "nullable" .= True ]
    -- migrated, then decoded into the 3.1 Schema
    (decode (encode (migrate30NullableValue v30)) :: Maybe Schema)
      `shouldBe`
      Just (mempty { _schemaType =
                       Just (OpenApiTypeArray [OpenApiString, OpenApiNull]) })
```

> `mempty` is valid here: `Schema` has `Semigroup`/`Monoid` instances (`Internal.hs:1045–1047`). `OpenApiNull` already exists as a constructor (`Internal.hs:608`), so no new type constructor is needed for the null case.

---

## Phase 7: Documentation and Migration Guide

### 7.1 Update Module Documentation

**File:** `src/Data/OpenApi.hs`

Update the module header to reflect 3.1 support:

```haskell
-- | OpenAPI 3.1 data model
--
-- This library supports OpenAPI Specification version 3.1.x
-- ...
```

### 7.2 Migration Guide

Create `MIGRATION_3.0_TO_3.1.md` with:

1. Breaking changes summary
2. Code migration examples
3. Schema transformation utilities
4. Common pitfalls

### 7.3 Update Cabal Metadata

**File:** `openapi3.cabal`

```cabal
name:        openapi3
version:     4.0.0
synopsis:    OpenAPI 3.1 data model
description:
  This library is intended to be used for decoding and encoding OpenAPI 3.1 API
  specifications as well as manipulating them.
  .
  The OpenAPI 3.1 specification is available at https://spec.openapis.org/oas/v3.1.0
```

---

## Implementation Order

### Milestone 1: Foundation (Breaking Changes)
1. [ ] Update `OpenApiTypeValue` to support type arrays
2. [ ] Change `exclusiveMaximum`/`exclusiveMinimum` to `Scientific`
3. [ ] Remove `_schemaNullable` field
4. [ ] Update version constants to 3.1.x
5. [ ] Fix all compilation errors from type changes

### Milestone 2: New Schema Features
6. [ ] Add `prefixItems` field
7. [ ] Add `const` field
8. [ ] Add `if`/`then`/`else` fields
9. [ ] Add `contains`, `minContains`, `maxContains`
10. [ ] Add `unevaluatedProperties`, `unevaluatedItems`
11. [ ] Add `$id`, `$anchor`, `$defs`, `$dynamicRef`, `$dynamicAnchor`
12. [ ] Add content encoding fields

### Milestone 3: Top-Level Features
13. [ ] Add `webhooks` to `OpenApi`
14. [ ] Add `summary` to `Info`
15. [ ] Add `identifier` to `License`
16. [ ] Update `PathItem` for `$ref` with overrides

### Milestone 4: Serialization
17. [ ] Update `ToJSON` instances for all changed types
18. [ ] Update `FromJSON` instances for all changed types
19. [ ] Add version-aware parsing utilities

### Milestone 5: Validation
20. [ ] Update validation for type arrays
21. [ ] Implement `prefixItems` validation
22. [ ] Implement conditional validation
23. [ ] Implement `contains` validation

### Milestone 6: Testing & Documentation
24. [ ] Write comprehensive test suite for 3.1 features
25. [ ] Ensure all existing tests pass or are updated
26. [ ] Write migration guide
27. [ ] Update all documentation

---

## Alternative Approaches Considered

### Option A: Version-Polymorphic Types (Rejected)
```haskell
data Schema (v :: OpenApiVersion) = Schema { ... }
```
**Rejected:** Too complex, requires significant API changes, poor ergonomics.

### Option B: Parallel Module Hierarchy (Rejected)
```haskell
-- Data.OpenApi for 3.0
-- Data.OpenApi31 for 3.1
```
**Rejected:** Code duplication, maintenance burden.

### Option C: Breaking Change Release (Selected)
Release as version 4.0.0 with breaking changes.
**Selected:** Clean API, follows semantic versioning, clear migration path.

---

## Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Breaking changes affect many users | High | Provide detailed migration guide and helper functions |
| JSON Schema 2020-12 complexity | Medium | Implement core features first, add advanced features incrementally |
| Test coverage gaps | Medium | Use property-based testing and official OpenAPI examples |
| Performance regression | Low | Benchmark before/after, optimize hot paths |

---

## References

- [OpenAPI 3.1.0 Specification](https://spec.openapis.org/oas/v3.1.0)
- [JSON Schema 2020-12](https://json-schema.org/draft/2020-12/json-schema-core.html)
- [OpenAPI 3.0 vs 3.1 Differences](https://www.openapis.org/blog/2021/02/18/openapi-specification-3-1-released)
- [JSON Schema Migration Guide](https://json-schema.org/draft/2020-12/release-notes.html)
