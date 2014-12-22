{-# OPTIONS_GHC -funbox-strict-fields -Wall -Werror #-}
{-# LANGUAGE FlexibleContexts, LambdaCase, OverloadedStrings, RankNTypes, ViewPatterns #-}

module Mud.Logging ( closeLogs
                   , closePlaLog
                   , initLogging
                   , initPlaLog
                   , logAndDispIOEx
                   , logError
                   , logExMsg
                   , logIOEx
                   , logIOExRethrow
                   , logNotice
                   , logPla
                   , logPlaExec
                   , logPlaExecArgs
                   , logPlaOut
                   , massLogPla
                   , rotatePlaLog ) where

import Mud.Data.Misc
import Mud.Data.State.State
import Mud.Data.State.Util
import Mud.TopLvlDefs
import Mud.Util

import Control.Applicative ((<$>), (<*>))
import Control.Concurrent.Async (async, wait)
import Control.Concurrent.STM.TQueue (newTQueueIO, readTQueue, writeTQueue)
import Control.Exception (IOException, SomeException)
import Control.Exception.Lifted (catch, throwIO)
import Control.Lens (at)
import Control.Lens.Getter (view)
import Control.Lens.Operators ((&), (.=), (?~))
import Control.Monad (forM_)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.STM (atomically)
import Control.Monad.State (gets)
import Data.Maybe (fromJust)
import Data.Monoid ((<>))
import Data.Time (getZonedTime)
import System.Directory (doesFileExist, renameFile)
import System.Log (Priority(..))
import System.Log.Formatter (simpleLogFormatter)
import System.Log.Handler (close, setFormatter)
import System.Log.Handler.Simple (fileHandler)
import System.Log.Logger (errorM, infoM, noticeM, removeAllHandlers, removeHandler, rootLoggerName, setHandlers, setLevel, updateGlobalLogger)
import System.Posix.Files (fileSize, getFileStatus)
import qualified Data.IntMap.Lazy as IM (elems, lookup)
import qualified Data.Text as T


-- ==================================================
-- Starting logs:


initLogging :: MudStack ()
initLogging = do
    liftIO . updateGlobalLogger rootLoggerName $ removeHandler
    (nq, eq) <- (,) <$> liftIO newTQueueIO <*> liftIO newTQueueIO
    (na, ea) <- (,) <$> (liftIO . spawnLogger "notice.log" NOTICE "currymud.notice" noticeM $ nq)
                    <*> (liftIO . spawnLogger "error.log"  ERROR  "currymud.error"  errorM  $ eq)
    nonWorldState.noticeLog .= Just (na, nq)
    nonWorldState.errorLog  .= Just (ea, eq)


type LogName    = T.Text
type LoggingFun = String -> String -> IO ()


spawnLogger :: FilePath -> Priority -> LogName -> LoggingFun -> LogQueue -> IO LogAsync
spawnLogger ((logDir ++) -> fn) p (T.unpack -> ln) f q = async . loop =<< initLog
  where
    initLog = fileHandler fn p >>= \gh ->
        let h = setFormatter gh . simpleLogFormatter $ "[$time $loggername] $msg"
        in updateGlobalLogger ln (setHandlers [h] . setLevel p) >> return gh
    loop gh = (atomically . readTQueue $ q) >>= \case
      LogMsg (T.unpack -> msg) -> f ln msg >> loop gh
      RotateLog                -> rotateLog gh
      StopLog                  -> close gh
    rotateLog gh = helper `catch` \e -> throwIO (e :: SomeException) -- TODO: What happens when there is an exception?
      where
        helper = doesFileExist fn >>= \case
          True  -> (fileSize <$> getFileStatus fn) >>= \fs ->
              if fs >= maxLogSize then rotateIt else loop gh
          False -> close gh >> (loop =<< initLog)
        rotateIt = getZonedTime >>= \t ->
            let wordy = words . show $ t
                date  = head wordy
                time  = map replaceColons . init . reverse . dropWhile (/= '.') . reverse . head . tail $ wordy
            in do
                close gh
                renameFile fn . concat $ [ dropExt fn, ".", date, "_", time, ".log" ]
                loop =<< initLog
        replaceColons ':' = '-'
        replaceColons x   = x
        dropExt           = reverse . drop 4 . reverse


initPlaLog :: Id -> Sing -> MudStack ()
initPlaLog i n@(T.unpack . (<> ".log") -> fn) = do
    q <- liftIO newTQueueIO
    a <- liftIO . spawnLogger fn INFO ("currymud." <> n) infoM $ q
    modifyNWS plaLogTblTMVar $ \plt ->
        plt & at i ?~ (a, q)


-- ==================================================
-- Stopping/closing logs:


stopLog :: LogQueue -> MudStack ()
stopLog = liftIO . atomically . flip writeTQueue StopLog


closePlaLog :: Id -> MudStack ()
closePlaLog = flip doIfLogging stopLog


doIfLogging :: Id -> (LogQueue -> MudStack ()) -> MudStack ()
doIfLogging i f = (IM.lookup i <$> readTMVarInNWS plaLogTblTMVar) >>= \case
  Nothing     -> return ()
  Just (_, q) -> f q


closeLogs :: MudStack ()
closeLogs = do
    logNotice "Mud.Logging" "closeLogs" "closing the logs."
    [ (na, nq), (ea, eq) ] <- sequence [ fromJust <$> gets (view (nonWorldState.noticeLog))
                                       , fromJust <$> gets (view (nonWorldState.errorLog )) ]
    (unzip -> (as, qs)) <- IM.elems <$> readTMVarInNWS plaLogTblTMVar
    mapM_ stopLog         $ nq : eq : qs
    mapM_ (liftIO . wait) $ na : ea : as
    liftIO removeAllHandlers


-- ==================================================
-- Rotating logs:


rotatePlaLog :: Id -> MudStack ()
rotatePlaLog = flip doIfLogging (liftIO . atomically . flip writeTQueue RotateLog)


-- ==================================================
-- Logging messages:


registerMsg :: T.Text -> LogQueue -> MudStack ()
registerMsg msg q = liftIO . atomically . writeTQueue q . LogMsg $ msg


logNotice :: T.Text -> T.Text -> T.Text -> MudStack ()
logNotice modName funName msg = maybeVoid helper =<< gets (view (nonWorldState.noticeLog))
  where
    helper = registerMsg (T.concat [ modName, " ", funName, ": ", msg ]) . snd


logError :: T.Text -> MudStack ()
logError msg = maybeVoid (registerMsg msg . snd) =<< gets (view (nonWorldState.errorLog))


logExMsg :: T.Text -> T.Text -> T.Text -> SomeException -> MudStack ()
logExMsg modName funName msg (dblQuote . showText -> e) =
    logError . T.concat $ [ modName, " ", funName, ": ", msg, ". ", e ]


logIOEx :: T.Text -> T.Text -> IOException -> MudStack ()
logIOEx modName funName (dblQuote . showText -> e) = logError . T.concat $ [ modName, " ", funName, ": ", e ]


logAndDispIOEx :: MsgQueue -> Cols -> T.Text -> T.Text -> IOException -> MudStack ()
logAndDispIOEx mq cols modName funName (dblQuote . showText -> e)
  | msg <- T.concat [ modName, " ", funName, ": ", e ] = logError msg >> wrapSend mq cols msg


logIOExRethrow :: T.Text -> T.Text -> IOException -> MudStack ()
logIOExRethrow modName funName e = do
    logError . T.concat $ [ modName, " ", funName, ": unexpected exception; rethrowing." ]
    liftIO . throwIO $ e


logPla :: T.Text -> T.Text -> Id -> T.Text -> MudStack ()
logPla modName funName i msg = doIfLogging i $ registerMsg (T.concat [ modName, " ", funName, ": ", msg ])


logPlaExec :: T.Text -> CmdName -> Id -> MudStack ()
logPlaExec modName (dblQuote -> cn) i = logPla modName cn i $ "executed " <> cn <> "."


logPlaExecArgs :: T.Text -> CmdName -> Args -> Id -> MudStack ()
logPlaExecArgs modName cn@(dblQuote -> cn') as i = logPla modName cn' i $ "executed " <> helper <> "."
  where
    helper = case as of [] -> cn' <> " with no arguments"
                        _  -> dblQuote . T.intercalate " " $ cn : as


logPlaOut :: T.Text -> CmdName -> Id -> [T.Text] -> MudStack ()
logPlaOut modName cn i (T.intercalate " / " -> msgs) = helper =<< getPlaLogQueue i
  where
    helper = registerMsg (T.concat [ modName, " ", cn, " (output): ", msgs ])


massLogPla :: T.Text -> T.Text -> T.Text -> MudStack ()
massLogPla modName funName msg = readTMVarInNWS plaLogTblTMVar >>= helper
  where
    helper (map snd . IM.elems -> logQueues) =
        forM_ logQueues $ registerMsg (T.concat [ modName, " ", funName, ": ", msg ])
