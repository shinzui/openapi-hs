# openapi-hs

[![Hackage](https://img.shields.io/hackage/v/openapi-hs.svg)](https://hackage.haskell.org/package/openapi-hs)
[![License BSD-3-Clause](https://img.shields.io/badge/license-BSD--3--Clause-blue.svg)](/LICENSE)

A Haskell library for **decoding, encoding, manipulating, and validating
[OpenAPI 3.1](https://spec.openapis.org/oas/v3.1.0) documents** — the format that
describes HTTP APIs in JSON or YAML. OpenAPI 3.1 adopts the
[JSON Schema 2020-12](https://json-schema.org/specification-links#2020-12) dialect.

> **Fork notice.** `openapi-hs` is a fork of
> [`biocad/openapi3`](https://github.com/biocad/openapi3), which is no longer actively
> maintained and supports only OpenAPI 3.0. This fork brings the library up to OpenAPI 3.1.
> The Haskell module namespace is unchanged (`Data.OpenApi.*`), so migrating is usually just a
> dependency-name swap: `openapi3` → `openapi-hs`. The fork keeps the upstream
> [BSD-3-Clause license](#license) and copyright.

---

## Highlights

- **Full OpenAPI 3.1 / JSON Schema 2020-12 data model** with lossless JSON round-tripping.
- **Type arrays** for nullability (`type: ["string", "null"]`) instead of the removed `nullable`.
- **Numeric** `exclusiveMaximum` / `exclusiveMinimum`, independent of `maximum` / `minimum`.
- **Tuples via `prefixItems`** (+ `items: false`) instead of the removed `items` array form.
- **Conditional & assertion keywords:** `if`/`then`/`else`, `const`, `contains` /
  `minContains` / `maxContains`, `dependentSchemas` / `dependentRequired`,
  `unevaluatedProperties` / `unevaluatedItems`, content keywords, and `examples`.
- **JSON Schema identification keywords:** `$id`, `$anchor`, `$defs`, `$ref`, `$dynamicRef`,
  `$dynamicAnchor`.
- **Top-level 3.1 features:** `webhooks`, `Info.summary`, `License.identifier`, and `$ref` on
  `PathItem`.
- **Schema validation** that understands the new 3.1 keywords.
- **`ToSchema` derivation** to generate schemas from your Haskell types via `GHC.Generics`.
- **`lens` accessors** for ergonomic reads and updates.
- **3.0 → 3.1 migration helpers** for documents you don't control yet.

## Installation

Add `openapi-hs` to your project's dependencies (Cabal):

```cabal
build-depends: openapi-hs
```

then import the umbrella module, which re-exports everything you typically need:

```haskell
import Data.OpenApi
```

Requires GHC **9.12.4** or **9.14.1**.

## Quick start

### Build and serialize a schema

```haskell
{-# LANGUAGE OverloadedStrings #-}
import Control.Lens
import Data.Aeson (encode)
import Data.OpenApi

-- "a string, or null" — 3.1 nullability via a type array
nullableString :: Schema
nullableString = mempty
  & type_       ?~ OpenApiTypeArray [OpenApiString, OpenApiNull]
  & description ?~ "an optional name"

-- encode nullableString == "{\"description\":\"an optional name\",\"type\":[\"string\",\"null\"]}"
```

### Derive a schema from a Haskell type

```haskell
{-# LANGUAGE DeriveGeneric #-}
import Data.Aeson (ToJSON)
import Data.Proxy (Proxy (..))
import GHC.Generics (Generic)
import Data.OpenApi

data User = User
  { name :: String
  , age  :: Int
  } deriving (Show, Generic)

instance ToJSON  User   -- needed for validation (below)
instance ToSchema User

userSchema :: Schema
userSchema = toSchema (Proxy :: Proxy User)
```

### Decode a 3.1 document

```haskell
import Data.Aeson (decode)
import Data.OpenApi (Schema)

-- decode "{\"prefixItems\":[{\"type\":\"string\"},{\"type\":\"number\"}],\"items\":false}"
--   :: Maybe Schema
```

### Validate a value against a schema

```haskell
import Data.OpenApi
import Data.OpenApi.Schema.Validation (validateToJSON)

-- Using the `User` from above (which has both ToJSON and ToSchema):
-- validateToJSON returns [] when the value conforms to its derived schema,
-- or a list of human-readable errors otherwise.
ok :: [ValidationError]
ok = validateToJSON (User "Ada" 36)   -- []
```

For validating an arbitrary JSON `Value` against a specific `Schema`, use
`validateJSON :: Definitions Schema -> Schema -> Value -> [ValidationError]`.

## Lenses

Every record field has a generated accessor from
[`lens`](https://hackage.haskell.org/package/lens), re-exported by the umbrella module:

```haskell
import Data.OpenApi -- lens accessors (Data.OpenApi.Lens)
```

A few field lenses are suffixed with `_` to avoid clashing with reserved words or `Prelude`
names: `type_`, `enum_`, `minimum_`, `maximum_`, `default_`, `const_`, `if_`, `then_`, `else_`,
`contains_`, `id_`.

## Migrating from OpenAPI 3.0

The 3.1 data types deliberately cannot represent 3.0-only constructs ("Strategy A"), so a 3.0
document does not decode directly. Rewrite the **parsed JSON** into a 3.1 shape first, using
`Data.OpenApi.Migration`:

```haskell
import Data.Aeson (Value, decode, encode)
import Data.OpenApi (OpenApi)
import Data.OpenApi.Migration (migrate30To31)

bring30Forward :: Value -> Maybe OpenApi
bring30Forward raw30 = decode (encode (migrate30To31 raw30))
```

`migrate30To31` recurses into every nested schema, rewriting `nullable` → type arrays, boolean
exclusive bounds → numeric bounds, and tuple `items` arrays → `prefixItems` + `items: false`.
The single-concern helpers (`migrate30NullableValue`, `migrate30ExclusiveBoundsValue`,
`migrate30ItemsArrayValue`) are also exported. They are intentionally **deprecated** to flag that
3.0 input is transitional.

See **[`MIGRATION_3.0_TO_3.1.md`](/MIGRATION_3.0_TO_3.1.md)** for the full breaking-changes list,
worked examples, and pitfalls.

## Examples

Runnable examples live in the [`examples/`](/examples) directory. Generated specifications can be
explored interactively in any OpenAPI 3.1 viewer or editor.

## Validation

The library's own correctness is checked at three complementary levels:

1. **Round-trip** — the test suite encodes documents and decodes them back through
   `FromJSON OpenApi`, which rejects any `openapi` version outside `3.1.0 … 3.1.1`, then
   compares for semantic equality.
2. **Schema conformance** — `Data.OpenApi.Schema.Validation` (`validateToJSON` /
   `validateJSON`) checks that values conform to their derived 3.1 schemas, including the new
   keywords.
3. **Authoritative conformance** — the `example` executable emits a complete OpenAPI 3.1
   contract (with `info`, a server, top-level `tags`, and a unique `operationId` per operation)
   that lints cleanly under [`vacuum`](https://quobix.com/vacuum/):

   ```bash
   cabal run example > openapi.json
   nix run nixpkgs#vacuum-go -- lint -d openapi.json
   ```

   The first two layers are *self-referential* — they confirm a document agrees with this
   library's own model of OpenAPI 3.1. `vacuum` is an external, authoritative linter, so it
   independently catches encoder output that is valid JSON but non-conformant OpenAPI.

## Building and developing

This repository ships a Nix flake providing a pinned GHC 9.12.4 toolchain. From the repository
root:

```bash
nix develop -c cabal build all
nix develop -c cabal test all
```

If you have a matching `cabal` + GHC 9.12.x on your `PATH`, the same commands work without the
`nix develop -c` prefix. The package is Cabal-only (`build-type: Simple`); there is no `stack.yaml`.

## Documentation

Full API documentation is on
[Hackage](https://hackage.haskell.org/package/openapi-hs). Each module's Haddocks include
worked examples.

The design and implementation strategy behind the 3.1 work is documented in
**[`docs/OPENAPI31_MIGRATION_PLAN.md`](https://github.com/shinzui/openapi-hs/blob/master/docs/OPENAPI31_MIGRATION_PLAN.md)**.

## License

`openapi-hs` retains the original **BSD-3-Clause** license of the upstream
[`openapi3`](https://github.com/biocad/openapi3) project, including its copyright. See the
[`LICENSE`](/LICENSE) file for the full text; this fork's changes are released under the same
terms.

---

*Originally derived from work by the GetShopTV and Biocad teams.*
