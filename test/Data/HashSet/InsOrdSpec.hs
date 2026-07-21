module Data.HashSet.InsOrdSpec where

import Control.DeepSeq (force, rnf)
import Control.DeepSeq qualified as NF
import Control.Exception (evaluate)
import Control.Lens (at, contains, ix, (&), (.~), (?~), (^?))
import Data.Aeson (eitherDecode, encode)
import Data.ByteString.Lazy.Char8 qualified as BSL
import Data.HashSet qualified as HashSet
import Data.HashSet.InsOrd qualified as InsOrd
import Data.Word (Word8)
import Test.Hspec
import Test.Hspec.QuickCheck (prop)
import Test.QuickCheck
import Test.QuickCheck.Function (Fun (..))

data Operation
  = FromList [Word8]
  | Empty
  | Singleton Word8
  | Insert Word8 Operation
  | Delete Word8 Operation
  | Union Operation Operation
  | Difference Operation Operation
  | Intersection Operation Operation
  | Map (Fun Word8 Word8) Operation
  | Filter (Fun Word8 Bool) Operation
  deriving (Show)

instance Arbitrary Operation where
  arbitrary = sized gen
    where
      terminals =
        [ FromList <$> arbitrary,
          pure Empty,
          Singleton <$> arbitrary
        ]
      gen 0 = oneof terminals
      gen n =
        oneof $
          terminals
            <> [ Insert <$> arbitrary <*> smaller,
                 Delete <$> arbitrary <*> smaller,
                 Union <$> half <*> half,
                 Difference <$> half <*> half,
                 Intersection <$> half <*> half,
                 Map <$> arbitrary <*> smaller,
                 Filter <$> arbitrary <*> smaller
               ]
        where
          smaller = gen (n - 1)
          half = gen (n `div` 2)

evalInsOrd :: Operation -> InsOrd.InsOrdHashSet Word8
evalInsOrd operation = case operation of
  FromList values -> InsOrd.fromList values
  Empty -> InsOrd.empty
  Singleton value -> InsOrd.singleton value
  Insert value rest -> InsOrd.insert value (evalInsOrd rest)
  Delete value rest -> InsOrd.delete value (evalInsOrd rest)
  Union left right -> InsOrd.union (evalInsOrd left) (evalInsOrd right)
  Difference left right -> InsOrd.difference (evalInsOrd left) (evalInsOrd right)
  Intersection left right -> InsOrd.intersection (evalInsOrd left) (evalInsOrd right)
  Map (Fun _ f) rest -> InsOrd.map f (evalInsOrd rest)
  Filter (Fun _ predicate) rest -> InsOrd.filter predicate (evalInsOrd rest)

evalHashSet :: Operation -> HashSet.HashSet Word8
evalHashSet operation = case operation of
  FromList values -> HashSet.fromList values
  Empty -> HashSet.empty
  Singleton value -> HashSet.singleton value
  Insert value rest -> HashSet.insert value (evalHashSet rest)
  Delete value rest -> HashSet.delete value (evalHashSet rest)
  Union left right -> HashSet.union (evalHashSet left) (evalHashSet right)
  Difference left right -> HashSet.difference (evalHashSet left) (evalHashSet right)
  Intersection left right -> HashSet.intersection (evalHashSet left) (evalHashSet right)
  Map (Fun _ f) rest -> HashSet.map f (evalHashSet rest)
  Filter (Fun _ predicate) rest -> HashSet.filter predicate (evalHashSet rest)

containsUnion :: Operation -> Bool
containsUnion operation = case operation of
  FromList _ -> False
  Empty -> False
  Singleton _ -> False
  Insert _ rest -> containsUnion rest
  Delete _ rest -> containsUnion rest
  Union _ _ -> True
  Difference left right -> containsUnion left || containsUnion right
  Intersection left right -> containsUnion left || containsUnion right
  Map _ rest -> containsUnion rest
  Filter _ rest -> containsUnion rest

prop_operationModel :: Operation -> Property
prop_operationModel operation =
  let actual = evalInsOrd operation
      expected = evalHashSet operation
   in conjoin
        [ counterexample ("ordered membership: " <> show (InsOrd.toList actual)) $
            InsOrd.toHashSet actual === expected,
          counterexample ("invalid ordered set: " <> show (InsOrd.toList actual)) $
            property (containsUnion operation || InsOrd.valid actual)
        ]

spec :: Spec
spec = do
  describe "operation model" $
    prop "matches Data.HashSet and preserves valid outside the union caveat" prop_operationModel

  describe "ordered set behavior" $ do
    it "keeps the last duplicate at the end" $
      InsOrd.toList (InsOrd.fromList ["a", "b", "a"])
        `shouldBe` ["b", "a"]

    it "moves an existing member to the end when inserted again" $
      InsOrd.toList (InsOrd.insert "a" (InsOrd.fromList ["a", "b"]))
        `shouldBe` ["b", "a"]

    it "uses left-biased union order followed by right-only members" $
      InsOrd.toList (InsOrd.union (InsOrd.fromList ["a", "b"]) (InsOrd.fromList ["b", "c"]))
        `shouldBe` ["a", "b", "c"]

    it "preserves the released union valid caveat and supports normalization" $ do
      let combined = InsOrd.union (InsOrd.singleton "a") (InsOrd.singleton "b")
      InsOrd.valid combined `shouldBe` False
      InsOrd.valid (InsOrd.fromHashSet (InsOrd.toHashSet combined)) `shouldBe` True

    it "supports lens ix, at, and contains" $ do
      let input = InsOrd.fromList ["a", "b"]
      input ^? ix "a" `shouldBe` Just ()
      InsOrd.toList (input & at "a" .~ Nothing) `shouldBe` ["b"]
      InsOrd.toList (input & at "c" ?~ ()) `shouldBe` ["a", "b", "c"]
      InsOrd.toList (input & contains "b" .~ False) `shouldBe` ["a"]
      InsOrd.toList (input & contains "c" .~ True) `shouldBe` ["a", "b", "c"]

    it "round-trips through Show and Read with order intact" $ do
      let input = InsOrd.fromList ['b', 'a']
          output = read (show input) :: InsOrd.InsOrdHashSet Char
      InsOrd.toList output `shouldBe` InsOrd.toList input

  describe "JSON and deep evaluation compatibility" $ do
    it "encodes as an insertion-ordered array" $
      encode (InsOrd.fromList ["b", "a"])
        `shouldBe` BSL.pack "[\"b\",\"a\"]"

    it "round-trips order and membership after index gaps" $ do
      let input = InsOrd.delete "b" (InsOrd.fromList ["a", "b", "c"])
          decoded = eitherDecode (encode input) :: Either String (InsOrd.InsOrdHashSet String)
      fmap InsOrd.toList decoded `shouldBe` Right (InsOrd.toList input)
      fmap InsOrd.toHashSet decoded `shouldBe` Right (InsOrd.toHashSet input)

    it "retains NFData and NFData1 instances" $ do
      let input = InsOrd.fromList ["a", "b"]
      evaluate (force input) `shouldReturn` input
      evaluate (NF.liftRnf rnf input) `shouldReturn` ()
