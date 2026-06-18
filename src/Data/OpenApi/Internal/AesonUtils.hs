-- |
-- Module:      Data.OpenApi.Internal.AesonUtils
-- Maintainer:  Nadeem Bitar <nadeem@gmail.com>
-- Stability:   experimental
--
-- Internal generic-SOP helpers for deriving the library's aeson instances. No
-- API stability guarantees.
module Data.OpenApi.Internal.AesonUtils (
    -- * Generic functions
    AesonDefaultValue(..),
    sopOpenApiGenericToJSON,
    sopOpenApiGenericToEncoding,
    sopOpenApiGenericToJSONWithOpts,
    sopOpenApiGenericParseJSON,
    -- * Options
    HasOpenApiAesonOptions(..),
    OpenApiAesonOptions,
    mkOpenApiAesonOptions,
    saoPrefix,
    saoAdditionalPairs,
    saoSubObject,
    -- * Dollar-prefixed keys (JSON Schema 2020-12: $id, $ref, $defs, …)
    applyKeyRenamesToJSON,
    applyKeyRenamesParseJSON,
    ) where

import Prelude ()
import Prelude.Compat

import Control.Applicative ((<|>))
import Control.Lens     (makeLenses, (^.))
import Control.Monad    (unless)
import Data.Aeson       (ToJSON(..), FromJSON(..), Value(..), Object, object, (.:), (.:?), (.!=), withObject, Encoding, pairs, (.=), Series)
import Data.Aeson.Types (Parser, Pair)
import Data.Char        (toLower, isUpper)
import Data.Foldable    (traverse_, foldl')
import Data.Text        (Text)

import Generics.SOP

import qualified Data.Text as T
import qualified Data.Set as Set
import qualified Data.HashMap.Strict.InsOrd.Compat as InsOrd
import qualified Data.HashSet.InsOrd as InsOrdHS

import Data.OpenApi.Aeson.Compat (keyToString, objectToList, stringToKey, lookupKey, insertKey, deleteKey)

-------------------------------------------------------------------------------
-- Dollar-prefixed keys (JSON Schema 2020-12)
-------------------------------------------------------------------------------

-- | Rewrite a generated JSON 'Value': for each @(plain, dollar)@ pair, if the
-- top-level object has the @plain@ key, move its value to the @dollar@ key. The
-- generic field-name rule cannot emit a key beginning with @$@, so this post-pass
-- injects them (e.g. @"ref"@ → @"$ref"@). Non-object values are returned unchanged.
applyKeyRenamesToJSON :: [(Text, Text)] -> Value -> Value
applyKeyRenamesToJSON renames (Object o) = Object (foldl' renameOne o renames)
  where
    renameOne obj (plain, dollar) =
      case lookupKey plain obj of
        Nothing -> obj
        Just v  -> insertKey dollar v (deleteKey (stringToKey (T.unpack plain)) obj)
applyKeyRenamesToJSON _ v = v

-- | The inverse of 'applyKeyRenamesToJSON': move each @dollar@ key back to its
-- @plain@ key before the generic parser runs (e.g. @"$ref"@ → @"ref"@).
applyKeyRenamesParseJSON :: [(Text, Text)] -> Object -> Object
applyKeyRenamesParseJSON renames o = foldl' renameOne o renames
  where
    renameOne obj (plain, dollar) =
      case lookupKey dollar obj of
        Nothing -> obj
        Just v  -> insertKey plain v (deleteKey (stringToKey (T.unpack dollar)) obj)

-------------------------------------------------------------------------------
-- OpenApiAesonOptions
-------------------------------------------------------------------------------

data OpenApiAesonOptions = OpenApiAesonOptions
    { _saoPrefix          :: String
    , _saoAdditionalPairs :: [Pair]
    , _saoSubObject       :: Maybe String
    }

mkOpenApiAesonOptions
    :: String  -- ^ prefix
    -> OpenApiAesonOptions
mkOpenApiAesonOptions pfx = OpenApiAesonOptions pfx [] Nothing

makeLenses ''OpenApiAesonOptions

class (Generic a, All2 AesonDefaultValue (Code a)) => HasOpenApiAesonOptions a where
    openApiAesonOptions :: Proxy a -> OpenApiAesonOptions

    -- So far we use only default definitions
    aesonDefaults :: Proxy a -> POP Maybe (Code a)
    aesonDefaults _ = hcpure (Proxy :: Proxy AesonDefaultValue) defaultValue

-------------------------------------------------------------------------------
-- Generics
-------------------------------------------------------------------------------

class AesonDefaultValue a where
    defaultValue :: Maybe a
    defaultValue = Nothing

instance AesonDefaultValue Text where defaultValue = Nothing
instance AesonDefaultValue (Maybe a) where defaultValue = Just Nothing
instance AesonDefaultValue [a] where defaultValue = Just []
instance AesonDefaultValue (Set.Set a) where defaultValue = Just Set.empty
instance AesonDefaultValue (InsOrdHS.InsOrdHashSet k) where defaultValue = Just InsOrdHS.empty
instance AesonDefaultValue (InsOrd.InsOrdHashMap k v) where defaultValue = Just InsOrd.empty

-------------------------------------------------------------------------------
-- ToJSON
-------------------------------------------------------------------------------

-- | Generic serialisation for OpenAPI records.
--
-- Features
--
-- * omits nulls, empty objects and empty arrays (configurable)
-- * possible to add fields
-- * possible to merge sub-object
sopOpenApiGenericToJSON
    :: forall a xs.
        ( HasDatatypeInfo a
        , HasOpenApiAesonOptions a
        , All2 ToJSON (Code a)
        , All2 Eq (Code a)
        , Code a ~ '[xs]
        )
    => a
    -> Value
sopOpenApiGenericToJSON x =
    let ps = sopOpenApiGenericToJSON' opts (from x) (datatypeInfo proxy) (aesonDefaults proxy)
    in object (opts ^. saoAdditionalPairs ++ ps)
  where
    proxy = Proxy :: Proxy a
    opts  = openApiAesonOptions proxy

-- | *TODO:* This is only used by ToJSON (ParamSchema for the schema kind)
--
-- Also uses default `aesonDefaults`
sopOpenApiGenericToJSONWithOpts
    :: forall a xs.
        ( Generic a
        , All2 AesonDefaultValue (Code a)
        , HasDatatypeInfo a
        , All2 ToJSON (Code a)
        , All2 Eq (Code a)
        , Code a ~ '[xs]
        )
    => OpenApiAesonOptions
    -> a
    -> Value
sopOpenApiGenericToJSONWithOpts opts x =
    let ps = sopOpenApiGenericToJSON' opts (from x) (datatypeInfo proxy) defs
    in object (opts ^. saoAdditionalPairs ++ ps)
  where
    proxy = Proxy :: Proxy a
    defs = hcpure (Proxy :: Proxy AesonDefaultValue) defaultValue

sopOpenApiGenericToJSON'
    :: (All2 ToJSON '[xs], All2 Eq '[xs])
    => OpenApiAesonOptions
    -> SOP I '[xs]
    -> DatatypeInfo '[xs]
    -> POP Maybe '[xs]
    -> [Pair]
sopOpenApiGenericToJSON' opts (SOP (Z fields)) (ADT _ _ (Record _ fieldsInfo :* Nil) _) (POP (defs :* Nil)) =
    sopOpenApiGenericToJSON'' opts fields fieldsInfo defs
sopOpenApiGenericToJSON' _ _ _ _ = error "sopOpenApiGenericToJSON: unsupported type"

sopOpenApiGenericToJSON''
    :: (All ToJSON xs, All Eq xs)
    => OpenApiAesonOptions
    -> NP I xs
    -> NP FieldInfo xs
    -> NP Maybe xs
    -> [Pair]
sopOpenApiGenericToJSON'' (OpenApiAesonOptions prefix _ sub) = go
  where
    go :: (All ToJSON ys, All Eq ys) => NP I ys -> NP FieldInfo ys -> NP Maybe ys -> [Pair]
    go  Nil Nil Nil = []
    go (I x :* xs) (FieldInfo name :* names) (def :* defs)
        | Just name' == sub = case json of
              Object m -> objectToList m ++ rest
              Null     -> rest
              _        -> error $ "sopOpenApiGenericToJSON: subjson is not an object: " ++ show json
        -- If default value: omit it.
        | Just x == def =
            rest
        | otherwise =
            (stringToKey name', json) : rest
      where
        json  = toJSON x
        name' = fieldNameModifier name
        rest  = go xs names defs

    fieldNameModifier = modifier . drop 1
    modifier = lowerFirstUppers . drop (length prefix)
    lowerFirstUppers s = map toLower x ++ y
      where (x, y) = span isUpper s

-------------------------------------------------------------------------------
-- FromJSON
-------------------------------------------------------------------------------

sopOpenApiGenericParseJSON
    :: forall a xs.
        ( HasDatatypeInfo a
        , HasOpenApiAesonOptions a
        , All2 FromJSON (Code a)
        , All2 Eq (Code a)
        , Code a ~ '[xs]
        )
    => Value
    -> Parser a
sopOpenApiGenericParseJSON = withObject "OpenAPI Record Object" $ \obj ->
    let ps = sopOpenApiGenericParseJSON' opts obj (datatypeInfo proxy) (aesonDefaults proxy)
    in do
        traverse_ (parseAdditionalField obj) (opts ^. saoAdditionalPairs)
        to <$> ps
  where
    proxy = Proxy :: Proxy a
    opts  = openApiAesonOptions proxy

    parseAdditionalField :: Object -> Pair -> Parser ()
    parseAdditionalField obj (k, v) = do
        v' <- obj .: k
        unless (v == v') $ fail $
            "Additonal field don't match for key " ++ keyToString k
            ++ ": " ++ show v
            ++ " /= " ++ show v'

sopOpenApiGenericParseJSON'
    :: (All2 FromJSON '[xs], All2 Eq '[xs])
    => OpenApiAesonOptions
    -> Object
    -> DatatypeInfo '[xs]
    -> POP Maybe '[xs]
    -> Parser (SOP I '[xs])
sopOpenApiGenericParseJSON' opts obj (ADT _ _ (Record _ fieldsInfo :* Nil) _) (POP (defs :* Nil)) =
    SOP . Z <$> sopOpenApiGenericParseJSON'' opts obj fieldsInfo defs
sopOpenApiGenericParseJSON' _ _ _ _ = error "sopOpenApiGenericParseJSON: unsupported type"

sopOpenApiGenericParseJSON''
    :: (All FromJSON xs, All Eq xs)
    => OpenApiAesonOptions
    -> Object
    -> NP FieldInfo xs
    -> NP Maybe xs
    -> Parser (NP I xs)
sopOpenApiGenericParseJSON'' (OpenApiAesonOptions prefix _ sub) obj = go
  where
    go :: (All FromJSON ys, All Eq ys) => NP FieldInfo ys -> NP Maybe ys -> Parser (NP I ys)
    go  Nil Nil = pure Nil
    go (FieldInfo name :* names) (def :* defs)
        | Just name' == sub =
            -- Note: we might strip fields of outer structure.
            cons <$> (withDef $ parseJSON $ Object obj) <*> rest
        | otherwise = case def of
            Just def' -> cons <$> obj .:? stringToKey name' .!= def' <*> rest
            Nothing  ->  cons <$> obj .: stringToKey name' <*> rest
      where
        cons h t = I h :* t
        name' = fieldNameModifier name
        rest  = go names defs

        withDef = case def of
            Just def' -> (<|> pure def')
            Nothing   -> id

    fieldNameModifier = modifier . drop 1
    modifier = lowerFirstUppers . drop (length prefix)
    lowerFirstUppers s = map toLower x ++ y
      where (x, y) = span isUpper s

-------------------------------------------------------------------------------
-- ToEncoding
-------------------------------------------------------------------------------

sopOpenApiGenericToEncoding
    :: forall a xs.
        ( HasDatatypeInfo a
        , HasOpenApiAesonOptions a
        , All2 ToJSON (Code a)
        , All2 Eq (Code a)
        , Code a ~ '[xs]
        )
    => a
    -> Encoding
sopOpenApiGenericToEncoding x =
    let ps = sopOpenApiGenericToEncoding' opts (from x) (datatypeInfo proxy) (aesonDefaults proxy)
    in pairs (pairsToSeries (opts ^. saoAdditionalPairs) <> ps)
  where
    proxy = Proxy :: Proxy a
    opts  = openApiAesonOptions proxy

pairsToSeries :: [Pair] -> Series
pairsToSeries = foldMap (\(k, v) -> (k .= v))

sopOpenApiGenericToEncoding'
    :: (All2 ToJSON '[xs], All2 Eq '[xs])
    => OpenApiAesonOptions
    -> SOP I '[xs]
    -> DatatypeInfo '[xs]
    -> POP Maybe '[xs]
    -> Series
sopOpenApiGenericToEncoding' opts (SOP (Z fields)) (ADT _ _ (Record _ fieldsInfo :* Nil) _) (POP (defs :* Nil)) =
    sopOpenApiGenericToEncoding'' opts fields fieldsInfo defs
sopOpenApiGenericToEncoding' _ _ _ _ = error "sopOpenApiGenericToEncoding: unsupported type"

sopOpenApiGenericToEncoding''
    :: (All ToJSON xs, All Eq xs)
    => OpenApiAesonOptions
    -> NP I xs
    -> NP FieldInfo xs
    -> NP Maybe xs
    -> Series
sopOpenApiGenericToEncoding'' (OpenApiAesonOptions prefix _ sub) = go
  where
    go :: (All ToJSON ys, All Eq ys) => NP I ys -> NP FieldInfo ys -> NP Maybe ys -> Series
    go  Nil Nil Nil = mempty
    go (I x :* xs) (FieldInfo name :* names) (def :* defs)
        | Just name' == sub = case toJSON x of
              Object m -> pairsToSeries (objectToList m) <> rest
              Null     -> rest
              _        -> error $ "sopOpenApiGenericToJSON: subjson is not an object: " ++ show (toJSON x)
        -- If default value: omit it.
        | Just x == def =
            rest
        | otherwise =
            (stringToKey name' .= x) <> rest
      where
        name' = fieldNameModifier name
        rest  = go xs names defs

    fieldNameModifier = modifier . drop 1
    modifier = lowerFirstUppers . drop (length prefix)
    lowerFirstUppers s = map toLower x ++ y
      where (x, y) = span isUpper s
