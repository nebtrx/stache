-- |
-- Module      :  Text.Mustache.Compile.TH
-- Copyright   :  © 2016–2017 Stack Builders
-- License     :  BSD 3 clause
--
-- Maintainer  :  Mark Karpov <markkarpov@openmailbox.org>
-- Stability   :  experimental
-- Portability :  portable
--
-- Template Haskell helpers to compile Mustache templates at compile time.
-- This module is not imported as part of "Text.Mustache", so you need to
-- import it yourself. Qualified import is recommended, but not necessary.
--
-- At the moment, functions in this module only work with GHC 8 (they
-- require at least @template-haskell-2.11@).

{-# LANGUAGE CPP               #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RankNTypes        #-}
{-# LANGUAGE TemplateHaskell   #-}

module Text.Mustache.Compile.TH
  ( compileMustacheDir
  , compileMustacheFile
  , compileMustacheText
  , mustache )
where

import Control.Exception (Exception(..))
import Control.Monad.Catch (try)
import Data.Text.Lazy (Text)
import Data.Typeable (cast)
import Language.Haskell.TH hiding (Dec)
import Language.Haskell.TH.Quote (QuasiQuoter (..))
import Language.Haskell.TH.Syntax (lift)
import Text.Mustache.Type
import qualified Data.Text             as T
import qualified Data.Text.Lazy        as TL
import qualified Text.Mustache.Compile as C

#if !MIN_VERSION_base(4,8,0)
import Control.Applicative
#endif

#if MIN_VERSION_template_haskell(2,11,0)
import Language.Haskell.TH.Syntax (dataToExpQ)
#else
import Data.Data (Data)
dataToExpQ :: Data a => (forall b. Data b => b -> Maybe (Q Exp)) -> a -> Q Exp
dataToExpQ _ _ = fail "The feature requires at least GHC 8 to work"
#endif

-- | Compile all templates in specified directory and select one. Template
-- files should have extension @mustache@, (e.g. @foo.mustache@) to be
-- recognized. This function /does not/ scan the directory recursively.
--
-- This version compiles the templates at compile time.

compileMustacheDir
  :: PName             -- ^ Which template to select after compiling
  -> FilePath          -- ^ Directory with templates
  -> Q Exp             -- ^ The resulting template
compileMustacheDir pname path =
  (runIO . try) (C.compileMustacheDir pname path) >>= handleEither

-- | Compile single Mustache template and select it.
--
-- This version compiles the template at compile time.

compileMustacheFile
  :: FilePath          -- ^ Location of the file
  -> Q Exp
compileMustacheFile path =
  (runIO . try) (C.compileMustacheFile path) >>= handleEither

-- | Compile Mustache template from 'Text' value. The cache will contain
-- only this template named according to given 'Key'.
--
-- This version compiles the template at compile time.

compileMustacheText
  :: PName             -- ^ How to name the template?
  -> Text              -- ^ The template to compile
  -> Q Exp
compileMustacheText pname text =
  (handleEither . either (Left . MustacheParserException) Right)
  (C.compileMustacheText pname text)

-- | Compile Mustache using QuasiQuoter. Usage:
--
-- > {-# LANGUAGE QuasiQuotes #-}
-- > import Text.Mustache.Compile.TH (mustache)
-- >
-- > foo :: Template
-- > foo = [mustache|This is my inline {{ template }}.|]
--
-- Name of created partial is set to @"quasi-quoted"@. You can extend cache
-- of 'Template' created this way using 'mappend' and so work with partials
-- as usual.
--
-- @since 0.1.7

mustache :: QuasiQuoter
mustache = QuasiQuoter
  { quoteExp  = compileMustacheText "quasi-quoted" . TL.pack
  , quotePat  = undefined
  , quoteType = undefined
  , quoteDec  = undefined }

-- | Given an 'Either' result return 'Right' and signal pretty-printed error
-- if we have a 'Left'.

handleEither :: Either MustacheException Template -> Q Exp
handleEither val =
  case val of
    Left err -> fail . indentNicely $
#if MIN_VERSION_base(4,8,0)
      displayException err
#else
      show err
#endif
    Right template -> dataToExpQ (fmap liftText . cast) template
  where
    -- NOTE Since the feature requires GHC 8 anyway, we follow indentation
    -- style of that version of compiler. This makes it look consistent with
    -- other error messages and allows Emacs and similar tools to parse the
    -- errors correctly.
    indentNicely x' =
      case lines x' of
        []     -> ""
        (x:xs) -> unlines (x : fmap (replicate 8 ' ' ++) xs)

-- | Lift strict 'T.Text' to 'Q' 'Exp'.

liftText :: T.Text -> Q Exp
liftText txt = AppE (VarE 'T.pack) <$> lift (T.unpack txt)
