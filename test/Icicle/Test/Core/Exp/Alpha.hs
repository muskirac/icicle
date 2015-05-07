{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -fno-warn-missing-signatures #-}
module Icicle.Test.Core.Exp.Alpha where

import           Icicle.Test.Core.Arbitrary
import           Icicle.Core.Eval.Exp
import           Icicle.Common.Base
import           Icicle.Common.Exp

import           P

import           System.IO

import           Test.QuickCheck


-- Anything is alpha equivalent to itself
-- =====================
prop_alpha_self x =
 x `alphaEquality` x


-- Any CLOSED expression is alpha equivalent to itself after prefixing
-- TODO: implement freevars or closed check
-- =====================
zzz_disabled_prop_alpha_self_prefix x =
 x `alphaEquality` renameExp (NameMod 0) x


-- If two things evaluate to a different value, they can't be alpha equivalent
-- =====================
prop_different_value__not_alpha x y =
 not (eval0 evalPrim x `equalExceptFunctionsE` eval0 evalPrim y)
 ==> not (x `alphaEquality` y)


-- Conversely, if two things are alpha equivalent they must have same value
-- =====================
prop_alpha__same_value x y =
 x `alphaEquality` y
 ==> eval0 evalPrim x `equalExceptFunctionsE` eval0 evalPrim y


-- It should follow from the above, but why not something about types
-- =====================
prop_wt_different_type__not_alpha =
 withTypedExp $ \x t ->
 withTypedExp $ \y s ->
 s /= t
 ==> not (x `alphaEquality` y)



return []
tests :: IO Bool
-- tests = $quickCheckAll
tests = $forAllProperties $ quickCheckWithResult (stdArgs { maxDiscardRatio = 10000})
