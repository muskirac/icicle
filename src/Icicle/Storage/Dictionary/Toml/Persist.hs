{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TupleSections     #-}
{-# LANGUAGE PatternGuards     #-}
module Icicle.Storage.Dictionary.Toml.Persist (
    normalisedTomlDictionary
  , normalisedDictionaryImports
  , normalisedTomlDictionaryEntry
  ) where

import qualified Data.Text as T

import           Icicle.Data
import           Icicle.Dictionary.Data
import           Icicle.Storage.Encoding

import           Icicle.Internal.Pretty hiding ((</>))

import           P hiding (empty)
import qualified Data.Map                           as Map

normalisedDictionaryImports :: Dictionary -> Doc
normalisedDictionaryImports dict
 = "# Autogenerated Imports File -- Do Not Edit"
 <> line
 <> (vcat $ fmap pprFun $ Map.toList $ dictionaryFunctions dict)

 where
  pprFun (f,(_,fun))
   = padDoc 20 (pretty f <+> pretty fun <> ".")

normalisedTomlDictionary :: Dictionary -> Doc
normalisedTomlDictionary dictionary
  =  "# Autogenerated Dictionary File -- Do Not Edit"
  <> line
  <> "imports" <+> "=" <+> dquotes "imports.icicle"
  <> line
  <> "version" <+> "=" <+> "1"
  <> line
  <> vcat (normalisedTomlDictionaryEntry <$> dictionaryEntries dictionary)

normalisedTomlDictionaryEntry :: DictionaryEntry -> Doc
normalisedTomlDictionaryEntry (DictionaryEntry attr (ConcreteDefinition enc ts)) =
  brackets ("fact." <> (text $ T.unpack $ getAttribute attr))
  <> line
  <> indent 2 ("encoding" <+> "=" <+> tquotes (text $ T.unpack $ prettyConcrete enc))
  <> line
  <> indent 2 ("namespace" <+> "=" <+> tquotes "default")
  <> line
  <> tombstoneDoc
    where
      tombstoneDoc | t:[] <- toList ts
                   = indent 2 ("tombstone" <+> "=" <+> tquotes (text $ T.unpack $ t))
                   | otherwise
                   = empty

normalisedTomlDictionaryEntry (DictionaryEntry attr (VirtualDefinition virtual)) =
  brackets ("feature." <> (text $ T.unpack $ getAttribute attr))
  <> line
  <> indent 2  "expression" <+> "=" <+> tquotes (pretty virtual)

tquotes :: Doc -> Doc
tquotes = dquotes . dquotes . dquotes
