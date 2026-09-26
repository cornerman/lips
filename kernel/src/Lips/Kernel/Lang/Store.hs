{-# LANGUAGE OverloadedStrings #-}

-- | The stored form of a minted engine: the @.lang@ file (spec v2, section 5;
-- crystallization + engine-synthesis plans). One file carries the whole
-- engine, in the same canonical decision text as everything else, so
-- regeneration is atomic and the halves cannot drift:
--
-- > lang.pattern.<id>   front half: loose line -> decision
-- > engine.rule.<id>    back half:  decision -> ground option assignments
-- > engine.demand.<id>  back half:  required subject + question
--
-- Pattern sub-grammar inside the assertion:
--
-- > <template>  =>  <kind> <subject> "<assertion>" ; <kind> <subject> "<assertion>" ...
--
-- A pattern emits one decision per @ ; @-separated clause (mirroring the rule
-- back half), so one dense loose line can state several facts. A single emit
-- renders with no @ ; @, identical to the pre-multi-emit form, so older engines
-- still read.
--
-- Holes are written @\<name\>@ in the template, subject, and assertion. A hole
-- used in the subject or assertion must be bound by the template; that is
-- checked on read, so 'applyPattern' is total. Rule and demand sub-grammars
-- live in 'Lips.Kernel.Engine.Data'. The engine round-trips:
-- @readLang . renderLang == Right@.
module Lips.Kernel.Lang.Store
  ( EngineData (..)
  , renderLang
  , readLang
  , patternToDecision
  , decisionToPattern
  , parsePatternBody
  , parseTplTok
  , renderTplTok
  ) where

import           Data.Char  (isSpace)
import           Data.List  (sortOn)
import           Data.Maybe (isJust)
import qualified Data.Map.Strict as Map
import           Data.Text  (Text)
import qualified Data.Text  as T

import Lips.Kernel.Engine.Data     (DemandSpec (..), IgnoreSpec (..), MapRule (..), MergeSpec (..),
                             parseDemandBody, parseIgnoreBody, parseMergeBody, parseRuleBody,
                             renderDemandBody, renderIgnoreBody, renderMergeBody, renderRuleBody)
import Lips.Kernel.Engine.Value    (parseHoleType)
import Lips.Kernel.Surface  (breakFirstOutsideQuotes, breakLastOutsideQuotes, naturalKey,
                             quoteText, splitOutsideQuotes)
import qualified Lips.Kernel.Surface as Q
import Lips.Kernel.Base     (fromList)
import Lips.Kernel.Decision
import Lips.Kernel.Reader   (ParseError (..), commentOrBlank, readDecision, renderBase)
import Lips.Kernel.Lang.Nest    (NestError (..), checkNesting, renderNestError)
import Lips.Kernel.Lang.Pattern

-- | A whole minted engine: the language (front half) and the semantics (back
-- half), as read from one @.lang@ file.
data EngineData = EngineData
  { edPatterns :: [Pattern]
  , edRules    :: [MapRule]
  , edDemands  :: [DemandSpec]
  , edMerges   :: [MergeSpec]
    -- ^ per-option aggregation choice (set or list); empty means every list
    -- option is a set, the default reading.
  , edIgnores  :: [IgnoreSpec]
    -- ^ the facts THIS world cannot place, each with the reason. Empty for a
    -- language whose every world lowers everything, which is every engine
    -- written before the declaration existed.
  }
  deriving (Eq, Show)

-- | Render an engine to canonical @.lang@ text, each group ordered by id.
-- Every line carries the given provenance -- for minted engines the
-- generation-event stamp ('FromGeneration'), so each engine decision names
-- the pinned event that produced it.
renderLang :: Provenance -> EngineData -> Text
renderLang prov ed =
  renderBase . fromList . map stamp $
    map patternToDecision (sortOn (naturalKey . pId) (edPatterns ed))
      ++ map ruleToDecision (sortOn (naturalKey . mrId) (edRules ed))
      ++ map demandToDecision (sortOn (naturalKey . dsId) (edDemands ed))
      ++ map mergeToDecision (sortOn (naturalKey . mgId) (edMerges ed))
      ++ map ignoreToDecision (sortOn (naturalKey . igId) (edIgnores ed))
  where
    stamp d = d { dProv = prov }

-- | One classified engine line: which group a @.lang@ decision belongs to.
data EngLine = ELPat Pattern | ELRule MapRule | ELDem DemandSpec | ELMerge MergeSpec
             | ELIgnore IgnoreSpec

-- | Read an engine from @.lang@ text in one line-aware pass, so every error
-- (envelope or body sub-grammar) names its real source line, not line 0.
-- Every non-blank, non-comment line must be a recognized engine decision
-- (@lang.pattern.*@, @engine.rule.*@, @engine.demand.*@); anything else fails
-- loud rather than being silently dropped -- a corrupted or mistyped @.lang@
-- must not lose a rule quietly (deduce-or-fail).
readLang :: Text -> Either [ParseError] EngineData
readLang src =
  let cands   = [ (n, t) | (n, l) <- zip [1 ..] (T.lines src)
                         , let t = T.strip l, not (skip t) ]
      results = [ fmap ((,) n) (readEngineLine n t) | (n, t) <- cands ]
      errs    = [ e | Left e <- results ]
      oks     = [ x | Right x <- results ]
      pats    = sortOn (naturalKey . pId) [p | (_, ELPat p) <- oks]
      patLine = Map.fromList [(pId p, n) | (n, ELPat p) <- oks]
      -- Nesting is a whole-engine property (a child's holes may be bound by an
      -- ancestor, which one pattern's parse cannot see), so it is judged here,
      -- at the ONE door every verb reads a .lang through. Each error is anchored
      -- to the offending pattern's own line, so the report points where the fix
      -- goes.
      nestErrs = [ ParseError (Map.findWithDefault 0 (nestSubject e) patLine)
                              (renderNestError e)
                 | e <- checkNesting pats ]
   in if null errs && null nestErrs
        then Right EngineData
               { edPatterns = pats
               , edRules    = sortOn (naturalKey . mrId) [r | (_, ELRule r) <- oks]
               , edDemands  = sortOn (naturalKey . dsId) [q | (_, ELDem q)  <- oks]
               , edMerges   = sortOn (naturalKey . mgId) [m | (_, ELMerge m) <- oks]
               , edIgnores  = sortOn (naturalKey . igId) [i | (_, ELIgnore i) <- oks]
               }
        else Left (errs ++ nestErrs)
  where
    skip = commentOrBlank
    -- Which pattern a nesting error is about, so it lands on that line.
    nestSubject e = case e of
      UnknownParent p _  -> p
      UnboundInScope p _ -> p
      KeyWithoutBlock p  -> p
      NotAListHole p _ _ -> p
      BlockUnderItem p _ -> p
      NestCycle (p : _)  -> p
      NestCycle []       -> ""
    -- Read the decision envelope (re-stamping its line), then classify and
    -- parse the group body -- both errors anchored to the real line n.
    readEngineLine n t = do
      d <- either (\pe -> Left pe { peLine = n }) Right (readDecision t)
      classify n d

classify :: Int -> Decision -> Either ParseError EngLine
classify n d = case dSubject d of
  -- A nested pattern names its parents in the path, in the order they are
  -- tried: lang.pattern.p3.under.p2, or lang.pattern.n1.under.n1.under.n0.
  Subject ("lang" : "pattern" : i : rest)
    | Just tok <- idTail rest -> tag ELPat (parsePatternBody (i <> tok) body)
  Subject ["engine", "rule", i]    -> tag ELRule (parseRuleBody   i body)
  Subject ["engine", "demand", i]  -> tag ELDem  (parseDemandBody i body)
  Subject ["engine", "merge", i]    -> tag ELMerge (parseMergeBody i body)
  Subject ["engine", "ignore", i]   -> tag ELIgnore (parseIgnoreBody i body)
  Subject segs -> Left (ParseError n
    ("unrecognized engine line (subject " <> T.intercalate "." segs
      <> "): a .lang carries only lang.pattern.*, engine.rule.*, engine.demand.*,"
      <> " engine.merge.*, engine.ignore.*"))
  where
    body = case dAssertion d of Assertion a -> a
    tag f = either (Left . ParseError n) (Right . f)

-- | Turn a rule into its canonical @meta@ decision.
ruleToDecision :: MapRule -> Decision
ruleToDecision r = metaDecision (mrId r) ["engine", "rule", mrId r] (renderRuleBody r)

-- | Turn a merge declaration into its canonical @meta@ decision.
mergeToDecision :: MergeSpec -> Decision
mergeToDecision m = metaDecision (mgId m) ["engine", "merge", mgId m] (renderMergeBody m)

-- | Turn an ignore declaration into its canonical @meta@ decision.
ignoreToDecision :: IgnoreSpec -> Decision
ignoreToDecision i = metaDecision (igId i) ["engine", "ignore", igId i] (renderIgnoreBody i)

-- | Turn a demand into its canonical @meta@ decision.
demandToDecision :: DemandSpec -> Decision
demandToDecision q = metaDecision (dsId q) ["engine", "demand", dsId q] (renderDemandBody q)

metaDecision :: Text -> [Text] -> Text -> Decision
metaDecision i segs body =
  Decision
    { dId        = DecisionId i
    , dSubject   = Subject segs
    , dKind      = Meta
    , dAssertion = Assertion body
    , dStrength  = Stated
    , dProv      = FromSource (SourceLoc "lang" 0)
    , dRationale = Nothing
    }

-- | Turn a pattern into its canonical @meta@ decision.
patternToDecision :: Pattern -> Decision
patternToDecision p = metaDecision (pId p) ("lang" : "pattern" : idSegs) (renderBody p)
  where
    -- Segments, not one dotted segment: the canonical renderer escapes a dot
    -- INSIDE a segment, so a nested id has to be spelled as the path it is.
    idSegs = pId p : case (pItemHole p, pParents p) of
      (Just h, parent : _) -> ["each", parent, h]
      _                    -> concat [["under", q] | q <- pParents p]

-- | Parse a @lang.pattern.*@ decision back into a pattern, or explain why not.
decisionToPattern :: Decision -> Either Text Pattern
decisionToPattern d = do
  pid <- case dSubject d of
    Subject ("lang" : "pattern" : i : rest)
      | Just tok <- idTail rest -> Right (i <> tok)
    _ -> Left "not a lang.pattern subject"
  parseBody pid (unAssertion (dAssertion d))
  where
    unAssertion (Assertion a) = a

-- Body grammar: @<template> => <kind> <subject> <strength> "<assertion>"@.

-- | Parse a pattern body (the sub-grammar) given its id. Exposed so @generate@
-- can read the patterns a model mints in exactly the stored form.
parsePatternBody :: Text -> Text -> Either Text Pattern
parsePatternBody = parseBody

renderBody :: Pattern -> Text
renderBody p =
  T.unwords (map renderTplTok (pTemplate p))
    <> " => "
    <> T.intercalate " ; " (map renderEmit (pEmits p))
  where
    renderEmit e =
      kindText (peKind e)
        <> " " <> renderParts (peSubject e)
        <> " " <> quoteParts (peAssertion e)

renderTplTok :: TplTok -> Text
renderTplTok (TLit t)   = t
renderTplTok (THole h)  = "<" <> h <> ">"
renderTplTok (TMulti h) = "<" <> h <> ".words>"
renderTplTok (TList h seps) =
  "<" <> h <> ".list:" <> T.intercalate "|" (map renderSep seps) <> ">"
  where
    -- A separator is written bare when it can be, and as a quoted span when it
    -- carries a character the spelling itself uses (@|@, an angle bracket, a
    -- space, a quote). One quoting convention, the one every stored lips line
    -- already uses, so everything is expressible without a second escape.
    renderSep s
      | T.null s || T.any (`elem` ("|<>\"" :: String)) s || T.any isSpace s = quoteText s
      | otherwise = s
renderTplTok (TFused segs) = T.concat (map seg segs)
  where
    seg (FLit t)  = t
    seg (FHole h) = "<" <> h <> ">"

renderParts :: [StrPart] -> Text
renderParts = T.concat . map r
  where
    r (SLit t)  = t
    r (SHole h) = "<" <> h <> ">"

quoteParts :: [StrPart] -> Text
quoteParts = quoteText . renderParts

parseBody :: Text -> Text -> Either Text Pattern
parseBody idTok body = do
  (pid, parents, itemHole) <- parsePatternId idTok
  (tplStr, rest0) <- maybe (Left ("pattern " <> pid <> ": missing =>")) Right
                       (splitOnSeparator body)
  -- Drop empty-literal tokens (a lone terminator), symmetric with
  -- 'tokenizeLine', so a period written apart from its word never survives as a
  -- phantom token that would unbalance the match after a render/read
  -- round-trip.
  let template = filter (not . emptyLit) (map parseTplTok (stripTerminator (lexTokens tplStr)))
      emptyLit (TLit t) = T.null t
      emptyLit _        = False
  -- A multi-token hole spans whitespace, which one token cannot contain: say so
  -- rather than bind a hole literally named "x.words".
  case [h | TFused segs <- template, h <- fusedHoles segs, ".words" `T.isSuffixOf` h] of
    (h : _) -> Left ("pattern " <> pid <> ": <" <> h
                       <> "> is fused inside a token, but a multi-token hole spans whitespace")
    []      -> Right ()
  -- A list hole binds a run of tokens, so it cannot share one token with text:
  -- read as a fused hole it would silently stop being a list. The line's own
  -- text needs no template token either way, since a separator the line writes
  -- against its last item ("x", print) is cut there like any other.
  case [ (h, lit) | TFused segs <- template, FHole h <- segs, Just _ <- [listSpelling h]
                  , let lit = T.concat [t | FLit t <- segs] ] of
    ((h, lit) : _) -> Left ("pattern " <> pid <> ": <" <> h <> "> is fused to \"" <> lit
                             <> "\" inside one token, but a list hole binds a run of tokens:"
                             <> " write <" <> h <> "> as a token of its own; a separator the"
                             <> " line writes against its last item is cut as one already")
    []             -> Right ()
  -- A list with no separator cannot be cut, and a run that is not cut is what
  -- <x.words> already is: say which form is meant rather than match nothing.
  case [h | TList h seps <- template, all T.null seps] of
    (h : _) -> Left ("pattern " <> pid <> ": <" <> h
                       <> ".list:> declares no separator; an uncut run is <" <> h <> ".words>")
    []      -> Right ()
  emits <- mapM (parseEmit pid . T.strip) (splitOutsideQuotes " ; " rest0)
  let p = Pattern { pId = pid, pParents = parents, pItemHole = itemHole
                  , pTemplate = template, pEmits = emits }
  -- Every hole in the target must be bound, so 'applyPattern' is total. A
  -- top-level pattern binds only through its own template, and is judged here.
  -- A NESTED one also sees its ancestors' captures, which one pattern's parse
  -- cannot know, so its holes are judged where every pattern is in hand:
  -- 'Lips.Kernel.Lang.Nest.checkNesting', run by 'readLang' -- the one door.
  let structs = map fst (structHoles p)
      bound   = holesOf p ++ structs
      used    = map refName
        (concat [ [h | SHole h <- peSubject e] ++ [h | SHole h <- peAssertion e] | e <- emits ])
      loose   = filter (`notElem` bound) used
      -- A structure-bound hole is filled by the kernel, a template hole by a
      -- program word: one name cannot mean both, and the collision would
      -- silently pick one.
      clash   = filter (`elem` holesOf p) structs
  -- Two lists in one emit would have to be read as a cross product, and which
  -- item pairs with which is not stated anywhere: one list per emit, and a
  -- second list in the same sentence gets its own emit.
  case [ e | e <- emits
           , let hs = [h | (h, _) <- listHoles p
                         , h `elem` map refName [r | SHole r <- peSubject e ++ peAssertion e]]
           , length hs > 1 ] of
    (e : _) -> Left ("pattern " <> pid <> ": emit " <> renderParts (peSubject e)
                       <> " mentions two list holes, but an emit repeats over one list")
    []      -> Right ()
  if not (null clash)
    then Left ("pattern " <> pid <> ": <" <> T.intercalate ">, <" clash
                 <> "> is bound by the template, so it cannot also be a structure hole")
    else if null loose || not (null parents)
      then Right p
      else Left ("pattern " <> pid <> ": target holes not bound by template: " <> T.intercalate "," loose)
  where
    -- Emit grammar is <kind> <subject> "<assertion>": no strength token. A
    -- pattern reads a program line the human wrote, so 'applyPattern' fixes the
    -- emitted decision to 'Stated'; there is nothing for the mint to choose or
    -- forget here.
    parseEmit pid t = do
      (kindTok, r1) <- firstToken t ("pattern " <> pid <> ": missing kind")
      (subjTok, r2) <- firstToken r1 ("pattern " <> pid <> ": missing subject")
      kind <- maybe (Left ("pattern " <> pid <> ": unknown kind " <> kindTok)) Right (lookup kindTok kindTable)
      assn <- parseQuoted (T.stripStart r2)
      Right (PatEmit kind (parseHoley subjTok) (parseHoley assn))

-- The pattern body is @<template> => <decision>@, but a template may itself
-- contain @=>@ (route arrows, lambdas and mappings are common domain syntax).
-- The decision grammar (@<kind> <subject> <strength> "<assertion>"@) never
-- contains @ => @ outside its quoted assertion, so the meta-separator is always
-- the LAST @ => @ lying outside quotes. Splitting there lets a template use
-- @=>@ freely: the kernel's own delimiter must not forbid a surface form.
splitOnSeparator :: Text -> Maybe (Text, Text)
splitOnSeparator = breakLastOutsideQuotes " => "

parseTplTok :: Text -> TplTok
parseTplTok w
  -- A quoted span in the template: "<body>" captures a quoted value (its
  -- inner text, spaces and all); a fixed "literal" matches a quoted token.
  -- Symmetric with 'tokenizeLine', which lexes a quoted line value as one
  -- token, so the two line up.
  | Just inner <- unquote w =
      maybe (TLit (T.toLower inner)) THole (holeName inner)
  -- A symbol inside the template is a literal the program line must carry, so
  -- nothing is stripped here; 'stripTerminator' already shed the template's own
  -- final terminator, which is why a minted "<when>." ending a template is the
  -- hole <when> (live mints glue the line's final period onto the hole).
  | Just h0 <- holeName w =
      case listSpelling h0 of
        Just (name, seps) -> TList name seps
        Nothing ->
          let h = dropHoleType h0
           in case T.stripSuffix ".words" h of
                Just name -> TMulti name
                Nothing   -> THole h
  -- A hole FUSED to literal text inside one token: a call argument, a flag
  -- value, a key=value. Recognized last, so the whole-token forms above keep
  -- their meaning.
  | segs <- fusedSegs w, any isHole segs = TFused segs
  | otherwise = TLit (normalizeToken w)
  where
    isHole (FHole _) = True
    isHole (FLit _)  = False

-- | Split a template token into its literal pieces and its holes. Literal
-- pieces are lowercased, matching how a whole-token literal is stored, so the
-- comparison is case-insensitive on both sides.
fusedSegs :: Text -> [FusedSeg]
fusedSegs t
  | T.null t = []
  | otherwise = case T.breakOn "<" t of
      (before, rest)
        | T.null rest -> [FLit (T.toLower before)]
        | otherwise ->
            let (body, afterClose) = T.breakOn ">" (T.drop 1 rest)
             in if T.null afterClose || T.null body
                  -- An unclosed "<" is ordinary text (a shell redirect, a
                  -- comparison), not a broken hole.
                  then [FLit (T.toLower t)]
                  else lit before ++ [FHole (dropHoleType body)]
                         ++ fusedSegs (T.drop 1 afterClose)
  where
    lit b = [FLit (T.toLower b) | not (T.null b)]

-- | Read a hole body as a LIST hole: @p.list:,|or@ is the hole @p@, cut into
-- items on @,@ and on @or@. The separators are a @|@-separated list, each item
-- a bare word or a @"..."@ span with the standard escapes of
-- 'Lips.Kernel.Surface', so a language may list on a pipe (@\<x.list:"|">@) or
-- on an angle bracket without a second escaping scheme.
listSpelling :: Text -> Maybe (Text, [Text])
listSpelling body = case breakFirstOutsideQuotes ".list:" body of
  Just (name, rest) | not (T.null name) -> Just (name, map sep (splitOutsideQuotes "|" rest))
  _ -> Nothing
  where
    -- A quoted separator hands over its inner text; anything else is itself.
    sep s = case Q.parseQuoted (T.strip s) of
      Right (inner, "") -> inner
      _                 -> s

-- | Drop a redundant @:type@ from a TEMPLATE hole name. A template hole binds a
-- token of program TEXT, so a type annotation carries no information there, and
-- rejecting @\<days:int\>@ would reject a form mints write naturally (two
-- independent models wrote it, for a path and for a count). Degraded to the
-- plain hole, exactly as 'Lips.Kernel.Engine.Value.stringHoleName' degrades the
-- same annotation inside a string; a genuine option-type mismatch is still
-- caught by option grounding. Only a RECOGNIZED type is dropped, so a colon
-- that is part of a name is left alone rather than silently mangled.
dropHoleType :: Text -> Text
dropHoleType h = case T.breakOn ":" h of
  (base, ty) | not (T.null ty), Just _ <- parseHoleType (T.drop 1 ty) -> base
  _ -> h

-- | Parse a holey string (literal text with @\<name\>@ holes) into parts.
parseHoley :: Text -> [StrPart]
parseHoley t
  | T.null t = []
  | otherwise =
      case T.breakOn "<" t of
        (before, rest)
          | T.null rest -> [SLit before | not (T.null before)]
          | otherwise ->
              let (holeBody, afterClose) = T.breakOn ">" (T.drop 1 rest)
               in if T.null afterClose
                    then [SLit t] -- unterminated hole: treat literally, stays visible
                    else [SLit before | not (T.null before)]
                           ++ [SHole holeBody]
                           ++ parseHoley (T.drop 1 afterClose)

-- | A token that is ONE hole and nothing else: @\<name>@. The body may hold no
-- angle bracket, otherwise a token carrying several holes glued by literal text
-- (@\<fname>(\<param>@, a call signature) would read as the single absurd hole
-- named @fname>(\<param@ -- swallowing both real holes and leaving the emit's
-- references unbound. Rejecting it here sends the token on to 'fusedSegs',
-- which is the form that actually describes it.
holeName :: Text -> Maybe Text
holeName w = do
  b <- T.stripPrefix "<" w
  n <- T.stripSuffix ">" b
  -- Outside quotes, because a list hole may declare an angle bracket as its
  -- separator (@\<z.list:">">@): a quoted span is content, here as everywhere
  -- else a lips line is read.
  if any (\c -> isJust (breakFirstOutsideQuotes c n)) ["<", ">"] then Nothing else Just n

firstToken :: Text -> Text -> Either Text (Text, Text)
firstToken t err =
  case T.words t of
    []      -> Left err
    (w : _) -> Right (w, T.drop (T.length w) (T.stripStart t))

parseQuoted :: Text -> Either Text Text
parseQuoted = fmap fst . Q.parseQuoted


-- | Read a pattern subject's tail as its parent chain: @["under","p2"]@ is one
-- parent, @["under","n1","under","n0"]@ two tried in order, @[]@ none. Anything
-- else is not a pattern subject at all.
underChain :: [Text] -> Maybe [Text]
underChain []                    = Just []
underChain ("under" : q : rest)  = (q :) <$> underChain rest
underChain _                     = Nothing

-- | Rebuild the id TOKEN's tail from a pattern subject's tail: @\"\"@ for a
-- top-level pattern, @.under.p2@ (repeatable) for a block child, @.each.p9.e@
-- for an ITEM child. One inverse for both nesting forms, so the stored subject
-- path and the minted id token cannot drift.
idTail :: [Text] -> Maybe Text
idTail ["each", q, h] = Just (".each." <> q <> "." <> h)
idTail rest = case underChain rest of
  Just parents -> Just (T.concat [".under." <> q | q <- parents])
  Nothing      -> Nothing
