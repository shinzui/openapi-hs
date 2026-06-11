{-# LANGUAGE OverloadedStrings #-}
-- | Property-based round-trip coverage for 3.1 'Schema' values (EP-7).
--
-- There is no @Arbitrary Schema@ instance in the tree (EP-3/EP-4 did not add one;
-- see the EP-7 Surprises). Rather than author a full recursive instance for the
-- ~50-field record, this generator combines a random subset of independent
-- single-field "fragments" — each exercising a 3.1 keyword — and asserts the
-- result survives @decode . encode@.
module Data.OpenApi.Schema.RoundtripSpec where

import           Data.Aeson      (decode, encode)
import           Test.Hspec
import           Test.Hspec.QuickCheck (prop)
import           Test.QuickCheck

import           Data.OpenApi
import           Data.OpenApi.Internal

strSchema :: Schema
strSchema = mempty { _schemaType = Just (OpenApiTypeSingle OpenApiString) }

numSchema :: Schema
numSchema = mempty { _schemaType = Just (OpenApiTypeSingle OpenApiNumber) }

-- | Independent single-field fragments, each setting one 3.1 keyword.
fragments :: [Schema -> Schema]
fragments =
  [ \s -> s { _schemaType = Just (OpenApiTypeArray [OpenApiString, OpenApiNull]) }
  , \s -> s { _schemaExclusiveMinimum = Just 0, _schemaExclusiveMaximum = Just 100 }
  , \s -> s { _schemaMaximum = Just 10 }
  , \s -> s { _schemaConst = Just "fixed" }
  , \s -> s { _schemaPrefixItems = Just [ Inline strSchema, Inline numSchema ] }
  , \s -> s { _schemaItems = Just (OpenApiItemsBoolean False) }
  , \s -> s { _schemaContains = Just (Inline numSchema), _schemaMinContains = Just 1 }
  , \s -> s { _schemaIf = Just (Inline strSchema), _schemaThen = Just (Inline numSchema) }
  , \s -> s { _schemaExamples = Just ["a", "b"] }
  , \s -> s { _schemaId = Just "https://example/s" }
  , \s -> s { _schemaRef = Just "#/$defs/A" }
  , \s -> s { _schemaTitle = Just "t", _schemaDescription = Just "d" }
  , \s -> s { _schemaUnevaluatedItems = Just (Inline strSchema) }
  ]

genSchema :: Gen Schema
genSchema = do
  fs <- sublistOf fragments
  pure (foldr (\f acc -> f acc) mempty fs)

prop_schema31_roundtrip :: Property
prop_schema31_roundtrip = forAll genSchema $ \s ->
  (decode (encode s) :: Maybe Schema) === Just s

spec :: Spec
spec = describe "Schema 3.1 round-trip" $
  prop "decode . encode == Just for random 3.1 schemas" prop_schema31_roundtrip
