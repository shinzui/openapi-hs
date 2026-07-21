module Data.HashMap.Strict.InsOrd.CompatSpec where

import Control.Lens (at, ix, (%~), (&), (.~), (?~))
import Control.Monad.State.Strict (runState, state)
import Data.Aeson (eitherDecode, encode)
import Data.ByteString.Lazy.Char8 qualified as BSL
import Data.HashMap.Strict qualified as HashMap
import Data.HashMap.Strict.InsOrd.Compat qualified as InsOrd
import Data.Word (Word8)
import Test.Hspec
import Test.Hspec.QuickCheck (prop)
import Test.QuickCheck
import Test.QuickCheck.Function (Fun (..))

data Operation
  = FromList [(Word8, Int)]
  | Empty
  | Singleton Word8 Int
  | Insert Word8 Int Operation
  | Delete Word8 Operation
  | Alter Word8 (Fun (Maybe Int) (Maybe Int)) Operation
  | Union Operation Operation
  | Difference Operation Operation
  | Intersection Operation Operation
  | Filter (Fun Int Bool) Operation
  deriving (Show)

instance Arbitrary Operation where
  arbitrary = sized gen
    where
      terminals =
        [ FromList <$> arbitrary,
          pure Empty,
          Singleton <$> arbitrary <*> arbitrary
        ]
      gen 0 = oneof terminals
      gen n =
        oneof $
          terminals
            <> [ Insert <$> arbitrary <*> arbitrary <*> smaller,
                 Delete <$> arbitrary <*> smaller,
                 Alter <$> arbitrary <*> arbitrary <*> smaller,
                 Union <$> half <*> half,
                 Difference <$> half <*> half,
                 Intersection <$> half <*> half,
                 Filter <$> arbitrary <*> smaller
               ]
        where
          smaller = gen (n - 1)
          half = gen (n `div` 2)

evalInsOrd :: Operation -> InsOrd.InsOrdHashMap Word8 Int
evalInsOrd operation = case operation of
  FromList pairs -> InsOrd.fromList pairs
  Empty -> InsOrd.empty
  Singleton key value -> InsOrd.singleton key value
  Insert key value rest -> InsOrd.insert key value (evalInsOrd rest)
  Delete key rest -> InsOrd.delete key (evalInsOrd rest)
  Alter key (Fun _ f) rest -> InsOrd.alter f key (evalInsOrd rest)
  Union left right -> InsOrd.union (evalInsOrd left) (evalInsOrd right)
  Difference left right -> InsOrd.difference (evalInsOrd left) (evalInsOrd right)
  Intersection left right -> InsOrd.intersection (evalInsOrd left) (evalInsOrd right)
  Filter (Fun _ predicate) rest -> InsOrd.filter predicate (evalInsOrd rest)

evalHashMap :: Operation -> HashMap.HashMap Word8 Int
evalHashMap operation = case operation of
  FromList pairs -> HashMap.fromList pairs
  Empty -> HashMap.empty
  Singleton key value -> HashMap.singleton key value
  Insert key value rest -> HashMap.insert key value (evalHashMap rest)
  Delete key rest -> HashMap.delete key (evalHashMap rest)
  Alter key (Fun _ f) rest -> HashMap.alter f key (evalHashMap rest)
  Union left right -> HashMap.union (evalHashMap left) (evalHashMap right)
  Difference left right -> HashMap.difference (evalHashMap left) (evalHashMap right)
  Intersection left right -> HashMap.intersection (evalHashMap left) (evalHashMap right)
  Filter (Fun _ predicate) rest -> HashMap.filter predicate (evalHashMap rest)

prop_operationModel :: Operation -> Property
prop_operationModel operation =
  let actual = evalInsOrd operation
   in counterexample (show (InsOrd.toList actual)) $
        conjoin
          [ InsOrd.toHashMap actual === evalHashMap operation,
            property (InsOrd.valid actual)
          ]

prop_mapKeysModel :: [(Word8, Int)] -> Fun Word8 Word8 -> Property
prop_mapKeysModel pairs (Fun _ f) =
  let input = InsOrd.fromList pairs
      actual = InsOrd.mapKeys f input
      expected = HashMap.fromList [(f key, value) | (key, value) <- HashMap.toList (InsOrd.toHashMap input)]
   in conjoin
        [ InsOrd.toHashMap actual === expected,
          property (InsOrd.valid actual)
        ]

