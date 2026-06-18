-- |
-- Module:      Data.OpenApi.Internal.Utils
-- Maintainer:  Nadeem Bitar <nadeem@gmail.com>
-- Stability:   experimental
--
-- Internal shared utilities (Template Haskell lens helpers, JSON/monoid
-- combinators). No API stability guarantees.
module Data.OpenApi.Internal.Utils where

import Control.Lens ((%~), (&))
import Control.Lens.TH
import Data.Aeson
import Data.Aeson.Encode.Pretty qualified as P
import Data.Aeson.Types
import Data.ByteString.Lazy qualified as BSL
import Data.Char
import Data.Data
import Data.HashMap.Strict (HashMap)
import Data.HashMap.Strict qualified as HashMap
import Data.HashMap.Strict.InsOrd.Compat (InsOrdHashMap)
import Data.HashMap.Strict.InsOrd.Compat qualified as InsOrdHashMap
import Data.Hashable (Hashable)
import Data.Map (Map)
import Data.Set (Set)
import Data.Text (Text)
import GHC.Generics
import Language.Haskell.TH (mkName)
import Prelude.Compat
import Prelude ()

openApiFieldRules :: LensRules
openApiFieldRules = defaultFieldRules & lensField %~ openApiFieldNamer
  where
    openApiFieldNamer namer dname fnames fname =
      map fixDefName (namer dname fnames fname)

    fixDefName (MethodName cname mname) = MethodName cname (fixName mname)
    fixDefName (TopName name) = TopName (fixName name)

    fixName = mkName . fixName' . show

    fixName' "in" = "in_" -- keyword
    fixName' "type" = "type_" -- keyword
    fixName' "default" = "default_" -- keyword
    fixName' "if" = "if_" -- keyword
    fixName' "then" = "then_" -- keyword
    fixName' "else" = "else_" -- keyword
    fixName' "minimum" = "minimum_" -- Prelude conflict
    fixName' "maximum" = "maximum_" -- Prelude conflict
    fixName' "enum" = "enum_" -- Control.Lens conflict
    fixName' "head" = "head_" -- Prelude conflict
    fixName' "not" = "not_" -- Prelude conflict
    fixName' "id" = "id_" -- Prelude conflict
    fixName' "const" = "const_" -- Prelude conflict
    fixName' "contains" = "contains_" -- Control.Lens conflict
    fixName' n = n

gunfoldEnum :: String -> [a] -> (forall b r. (Data b) => c (b -> r) -> c r) -> (forall r. r -> c r) -> Constr -> c a
gunfoldEnum tname xs _k z c = case lookup (constrIndex c) (zip [1 ..] xs) of
  Just x -> z x
  Nothing -> error $ "Data.Data.gunfold: Constructor " ++ show c ++ " is not of type " ++ tname ++ "."

jsonPrefix :: String -> Options
jsonPrefix prefix =
  defaultOptions
    { fieldLabelModifier = modifier . drop 1,
      constructorTagModifier = modifier,
      sumEncoding = ObjectWithSingleField,
      omitNothingFields = True
    }
  where
    modifier = lowerFirstUppers . drop (length prefix)

    lowerFirstUppers s = map toLower x ++ y
      where
        (x, y) = span isUpper s

parseOneOf :: (ToJSON a) => [a] -> Value -> Parser a
parseOneOf xs js =
  case lookup js ys of
    Nothing -> fail $ "invalid json: " ++ show js ++ " (expected one of " ++ show (map fst ys) ++ ")"
    Just x -> pure x
  where
    ys = zip (map toJSON xs) xs

(<+>) :: Value -> Value -> Value
Object x <+> Object y = Object (x <> y)
_ <+> _ = error "<+>: merging non-objects"

genericMempty :: (Generic a, GMonoid (Rep a)) => a
genericMempty = to gmempty

genericMappend :: (Generic a, GMonoid (Rep a)) => a -> a -> a
genericMappend x y = to (gmappend (from x) (from y))

class GMonoid f where
  gmempty :: f p
  gmappend :: f p -> f p -> f p

instance GMonoid U1 where
  gmempty = U1
  gmappend _ _ = U1

instance (GMonoid f, GMonoid g) => GMonoid (f :*: g) where
  gmempty = gmempty :*: gmempty
  gmappend (a :*: x) (b :*: y) = gmappend a b :*: gmappend x y

instance (OpenApiMonoid a) => GMonoid (K1 i a) where
  gmempty = K1 openApiMempty
  gmappend (K1 x) (K1 y) = K1 (openApiMappend x y)

instance (GMonoid f) => GMonoid (M1 i t f) where
  gmempty = M1 gmempty
  gmappend (M1 x) (M1 y) = M1 (gmappend x y)

class OpenApiMonoid m where
  openApiMempty :: m
  openApiMappend :: m -> m -> m
  default openApiMempty :: (Monoid m) => m
  openApiMempty = mempty
  default openApiMappend :: (Monoid m) => m -> m -> m
  openApiMappend = mappend

instance OpenApiMonoid [a]

instance (Ord a) => OpenApiMonoid (Set a)

instance (Ord k) => OpenApiMonoid (Map k v)

instance (Eq k, Hashable k) => OpenApiMonoid (HashMap k v) where
  openApiMempty = mempty
  openApiMappend = HashMap.unionWith (\_old new -> new)

instance (Eq k, Hashable k) => OpenApiMonoid (InsOrdHashMap k v) where
  openApiMempty = mempty
  openApiMappend = InsOrdHashMap.unionWith (\_old new -> new)

instance OpenApiMonoid Text where
  openApiMempty = mempty
  openApiMappend x "" = x
  openApiMappend _ y = y

instance OpenApiMonoid (Maybe a) where
  openApiMempty = Nothing
  openApiMappend x Nothing = x
  openApiMappend _ y = y

encodePretty :: (ToJSON a) => a -> BSL.ByteString
encodePretty = P.encodePretty' $ P.defConfig {P.confCompare = P.compare}
