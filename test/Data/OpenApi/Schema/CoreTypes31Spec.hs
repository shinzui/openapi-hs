{-# LANGUAGE OverloadedStrings #-}

-- | Round-trip coverage for the OpenAPI 3.1 core type changes introduced in EP-3:
-- type arrays, numeric exclusive bounds, removal of @nullable@, and boolean @items@.
module Data.OpenApi.Schema.CoreTypes31Spec where

import Data.Aeson (decode, encode)
import Data.OpenApi
import Data.OpenApi.Internal
import Data.Version (makeVersion)
import Test.Hspec

spec :: Spec
spec = do
  describe "OpenAPI 3.1 core type changes" $ do
    it "type array {\"type\":[\"string\",\"null\"]} round-trips" $ do
      let s = mempty {_schemaType = Just (OpenApiTypeArray [OpenApiString, OpenApiNull])}
      encode s `shouldBe` "{\"type\":[\"string\",\"null\"]}"
      (decode (encode s) :: Maybe Schema) `shouldBe` Just s

    it "single type still serializes as a bare string" $ do
      let s = mempty {_schemaType = Just (OpenApiTypeSingle OpenApiString)}
      encode s `shouldBe` "{\"type\":\"string\"}"
      (decode (encode s) :: Maybe Schema) `shouldBe` Just s

    it "numeric exclusive bounds round-trip" $ do
      let s =
            mempty
              { _schemaExclusiveMinimum = Just 0,
                _schemaExclusiveMaximum = Just 100
              }
      (decode (encode s) :: Maybe Schema) `shouldBe` Just s
      (decode "{\"exclusiveMinimum\":0,\"exclusiveMaximum\":100}" :: Maybe Schema)
        `shouldBe` Just s

    it "items:false round-trips" $ do
      let s = mempty {_schemaItems = Just (OpenApiItemsBoolean False)}
      encode s `shouldBe` "{\"items\":false}"
      (decode (encode s) :: Maybe Schema) `shouldBe` Just s

    it "items:true round-trips" $ do
      let s = mempty {_schemaItems = Just (OpenApiItemsBoolean True)}
      (decode (encode s) :: Maybe Schema) `shouldBe` Just s

    it "homogeneous array schema round-trips" $ do
      let s =
            mempty
              { _schemaType = Just (OpenApiTypeSingle OpenApiArray),
                _schemaItems =
                  Just
                    ( OpenApiItemsObject
                        (Inline (mempty {_schemaType = Just (OpenApiTypeSingle OpenApiString)}))
                    )
              }
      (decode (encode s) :: Maybe Schema) `shouldBe` Just s

  describe "OpenAPI version detection" $ do
    it "detectVersion classifies 3.1.x as OpenApi31" $
      detectVersion (OpenApiSpecVersion (makeVersion [3, 1, 0])) `shouldBe` OpenApi31
    it "detectVersion classifies 3.0.x as OpenApi30" $
      detectVersion (OpenApiSpecVersion (makeVersion [3, 0, 3])) `shouldBe` OpenApi30
