{-# LANGUAGE OverloadedStrings #-}

module Mud.Threads.Receive (threadReceive) where

import Mud.Data.State.MsgQueue
import Mud.Data.State.MudData
import Mud.Data.State.Util.Output
import Mud.Threads.Misc
import Mud.TopLvlDefs.Chars
import Mud.Util.Misc
import Mud.Util.Text
import qualified Mud.Misc.Logging as L (logPla)

import Control.Exception.Lifted (catch)
import Control.Monad.IO.Class (liftIO)
import Data.Monoid ((<>))
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as T (hGetLine)
import System.IO (Handle, hIsEOF)


logPla :: Text -> Id -> Text -> MudStack ()
logPla = L.logPla "Mud.Threads.Receive"


-- ==================================================


threadReceive :: Handle -> Id -> MsgQueue -> MudStack ()
threadReceive h i mq = sequence_ [ setThreadType . Receive $ i, loop `catch` plaThreadExHandler ("receive " <> showText i) i ]
  where
    loop = mIf (liftIO . hIsEOF $ h)
               (sequence_ [ logPla "threadReceive loop" i "connection dropped.", writeMsg mq Dropped ])
               (sequence_ [ writeMsg mq . FromClient . remDelimiters =<< liftIO (T.hGetLine h), loop ])
    remDelimiters = T.foldr helper ""
    helper c acc  | T.singleton c `notInfixOf` delimiters = c `T.cons` acc
                  | otherwise                             = acc
    delimiters    = T.pack [ stdDesigDelimiter, nonStdDesigDelimiter, desigDelimiter ]
