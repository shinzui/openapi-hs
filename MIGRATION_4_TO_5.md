# Migrating from `openapi-hs` 4 to 5

`openapi-hs` 5.0.0 removes its `optics` interface and the external
`insert-ordered-containers` dependency. The `lens` interface remains the supported way to read
and update OpenAPI records. This guide covers the source changes needed by downstream users.

## Replace optics labels with lens accessors

Version 4 generated both overloaded `optics` labels and ordinary `lens` accessors. Version 5
removes `Data.OpenApi.Optics`, so remove that import and use the accessors re-exported by
`Data.OpenApi`:

```haskell
-- Before (openapi-hs 4)
{-# LANGUAGE OverloadedLabels #-}
import Data.OpenApi
import Data.OpenApi.Optics ()
import Optics.Core

schemaType = view #type schema
updated = set (#schema % #type) (Just (OpenApiTypeSingle OpenApiString)) namedSchema
```

```haskell
-- After (openapi-hs 5)
import Control.Lens
import Data.OpenApi

schemaType = view type_ schema
updated = set (schema . type_) (Just (OpenApiTypeSingle OpenApiString)) namedSchema
```

`lens` accessors compose with ordinary `(.)`; the removed `optics` labels composed with `%`.
Fields whose ordinary names collide with Haskell keywords, Prelude names, or other accessors
have a trailing underscore. Common migrations are `#type` to `type_`, `#default` to `default_`,
`#maximum` to `maximum_`, and `#minimum` to `minimum_`. Other examples include `enum_`,
`const_`, `if_`, `then_`, `else_`, `contains_`, and `id_`.

Remove `optics-core` and `optics-th` from your own dependencies only when your code has no
independent use for them.

## Use the compat insertion-ordered map

OpenAPI map fields use the public compat map from this package. Change direct imports from the
external package:

```haskell
-- Before
import Data.HashMap.Strict.InsOrd qualified as InsOrdHashMap
```

```haskell
-- After
import Data.HashMap.Strict.InsOrd.Compat qualified as InsOrdHashMap
```

Functions such as `empty`, `fromList`, `insert`, `insertWith`, `unionWith`, and `lookup` retain
the same names. The compat map intentionally compares equality without considering insertion
order and encodes string-like keys as a JSON object in insertion order.

## Use the compat insertion-ordered set

OpenAPI tag fields now use a set exposed directly by `openapi-hs`:

```haskell
-- Before
import Data.HashSet.InsOrd qualified as InsOrdHashSet
```

```haskell
-- After
import Data.HashSet.InsOrd.Compat qualified as InsOrdHashSet
```

The set keeps its non-optics public instances, including `NFData`, `NFData1`, `ToJSON`,
`FromJSON`, and the `lens` `Ixed`, `At`, and `Contains` instances.

Remove `insert-ordered-containers` from your own dependencies only when no other part of your
application still imports it independently.

## Compiler and lens bounds

Version 5 requires `lens >=5.3.6 && <5.4`. That release line is tested with this package's
supported GHC 9.12 and GHC 9.14 compiler matrix.
