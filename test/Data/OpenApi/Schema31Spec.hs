{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes       #-}
-- | Round-trip coverage for the OpenAPI 3.1 / JSON Schema 2020-12 additive fields
-- and the @$@-prefixed identification/reference keywords introduced in EP-4.
module Data.OpenApi.Schema31Spec where

import           Data.Aeson           (Value, decode, encode, object, toJSON, (.=))
import           Data.Aeson.QQ.Simple (aesonQQ)
import           Data.Text            (Text)
import           Test.Hspec

import qualified Data.HashMap.Strict.InsOrd.Compat as InsOrdHashMap

import           Data.OpenApi
import           Data.OpenApi.Internal

import           SpecCommon

-- Small helpers to keep the cases terse.
strSchema :: Schema
strSchema = mempty { _schemaType = Just (OpenApiTypeSingle OpenApiString) }

numSchema :: Schema
numSchema = mempty { _schemaType = Just (OpenApiTypeSingle OpenApiNumber) }

spec :: Spec
spec = do
  describe "JSON Schema 2020-12 additive fields" $ do

    context "prefixItems with items:false" $
      mempty
        { _schemaPrefixItems = Just [ Inline strSchema, Inline numSchema ]
        , _schemaItems       = Just (OpenApiItemsBoolean False)
        } <=> [aesonQQ|
          { "prefixItems": [ {"type":"string"}, {"type":"number"} ]
          , "items": false }
        |]

    context "if/then conditional" $
      mempty
        { _schemaIf   = Just (Inline (mempty { _schemaConst = Just "USA" }))
        , _schemaThen = Just (Inline strSchema)
        } <=> [aesonQQ|
          { "if": {"const":"USA"}, "then": {"type":"string"} }
        |]

    context "const" $
      mempty { _schemaConst = Just (toJSON (42 :: Int)) } <=> [aesonQQ| {"const": 42} |]

    context "contains with minContains" $
      mempty
        { _schemaContains    = Just (Inline (mempty { _schemaType = Just (OpenApiTypeSingle OpenApiInteger) }))
        , _schemaMinContains = Just 1
        } <=> [aesonQQ| {"contains": {"type":"integer"}, "minContains": 1} |]

    context "examples (3.1 array form)" $
      mempty { _schemaExamples = Just [toJSON (1 :: Int), toJSON ("x" :: Text)] }
        <=> [aesonQQ| {"examples": [1, "x"]} |]

  describe "$-prefixed identification/reference keywords" $ do

    context "$defs" $
      mempty
        { _schemaDefs = Just (InsOrdHashMap.fromList [ ("A", Inline strSchema) ]) }
        <=> [aesonQQ| {"$defs": {"A": {"type":"string"}}} |]

    it "$defs emits the literal \"$defs\" key" $ do
      let s = mempty { _schemaDefs = Just (InsOrdHashMap.fromList [ ("A", Inline strSchema) ]) }
      toJSON s `shouldBe` object [ "$defs" .= object [ "A" .= object [ "type" .= ("string" :: Text) ] ] ]

    it "$id + sibling $ref stays Inline and round-trips" $ do
      let s = mempty { _schemaId = Just "https://example/s", _schemaRef = Just "#/$defs/A" }
      toJSON s `shouldBe` object [ "$id"  .= ("https://example/s" :: Text)
                                 , "$ref" .= ("#/$defs/A" :: Text) ]
      (decode (encode s) :: Maybe Schema) `shouldBe` Just s
      -- As a sub-schema, a $ref that is not a component reference parses to Inline (not Ref):
      (decode (encode s) :: Maybe (Referenced Schema)) `shouldBe` Just (Inline s)

    it "a pure component $ref still parses to Ref" $ do
      (decode "{\"$ref\":\"#/components/schemas/Foo\"}" :: Maybe (Referenced Schema))
        `shouldBe` Just (Ref (Reference "Foo"))

  describe "boolean sub-schemas (read direction)" $ do

    it "decodes contains:true / unevaluatedItems:false to canonical inline schemas" $ do
      let expected = mempty
            { _schemaContains         = Just (Inline mempty)
            , _schemaUnevaluatedItems = Just (Inline (mempty { _schemaNot = Just (Inline mempty) }))
            }
      (decode "{\"contains\":true,\"unevaluatedItems\":false}" :: Maybe Schema)
        `shouldBe` Just expected
