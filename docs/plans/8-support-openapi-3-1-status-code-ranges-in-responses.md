---
id: 8
slug: support-openapi-3-1-status-code-ranges-in-responses
title: "Support OpenAPI 3.1 status code ranges in Responses"
kind: exec-plan
created_at: 2026-07-03T23:34:08Z
---

# Support OpenAPI 3.1 status code ranges in Responses

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.


## Purpose / Big Picture

The OpenAPI 3.1 specification allows the keys of a Responses Object (the map of HTTP
responses an operation can produce) to be one of three things: the literal word
`default`, an explicit HTTP status code such as `200` or `404`, or a **status-code
range** written as a single leading digit `1`–`5` followed by two literal uppercase `X`
characters — `1XX`, `2XX`, `3XX`, `4XX`, `5XX`. A range key means "any response in this
class"; for example `4XX` documents a single shape used for all client-error responses.

Today this library cannot parse a document that uses a range key. The reporter of
[issue #1](https://github.com/shinzui/openapi-hs/issues/1) feeds in a perfectly valid
3.1 document whose responses include `"4XX"`, and the whole parse fails. The root cause
is that the Responses map is keyed on `HttpStatusCode`, which is defined as a bare
`type HttpStatusCode = Int` (see `src/Data/OpenApi/Internal.hs:796`). When Aeson (the
JSON library) decodes the map it tries to read every key as an integer; the text `"4XX"`
is not an integer, so the entire `FromJSON Responses` parse aborts.

After this change, a user can take the exact JSON from the issue — an operation whose
`responses` object contains `200`, `429`, and `4XX` — hand it to `Data.Aeson.decode`
(or `eitherDecode`) at type `OpenApi`, and get back a fully populated value with the
`4XX` response preserved. Re-encoding that value reproduces the `"4XX"` key verbatim.
Users constructing documents in Haskell can also write a range response directly, e.g.
`responses & at (StatusRange R4XX) ?~ Inline someResponse`, while existing code that uses
plain integer literals like `at 200` or `setResponse 404 ...` keeps compiling and working
unchanged.

You can see it working two ways once the change is in:

- Run the test suite; a new "Status Code Range" example round-trips a `Responses` value
  containing a `4XX` key through `toJSON`/`fromJSON`/`encode`/`decode`.
- In a GHCi session, `eitherDecode` the issue's JSON at type `Operation` and observe a
  `Right` result whose responses map contains the range key (transcript in
  Validation and Acceptance below).


## Progress

Use a checklist to summarize granular steps. Every stopping point must be documented here,
even if it requires splitting a partially completed task into two ("done" vs. "remaining").
This section must always reflect the actual current state of the work.

- [x] Milestone 1: Replace `type HttpStatusCode = Int` with the `HttpStatusCode` /
      `StatusCodeRange` data types plus `Num`, `Eq`, `Ord`, `Hashable`, `Show`, `Data`,
      `Generic`, `Typeable` instances in `src/Data/OpenApi/Internal.hs`. Library compiles.
      Completed 2026-07-03T23:47:47Z; `nix develop -c cabal build openapi-hs` passed
      after Milestones 1-3.
- [x] Milestone 2: Add `ToJSONKey` / `FromJSONKey` instances and the
      `renderHttpStatusCode` / `parseHttpStatusCode` helpers so `"4XX"` round-trips.
      Completed 2026-07-03T23:47:47Z; the build passed after adding the key instances plus
      value-level `ToJSON` / `FromJSON` instances required by Aeson 2.2's default list-key
      methods.
- [x] Milestone 3: Widen the export list in `src/Data/OpenApi.hs` to expose the new
      constructors and the range type. Completed 2026-07-03T23:47:47Z.
- [x] Milestone 4: Add tests — a `Responses` round-trip with a `4XX` key; a regression decode
      of the issue's JSON; unit tests for the key parser/renderer; a mixed `Responses`
      round-trip covering `default` + explicit code + inline range + `$ref` range (closing an
      existing coverage gap); and a QuickCheck property that the key codec round-trips, added to
      `test/Data/OpenApi/Schema/RoundtripSpec.hs`. Completed 2026-07-03T23:54:57Z; the
      focused filters passed: `Status Code Range Responses` (5 examples), `Responses with
      default, exact, range and $ref` (5 examples), `Issue #1` (1 example), `Responses key
      parsing` (3 examples), and `HttpStatusCode key round-trip` (1 QuickCheck property,
      100 tests).
- [x] Milestone 5: Update `CHANGELOG.md` and confirm the whole suite is green under
      `nix develop` / `cabal`. Completed 2026-07-03T23:56:06Z; `nix develop -c cabal
      test spec` passed with 463 examples and 0 failures. Corrected after review to place
      the changelog note under a new `4.1.0` section because `4.0.0` had already been
      released.


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

- Discovery: Aeson 2.2.5.0's `ToJSONKey` and `FromJSONKey` classes have default
  `toJSONKeyList` / `fromJSONKeyList` methods that require ordinary `ToJSON` /
  `FromJSON` instances when the list-key methods are not overridden. The first build failed
  until `HttpStatusCode` gained value-level instances that encode and decode the same text
  form used for object keys.
  Evidence:
  ```text
  src/Data/OpenApi/Internal.hs:885:10: error:
      No instance for 'ToJSON HttpStatusCode'
        arising from a use of '$dmtoJSONKeyList'
  src/Data/OpenApi/Internal.hs:888:10: error:
      No instance for 'FromJSON HttpStatusCode'
        arising from a use of '$dmfromJSONKeyList'
  ```

- Discovery: `DeriveAnyClass` was not enabled for `src/Data/OpenApi/Internal.hs` despite
  the package default language being GHC2024, so deriving `Hashable` with the `anyclass`
  strategy required an explicit file pragma.
  Evidence:
  ```text
  Can't make a derived instance of 'Hashable HttpStatusCode' with the anyclass strategy
  Suggested fix: Perhaps you intended to use the 'DeriveAnyClass' extension
  ```


## Decision Log

Record every decision made while working on the plan.

- Decision: Model the map key as a two-constructor data type `HttpStatusCode = StatusCode
  Int | StatusRange StatusCodeRange`, rather than adding separate fields to `Responses` or
  smuggling ranges through a sentinel `Int`.
  Rationale: The spec treats `default`, explicit codes, and ranges as three kinds of key in
  one map. `default` already has its own field (`_responsesDefault`), so the remaining map
  must hold both explicit codes and ranges. A dedicated sum type keeps a single
  `InsOrdHashMap HttpStatusCode (Referenced Response)` (matching the spec's single map) and
  makes the two cases explicit and total, instead of overloading `Int` with magic values.
  Date: 2026-07-03

- Decision: Provide a `Num HttpStatusCode` instance whose `fromInteger` builds
  `StatusCode`, so existing integer-literal call sites (`at 200`, `setResponse 404`, and the
  test fixtures at `test/Data/OpenApiSpec.hs:176-177`) keep compiling.
  Rationale: Status codes are overwhelmingly written as bare integer literals throughout the
  package, its Haddocks, and downstream user code. Without a `Num` instance every such site
  would need editing to `StatusCode 200`, a large and gratuitous break. The `Num` instance
  preserves the ergonomics the package already advertises. The non-`fromInteger` arithmetic
  methods are defined totally (by projecting to `Int`) but are not semantically meaningful;
  they exist only so numeric literals type-check. This tradeoff is documented in a Haddock
  comment on the instance.
  Date: 2026-07-03

- Decision: Accept range keys **only** in the exact spec form `[1-5]XX` with uppercase `X`,
  and accept explicit-code keys only as a run of ASCII digits. Any other key text
  (`"6XX"`, `"4xx"`, `"4X"`, `"twohundred"`, empty) is a parse failure with a descriptive
  message.
  Rationale: OpenAPI 3.1 defines the range grammar as uppercase `X` and a leading digit
  1–5; being strict keeps us spec-compliant and rejects malformed documents loudly rather
  than silently mis-parsing them. Digit-only exact codes match the previous behavior closely
  enough for real documents (HTTP status codes are positive integers) while dropping the
  sign/other quirks Aeson's generic `Int` key parser tolerated.
  Date: 2026-07-03

- Decision: Expand test coverage of the `Responses` area beyond the minimal range fixture:
  add a mixed `Responses` round-trip (`default` + explicit code + inline range + `$ref` range)
  and a QuickCheck property for the key codec, the latter placed in the existing
  `test/Data/OpenApi/Schema/RoundtripSpec.hs`.
  Rationale: A review of the current suite found the status-code-keyed `Responses` type is
  covered today only by one happy-path fixture (exact codes `200`/`405`) plus two
  whole-document smoke tests; `default` and `$ref` responses are exercised only incidentally
  inside those blobs, and there is no property-based coverage of the key codec. The mixed
  fixture pins the `default`-splitting/`$ref` interaction as a focused, readable test, and the
  property check guards the new `parseHttpStatusCode`/`renderHttpStatusCode` pair across the
  whole code/range space. `RoundtripSpec.hs` already imports `Data.OpenApi.Internal`,
  `Test.QuickCheck`, and `Test.Hspec.QuickCheck`, so the property needs no new module wiring and
  can call the (unexported-from-`Data.OpenApi`) helpers directly without widening the public API.
  Date: 2026-07-03

- Decision: Fold the change into the in-progress `4.0.0` CHANGELOG entry rather than opening
  a new version section.
  Rationale: `4.0.0` is the current unreleased entry at the top of `CHANGELOG.md` and is
  already a large breaking release (package rename, 3.0→3.1 migration). The `HttpStatusCode`
  change is breaking (its definition changes from a type alias to a data type), so it belongs
  with the other `4.0.0` breaking notes.
  Date: 2026-07-03

- Decision: Supersede the previous changelog placement decision and open a new `4.1.0`
  section for this change.
  Rationale: The user clarified that `4.0.0` had already been released. Since the
  `HttpStatusCode` change is a breaking API change after that release, it must not be added
  retroactively to the `4.0.0` notes. Under the package's PVP-style versioning, the next
  breaking release after `4.0.0` is represented by a new `4.1.0` section.
  Date: 2026-07-03

- Decision: Add ordinary `ToJSON` / `FromJSON HttpStatusCode` instances that use
  `renderHttpStatusCode` and `parseHttpStatusCode`, in addition to the map-key instances.
  Rationale: Aeson 2.2.5.0's key classes require these value-level instances for their
  default list-key methods unless every list-key method is implemented manually. Encoding the
  value as the same string form (`"200"`, `"4XX"`) keeps the representation consistent and
  avoids widening the public API with extra helpers.
  Date: 2026-07-03


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose.

- Outcome: Completed 2026-07-03. `Responses` maps now support OpenAPI 3.1 status-code
  range keys through `HttpStatusCode = StatusCode Int | StatusRange StatusCodeRange`.
  Existing integer-literal call sites continue to work through the `Num HttpStatusCode`
  instance, while users can construct range keys explicitly with `StatusRange R1XX` through
  `StatusRange R5XX`. Encoding preserves range keys such as `"4XX"`, and decoding rejects
  malformed range spellings such as `"4xx"` and `"6XX"`.

- Outcome: The reported issue #1 scenario is covered by a regression test that decodes an
  `Operation` whose `responses` object contains `200`, `429`, and `4XX`, then verifies the
  parsed operation stores the `4XX` entry under `StatusRange R4XX`. Additional tests cover a
  `Responses` round-trip with a range key, a mixed `default` / explicit / range / `$ref`
  object, parser rejection cases, and a QuickCheck parse/render round-trip property.

- Outcome: The changelog entry was corrected after review to live under a new `4.1.0`
  section, leaving the already-released `4.0.0` section unchanged.

- Validation: `nix develop -c cabal build openapi-hs` passed after the implementation
  milestones. `nix develop -c cabal test spec` passed at completion with 463 examples and
  0 failures.


## Context and Orientation

This is `openapi-hs`, a Haskell library (Cabal package `openapi-hs`, version `4.0.0`) that
models OpenAPI 3.1 documents as Haskell data types with `ToJSON`/`FromJSON` instances so
that programs can read, construct, and emit OpenAPI contracts. "OpenAPI" is a standard for
describing HTTP APIs as a JSON (or YAML) document; a "Responses Object" is the part of that
document describing what an operation returns for each HTTP status. Terms used below:

- **Aeson**: the Haskell JSON library. `ToJSON`/`FromJSON` convert Haskell values to and
  from JSON *values*. `ToJSONKey`/`FromJSONKey` convert Haskell values to and from JSON
  *object keys* (keys are always strings in JSON). A map is serialized by encoding each key
  with its `ToJSONKey` instance.
- **`InsOrdHashMap k v`**: an insertion-ordered hash map from the `insert-ordered-containers`
  package (this repo vendors a compatibility shim at
  `src/Data/HashMap/Strict/InsOrd/Compat.hs`). Its Aeson instances require the key type to
  have `Eq`, `Hashable`, `ToJSONKey`, and `FromJSONKey` (see
  `src/Data/HashMap/Strict/InsOrd/Compat.hs:190-205`). This is the exact set of instances the
  new key type must satisfy.
- **`Referenced a`**: a value that is either an inline `a` (`Inline a`) or a JSON `$ref`
  pointer to one (`Ref (Reference Text)`). Response entries are `Referenced Response`.
- **`Data`/`Typeable`/`Generic`**: standard generic-programming type classes GHC can derive.
  Every core type in this module derives them (see the `deriving stock (Eq, Show, Generic,
  Data, Typeable)` clauses throughout `Internal.hs`), so the new types must too, to fit in.

The relevant files and locations:

- `src/Data/OpenApi/Internal.hs` — the single big module defining every core datatype and
  its JSON instances. Key spots:
  - Line 785–792: `data Responses` with the field
    `_responsesResponses :: InsOrdHashMap HttpStatusCode (Referenced Response)`.
  - Line 795–796: `type HttpStatusCode = Int` (the definition being replaced).
  - Line 1406–1411: the `MediaType` key instances — a working template for a custom
    text-based `ToJSONKey`, using `JSON.toJSONKeyText (Text.pack . show)`.
  - Line 1619–1620: `instance FromJSONKey MediaType` using
    `FromJSONKeyTextParser (parseJSON . String)` — the template for a custom `FromJSONKey`.
  - Line 1674–1679: `instance FromJSON Responses`, which splits off `default` and hands the
    remaining object to `parseJSON` for the map. This is where a bad key currently makes the
    whole parse fail; it needs no change once the key type parses ranges, but understand it.
  - Line 363–364: `instance Hashable MediaType` — template for a hand-written `Hashable`.
  - The imports already include `Data.Aeson hiding (Encoding)` (line 15), `Data.Aeson.Types
    qualified as JSON` (line 22), `Data.Hashable (Hashable (..))` (line 37), `Data.Text
    (Text)` (line 59), and `Data.Text qualified as Text` (line 60). No new imports are
    required, though you may add `Text.Read (readMaybe)` if you prefer it over a hand-rolled
    digit check; `base` is already a dependency.
- `src/Data/OpenApi.hs` — the public umbrella module and its export list. Line 95 currently
  exports `HttpStatusCode,` (type only). It must become `HttpStatusCode (..),` and gain the
  range type.
- `src/Data/OpenApi/Lens.hs` (lines 75–89) and `src/Data/OpenApi/Optics.hs` (lines 181–183)
  — declare `type instance Index Responses = HttpStatusCode` and the `Ixed`/`At` instances.
  These reference the type *name* only, so they compile unchanged; but the `at`/`ix`
  functions they enable are exactly what the `Num` instance keeps working with integer
  literals.
- `src/Data/OpenApi/Operation.hs` (lines 257–307) — helper functions `setResponse`,
  `setResponseWith`, `setResponseFor`, `setResponseForWith`, all typed
  `... -> HttpStatusCode -> ...`. Signatures are unchanged; callers passing integer literals
  keep working via `Num`.
- `test/Data/OpenApiSpec.hs` — HSpec test module. Uses `import Data.OpenApi` (the public
  module, so new constructors must be exported to be usable here). The `<=>` operator from
  `test/SpecCommon.hs` asserts a value both encodes to an expected JSON `Value` and
  round-trips through `toJSON`/`fromJSON`/`encode`/`decode`/`toEncoding`. The spec tree is
  assembled in `spec` at line 20; fixtures such as `operationExample`/`operationExampleJSON`
  live further down (line 135+). Fixtures use `{-# LANGUAGE OverloadedStrings #-}`,
  `OverloadedLists`, and `Data.Aeson.QQ.Simple`'s `aesonQQ` quasi-quoter for inline JSON.
  Existing response fixtures at lines 176–177 (`& at 200 ?~ "Pet updated."`) prove integer
  literals are used as `Index Responses`.
- `CHANGELOG.md` — the top section is `4.0.0` (unreleased), a list of bullet points.

There are no `Arbitrary` instances for `Responses` or `HttpStatusCode` anywhere in `test/`
(verified by grep), so no QuickCheck generator needs updating. There is no `ToSchema`
instance for `Responses` or for the map key, so the reflection machinery in
`src/Data/OpenApi/Internal/Schema.hs` is unaffected.


## Plan of Work

The work is one cohesive change split into five verifiable milestones. Milestones 1–3 are
the implementation; 4 proves it against the reported bug; 5 documents and finalizes.

### Milestone 1 — Introduce the `HttpStatusCode` data type

Scope: replace the `type HttpStatusCode = Int` alias at `src/Data/OpenApi/Internal.hs:795-796`
with a proper data type that can represent either an explicit code or a range, and give it
the value-level instances (`Eq`, `Ord`, `Hashable`, `Show`, `Generic`, `Data`, `Typeable`,
`Num`) needed to be a map key and to accept integer literals. At the end of this milestone
the library still fails to serialize ranges (no key instances yet) but compiles and all
existing integer-literal usages type-check.

Replace lines 795–796 with the following. Keep the existing Haddock intent (an HTTP status
code keying an entry in `Responses`) and expand it to cover ranges:

```haskell
-- | A key in a 'Responses' map. Per the OpenAPI 3.1 specification a response
-- may be keyed either by an explicit HTTP status code (e.g. @200@, @404@) or by
-- a status-code /range/ that stands for a whole class of responses. A range is
-- written as a single leading digit @1@–@5@ followed by two literal uppercase
-- @X@ characters: @1XX@, @2XX@, @3XX@, @4XX@, @5XX@.
--
-- The @default@ key is represented separately by '_responsesDefault' and is
-- never stored in the map, so it is not a constructor here.
--
-- A 'Num' instance is provided so that ordinary integer literals continue to
-- denote explicit status codes: writing @200@ where an 'HttpStatusCode' is
-- expected yields @'StatusCode' 200@. Only 'fromInteger' is meaningful; the
-- arithmetic operators are defined for totality (projecting to 'Int') but have
-- no real-world meaning for status codes.
data HttpStatusCode
  = -- | An explicit status code such as @200@ or @404@.
    StatusCode Int
  | -- | A whole class of responses, e.g. @'StatusRange' 'R4XX'@ for the @4XX@ key.
    StatusRange StatusCodeRange
  deriving stock (Eq, Ord, Show, Generic, Data, Typeable)
  deriving anyclass (Hashable)

-- | The five status-code range classes permitted by OpenAPI 3.1, one per
-- leading digit. @'R1XX'@ serializes as @1XX@, @'R2XX'@ as @2XX@, and so on.
data StatusCodeRange
  = R1XX
  | R2XX
  | R3XX
  | R4XX
  | R5XX
  deriving stock (Eq, Ord, Show, Enum, Bounded, Generic, Data, Typeable)
  deriving anyclass (Hashable)

-- | Project an 'HttpStatusCode' onto a representative integer: explicit codes map
-- to themselves; a range maps to its hundreds value (@R1XX -> 100@, …, @R5XX ->
-- 500@). Used only to give the 'Num' instance total arithmetic; not exported.
httpStatusCodeToInt :: HttpStatusCode -> Int
httpStatusCodeToInt (StatusCode n) = n
httpStatusCodeToInt (StatusRange r) = (fromEnum r + 1) * 100

-- | Integer literals denote explicit status codes (see 'HttpStatusCode'). The
-- non-'fromInteger' methods are total but not semantically meaningful.
instance Num HttpStatusCode where
  fromInteger = StatusCode . fromInteger
  a + b = StatusCode (httpStatusCodeToInt a + httpStatusCodeToInt b)
  a - b = StatusCode (httpStatusCodeToInt a - httpStatusCodeToInt b)
  a * b = StatusCode (httpStatusCodeToInt a * httpStatusCodeToInt b)
  abs = StatusCode . abs . httpStatusCodeToInt
  signum = StatusCode . signum . httpStatusCodeToInt
  negate = StatusCode . negate . httpStatusCodeToInt
```

Notes for the implementer:

- The repository convention (see recent commit "style: add explicit deriving strategies to
  all deriving clauses") is that every `deriving` clause names its strategy. Use `deriving
  stock` for the structural classes and `deriving anyclass (Hashable)` for `Hashable`
  (its class has a `Generic`-based default). `DeriveAnyClass` and `DeriveGeneric` are
  implied by the module's `GHC2024` default language plus existing extensions; if the
  compiler complains that `DeriveAnyClass` is off, add `{-# LANGUAGE DeriveAnyClass #-}` at
  the top of `Internal.hs` (check the existing pragma block first — the file already derives
  `Generic`/`Data` widely). If the `anyclass` `Hashable` derivation does not resolve, fall
  back to a hand-written instance mirroring `instance Hashable MediaType`
  (`Internal.hs:363-364`):

  ```haskell
  instance Hashable HttpStatusCode where
    hashWithSalt s (StatusCode n)  = s `hashWithSalt` (0 :: Int) `hashWithSalt` n
    hashWithSalt s (StatusRange r) = s `hashWithSalt` (1 :: Int) `hashWithSalt` fromEnum r

  instance Hashable StatusCodeRange where
    hashWithSalt s r = s `hashWithSalt` fromEnum r
  ```

- Do **not** change the `Responses` record — its field stays
  `InsOrdHashMap HttpStatusCode (Referenced Response)`; only the meaning of the key type
  changes.

Acceptance: `cabal build openapi-hs` (or `nix develop -c cabal build openapi-hs`) compiles
the library. It will not yet serialize ranges — that is Milestone 2.

### Milestone 2 — Key serialization: `ToJSONKey` / `FromJSONKey`

Scope: teach Aeson how to turn an `HttpStatusCode` into a JSON object key and back, so that
`StatusCode 200` ↔ `"200"` and `StatusRange R4XX` ↔ `"4XX"`. At the end, encoding a
`Responses` value with a range produces the `"4XX"` key, and decoding the issue's JSON
succeeds.

Add, near the other key instances (a natural home is just after the `HttpStatusCode`
definition, or beside the `MediaType` key instances around `Internal.hs:1406-1411` and
`1619-1620` — keep related code together and match the file's existing grouping):

```haskell
-- | Render an 'HttpStatusCode' as the text used for a JSON object key.
renderHttpStatusCode :: HttpStatusCode -> Text
renderHttpStatusCode (StatusCode n) = Text.pack (show n)
renderHttpStatusCode (StatusRange r) = case r of
  R1XX -> "1XX"
  R2XX -> "2XX"
  R3XX -> "3XX"
  R4XX -> "4XX"
  R5XX -> "5XX"

-- | Parse a JSON object key into an 'HttpStatusCode'. Accepts a run of ASCII
-- digits as an explicit code, or the exact forms @1XX@…@5XX@ (uppercase @X@) as
-- a range. Anything else is rejected with a descriptive message.
parseHttpStatusCode :: Text -> Either String HttpStatusCode
parseHttpStatusCode t = case parseRange t of
  Just r -> Right (StatusRange r)
  Nothing
    | not (Text.null t) && Text.all isDigit t ->
        case readMaybe (Text.unpack t) of
          Just n -> Right (StatusCode n)
          Nothing -> Left err
    | otherwise -> Left err
  where
    err =
      "Invalid Responses key "
        <> show (Text.unpack t)
        <> "; expected an HTTP status code (e.g. \"200\") or a range (\"1XX\"…\"5XX\")."
    parseRange x = case Text.unpack x of
      [d, 'X', 'X'] -> case d of
        '1' -> Just R1XX
        '2' -> Just R2XX
        '3' -> Just R3XX
        '4' -> Just R4XX
        '5' -> Just R5XX
        _ -> Nothing
      _ -> Nothing

instance ToJSONKey HttpStatusCode where
  toJSONKey = JSON.toJSONKeyText renderHttpStatusCode

instance FromJSONKey HttpStatusCode where
  fromJSONKey = FromJSONKeyTextParser (either fail pure . parseHttpStatusCode)
```

Notes:

- `isDigit` comes from `Data.Char`; add `import Data.Char (isDigit)` if it is not already
  imported (grep the import block first). `readMaybe` comes from `Text.Read`; add
  `import Text.Read (readMaybe)` if absent. Both are in `base`, already a dependency.
- `JSON.toJSONKeyText` and `FromJSONKeyTextParser` are the exact combinators the `MediaType`
  instances use (`Internal.hs:1411`, `1620`); `JSON` is the qualified alias for
  `Data.Aeson.Types` established at `Internal.hs:22`, and `FromJSONKeyTextParser` /
  `toJSONKeyText` are re-exported from `Data.Aeson` (imported unqualified at line 15). If a
  name does not resolve unqualified, qualify it as `JSON.toJSONKeyText` /
  `JSON.FromJSONKeyTextParser`.
- No value-level `ToJSON`/`FromJSON HttpStatusCode` instance is needed: the map's Aeson
  instances (`src/Data/HashMap/Strict/InsOrd/Compat.hs:190-205`) go through the *key*
  classes only.
- The existing `FromJSON Responses` at `Internal.hs:1674-1679` needs **no** change; once the
  key parser accepts `"4XX"`, its `parseJSON (Object …)` over the map just works.

Acceptance: `cabal build openapi-hs` still compiles; the GHCi transcript in Validation and
Acceptance now decodes the issue's JSON successfully.

### Milestone 3 — Export the constructors

Scope: expose the new constructors so downstream users (and the test module, which imports
`Data.OpenApi`, not `Internal`) can pattern-match and construct ranges.

In `src/Data/OpenApi.hs`, change the export at line 95 from:

```haskell
    HttpStatusCode,
```

to:

```haskell
    HttpStatusCode (..),
    StatusCodeRange (..),
```

Confirm `Data.OpenApi` re-exports from `Data.OpenApi.Internal` (it does — that is how
`Responses (..)` etc. are exported). If the umbrella module uses an explicit import list
from `Internal`, add `StatusCodeRange (..)` there too; if it re-exports the whole module,
only the export list above needs editing.

Acceptance: `cabal build` compiles; `StatusCode`, `StatusRange`, and `R4XX` are usable from
a module that only imports `Data.OpenApi`.

### Milestone 4 — Tests proving the bug is fixed

Scope: add tests that (a) round-trip a `Responses` value containing a `4XX` key, (b) decode
the reporter's JSON without error, (c) unit-test the key parser/renderer for the
spec-compliant and rejected forms, (d) round-trip a *mixed* `Responses` value that combines
a `default` key, an explicit code, an inline range, and a `$ref`-valued range in one object
(closing the pre-existing gap where `default` and `$ref` responses were only ever exercised
incidentally inside the big PetStore/Swagger blobs), and (e) add a property-based check that
the key codec round-trips for every code and range. These fail before Milestones 1–3 and
pass after.

Why (d) and (e): a coverage review of the current suite found that the status-code-keyed
`Responses` type is exercised today only by one happy-path fixture (`operationExample`, exact
codes `200`/`405`) plus two whole-document smoke tests. There is no focused, readable test
that pins the interaction between the `default`-splitting logic in `FromJSON Responses`
(`Internal.hs:1674-1679`) and the map, no focused test of a `$ref` response value under a
status key, and no property-based coverage of the new key codec. Steps 5 and 6 below close
those gaps; they are the parts most likely to regress under this change.

Edit `test/Data/OpenApiSpec.hs`:

1. Add the fixture pairs and wire them into the spec tree. Near the other `describe` lines in
   `spec` (around line 34, next to "Responses Definition Object"), add:

   ```haskell
   describe "Status Code Range Responses" $ statusRangeResponsesExample <=> statusRangeResponsesExampleJSON
   describe "Responses with default, exact, range and $ref" $ responsesMixedExample <=> responsesMixedExampleJSON
   ```

2. Define the fixtures alongside the other example values (anywhere at top level in the
   module; keep them near the existing response fixtures for readability):

   ```haskell
   statusRangeResponsesExample :: Responses
   statusRangeResponsesExample =
     mempty
       & at 200 ?~ Inline (mempty & description .~ "OK")
       & at (StatusRange R4XX) ?~ Inline (mempty & description .~ "Client error")

   statusRangeResponsesExampleJSON :: Value
   statusRangeResponsesExampleJSON =
     [aesonQQ|
   {
     "200": { "description": "OK" },
     "4XX": { "description": "Client error" }
   }
   |]
   ```

   Verify the field lens name for a response description: it is `description` (the `Response`
   record field `_responseDescription`, exposed via the `HasDescription`/lens machinery — the
   same `description` used elsewhere in this file, e.g. line 169). `mempty :: Response` is
   valid because `Response` has a `Monoid` instance in this library; if `mempty` does not
   resolve for `Response`, construct it explicitly with the `Response` constructor and empty
   fields instead. Confirm `Responses` also has a `Monoid` instance (it does —
   `Internal.hs:1148-1151`), so `mempty & at … ?~ …` builds the map.

3. Add a regression test that decodes the reporter's operation JSON. Add a new `describe`
   block in `spec`:

   ```haskell
   describe "Issue #1: range status code parses" $
     it "decodes an operation whose responses include a 4XX range" $ do
       let js =
             [aesonQQ|
   {
     "operationId": "test_endpoint",
     "responses": {
       "200": { "description": "200 response" },
       "429": { "description": "too many requests" },
       "4XX": { "description": "client error" }
     }
   }
   |]
       case fromJSON js :: Result Operation of
         Success op ->
           (op ^. responses . at (StatusRange R4XX)) `shouldBe`
             Just (Inline (mempty & description .~ "client error"))
         Error e -> expectationFailure ("expected successful parse, got: " <> e)
   ```

   `responses` here is the lens from `Operation` to its `Responses` (used elsewhere in the
   file, e.g. `responses . at 200` at line 744). `Result`, `fromJSON`, `Success`, `Error`
   come from `Data.Aeson` (already imported).

4. Add unit tests for the key parser/renderer. Because `parseHttpStatusCode` and
   `renderHttpStatusCode` live in `Internal` and are not exported from `Data.OpenApi`,
   assert their behavior *through the public map instances* rather than importing the
   helpers, to avoid widening the public API. Add:

   ```haskell
   describe "Responses key parsing" $ do
     it "rejects a lowercase range key" $
       (fromJSON [aesonQQ| { "4xx": { "description": "x" } } |] :: Result Responses)
         `shouldSatisfy` isError
     it "rejects an out-of-range class key" $
       (fromJSON [aesonQQ| { "6XX": { "description": "x" } } |] :: Result Responses)
         `shouldSatisfy` isError
     it "accepts every valid range class" $
       (fromJSON
          [aesonQQ| { "1XX": {"description":"a"}, "5XX": {"description":"b"} } |]
          :: Result Responses)
         `shouldSatisfy` isSuccess
   ```

   with local helpers (add near the top of the module, or inline as `where` clauses):

   ```haskell
   isError :: Result a -> Bool
   isError (Error _) = True
   isError _ = False

   isSuccess :: Result a -> Bool
   isSuccess (Success _) = True
   isSuccess _ = False
   ```

   `shouldSatisfy` is from `Test.Hspec` (already imported). Note the value-under-test type is
   `Responses`, not `Operation`, so `default` handling does not interfere: keys `4xx`/`6XX`
   land in the map parse and must fail.

5. Add the mixed fixture that exercises `default`, an explicit code, an inline range, and a
   `$ref`-valued range together (coverage gap (d)). Define alongside the other example values:

   ```haskell
   responsesMixedExample :: Responses
   responsesMixedExample =
     mempty
       & default_ ?~ Inline (mempty & description .~ "Unexpected error")
       & at 200 ?~ Inline (mempty & description .~ "OK")
       & at (StatusRange R4XX) ?~ Inline (mempty & description .~ "Client error")
       & at (StatusRange R5XX) ?~ Ref (Reference "ServerError")

   responsesMixedExampleJSON :: Value
   responsesMixedExampleJSON =
     [aesonQQ|
   {
     "default": { "description": "Unexpected error" },
     "200": { "description": "OK" },
     "4XX": { "description": "Client error" },
     "5XX": { "$ref": "#/components/responses/ServerError" }
   }
   |]
   ```

   Notes: `default_` is the lens for the `_responsesDefault` field (the field rules strip the
   `responses` prefix and append `_` because `default` is a keyword — see
   `src/Data/OpenApi/Internal/Utils.hs:44`); it is exported from `Data.OpenApi` (referenced in
   `src/Data/OpenApi.hs:311`). `Ref`/`Reference` are exported from `Data.OpenApi` and already
   used in this file (e.g. `Ref (Reference "Address")` at line 264). A `Referenced Response`
   `Ref` renders through the `#/components/responses/` prefix (`Internal.hs:1571`,
   round-tripped by the matching `FromJSON` at `Internal.hs:1735`), which is why the JSON uses
   `"#/components/responses/ServerError"`. The `<=>` operator asserts this value encodes to
   exactly that JSON and survives every decode/encode path, so it pins the `default`-split plus
   map-with-`$ref` interaction in one focused test. (Aeson compares JSON objects as maps, so the
   key order in the fixture does not matter.)

6. Add the property-based codec round-trip (coverage gap (e)) to
   `test/Data/OpenApi/Schema/RoundtripSpec.hs`. That module is the QuickCheck home in this
   suite and **already** imports `Data.OpenApi.Internal` (giving direct access to
   `parseHttpStatusCode`, `renderHttpStatusCode`, and the constructors), `Test.QuickCheck`, and
   `Test.Hspec.QuickCheck (prop)`, so no new imports or Cabal `other-modules` wiring are
   needed. Add the generator and property:

   ```haskell
   -- | Every key the renderer can produce must parse back to the same value.
   genHttpStatusCode :: Gen HttpStatusCode
   genHttpStatusCode =
     oneof
       [ StatusCode <$> choose (100, 599)
       , StatusRange <$> elements [minBound .. maxBound]
       ]

   prop_httpStatusCode_key_roundtrip :: Property
   prop_httpStatusCode_key_roundtrip = forAll genHttpStatusCode $ \c ->
     parseHttpStatusCode (renderHttpStatusCode c) === Right c
   ```

   Then extend that module's `spec` (currently a single `describe`) to a `do` block adding the
   new group:

   ```haskell
   spec :: Spec
   spec = do
     describe "Schema 3.1 round-trip" $
       prop "decode . encode == Just for random 3.1 schemas" prop_schema31_roundtrip
     describe "HttpStatusCode key round-trip" $
       prop "parse . render == Right for codes and ranges" prop_httpStatusCode_key_roundtrip
   ```

   `elements [minBound .. maxBound]` enumerates all five range classes (they derive `Enum` and
   `Bounded` in Milestone 1); `choose (100, 599)` covers the realistic explicit-code space.

Acceptance: `cabal test spec` (or `nix develop -c cabal test spec`) runs green, including the
new `describe` groups in both `Data.OpenApiSpec` (status-range, mixed, issue-#1, key-parsing)
and `Data.OpenApi.Schema.RoundtripSpec` (the key codec property).

### Milestone 5 — Changelog and final verification

Scope: document the change and run the full suite.

Add a bullet to the `4.0.0` section of `CHANGELOG.md` (top of file), for example:

```text
- **Breaking:** `HttpStatusCode` is now a data type (`StatusCode Int | StatusRange
  StatusCodeRange`) instead of `type HttpStatusCode = Int`, so a `Responses` map can hold
  OpenAPI 3.1 status-code range keys (`1XX`…`5XX`) in addition to explicit codes. A `Num`
  instance keeps integer literals such as `at 200` and `setResponse 404` working unchanged.
  Fixes #1.
```

Then run the full test suite and confirm green (commands in Concrete Steps).

Acceptance: entire `cabal test` suite passes; `git diff` shows only the intended files
changed.


## Concrete Steps

All commands run from the repository root
`/Users/shinzui/Keikaku/bokuno/openapi-hs-project/openapi-hs`. This repo builds with Cabal,
and its toolchain is pinned via Nix (`flake.nix`). If a bare `cabal` is not on your PATH or
uses the wrong GHC, prefix commands with `nix develop -c` to enter the pinned dev shell. The
test-suite component is named `spec` (see the `.cabal` file, `test-suite spec`).

Build the library after Milestones 1–3:

```bash
nix develop -c cabal build openapi-hs
```

Expected: it compiles with no errors. Warnings about the `Num` instance's unused-ish methods
are acceptable; there should be no errors.

Run the focused tests after Milestone 4. HSpec supports a match filter via `-m`:

```bash
nix develop -c cabal test spec --test-options='-m "Status Code Range Responses"'
nix develop -c cabal test spec --test-options='-m "Responses with default, exact, range and $ref"'
nix develop -c cabal test spec --test-options='-m "Issue #1"'
nix develop -c cabal test spec --test-options='-m "Responses key parsing"'
nix develop -c cabal test spec --test-options='-m "HttpStatusCode key round-trip"'
```

Expected: each prints passing examples, e.g.:

```text
Status Code Range Responses
  encodes correctly
  decodes correctly
  roundtrips: eitherDecode . encode
  roundtrips with toJSON
  roundtrips with toEncoding

Finished in 0.00xx seconds
5 examples, 0 failures
```

Run the full suite after Milestone 5:

```bash
nix develop -c cabal test spec
```

Expected: `N examples, 0 failures` (N is the pre-existing count plus the new examples).

If you prefer to see the fix at the REPL, see the transcript under Validation and Acceptance.


## Validation and Acceptance

The acceptance criterion is behavioral: the exact document from issue #1 parses, and a range
response round-trips.

1. **Regression: the issue's JSON parses.** In a REPL (`nix develop -c cabal repl spec`, or
   `cabal repl openapi-hs` and `:set -XOverloadedStrings`), evaluate:

   ```haskell
   :set -XOverloadedStrings
   import Data.Aeson
   import Data.OpenApi
   import Control.Lens
   let src = "{\"operationId\":\"test_endpoint\",\"responses\":{\"200\":{\"description\":\"ok\"},\"429\":{\"description\":\"rl\"},\"4XX\":{\"description\":\"client error\"}}}"
   let r = eitherDecode src :: Either String Operation
   fmap (\op -> op ^. responses . at (StatusRange R4XX)) r
   ```

   Expected output (a `Right` holding the inline `4XX` response), demonstrating the key was
   parsed and stored:

   ```text
   Right (Just (Inline (Response {_responseDescription = "client error", ...})))
   ```

   Before the change, `r` is `Left "...4XX..."` (a parse error) — you can confirm the "before"
   state by checking out the pre-change commit, or simply trust that the new test's
   `expectationFailure` branch guards it.

2. **Round-trip: a range key survives encode/decode.** Still in the REPL:

   ```haskell
   let resp = mempty & at (StatusRange R4XX) ?~ Inline (mempty & description .~ "client error") :: Responses
   encode resp
   (eitherDecode (encode resp) :: Either String Responses) == Right resp
   ```

   Expected: `encode resp` contains `"4XX":{"description":"client error"}`, and the equality
   prints `True`.

3. **Automated proof.** The three new `describe` groups added in Milestone 4 encode all of
   the above as HSpec examples. Running `nix develop -c cabal test spec` and observing
   `0 failures` is the durable acceptance signal. The `<=>` operator additionally verifies
   the `toEncoding` path (streaming encoder) agrees with `toJSON`, so both encoders emit
   `"4XX"` identically.

4. **No regression in existing behavior.** The full suite passing confirms that integer
   literal keys (`at 200`, `setResponse …`) and the existing `operationExample`/`responses`
   fixtures still encode/decode exactly as before — i.e. the `Num` instance preserves the old
   ergonomics.


## Idempotence and Recovery

Every step is a source edit or a build/test command; all are safe to repeat. Re-running the
build or tests is idempotent. If a milestone's build fails:

- **`DeriveAnyClass` / `Hashable` derivation errors** — switch from `deriving anyclass
  (Hashable)` to the hand-written `Hashable` instances shown in Milestone 1.
- **Name resolution for `toJSONKeyText` / `FromJSONKeyTextParser`** — qualify them through
  the `JSON` alias (`Data.Aeson.Types`), matching how `MediaType` does it at
  `Internal.hs:1411`/`1620`.
- **`mempty :: Response` does not resolve** — construct the `Response` explicitly with empty
  fields, or use whatever minimal constructor the `Response` record needs; the test only
  relies on `_responseDescription`.
- **An existing call site fails to compile** because it pattern-matched on `HttpStatusCode`
  as an `Int` — that site now needs to match `StatusCode n`. Grep the tree for direct
  `HttpStatusCode` matches (there are none in this repo today outside the definition, so this
  should not occur; if a future rebase introduces one, update it to the constructor form).

To roll back entirely, revert the touched files: `src/Data/OpenApi/Internal.hs`,
`src/Data/OpenApi.hs`, `test/Data/OpenApiSpec.hs`, `CHANGELOG.md`. No data migration or
destructive operation is involved.


## Interfaces and Dependencies

No new library dependencies. Everything relies on already-present packages: `aeson`
(`ToJSONKey`/`FromJSONKey`/`toJSONKeyText`/`FromJSONKeyTextParser`), `hashable` (`Hashable`),
`text` (`Text`), `insert-ordered-containers` (the map), and `base` (`Data.Char.isDigit`,
`Text.Read.readMaybe`, `Num`, `Enum`, `Bounded`). All are listed in the `.cabal` file for
both the library and the `spec` test-suite.

The interfaces that must exist at the end of each milestone, by full module path:

- After Milestone 1, in `Data.OpenApi.Internal`:
  - `data HttpStatusCode = StatusCode Int | StatusRange StatusCodeRange` with instances
    `Eq`, `Ord`, `Show`, `Generic`, `Data`, `Typeable`, `Hashable`, `Num`.
  - `data StatusCodeRange = R1XX | R2XX | R3XX | R4XX | R5XX` with instances `Eq`, `Ord`,
    `Show`, `Enum`, `Bounded`, `Generic`, `Data`, `Typeable`, `Hashable`.
  - The `Responses` field type is still
    `_responsesResponses :: InsOrdHashMap HttpStatusCode (Referenced Response)`.
- After Milestone 2, in `Data.OpenApi.Internal`:
  - `renderHttpStatusCode :: HttpStatusCode -> Text`
  - `parseHttpStatusCode :: Text -> Either String HttpStatusCode`
  - `instance ToJSONKey HttpStatusCode`
  - `instance FromJSONKey HttpStatusCode`
- After Milestone 3, `Data.OpenApi` re-exports `HttpStatusCode (..)` and
  `StatusCodeRange (..)`.
- After Milestone 4, `test/Data/OpenApiSpec.hs` defines `statusRangeResponsesExample ::
  Responses`, `statusRangeResponsesExampleJSON :: Value`, `responsesMixedExample :: Responses`,
  and `responsesMixedExampleJSON :: Value`, plus the issue-#1 and key-parsing `describe` groups,
  all wired into `spec`. `test/Data/OpenApi/Schema/RoundtripSpec.hs` gains
  `genHttpStatusCode :: Gen HttpStatusCode` and `prop_httpStatusCode_key_roundtrip :: Property`,
  wired into its `spec` (which becomes a two-`describe` `do` block). This is the only test that
  touches `parseHttpStatusCode`/`renderHttpStatusCode` directly; both remain unexported from
  `Data.OpenApi` (reached via that module's existing `import Data.OpenApi.Internal`).

Signatures that must remain unchanged (to preserve source compatibility for existing users
via the `Num` instance): `Data.OpenApi.Operation.setResponse`, `setResponseWith`,
`setResponseFor`, `setResponseForWith` (all `... HttpStatusCode ...`), and the
`type instance Index Responses = HttpStatusCode` / `Index Operation = HttpStatusCode` and
`At`/`Ixed` instances in `Data.OpenApi.Lens` and `Data.OpenApi.Optics`.
