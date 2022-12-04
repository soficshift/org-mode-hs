{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE TypeFamilies #-}

module Org.Exporters.Pandoc where

import Control.Exception (throw)
import Ondim.Extra.Loading (TemplateLoadingError (..))
import Ondim.Pandoc hiding (stringify)
import Ondim.Pandoc qualified
import Org.Exporters.Common
import Org.Types (OrgDocument)
import System.FilePath
import Text.Pandoc (def, readerExtensions, renderError, runPure)
import Text.Pandoc.Builder qualified as B
import Text.Pandoc.Definition qualified as P
import Text.Pandoc.Extensions (pandocExtensions)
import Text.Pandoc.Readers.Markdown (readMarkdown)
import Org.Exporters.Processing.OrgData

type PandocBackend m = ExportBackend PandocTag m P.Inline P.Block

defPandocBackend :: Monad m => PandocBackend m
defPandocBackend =
  let nullObj = P.Str ""
      plain = toList . B.text
      softbreak = [P.SoftBreak]
      exportSnippet l = one . P.RawInline (P.Format l)
      nullEl = P.Null
      affiliatedEnv _ = id
      rawBlock l = one . P.RawBlock (P.Format l)
      srcPretty _ _ _ = pure Nothing
      mergeLists = (foldr go [] <$>)
        where
          go :: P.Block -> [P.Block] -> [P.Block]
          go (P.BulletList x) (P.BulletList y : r) = P.BulletList (x ++ y) : r
          go (P.OrderedList a x) (P.OrderedList b y : r) | a == b = P.OrderedList a (x ++ y) : r
          go (P.DefinitionList x) (P.DefinitionList y : r) = P.DefinitionList (x ++ y) : r
          go x y = x : y
      plainObjsToEls = one . P.Plain
      srcExpansionType = "md"
      srcExpansion src = do
        fromMaybe (pure []) do
          P.Pandoc _ parsed <-
            rightToMaybe $
              runPure $
                readMarkdown
                  def {readerExtensions = pandocExtensions}
                  src
          pure $ liftNodes parsed
      inlBabelCall _ = pure []
      macro key _ = callExpansion key nullObj
      stringify = Ondim.Pandoc.stringify
   in ExportBackend {..}

pandocTemplateDir :: IO FilePath
pandocTemplateDir = (</> "pandoc") <$> templateDir

loadPandocDoc :: FilePath -> IO P.Pandoc
loadPandocDoc dir = do
  let file = dir </> "org/document.md"
  text :: Text <- decodeUtf8 <$> readFileBS file
  let pandoc =
        runPure $
          readMarkdown def {readerExtensions = pandocExtensions} text
  case pandoc of
    Left s -> throw (TemplateLoadingException (toString $ renderError s))
    Right t -> pure t

renderDoc ::
  Monad m =>
  PandocBackend m ->
  OndimMS PandocTag m ->
  P.Pandoc ->
  OrgData ->
  OrgDocument ->
  m (Either OndimException P.Pandoc)
renderDoc bk st layout datum doc =
  liftDocument bk datum doc layout
    & bindDefaults
    & evalOndimTWith st
    & flip evalStateT initialExporterState
