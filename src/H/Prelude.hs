-- |
-- Copyright: (C) 2013 Amgen, Inc.
{-# Language ViewPatterns #-}
{-# Language GADTs #-}
module H.Prelude
  ( module Data.IORef
  , module Foreign
  , module H.HVal
  , module Language.R.Interpreter
  , print
  -- * Evaluation constructs
  , module H.Prelude.Eval
  -- * Language.R functions
  , module H.Prelude.Reexports
  -- * Globals
  , module H.Prelude.Globals
  ) where

import           H.HVal
import qualified Foreign.R as R

import           Foreign hiding ( unsafePerformIO, void )

-- Reexported modules.
import           H.Prelude.Reexports
import           H.Prelude.Eval
import           H.Prelude.Globals
import Data.IORef
import Language.R.Interpreter

import Prelude hiding (print)

print :: R.SEXP a -> IO ()
print = R.printValue
