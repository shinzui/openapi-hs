{-# LANGUAGE GADTs #-}

-- | Vendored from @insert-ordered-containers-0.3.0@.
--
-- Copyright (c) 2015-2026 Oleg Grenrus
-- Licensed under BSD-3-Clause; see
-- @LICENSES/insert-ordered-containers-BSD-3-Clause.txt@.
module Data.HashMap.InsOrd.Compat.Internal where

import Control.Applicative ((<**>))
import Prelude hiding (filter, foldr, lookup, map, null)

-------------------------------------------------------------------------------
-- SortedAp
-------------------------------------------------------------------------------

-- Sort using insertion sort
-- Hopefully it's fast enough for where we need it
-- otherwise: https://gist.github.com/treeowl/9621f58d55fe0c4f9162be0e074b1b29
-- http://elvishjerricco.github.io/2017/03/23/applicative-sorting.html also related

-- Free applicative which re-orders effects
-- Mostly from Edward Kmett's `free` package.
data SortedAp f a where
  Pure :: a -> SortedAp f a
  SortedAp :: !Int -> f a -> SortedAp f (a -> b) -> SortedAp f b

instance Functor (SortedAp f) where
  fmap f (Pure a) = Pure (f a)
  fmap f (SortedAp i x y) = SortedAp i x ((f .) <$> y)

instance Applicative (SortedAp f) where
  pure = Pure
  Pure f <*> y = fmap f y
  -- This is different from real Ap
  f <*> Pure y = fmap ($ y) f
  f@(SortedAp i x y) <*> z@(SortedAp j u v)
    | i < j = SortedAp i x (flip <$> y <*> z)
    | otherwise = SortedAp j u ((.) <$> f <*> v)

liftSortedAp :: Int -> f a -> SortedAp f a
liftSortedAp i x = SortedAp i x (Pure id)

retractSortedAp :: (Applicative f) => SortedAp f a -> f a
retractSortedAp (Pure x) = pure x
retractSortedAp (SortedAp _ f x) = f <**> retractSortedAp x
