{-# LANGUAGE OverloadedLists   #-}
{-# LANGUAGE OverloadedStrings #-}
-- |
-- Module:      Data.OpenApi.Migration
--
-- Value-layer helpers that rewrite a raw, already-parsed OpenAPI __3.0__
-- 'Data.Aeson.Value' into a __3.1__-shaped 'Value', which then 'Data.Aeson.decode's
-- into the 3.1-only 'Data.OpenApi.Schema' types.
--
-- Under the project's "Strategy A" the 3.1 Haskell types deliberately cannot
-- represent 3.0-only constructs (there is no @nullable@ field, exclusive bounds
-- are numeric, and tuple @items@ arrays are gone). So a user holding a 3.0
-- document must rewrite the parsed JSON before decoding it — that is what these
-- helpers do. They are intentionally deprecated to flag that 3.0 input is
-- transitional.
module Data.OpenApi.Migration
  ( migrate30To31
  , migrate30NullableValue
  , migrate30ExclusiveBoundsValue
  , migrate30ItemsArrayValue
  , migrate30SchemaValue
  ) where

import           Data.Aeson                (Object, Value (..))
import qualified Data.Text                 as T

import           Data.OpenApi.Aeson.Compat (deleteKey, insertKey, lookupKey, stringToKey)

-- | Apply a function to a JSON object's underlying map; leave non-objects alone.
overObject :: (Object -> Object) -> Value -> Value
overObject f (Object o) = Object (f o)
overObject _ v          = v

-- | Delete a key given as 'T.Text'.
delKey :: T.Text -> Object -> Object
delKey k = deleteKey (stringToKey (T.unpack k))

-- | Rewrite a decoded 3.0 schema JSON object's @nullable@ keyword into a 3.1
-- type array. @nullable:true@ removes the @nullable@ key and adds @"null"@ to the
-- @type@ key (@"string"@ becomes @["string","null"]@; @["string"]@ becomes
-- @["string","null"]@; absent @type@ becomes @["null"]@). @nullable:false@ just
-- removes the @nullable@ key.
migrate30NullableValue :: Value -> Value
migrate30NullableValue = overObject $ \o ->
  case lookupKey "nullable" o of
    Just (Bool True)  -> insertKey "type" (addNull (lookupKey "type" o)) (delKey "nullable" o)
    Just (Bool False) -> delKey "nullable" o
    _                 -> o
  where
    addNull :: Maybe Value -> Value
    addNull (Just (String t)) = Array [String t, String "null"]
    addNull (Just (Array xs))
      | String "null" `elem` xs = Array xs
      | otherwise               = Array (xs <> [String "null"])
    addNull (Just v)          = Array [v, String "null"]
    addNull Nothing           = Array [String "null"]

-- | Rewrite 3.0 boolean exclusive bounds into 3.1 numeric ones.
--
-- @{"maximum":100,"exclusiveMaximum":true}@  becomes @{"exclusiveMaximum":100}@
-- (the @maximum@ is dropped); @{"maximum":100,"exclusiveMaximum":false}@ becomes
-- @{"maximum":100}@. Symmetric for @minimum@/@exclusiveMinimum@. An already-numeric
-- exclusive bound is left unchanged.
migrate30ExclusiveBoundsValue :: Value -> Value
migrate30ExclusiveBoundsValue =
  overObject (rewriteBound "maximum" "exclusiveMaximum" . rewriteBound "minimum" "exclusiveMinimum")
  where
    rewriteBound boundKey exclKey o =
      case lookupKey exclKey o of
        Just (Bool True) -> case lookupKey boundKey o of
          Just n@(Number _) -> insertKey exclKey n (delKey boundKey o)
          _                 -> delKey exclKey o   -- exclusive:true but no bound: drop the bool
        Just (Bool False) -> delKey exclKey o
        _                 -> o

-- | Rewrite a 3.0 tuple @items@ array into 3.1 @prefixItems@ + @items:false@.
--
-- @{"items":[a,b]}@ becomes @{"prefixItems":[a,b],"items":false}@. Fires only when
-- @items@ is a JSON array; an object or boolean @items@ is left unchanged.
migrate30ItemsArrayValue :: Value -> Value
migrate30ItemsArrayValue = overObject $ \o ->
  case lookupKey "items" o of
    Just (Array xs) -> insertKey "items" (Bool False)
                         (insertKey "prefixItems" (Array xs) (delKey "items" o))
    _               -> o

-- | Apply all single-object 3.0->3.1 rewrites to one schema object. The three
-- rewrites operate on disjoint keys, so their order does not matter.
migrate30SchemaValue :: Value -> Value
migrate30SchemaValue =
  migrate30NullableValue . migrate30ExclusiveBoundsValue . migrate30ItemsArrayValue

-- | Recursively rewrite a whole 3.0 document 'Value' into 3.1 shape, applying the
-- schema rewrites to every nested object (so schemas inside @properties@,
-- @prefixItems@, @$defs@, @allOf@, request/response bodies, … are all migrated).
-- Applying the per-object rewrite to every object is safe because each rewrite is
-- a no-op on objects lacking its trigger keys.
migrate30To31 :: Value -> Value
migrate30To31 = go
  where
    go (Object o) = migrate30SchemaValue (Object (fmap go o))
    go (Array xs) = Array (fmap go xs)
    go v          = v

{-# DEPRECATED migrate30To31, migrate30NullableValue, migrate30ExclusiveBoundsValue,
               migrate30ItemsArrayValue, migrate30SchemaValue
      "3.0 input support is transitional; remove once all inputs are 3.1." #-}
