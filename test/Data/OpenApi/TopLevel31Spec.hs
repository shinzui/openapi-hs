{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes       #-}
-- | Round-trip coverage for the OpenAPI 3.1 top-level object features added in EP-5:
-- @Info.summary@, @License.identifier@, @OpenApi.webhooks@, and @PathItem.$ref@.
module Data.OpenApi.TopLevel31Spec where

import           Control.Lens         hiding ((.=))
import           Data.Aeson           (Value, decode, encode, object, toJSON, (.=))
import           Data.Aeson.QQ.Simple (aesonQQ)
import           Data.Text            (Text)
import           Test.Hspec

import qualified Data.HashMap.Strict.InsOrd.Compat as InsOrdHashMap

import           Data.OpenApi
import           Data.OpenApi.Internal

import           SpecCommon

licenseIdentifierExample :: License
licenseIdentifierExample = "MIT" & identifier ?~ "MIT"

licenseIdentifierExampleJSON :: Value
licenseIdentifierExampleJSON = [aesonQQ|
{
  "name": "MIT",
  "identifier": "MIT"
}
|]

pathItemRefExample :: PathItem
pathItemRefExample = mempty
  & ref     ?~ "#/components/pathItems/Foo"
  & summary ?~ "Shared path item"

pathItemRefExampleJSON :: Value
pathItemRefExampleJSON = [aesonQQ|
{
  "$ref": "#/components/pathItems/Foo",
  "summary": "Shared path item"
}
|]

webhooksExample :: OpenApi
webhooksExample = mempty
  & webhooks .~ InsOrdHashMap.fromList
      [ ("newPet", Inline (mempty & summary ?~ "A new pet was created")) ]

spec :: Spec
spec = do
  describe "Info.summary (OpenAPI 3.1)" $
    it "round-trips a summary and emits the \"summary\" key" $ do
      let i = (mempty :: Info) & title .~ "Pets" & summary ?~ "A pet store API" & version .~ "1.0.0"
      i ^. summary `shouldBe` Just "A pet store API"
      (decode (encode i) :: Maybe Info) `shouldBe` Just i

  describe "License Object (SPDX identifier)" $
    licenseIdentifierExample <=> licenseIdentifierExampleJSON

  describe "License.identifier is url-free" $
    it "decodes {name, identifier} with no url" $
      (decode "{\"name\":\"MIT\",\"identifier\":\"MIT\"}" :: Maybe License)
        `shouldBe` Just (License "MIT" (Just "MIT") Nothing)

  describe "OpenApi.webhooks (OpenAPI 3.1)" $ do
    it "round-trips an inline webhook path item" $
      (decode (encode webhooksExample) :: Maybe OpenApi) `shouldBe` Just webhooksExample
    it "decodes a webhook value given by $ref into Ref" $
      (decode "{\"$ref\":\"#/components/pathItems/Foo\"}" :: Maybe (Referenced PathItem))
        `shouldBe` Just (Ref (Reference "Foo"))

  describe "PathItem Object ($ref, OpenAPI 3.1)" $ do
    pathItemRefExample <=> pathItemRefExampleJSON
    it "emits the literal \"$ref\" key, not \"ref\"" $
      toJSON pathItemRefExample `shouldBe`
        object [ "$ref" .= ("#/components/pathItems/Foo" :: Text)
               , "summary" .= ("Shared path item" :: Text) ]
