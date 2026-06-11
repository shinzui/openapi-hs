{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wno-deprecations #-}  -- this spec intentionally exercises the deprecated migration helpers
-- | Tests for the 3.0 -> 3.1 'Data.Aeson.Value'-layer migration helpers (EP-7).
module Data.OpenApi.MigrationSpec where

import           Data.Aeson         (Value, decode, encode, object, (.=))
import           Data.Text          (Text)
import qualified Data.HashMap.Strict.InsOrd.Compat as InsOrdHashMap
import           Test.Hspec

import           Data.OpenApi
import           Data.OpenApi.Internal
import           Data.OpenApi.Migration (migrate30ExclusiveBoundsValue,
                                         migrate30ItemsArrayValue,
                                         migrate30NullableValue,
                                         migrate30To31)

spec :: Spec
spec = describe "3.0 to 3.1 migration" $ do

  it "converts nullable:true to a type array" $ do
    let v30 = object [ "type" .= ("string" :: Text), "nullable" .= True ]
    (decode (encode (migrate30NullableValue v30)) :: Maybe Schema)
      `shouldBe`
      Just (mempty { _schemaType = Just (OpenApiTypeArray [OpenApiString, OpenApiNull]) })

  it "drops nullable:false without touching type" $ do
    let v30 = object [ "type" .= ("string" :: Text), "nullable" .= False ]
    (decode (encode (migrate30NullableValue v30)) :: Maybe Schema)
      `shouldBe`
      Just (mempty { _schemaType = Just (OpenApiTypeSingle OpenApiString) })

  it "rewrites boolean exclusiveMaximum to a numeric bound (dropping maximum)" $ do
    let v30 = object [ "maximum" .= (100 :: Int), "exclusiveMaximum" .= True ]
    (decode (encode (migrate30ExclusiveBoundsValue v30)) :: Maybe Schema)
      `shouldBe`
      Just (mempty { _schemaExclusiveMaximum = Just 100 })

  it "keeps maximum when exclusiveMaximum:false" $ do
    let v30 = object [ "maximum" .= (100 :: Int), "exclusiveMaximum" .= False ]
    (decode (encode (migrate30ExclusiveBoundsValue v30)) :: Maybe Schema)
      `shouldBe`
      Just (mempty { _schemaMaximum = Just 100 })

  it "rewrites a tuple items array into prefixItems + items:false" $ do
    let v30 = object [ "items" .=
                ([ object ["type" .= ("string" :: Text)]
                 , object ["type" .= ("number" :: Text)] ] :: [Value]) ]
        expected = mempty
          { _schemaPrefixItems =
              Just [ Inline (mempty { _schemaType = Just (OpenApiTypeSingle OpenApiString) })
                   , Inline (mempty { _schemaType = Just (OpenApiTypeSingle OpenApiNumber) }) ]
          , _schemaItems = Just (OpenApiItemsBoolean False) }
    (decode (encode (migrate30ItemsArrayValue v30)) :: Maybe Schema) `shouldBe` Just expected

  it "migrate30To31 recurses into nested properties" $ do
    let v30 = object
          [ "type" .= ("object" :: Text)
          , "properties" .= object
              [ "n" .= object [ "type" .= ("string" :: Text), "nullable" .= True ] ] ]
        nestedType = do
          s  <- decode (encode (migrate30To31 v30)) :: Maybe Schema
          pn <- InsOrdHashMap.lookup ("n" :: Text) (_schemaProperties s)
          case pn of
            Inline ns -> _schemaType ns
            _         -> Nothing
    -- the nested property schema's nullable became a 3.1 type array
    nestedType `shouldBe` Just (OpenApiTypeArray [OpenApiString, OpenApiNull])
