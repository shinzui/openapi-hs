{-# LANGUAGE OverloadedLists #-}
{-# LANGUAGE OverloadedStrings #-}

-- | OpenAPI 3.1 / JSON Schema 2020-12 keyword validation (EP-6): type arrays,
-- numeric exclusive bounds, prefixItems, contains/minContains/maxContains,
-- if/then/else, const, and best-effort unevaluatedProperties/unevaluatedItems.
module Data.OpenApi.Schema.Validation31Spec where

import Data.Aeson (Value (..), object, (.=))
import Data.OpenApi
import Data.OpenApi.Internal
import Test.Hspec

spec :: Spec
spec = describe "OpenAPI 3.1 keyword validation" $ do
  -- M1: type arrays (matches-any; OpenApiNull matches JSON null)
  it "type [string,null] accepts a string and null, rejects a number" $ do
    let s = mempty {_schemaType = Just (OpenApiTypeArray [OpenApiString, OpenApiNull])}
    validateJSON mempty s (String "hi") `shouldBe` []
    validateJSON mempty s Null `shouldBe` []
    validateJSON mempty s (Number 3) `shouldNotBe` []

  -- M1: numeric exclusive bounds (independent of maximum/minimum)
  it "exclusiveMinimum 0 / exclusiveMaximum 100 accept 50, reject 0 and 100" $ do
    let s =
          mempty
            { _schemaType = Just (OpenApiTypeSingle OpenApiNumber),
              _schemaExclusiveMinimum = Just 0,
              _schemaExclusiveMaximum = Just 100
            }
    validateJSON mempty s (Number 50) `shouldBe` []
    validateJSON mempty s (Number 0) `shouldNotBe` []
    validateJSON mempty s (Number 100) `shouldNotBe` []

  -- M2: prefixItems + items:false (tuple)
  it "prefixItems [string,number] + items:false validates [a,1], rejects extras/wrong types" $ do
    let s =
          mempty
            { _schemaType = Just (OpenApiTypeSingle OpenApiArray),
              _schemaPrefixItems =
                Just
                  [ Inline (mempty {_schemaType = Just (OpenApiTypeSingle OpenApiString)}),
                    Inline (mempty {_schemaType = Just (OpenApiTypeSingle OpenApiNumber)})
                  ],
              _schemaItems = Just (OpenApiItemsBoolean False)
            }
    validateJSON mempty s (Array [String "a", Number 1]) `shouldBe` []
    validateJSON mempty s (Array [String "a", Number 1, Bool True]) `shouldNotBe` []
    validateJSON mempty s (Array [Number 1, String "a"]) `shouldNotBe` []

  -- M2: contains + minContains
  it "contains integer + minContains 2 accepts two integers, rejects fewer" $ do
    let s =
          mempty
            { _schemaType = Just (OpenApiTypeSingle OpenApiArray),
              _schemaContains =
                Just (Inline (mempty {_schemaType = Just (OpenApiTypeSingle OpenApiInteger)})),
              _schemaMinContains = Just 2
            }
    validateJSON mempty s (Array [Number 1, Number 2, String "x"]) `shouldBe` []
    validateJSON mempty s (Array [String "x"]) `shouldNotBe` []

  -- M2: maxContains
  it "contains integer + maxContains 1 rejects two integers" $ do
    let s =
          mempty
            { _schemaType = Just (OpenApiTypeSingle OpenApiArray),
              _schemaContains =
                Just (Inline (mempty {_schemaType = Just (OpenApiTypeSingle OpenApiInteger)})),
              _schemaMaxContains = Just 1
            }
    validateJSON mempty s (Array [Number 1, String "x"]) `shouldBe` []
    validateJSON mempty s (Array [Number 1, Number 2]) `shouldNotBe` []

  -- M3: if/then (kept scalar to avoid this engine's strict-object behavior and
  -- its no-op pattern checker: "if the value is a string, then it must be \"yes\"").
  it "if (string) then const yes; non-string skips the constraint" $ do
    let s =
          mempty
            { _schemaIf = Just (Inline (mempty {_schemaType = Just (OpenApiTypeSingle OpenApiString)})),
              _schemaThen = Just (Inline (mempty {_schemaConst = Just (String "yes")}))
            }
    validateJSON mempty s (String "yes") `shouldBe` [] -- matches if, then satisfied
    validateJSON mempty s (String "no") `shouldNotBe` [] -- matches if, then violated
    validateJSON mempty s (Number 42) `shouldBe` [] -- if not matched, no else -> ok

  -- M3: const
  it "const 42 accepts 42, rejects 43" $ do
    let s = mempty {_schemaConst = Just (Number 42)}
    validateJSON mempty s (Number 42) `shouldBe` []
    validateJSON mempty s (Number 43) `shouldNotBe` []

  -- M4: best-effort unevaluatedProperties (local-only)
  it "unevaluatedProperties:false rejects a property not in properties" $ do
    let s =
          mempty
            { _schemaType = Just (OpenApiTypeSingle OpenApiObject),
              _schemaProperties =
                [("a", Inline (mempty {_schemaType = Just (OpenApiTypeSingle OpenApiString)}))],
              _schemaUnevaluatedProperties = Just (AdditionalPropertiesAllowed False)
            }
    validateJSON mempty s (object ["a" .= ("x" :: String)]) `shouldBe` []
    validateJSON mempty s (object ["a" .= ("x" :: String), "b" .= ("y" :: String)]) `shouldNotBe` []

  -- M4: best-effort unevaluatedItems (local-only). The unevaluated schema requires
  -- a string; the third element (a bool) is beyond prefixItems and so must satisfy it.
  -- (A `{not:{}}` "always-false" schema would not work: this engine does not validate `not`.)
  it "unevaluatedItems requires string; rejects a non-string beyond prefixItems" $ do
    let s =
          mempty
            { _schemaType = Just (OpenApiTypeSingle OpenApiArray),
              _schemaPrefixItems =
                Just
                  [ Inline (mempty {_schemaType = Just (OpenApiTypeSingle OpenApiString)}),
                    Inline (mempty {_schemaType = Just (OpenApiTypeSingle OpenApiNumber)})
                  ],
              _schemaUnevaluatedItems = Just (Inline (mempty {_schemaType = Just (OpenApiTypeSingle OpenApiString)}))
            }
    validateJSON mempty s (Array [String "a", Number 1]) `shouldBe` []
    validateJSON mempty s (Array [String "a", Number 1, Bool True]) `shouldNotBe` []