spec :: Spec
spec = do
  describe "operation model" $ do
    prop "matches Data.HashMap.Strict and preserves valid" prop_operationModel
    prop "matches HashMap collision semantics in mapKeys" prop_mapKeysModel

  describe "ordered map behavior" $ do
    it "keeps the last duplicate at the end" $
      InsOrd.toList (InsOrd.fromList [("a", 1 :: Int), ("b", 2), ("a", 3)])
        `shouldBe` [("b", 2), ("a", 3)]

    it "uses left-biased union and appends right-only keys" $
      InsOrd.toList
        ( InsOrd.union
            (InsOrd.fromList [("a", 1 :: Int), ("b", 2)])
            (InsOrd.fromList [("b", 9), ("c", 3)])
        )
        `shouldBe` [("a", 1), ("b", 2), ("c", 3)]

    it "combines existing values with insertWith" $
      InsOrd.toList (InsOrd.insertWith (+) "a" (4 :: Int) (InsOrd.fromList [("a", 3), ("b", 2)]))
        `shouldBe` [("a", 7), ("b", 2)]

    it "combines unions with their key and preserves union order" $
      InsOrd.toList
        ( InsOrd.unionWithKey
            (\key left right -> key <> ":" <> left <> right)
            (InsOrd.fromList [("a", "L"), ("b", "L")])
            (InsOrd.fromList [("b", "R"), ("c", "R")])
        )
        `shouldBe` [("a", "L"), ("b", "b:LR"), ("c", "R")]

    it "filters and transforms with mapMaybeWithKey in insertion order" $
      InsOrd.toList
        ( InsOrd.mapMaybeWithKey
            (\key value -> if key == "b" then Nothing else Just (value * 10))
            (InsOrd.fromList [("a", 1 :: Int), ("b", 2), ("c", 3)])
        )
        `shouldBe` [("a", 10), ("c", 30)]

    it "folds and traverses in insertion order" $ do
      let input = InsOrd.fromList [("b", 1 :: Int), ("a", 2), ("c", 3)]
          folded = InsOrd.foldrWithKey (\key value rest -> (key, value) : rest) [] input
          (traversed, visited) =
            runState
              (InsOrd.traverseWithKey (\key value -> state (\keys -> (value + 1, keys <> [key]))) input)
              []
      folded `shouldBe` InsOrd.toList input
      visited `shouldBe` ["b", "a", "c"]
      InsOrd.toList traversed `shouldBe` [("b", 2), ("a", 3), ("c", 4)]

    it "supports lens ix and at operations" $ do
      let input = InsOrd.fromList [("a", 1 :: Int), ("b", 2)]
      InsOrd.toList (input & ix "a" %~ (+ 10)) `shouldBe` [("a", 11), ("b", 2)]
      InsOrd.toList (input & at "b" .~ Nothing) `shouldBe` [("a", 1)]
      InsOrd.toList (input & at "c" ?~ 3) `shouldBe` [("a", 1), ("b", 2), ("c", 3)]

    it "round-trips through Show and Read with order intact" $ do
      let input = InsOrd.fromList [('b', 1 :: Int), ('a', 2)]
          output = read (show input) :: InsOrd.InsOrdHashMap Char Int
      InsOrd.toList output `shouldBe` InsOrd.toList input

    it "keeps order-insensitive compat equality" $ do
      let left = InsOrd.fromList [("a", 1 :: Int), ("b", 2)]
          right = InsOrd.fromList [("b", 2), ("a", 1)]
      left `shouldBe` right
      InsOrd.toList left `shouldNotBe` InsOrd.toList right

  describe "JSON compatibility" $ do
    it "encodes as an insertion-ordered object" $
      encode (InsOrd.fromList [("b", 1 :: Int), ("a", 2)])
        `shouldBe` BSL.pack "{\"b\":1,\"a\":2}"

    it "round-trips map contents semantically" $ do
      let input = InsOrd.fromList [("b", 1 :: Int), ("a", 2)]
          decoded = eitherDecode (encode input) :: Either String (InsOrd.InsOrdHashMap String Int)
      fmap InsOrd.toHashMap decoded `shouldBe` Right (InsOrd.toHashMap input)

  describe "upstream regressions" $
    it "avoids insertion-index overflow after repeated unions" $ do
      let base = InsOrd.fromList (zip "hello" "world")
          expanded = iterate (\value -> InsOrd.union value value) base !! 64
          final = InsOrd.insert '!' '!' expanded
      InsOrd.elems final `shouldBe` "wold!"
      InsOrd.valid final `shouldBe` True
