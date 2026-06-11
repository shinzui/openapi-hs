# Migrating from OpenAPI 3.0 to 3.1 (`openapi-hs` 4.0.0)

`openapi-hs` 4.0.0 models **OpenAPI 3.1 / JSON Schema 2020-12 only**. The Haskell
types deliberately cannot represent 3.0-only constructs ("Strategy A"), so a 3.0
document does not decode directly. This guide explains what changed and how to
bring a 3.0 document forward.

The Haskell module namespace is unchanged (`Data.OpenApi.*`); downstream code only
swaps the dependency name `openapi3` → `openapi-hs`.

## Breaking changes

- **`nullable` removed.** JSON Schema 2020-12 has no `nullable` keyword. Express
  nullability with a type array instead: `{"type": "string", "nullable": true}`
  becomes `{"type": ["string", "null"]}`. In Haskell, `_schemaType` is now
  `Maybe OpenApiTypeValue` (`OpenApiTypeSingle` or `OpenApiTypeArray`); there is no
  `_schemaNullable` field.
- **`exclusiveMaximum` / `exclusiveMinimum` are numeric and independent.** In 3.0
  they were booleans modifying `maximum` / `minimum`. In 3.1 they are numbers
  carrying a strict bound, independent of `maximum` / `minimum` (a schema may carry
  both). In Haskell they are `Maybe Scientific`, not `Maybe Bool`.
- **Tuple `items` arrays removed.** 3.0 used `"items": [s1, s2]` for fixed-length
  tuples. 3.1 uses `"prefixItems": [s1, s2]` plus `"items": false` (no extra
  elements). In Haskell, `OpenApiItems` is now `OpenApiItemsObject | OpenApiItemsBoolean`
  (no `OpenApiItemsArray`); tuple positions live in the new `_schemaPrefixItems` field.
- **Supported spec versions are 3.1.x.** `lowerOpenApiSpecVersion`/
  `upperOpenApiSpecVersion` are `3.1.0` / `3.1.1`; the default `mempty :: OpenApi`
  emits `"openapi": "3.1.0"`. A 3.0.x version string fails the version-bounds check.
- **Package renamed** `openapi3` → `openapi-hs` (modules unchanged).
- **Build modernized:** Cabal-only on GHC 9.12.4 / 9.14.1; no `stack.yaml`, no
  custom `Setup.hs` / `cabal-doctest`.

## What's new in 3.1

Additive JSON Schema 2020-12 fields: `const`, `prefixItems`, `contains` /
`minContains` / `maxContains`, `if` / `then` / `else`, `dependentSchemas` /
`dependentRequired`, `unevaluatedProperties` / `unevaluatedItems`, `propertyNames`,
`contentEncoding` / `contentMediaType` / `contentSchema`, `examples`, and the
`$`-prefixed identification keywords `$id` / `$anchor` / `$defs` / `$ref` /
`$dynamicRef` / `$dynamicAnchor`. Top-level: `webhooks` on `OpenApi`, `summary` on
`Info`, `identifier` on `License`, and `$ref` on `PathItem`.

## Bringing a 3.0 document forward

Rewrite the **parsed JSON** (a `Data.Aeson.Value`) into a 3.1 shape *before*
decoding, using `Data.OpenApi.Migration`. The whole-document walk is `migrate30To31`:

```haskell
{-# LANGUAGE OverloadedStrings #-}
import Data.Aeson (decode, encode, eitherDecode)
import Data.OpenApi (OpenApi, Schema)
import Data.OpenApi.Migration (migrate30To31)

bring30Forward :: Data.Aeson.Value -> Maybe OpenApi
bring30Forward raw30 = decode (encode (migrate30To31 raw30))
```

`migrate30To31` recurses into every nested object (`properties`, `prefixItems`,
`$defs`, `allOf`, request/response bodies, …), so nested schemas are migrated too.

The single-concern helpers are also exported and can be applied to one schema object:

```haskell
import Data.OpenApi.Migration
  ( migrate30NullableValue          -- nullable:true  -> type array
  , migrate30ExclusiveBoundsValue   -- boolean bounds -> numeric bounds
  , migrate30ItemsArrayValue        -- items:[..]     -> prefixItems + items:false
  )

-- {"type":"string","nullable":true}  ->  {"type":["string","null"]}
migrate30NullableValue v
```

All migration helpers are **`{-# DEPRECATED #-}` on purpose**: they exist to flag
that 3.0 input is transitional. The warning is your cue to migrate inputs to 3.1 at
the source and drop the helper call.

## Pitfalls

- A bare `nullable: true` with **no** `type` becomes `{"type": ["null"]}` (a value
  that may only be `null`).
- `exclusiveMaximum: true` **drops** the accompanying `maximum` (its value moves into
  the numeric `exclusiveMaximum`). `exclusiveMaximum: false` just removes the boolean
  and keeps `maximum`.
- `migrate30ItemsArrayValue` fires only when `items` is a JSON **array**; an object or
  boolean `items` is left unchanged.
- Tuple `ToSchema` derivation for Haskell tuples currently emits a homogenised
  `anyOf` `items` element rather than positional `prefixItems` (a documented interim
  behavior; the `prefixItems` field exists for a future switch).
