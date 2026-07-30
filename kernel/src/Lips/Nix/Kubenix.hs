{-# LANGUAGE OverloadedStrings #-}

-- | The kubenix-specific shell layer: turn kubenix's @optionsJSON@ into the
-- kernel's 'OptionSchema'. The document is produced by the same
-- @nixosOptionsDoc@ the other two worlds use, so its type wordings are nixpkgs
-- wordings and 'Lips.Nix.Options.parseNixOptionsJson' reads it verbatim; what
-- kubenix needs on top is three reshapings, and all three are knowledge about
-- kubenix, so they live here and the kernel stays blind.
--
--   1. RE-KEY. kubenix's typed resource tree is declared at
--      @kubernetes.api.resources.\<kind\>.\<name\>.…@, while the path every
--      published kubenix module (and so every lips engine) writes is the alias
--      @kubernetes.resources.…@. The alias is moved onto, not copied beside,
--      the typed tree: one spelling grounds, and a rule that emits the
--      @api.resources@ form fails loud naming the alias.
--   2. DROP INNER NODES. 'Lips.Kernel.OptionType.checkEmits' accepts any path
--      that descends into a declared option, because a target's free-form
--      regions cannot enumerate their children. kubenix declares its inner
--      nodes (@kubernetes.resources@ itself is @attribute set of (attribute
--      set)@, each kind is @attribute set of (submodule)@), so keeping them
--      would make every misspelled field admissible and grounding would
--      silently become path-blind. Only maximal paths survive; a genuinely
--      free-form LEAF (a label map, a ConfigMap's data) still admits any key
--      below it, which is correct.
--   3. UNWRAP OPTIONALS. Almost every Kubernetes field is declared
--      @null or \<type\>@. Unwrapping it before classification is what keeps a
--      scalar field type-checked instead of degrading to 'OTOther'. The
--      original wording is kept whenever the unwrapped type is still
--      unmodelled, because that text is what a refusal shows a human.
module Lips.Nix.Kubenix
  ( parseKubenixOptionsJson
  ) where

import           Data.ByteString.Lazy (ByteString)
import qualified Data.List            as List
import           Data.Map.Strict      (Map)
import qualified Data.Map.Strict      as Map
import qualified Data.Set             as Set
import           Data.Text            (Text)
import qualified Data.Text            as T

import Lips.Kernel.OptionType (OptionSchema, OptionType (..))
import Lips.Nix.Options       (classifyNixType, parseNixOptionsJson)

-- | Parse kubenix's @optionsJSON@ into the schema lips grounds against.
parseKubenixOptionsJson :: ByteString -> Either Text OptionSchema
parseKubenixOptionsJson = fmap reshape . parseNixOptionsJson

reshape :: OptionSchema -> OptionSchema
reshape = Map.map unwrapOptional . dropInnerNodes . Map.mapKeys aliasKey

-- | Move a typed resource path onto the alias path programs write. Only the
-- prefix changes; the wildcarded instance name and the field tail are untouched.
aliasKey :: [Text] -> [Text]
aliasKey p = case p of
  ("kubernetes" : "api" : "resources" : rest) -> "kubernetes" : "resources" : rest
  _                                           -> p

-- | Keep only paths that no other kept path extends. An inner node is a
-- declared option, and a declared option makes every path below it admissible;
-- see the note on 'reshape'.
dropInnerNodes :: Map [Text] a -> Map [Text] a
dropInnerNodes m = Map.filterWithKey (\k _ -> not (Set.member k inner)) m
  where
    keys = Map.keys m
    -- Keys come out sorted, and the smallest paths greater than k are exactly
    -- its extensions, so k is an inner node iff its immediate successor extends
    -- it. One pairwise scan decides every key (the schema has tens of thousands).
    inner = Set.fromList
      [ k | (k, next) <- zip keys (drop 1 keys), k `List.isPrefixOf` next ]

-- | @null or X@ is how kubenix spells an optional Kubernetes field. Classify
-- the wrapped type instead, unless it too is unmodelled -- then the original
-- wording is more useful, since a refusal quotes it.
unwrapOptional :: OptionType -> OptionType
unwrapOptional (OTOther raw)
  | Just inner <- T.stripPrefix "null or " (T.strip raw)
  , t <- classifyNixType (unparen inner)
  , t /= OTOther (unparen inner)
  = t
  where
    unparen s
      | "(" `T.isPrefixOf` s, ")" `T.isSuffixOf` s = T.dropEnd 1 (T.drop 1 s)
      | otherwise                                  = s
unwrapOptional t = t
