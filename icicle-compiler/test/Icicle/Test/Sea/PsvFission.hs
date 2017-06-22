{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE PatternGuards#-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TemplateHaskell#-}
{-# LANGUAGE TupleSections #-}
{-# OPTIONS_GHC -fno-warn-missing-signatures #-}

module Icicle.Test.Sea.PsvFission where

import           Icicle.Test.Sea.Psv hiding (tests)

import           Control.Monad.IO.Class (liftIO)
import           Control.Monad.Morph (hoist)

import qualified Data.ByteString.Lazy as L
import           Data.List.NonEmpty ( NonEmpty(..) )
import qualified Data.Map as Map
import qualified Data.Set as Set
import qualified Data.Text as T
import qualified Data.Text.Lazy as LT
import qualified Data.Text.Lazy.Encoding as LT
import qualified Data.Text.Lazy.IO as LT

import           Disorder.Core.IO



import           Icicle.Sea.Eval (SeaError(..))
import qualified Icicle.Sea.Eval as S
import           Icicle.Sea.Fleet
import qualified Icicle.Core.Program.Program as C
import           Icicle.Data.Name

import           Icicle.Test.Arbitrary
import           Icicle.Test.Arbitrary.Corpus

import qualified Jetski as J

import           P
import qualified Prelude as Savage

import           System.IO

import           Test.QuickCheck (Arbitrary(..), forAll)
import           Test.QuickCheck (property, discard)
import           Test.QuickCheck.Property (succeeded)

import           X.Control.Monad.Trans.Either (EitherT, runEitherT, hoistEither)
import           X.Control.Monad.Trans.Either (bracketEitherT', left)


prop_psv_fission =
  forAll arbitrary $ \input ->
  forAll (validated 100 $ tryGenWellTypedWith S.DoNotAllowDupTime input) $ \wt1 ->
  forAll (validated 100 $ tryGenWellTypedWith S.DoNotAllowDupTime input) $ \wt2 ->
  forAll (genPsvConstants wt1) $ \psv -> testIO $ do

  -- Make sure no duplicate output names..
  let ret1 = fmap (outputName . fst) $ C.returns (wtCore wt1)
  let ret2 = fmap (outputName . fst) $ C.returns (wtCore wt2)
  let intersect = any (flip elem ret1) ret2
  case intersect of
   True -> pure discard
   False -> do
    x <- runEitherT
       $ runTest2 wt1 wt2 psv
       $ TestOpts ShowInputOnError ShowOutputOnError S.PsvInputSparse S.DoNotAllowDupTime
    case x of
      Left err -> failWithError wt1 err
      Right () -> pure (property succeeded)


compileTest2 :: WellTyped -> WellTyped -> TestOpts -> EitherT SeaError IO (SeaFleet S.PsvState)
compileTest2 wt1 wt2 (TestOpts _ _ inputFormat allowDupTime) = do
  options0 <- S.getCompilerOptions

  let optionsAssert = ["-DICICLE_ASSERT=1", "-DICICLE_ASSERT_MAXIMUM_ARRAY_COUNT=" <> T.pack (show (100 * (length $ wtFacts wt1))) ]
      options  = options0 <> ["-O0", "-DICICLE_NOINLINE=1"] <> optionsAssert
      programs = Map.singleton (wtInputId wt1) (wtAvalancheFlat wt1 :| [wtAvalancheFlat wt2])
      iconfig  = S.PsvInputConfig
                (S.Snapshot (wtTime wt1))
                 inputFormat
      oconfig  = S.PsvOutputConfig
                (S.Snapshot (wtTime wt1))
                (S.PsvOutputSparse)
                (S.defaultOutputMissing)
      conf     = S.PsvConfig iconfig oconfig
      iformat  = S.FormatPsv conf
      iopts    = S.InputOpts allowDupTime (Map.singleton (wtInputId wt1) (Set.singleton tombstone))
      attrs    = [wtInputId wt1]
      -- psv now uses piano, so we need this trick for testing.
      piano = T.concat
        [ "int64_t piano_max_count (piano_t *piano) {"
        , "    return 1;"
        , "}"
        , ""
        , "error_t piano_lookup (piano_t *piano, const uint8_t *needle_id, size_t needle_id_size, int64_t *out_count, const int64_t **out_label_times, const int64_t **out_label_name_offsets, const int64_t **out_label_name_lengths, const uint8_t **out_label_name_data) {"
        , "    return 0;"
        , "}"
        ]

  let input = HasInput iformat iopts "dummy_path"
  code <- hoistEither (S.codeOfPrograms input attrs (Map.toList programs))
  S.seaCreateFleet options (S.fromCacheSea S.NoCacheSea) input Nothing (code <> piano)

runTest2 :: WellTyped -> WellTyped -> S.PsvConstants -> TestOpts -> EitherT S.SeaError IO ()
runTest2 wt1 wt2 consts testOpts = do
  let compile  = compileTest2 wt1 wt2 testOpts
      release  = S.seaRelease
      expect_values1 = Map.fromList $ evalWellTyped wt1
      expect_values2 = Map.fromList $ evalWellTyped wt1 { wtCore = wtCore wt2 }
      expect   
       | length (wtFacts wt1) <= S.psvFactsLimit consts
       = textOfOutputs (wtEntities wt1) (Map.toList $ Map.union expect_values1 expect_values2)
       | otherwise
       = ""

  bracketEitherT' compile (hoist liftIO . release) $ \fleet -> hoist liftIO $ do

  let install  = liftIO (S.sfSegvInstall fleet (show consts <> "\n" <> show wt1 <> "\n" <> show wt2))
      remove _ = liftIO (S.sfSegvRemove  fleet)
  bracketEitherT' install remove  $ \() -> do

  withSystemTempDirectory "psv-test-" $ \dir -> do
    let source  = J.libSource (S.sfLibrary fleet)
        program = dir <> "/program.c"
        input   = dir <> "/input.psv"
        output  = dir <> "/output.psv"
        dropped = dir <> "/dropped.txt"
        chords  = Nothing

    liftIO (LT.writeFile program (LT.fromStrict source))

    let inputPsv = textOfFacts (wtEntities wt1) (inputName $ wtInputId wt1) (wtFacts wt1)
    liftIO (L.writeFile input (LT.encodeUtf8 inputPsv))

    result <- liftIO (runEitherT (S.seaPsvSnapshotFilePath fleet input output dropped chords S.FlagUseDropFile consts))

    case result of
      Left err -> do
        left err
      Right _ -> do
        outputPsv <- liftIO $ LT.readFile output
        when (outputPsv /= expect) $ do
          Savage.error ("Expected:\n" <> LT.unpack expect <> "\nGot:\n" <> LT.unpack outputPsv)

        pure ()


return []
tests :: IO Bool
tests = $checkAllWith TestRunNormal (checkArgsSized 10)
