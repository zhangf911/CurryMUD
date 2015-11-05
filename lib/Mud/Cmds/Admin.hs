{-# LANGUAGE FlexibleContexts, LambdaCase, MonadComprehensions, MultiWayIf, NamedFieldPuns, OverloadedStrings, PatternSynonyms, RecordWildCards, TransformListComp, TupleSections, ViewPatterns #-}

module Mud.Cmds.Admin (adminCmds) where

import Mud.Cmds.ExpCmds
import Mud.Cmds.Msgs.Advice
import Mud.Cmds.Msgs.Hint
import Mud.Cmds.Msgs.Misc
import Mud.Cmds.Msgs.Sorry
import Mud.Cmds.Pla
import Mud.Cmds.Util.Abbrev
import Mud.Cmds.Util.CmdPrefixes
import Mud.Cmds.Util.EmoteExp.EmoteExp
import Mud.Cmds.Util.EmoteExp.TwoWayEmoteExp
import Mud.Cmds.Util.Misc
import Mud.Data.Misc
import Mud.Data.State.ActionParams.ActionParams
import Mud.Data.State.MsgQueue
import Mud.Data.State.MudData
import Mud.Data.State.Util.Calc
import Mud.Data.State.Util.Get
import Mud.Data.State.Util.Misc
import Mud.Data.State.Util.Output
import Mud.Data.State.Util.Random
import Mud.Misc.ANSI
import Mud.Misc.Database
import Mud.Misc.LocPref
import Mud.Misc.Persist
import Mud.TopLvlDefs.Misc
import Mud.Util.List hiding (headTail)
import Mud.Util.Misc hiding (patternMatchFail)
import Mud.Util.Operators
import Mud.Util.Padding
import Mud.Util.Quoting
import Mud.Util.Text
import Mud.Util.Wrapping
import qualified Mud.Misc.Logging as L (logIOEx, logNotice, logPla, logPlaExec, logPlaExecArgs, logPlaOut, massLogPla)
import qualified Mud.Util.Misc as U (patternMatchFail)

import Control.Arrow ((***))
import Control.Concurrent.STM (atomically)
import Control.Concurrent.STM.TQueue (writeTQueue)
import Control.Exception (IOException)
import Control.Exception.Lifted (try)
import Control.Lens (_1, _2, _3, to, view, views)
import Control.Lens.Operators ((%~), (&), (.~), (<>~), (^.))
import Control.Monad ((>=>), forM_, unless, when)
import Control.Monad.IO.Class (liftIO)
import Data.Either (rights)
import Data.Function (on)
import Data.List (delete, foldl', intercalate, partition, sortBy)
import Data.Maybe (fromJust, fromMaybe)
import Data.Monoid ((<>), Any(..), Sum(..), getSum)
import Data.Time (TimeZone, UTCTime, defaultTimeLocale, diffUTCTime, formatTime, getCurrentTime, getCurrentTimeZone, getZonedTime, utcToLocalTime)
import GHC.Exts (sortWith)
import Prelude hiding (pi)
import qualified Data.IntMap.Lazy as IM (elems, filter, keys, size, toList)
import qualified Data.Map.Lazy as M (foldl, foldrWithKey)
import qualified Data.Text as T
import qualified Data.Text.IO as T (putStrLn)
import System.Process (readProcess)
import System.Time.Utils (renderSecs)


default (Int)


-----


patternMatchFail :: T.Text -> [T.Text] -> a
patternMatchFail = U.patternMatchFail "Mud.Cmds.Admin"


-----


logIOEx :: T.Text -> IOException -> MudStack ()
logIOEx = L.logIOEx "Mud.Cmds.Admin"


logNotice :: T.Text -> T.Text -> MudStack ()
logNotice = L.logNotice "Mud.Cmds.Admin"


logPla :: T.Text -> Id -> T.Text -> MudStack ()
logPla = L.logPla "Mud.Cmds.Admin"


logPlaExec :: CmdName -> Id -> MudStack ()
logPlaExec = L.logPlaExec "Mud.Cmds.Admin"


logPlaExecArgs :: CmdName -> Args -> Id -> MudStack ()
logPlaExecArgs = L.logPlaExecArgs "Mud.Cmds.Admin"


logPlaOut :: CmdName -> Id -> [T.Text] -> MudStack ()
logPlaOut = L.logPlaOut "Mud.Cmds.Admin"


massLogPla :: T.Text -> T.Text -> MudStack ()
massLogPla = L.massLogPla "Mud.Cmds.Admin"


-- ==================================================


adminCmds :: [Cmd]
adminCmds =
    [ mkAdminCmd "?"          adminDispCmdList "Display or search this command list."
    , mkAdminCmd "admin"      adminAdmin       ("Send a message on the admin channel " <> plusRelatedMsg)
    , mkAdminCmd "banhost"    adminBanHost     "Dump the banned hostname database, or ban/unban a host."
    , mkAdminCmd "banplayer"  adminBanPla      "Dump the banned player database, or ban/unban a player."
    , mkAdminCmd "announce"   adminAnnounce    "Send a message to all players."
    , mkAdminCmd "boot"       adminBoot        "Boot a player, optionally with a custom message."
    , mkAdminCmd "bug"        adminBug         "Dump the bug database."
    , mkAdminCmd "channel"    adminChan        "Display information about one or more telepathic channels."
    , mkAdminCmd "date"       adminDate        "Display the current system date."
    , mkAdminCmd "host"       adminHost        "Display a report of connection statistics for one or more players."
    , mkAdminCmd "incognito"  adminIncognito   "Toggle your incognito status."
    , mkAdminCmd "ip"         adminIp          "Display the server's IP addresses and listening port."
    , mkAdminCmd "message"    adminMsg         "Send a message to a regular player."
    , mkAdminCmd "mychannels" adminMyChans     "Display information about telepathic channels for one or more players."
    , mkAdminCmd "peep"       adminPeep        "Start or stop peeping one or more players."
    , mkAdminCmd "persist"    adminPersist     "Persist the world (save the current world state to disk)."
    , mkAdminCmd "print"      adminPrint       "Print a message to the server console."
    , mkAdminCmd "profanity"  adminProfanity   "Dump the profanity database."
    , mkAdminCmd "shutdown"   adminShutdown    "Shut down CurryMUD, optionally with a custom message."
    , mkAdminCmd "sudoer"     adminSudoer      "Toggle a player's admin status."
    , mkAdminCmd "telepc"     adminTelePC      "Teleport to a PC."
    , mkAdminCmd "telerm"     adminTeleRm      "Display a list of rooms to which you may teleport, or teleport to a \
                                               \room."
    , mkAdminCmd "time"       adminTime        "Display the current system time."
    , mkAdminCmd "typo"       adminTypo        "Dump the typo database."
    , mkAdminCmd "uptime"     adminUptime      "Display the system uptime."
    , mkAdminCmd "whoin"      adminWhoIn       "Display or search a list of all the people that are currently logged \
                                               \in."
    , mkAdminCmd "whoout"     adminWhoOut      "Display or search a list of all the people that are currently logged \
                                               \out."
    , mkAdminCmd "wiretap"    adminWire        "Start or stop tapping one or more telepathic channels." ]


mkAdminCmd :: T.Text -> Action -> CmdDesc -> Cmd
mkAdminCmd (prefixAdminCmd -> cn) act cd = Cmd { cmdName           = cn
                                               , cmdPriorityAbbrev = Nothing
                                               , cmdFullName       = cn
                                               , action            = act
                                               , cmdDesc           = cd }


-----


adminAdmin :: Action
adminAdmin (NoArgs i mq cols) = getState >>= \ms ->
    let triples = sortBy (compare `on` view _2) [ (ai, as, isTuned) | ai <- getLoggedInAdminIds ms
                                                                    , let as      = getSing ai ms
                                                                    , let ap      = getPla  ai ms
                                                                    , let isTuned = isTunedAdmin ap ]
        ([self],   others   )  = partition (\x -> x^._1.to (== i)) triples
        (tunedIns, tunedOuts)  = partition (view _3) others
        styleds                = styleAbbrevs Don'tQuote . map (view _2) $ tunedIns
        others'                = zipWith (\triple styled -> triple & _2 .~ styled) tunedIns styleds ++ tunedOuts
        mkDesc (_, n, isTuned) = padName n <> tunedInOut isTuned
        descs                  = mkDesc self : map mkDesc others'
    in multiWrapSend mq cols descs >> logPlaExecArgs (prefixAdminCmd "admin") [] i
adminAdmin (Msg i mq cols msg) = getState >>= \ms ->
    if isTunedAdminId i ms
      then case getTunedAdminIds ms of
        [_]      -> wrapSend mq cols . sorryChanNoOneListening $ "admin"
        tunedIds ->
          let tunedSings         = map (`getSing` ms) tunedIds
              getStyled targetId = let styleds = styleAbbrevs Don'tQuote $ getSing targetId ms `delete` tunedSings
                                   in head . filter ((== s) . dropANSI) $ styleds
              s                  = getSing i ms
              format (txt, is)   = if i `elem` is
                then (formatChanMsg "Admin" s txt, pure i) : mkBsWithStyled (i `delete` is)
                else mkBsWithStyled is
                where
                  mkBsWithStyled is' = [ (formatChanMsg "Admin" (getStyled i') txt, pure i') | i' <- is' ]
              f bs = ioHelper s (concatMap format bs)
              ws   = wrapSend      mq cols
              mws  = multiWrapSend mq cols
          in case adminChanTargetify tunedIds tunedSings msg of
            Left errorMsg    -> ws errorMsg
            Right (Right bs) -> f bs . mkLogMsg $ bs
            Right (Left ())  -> case adminChanEmotify i ms tunedIds tunedSings msg of
              Left  errorMsgs  -> mws errorMsgs
              Right (Right bs) -> f bs . mkLogMsg $ bs
              Right (Left ())  -> case adminChanExpCmdify i ms tunedIds tunedSings msg of
                Left  errorMsg     -> ws errorMsg
                Right (bs, logMsg) -> f bs logMsg
      else wrapSend mq cols . sorryTunedOutOOCChan $ "admin"
  where
    getTunedAdminIds ms  = [ ai | ai <- getLoggedInAdminIds ms, isTunedAdminId ai ms ]
    mkLogMsg             = dropANSI . fst . head
    ioHelper s bs logMsg = bcastNl bs >> logHelper
      where
        logHelper = do
            logPlaOut (prefixAdminCmd "admin") i . pure $ logMsg
            ts <- liftIO mkTimestamp
            withDbExHandler_ "adminAdmin" . insertDbTblAdminChan . AdminChanRec ts s $ logMsg
adminAdmin p = patternMatchFail "adminAdmin" [ showText p ]


-----


adminAnnounce :: Action
adminAnnounce p@AdviseNoArgs  = advise p [ prefixAdminCmd "announce" ] adviceAAnnounceNoArgs
adminAnnounce (Msg' i mq msg) = getState >>= \ms -> let s = getSing i ms in do
    ok mq
    massSend $ announceColor <> msg <> dfltColor
    logPla    "adminAnnounce" i $       "announced "  <> dblQuote msg
    logNotice "adminAnnounce"   $ s <> " announced, " <> dblQuote msg
adminAnnounce p = patternMatchFail "adminAnnounce" [ showText p ]


-----


adminBanHost :: Action
adminBanHost (NoArgs i mq cols) = (withDbExHandler "adminBanHost" . getDbTblRecs $ "ban_host") >>= \case
  Just xs -> dumpDbTblHelper mq cols (xs :: [BanHostRec]) >> logPlaExecArgs (prefixAdminCmd "banhost") [] i
  Nothing -> wrapSend mq cols dbErrorMsg
adminBanHost p@(AdviseOneArg a) = advise p [ prefixAdminCmd "banhost" ] . adviceABanHostNoReason $ a
adminBanHost (MsgWithTarget i mq cols (uncapitalize -> target) msg) = getState >>= \ms ->
    (withDbExHandler "adminBanHost" . isHostBanned $ target) >>= \case
      Nothing      -> wrapSend mq cols dbErrorMsg
      Just (Any b) -> let newStatus = not b in liftIO mkTimestamp >>= \ts -> do
          let banHost = BanHostRec ts target newStatus msg
          withDbExHandler_ "adminBanHost" . insertDbTblBanHost $ banHost
          notifyBan i mq cols (getSing i ms) target newStatus banHost
adminBanHost p = patternMatchFail "adminBanHost" [ showText p ]


dumpDbTblHelper :: (Pretty a) => MsgQueue -> Cols -> [a] -> MudStack ()
dumpDbTblHelper mq cols [] = wrapSend mq cols dbEmptyMsg
dumpDbTblHelper mq cols xs = multiWrapSend mq cols . map pp $ xs


notifyBan :: (Pretty a) => Id -> MsgQueue -> Cols -> Sing -> T.Text -> Bool -> a -> MudStack ()
notifyBan i mq cols selfSing target newStatus x =
    let fn          = "notifyBan"
        (v, suffix) = newStatus ? ("banned", [ ": " <> pp x ]) :? ("unbanned", [ ": " <> pp x ])
    in do
        wrapSend mq cols   . T.concat $ [ "You have ",   v, " ", target ] ++ suffix
        bcastOtherAdmins i . T.concat $ [ selfSing, " ", v, " ", target ] ++ suffix
        logNotice fn       . T.concat $ [ selfSing, " ", v, " ", target ] ++ suffix
        logPla    fn i     . T.concat $ [                v, " ", target ] ++ suffix


-----


adminBanPla :: Action
adminBanPla (NoArgs i mq cols) = (withDbExHandler "adminBanPla" . getDbTblRecs $ "ban_pla") >>= \case
  Just xs -> dumpDbTblHelper mq cols (xs :: [BanPlaRec]) >> logPlaExecArgs (prefixAdminCmd "banpla") [] i
  Nothing -> wrapSend mq cols dbErrorMsg
adminBanPla p@(AdviseOneArg a) = advise p [ prefixAdminCmd "banplayer" ] . adviceABanPlaNoReason $ a
adminBanPla p@(MsgWithTarget i mq cols target msg) = getState >>= \ms ->
    let fn = "adminBanPla"
        SingleTarget { .. } = mkSingleTarget mq cols target "The PC name of the player you wish to ban"
    in case [ pi | pi <- views pcTbl IM.keys ms, getSing pi ms == strippedTarget ] of
      []      -> sendFun . sorryPCName $ strippedTarget <> " " <> hintABan
      [banId] -> let selfSing = getSing i     ms
                     pla      = getPla  banId ms
                 in if
                   | banId == i  -> sendFun sorryBanSelf
                   | isAdmin pla -> sendFun sorryBanAdmin
                   | otherwise   -> (withDbExHandler "adminBanPla" . isPlaBanned $ strippedTarget) >>= \case
                     Nothing      -> wrapSend mq cols dbErrorMsg
                     Just (Any b) -> let newStatus = not b in liftIO mkTimestamp >>= \ts -> do
                         let banPla = BanPlaRec ts strippedTarget newStatus msg
                         withDbExHandler_ "adminBanPla" . insertDbTblBanPla $ banPla
                         notifyBan i mq cols selfSing strippedTarget newStatus banPla
                         when (newStatus && isLoggedIn pla)
                              (adminBoot p { args = strippedTarget : T.words bannedMsg })
      xs      -> patternMatchFail fn [ showText xs ]
adminBanPla p = patternMatchFail "adminBanPla" [ showText p ]


-----


adminBoot :: Action
adminBoot p@AdviseNoArgs = advise p [ prefixAdminCmd "boot" ] adviceABootNoArgs
adminBoot (MsgWithTarget i mq cols target msg) = getState >>= \ms ->
    let SingleTarget { .. } = mkSingleTarget mq cols target "The PC name of the player you wish to boot"
    in case [ pi | pi <- views pcTbl IM.keys ms, getSing pi ms == strippedTarget ] of
      []       -> sendFun . sorryPCName $ strippedTarget <> " " <> hintABoot
      [bootId] -> let selfSing = getSing i ms in if
                    | not . isLoggedIn . getPla bootId $ ms -> sendFun . sorryLoggedOut $ strippedTarget
                    | bootId == i -> sendFun sorryBootSelf
                    | bootMq <- getMsgQueue bootId ms, f <- ()# msg ? dfltMsg :? customMsg -> do
                        wrapSend mq cols $ "You have booted " <> strippedTarget <> "."
                        sendMsgBoot bootMq =<< f bootId strippedTarget selfSing
                        bcastAdminsExcept [ i, bootId ] . T.concat $ [ selfSing, " booted ", strippedTarget, "." ]
      xs       -> patternMatchFail "adminBoot" [ showText xs ]
  where
    dfltMsg   bootId target' s = emptied $ do
        logPla "adminBoot dfltMsg"   i      $ T.concat [ "booted ", target', " ", parensQuote "no message given", "." ]
        logPla "adminBoot dfltMsg"   bootId $ T.concat [ "booted by ", s,    " ", parensQuote "no message given", "." ]
    customMsg bootId target' s = do
        logPla "adminBoot customMsg" i      $ T.concat [ "booted ", target', "; message: ", dblQuote msg ]
        logPla "adminBoot customMsg" bootId $ T.concat [ "booted by ", s,    "; message: ", dblQuote msg ]
        unadulterated msg
adminBoot p = patternMatchFail "adminBoot" [ showText p ]


-----


adminBug :: Action
adminBug (NoArgs i mq cols) = (withDbExHandler "adminBug" . getDbTblRecs $ "bug") >>= \case
  Just xs -> dumpDbTblHelper mq cols (xs :: [BugRec]) >> logPlaExec (prefixAdminCmd "bug") i
  Nothing -> wrapSend mq cols dbErrorMsg
adminBug p = withoutArgs adminBug p


-----


adminChan :: Action
adminChan (NoArgs i mq cols) = getState >>= \ms -> case views chanTbl (map (mkChanReport i ms) . IM.elems) ms of
  []      -> informNoChans mq cols
  reports -> adminChanIOHelper i mq reports
adminChan (LowerNub i mq cols as) = getState >>= \ms ->
    let helper a = case reads . T.unpack $ a :: [(Int, String)] of
          [(ci, "")] | ci < 0                                -> pure sorryWtf
                     | ci `notElem` (ms^.chanTbl.to IM.keys) -> sorry
                     | otherwise                             -> mkChanReport i ms . getChan ci $ ms
          _                                                  -> sorry
          where
            sorry = pure . sorryParseChanId $ a
        reports = map helper as
    in case views chanTbl IM.size ms of 0 -> informNoChans mq cols
                                        _ -> adminChanIOHelper i mq reports
adminChan p = patternMatchFail "adminChan" [ showText p ]


informNoChans :: MsgQueue -> Cols -> MudStack ()
informNoChans mq cols = wrapSend mq cols "No channels exist!"


adminChanIOHelper :: Id -> MsgQueue -> [[T.Text]] -> MudStack ()
adminChanIOHelper i mq reports =
    (pager i mq . intercalate [""] $ reports) >> logPlaExec (prefixAdminCmd "channel") i


-----


adminDate :: Action
adminDate (NoArgs' i mq) = do
    send mq . nlnl . T.pack . formatTime defaultTimeLocale "%A %B %d" =<< liftIO getZonedTime
    logPlaExec (prefixAdminCmd "date") i
adminDate p = withoutArgs adminDate p


-----


adminDispCmdList :: Action
adminDispCmdList p@(LowerNub' i as) = dispCmdList adminCmds p >> logPlaExecArgs (prefixAdminCmd "?") as i
adminDispCmdList p                  = patternMatchFail "adminDispCmdList" [ showText p ]


-----


adminHost :: Action
adminHost p@AdviseNoArgs = advise p [ prefixAdminCmd "host" ] adviceAHostNoArgs
adminHost (LowerNub i mq cols as) = do
    ms          <- getState
    (now, zone) <- (,) <$> liftIO getCurrentTime <*> liftIO getCurrentTimeZone
    let (f, guessWhat) | any hasLocPref as = (stripLocPref, sorryHostIgnore)
                       | otherwise         = (id,           ""             )
        g = ()# guessWhat ? id :? (guessWhat :)
        helper target =
            let notFound = pure . sorryPCName $ target
                found    = uncurry (mkHostReport ms now zone)
            in findFullNameForAbbrev target (mkAdminPlaIdSingList ms) |&| maybe notFound found
    multiWrapSend mq cols . g . intercalate [""] . map (helper . capitalize . T.toLower . f) $ as
    logPlaExec (prefixAdminCmd "host") i
adminHost p = patternMatchFail "adminHost" [ showText p ]


mkHostReport :: MudState -> UTCTime -> TimeZone -> Id -> Sing -> [T.Text]
mkHostReport ms now zone i s = (header ++) $ case getHostMap s ms of
  Nothing      -> [ "There are no host records for " <> s <> "." ]
  Just hostMap | dur       <- ili |?| duration
               , total     <- M.foldl (\acc -> views secsConnected (+ acc)) 0 hostMap + getSum dur
               , totalDesc <- "Grand total time connected: " <> renderIt total
               -> M.foldrWithKey helper [] hostMap ++ pure totalDesc
  where
    header = [ s <> ": "
             , "Currently logged " <> if ili
                 then T.concat [ "in from "
                               , T.pack . getCurrHostName i $ ms
                               , " "
                               , parensQuote . renderIt . getSum $ duration
                               , "." ]
                 else "out." ]
    ili       = isLoggedIn . getPla i $ ms
    renderIt  = T.pack . renderSecs
    duration  = Sum . round $ now `diffUTCTime` conTime
    conTime   = fromJust . getConnectTime i $ ms
    helper (T.pack -> host) r = (T.concat [ host
                                          , ": "
                                          , let n      = r^.noOfLogouts
                                                suffix = n > 1 |?| "s"
                                            in showText n <> " time" <> suffix
                                          , ", "
                                          , views secsConnected renderIt r
                                          , ", "
                                          , views lastLogout (showText . utcToLocalTime zone) r ] :)


-----


adminIncognito :: Action
adminIncognito (NoArgs i mq cols) = modifyState helper >>= sequence_
  where
    helper ms = let s              = getSing i ms
                    isIncog        = isIncognitoId i ms
                    fs | isIncog   = [ wrapSend mq cols "You are no longer incognito."
                                     , bcastOtherAdmins i $ s <> " is no longer incognito."
                                     , logPla "adminIncognito helper fs" i "no longer incognito." ]
                       | otherwise = [ wrapSend mq cols "You have gone incognito."
                                     , bcastOtherAdmins i $ s <> " has gone incognito."
                                     , logPla "adminIncognito helper fs" i "went incognito." ]
                in (ms & plaTbl.ind i %~ setPlaFlag IsIncognito (not isIncog), fs)
adminIncognito p = withoutArgs adminIncognito p


-----


adminIp :: Action
adminIp (NoArgs i mq cols) = do
    ifList <- liftIO mkInterfaceList
    multiWrapSend mq cols [ "Interfaces: " <> ifList <> ".", "Listening on port " <> showText port <> "." ]
    logPlaExec (prefixAdminCmd "ip") i
adminIp p = withoutArgs adminIp p


-----


adminMsg :: Action
adminMsg p@AdviseNoArgs     = advise p [ prefixAdminCmd "message" ] adviceAMsgNoArgs
adminMsg p@(AdviseOneArg a) = advise p [ prefixAdminCmd "message" ] . adviceAMsgNoMsg $ a
adminMsg (MsgWithTarget i mq cols target msg) = getState >>= helper >>= \logMsgs ->
    logMsgs |#| let f = uncurry (logPla "adminMsg") in mapM_ f
  where
    helper ms =
        let SingleTarget { .. } = mkSingleTarget mq cols target "The PC name of the player you wish to message"
            s                   = getSing i ms
            notFound            = emptied . sendFun . sorryRegPlaName $ strippedTarget
            found pair@(targetId, targetSing) = case emotifyTwoWay (prefixAdminCmd "message") i ms targetId msg of
              Left  errorMsgs  -> emptied . multiSendFun $ errorMsgs
              Right (Right bs) -> ioHelper pair bs
              Right (Left  ()) -> case expCmdifyTwoWay i ms targetId targetSing msg of
                Left  errorMsg -> emptied . sendFun $ errorMsg
                Right bs       -> ioHelper pair bs
            ioHelper (targetId, targetSing) [ fst -> toSelf, fst -> toTarget ] = if
              | isLoggedIn targetPla, isIncognitoId i ms ->
                emptied . sendFun $ sorryMsgIncog
              | isLoggedIn targetPla ->
                  let (targetMq, targetCols) = getMsgQueueColumns targetId ms
                      adminSings             = map snd . filter f . mkAdminIdSingList $ ms
                      f (iRoot, "Root")      = let rootPla = getPla iRoot ms
                                               in isLoggedIn rootPla && (not . isIncognito $ rootPla)
                      f _                    = True
                      me                     = head . filter g . styleAbbrevs Don'tQuote $ adminSings
                      g                      = (== s) . dropANSI
                      toTarget'              = quoteWith "__" me <> " " <> toTarget
                  in do
                      sendFun formatted
                      (multiWrapSend targetMq targetCols =<<) $ if isNotFirstAdminMsg targetPla
                        then unadulterated toTarget'
                        else [ toTarget' : hints | hints <- firstAdminMsg targetId s ]
                      dbHelper
              | otherwise -> do
                  multiSendFun [ formatted, parensQuote "Message retained." ]
                  retainedMsg targetId ms . mkRetainedMsgFromPerson s $ toTarget
                  dbHelper
              where
                targetPla = getPla targetId ms
                formatted = T.concat [ parensQuote $ "to " <> targetSing
                                     , " "
                                     , quoteWith "__" s
                                     , " "
                                     , toSelf ]
                dbHelper  = do
                    ts <- liftIO mkTimestamp
                    withDbExHandler_ "admin_msg" . insertDbTblAdminMsg . AdminMsgRec ts s targetSing $ toSelf
                    return [ sentLogMsg, receivedLogMsg ]
                sentLogMsg     = (i,        T.concat [ "sent message to ", targetSing, ": ", toSelf   ])
                receivedLogMsg = (targetId, T.concat [ "received message from ", s,    ": ", toTarget ])
            ioHelper _ xs = patternMatchFail "adminMsg helper ioHelper" [ showText xs ]
        in (findFullNameForAbbrev strippedTarget . mkPlaIdSingList $ ms) |&| maybe notFound found
adminMsg p = patternMatchFail "adminMsg" [ showText p ]


firstAdminMsg :: Id -> Sing -> MudStack [T.Text]
firstAdminMsg i adminSing =
    modifyState $ (, [ "", hintAMsg adminSing ]) . (plaTbl.ind i %~ setPlaFlag IsNotFirstAdminMsg True)


-----


adminMyChans :: Action
adminMyChans p@AdviseNoArgs          = advise p [ prefixAdminCmd "mychannels" ] adviceAMyChansNoArgs
adminMyChans (LowerNub i mq cols as) = getState >>= \ms ->
    let (f, guessWhat) | any hasLocPref as = (stripLocPref, sorryMyChansIgnore)
                       | otherwise         = (id,           ""                )
        g = ()# guessWhat ? id :? ((guessWhat :) . ("" :))
        helper target =
            let notFound                     = pure . sorryPCName $ target
                found (targetId, targetSing) = case getPCChans targetId ms of
                  [] -> header . pure $ "None."
                  cs -> header . intercalate [""] . map (mkChanReport i ms) $ cs
                  where
                    header = (targetSing <> "'s channels:" :) . ("" :)
            in findFullNameForAbbrev target (mkAdminPlaIdSingList ms) |&| maybe notFound found
        allReports = intercalateDivider cols . map (helper . capitalize . f) $ as
    in case views chanTbl IM.size ms of
      0 -> informNoChans mq cols
      _ -> pager i mq (g allReports) >> logPlaExec (prefixAdminCmd "mychannels") i
adminMyChans p = patternMatchFail "adminMyChans" [ showText p ]


-----


adminPeep :: Action
adminPeep p@AdviseNoArgs = advise p [ prefixAdminCmd "peep" ] adviceAPeepNoArgs
adminPeep (LowerNub i mq cols as) = do
    (msgs, unzip -> (logMsgsSelf, logMsgsOthers)) <- modifyState helper
    multiWrapSend mq cols msgs
    logPla "adminPeep" i . (<> ".") . slashes $ logMsgsSelf
    forM_ logMsgsOthers $ uncurry (logPla "adminPeep")
  where
    helper ms =
        let s     = getSing i ms
            apiss = [ apis | apis@(api, _) <- mkAdminPlaIdSingList ms, isLoggedIn . getPla api $ ms ]
            (f, guessWhat) | any hasLocPref as = (stripLocPref, sorryPeepIgnore)
                           | otherwise         = (id,           ""             )
            g = ()# guessWhat ? id :? (guessWhat :)
            peep target a@(pt, _, _) =
                let notFound = a & _2 %~ (sorryPCNameLoggedIn target :)
                    found (peepId@(flip getPla ms -> peepPla), peepSing) = if peepId `notElem` pt^.ind i.peeping
                      then if
                        | peepId == i     -> a & _2 %~ (sorryPeepSelf  :)
                        | isAdmin peepPla -> a & _2 %~ (sorryPeepAdmin :)
                        | otherwise       ->
                          let pt'     = pt & ind i     .peeping %~ (peepId :)
                                           & ind peepId.peepers %~ (i      :)
                              msg     = "You are now peeping " <> peepSing <> "."
                              logMsgs = [("started peeping " <> peepSing, (peepId, s <> " started peeping."))]
                          in a & _1 .~ pt' & _2 %~ (msg :) & _3 <>~ logMsgs
                      else let pt'     = pt & ind i     .peeping %~ (peepId `delete`)
                                            & ind peepId.peepers %~ (i      `delete`)
                               msg     = "You are no longer peeping " <> peepSing <> "."
                               logMsgs = [("stopped peeping " <> peepSing, (peepId, s <> " stopped peeping."))]
                           in a & _1 .~ pt' & _2 %~ (msg :) & _3 <>~ logMsgs
                in findFullNameForAbbrev target apiss |&| maybe notFound found
            res = foldr (peep . capitalize . f) (ms^.plaTbl, [], []) as
        in (ms & plaTbl .~ res^._1, (res^._2.to g, res^._3))
adminPeep p = patternMatchFail "adminPeep" [ showText p ]


-----


adminPersist :: Action
adminPersist (NoArgs' i mq) = persist >> ok mq >> logPlaExec (prefixAdminCmd "persist") i
adminPersist p              = withoutArgs adminPersist p


-----


adminPrint :: Action
adminPrint p@AdviseNoArgs  = advise p [ prefixAdminCmd "print" ] adviceAPrintNoArgs
adminPrint (Msg' i mq msg) = getState >>= \ms -> let s = getSing i ms in do
    liftIO . T.putStrLn . T.concat $ [ bracketQuote s, " ", printConsoleColor, msg, dfltColor ]
    ok mq
    logPla    "adminPrint" i $       "printed "  <> dblQuote msg
    logNotice "adminPrint"   $ s <> " printed, " <> dblQuote msg
adminPrint p = patternMatchFail "adminPrint" [ showText p ]


-----


adminProfanity :: Action
adminProfanity (NoArgs i mq cols) = (withDbExHandler "adminProfanity" . getDbTblRecs $ "profanity") >>= \case
  Just xs -> dumpDbTblHelper mq cols (xs :: [ProfRec]) >> logPlaExec (prefixAdminCmd "profanity") i
  Nothing -> wrapSend mq cols dbErrorMsg
adminProfanity p = withoutArgs adminProfanity p


-----


adminShutdown :: Action
adminShutdown (NoArgs' i mq    ) = shutdownHelper i mq Nothing
adminShutdown (Msg'    i mq msg) = shutdownHelper i mq . Just $ msg
adminShutdown p                  = patternMatchFail "adminShutdown" [ showText p ]


shutdownHelper :: Id -> MsgQueue -> Maybe T.Text -> MudStack ()
shutdownHelper i mq maybeMsg = getState >>= \ms ->
    let s    = getSing i ms
        rest = maybeMsg |&| maybe (" " <> parensQuote "no message given" <> ".") (("; message: " <>) . dblQuote)
    in do
        massSend $ shutdownMsgColor <> fromMaybe dfltShutdownMsg maybeMsg <> dfltColor
        logPla     "shutdownHelper" i $ "initiating shutdown" <> rest
        massLogPla "shutdownHelper"   $ "closing connection due to server shutdown initiated by " <> s <> rest
        logNotice  "shutdownHelper"   $ "server shutdown initiated by "                           <> s <> rest
        liftIO . atomically . writeTQueue mq $ Shutdown


-----


adminSudoer :: Action
adminSudoer p@AdviseNoArgs = advise p [ prefixAdminCmd "sudoer" ] adviceASudoerNoArgs
adminSudoer (OneArgNubbed i mq cols target) = modifyState helper >>= sequence_
  where
    helper ms =
      let fn                  = "adminSudoer helper"
          SingleTarget { .. } = mkSingleTarget mq cols target "The PC name of the player you wish to promote/demote"
      in case [ pi | pi <- views pcTbl IM.keys ms, getSing pi ms == strippedTarget ] of
        [] -> (ms, pure . sendFun . sorryPCName $ strippedTarget <> " " <> hintASudoer)
        [targetId]
          | selfSing       <- getSing i ms
          , targetSing     <- getSing targetId ms
          , ia             <- isAdminId targetId ms
          , (verb, toFrom) <- ia ? ("demoted", "from") :? ("promoted", "to")
          , handleIncog    <- let act = adminIncognito . mkActionParams targetId ms $ []
                              in when (isIncognitoId targetId ms) act
          , handlePeep     <- let peepingIds = getPeeping targetId ms
                                  act        = adminPeep . mkActionParams targetId ms . map (`getSing` ms) $ peepingIds
                              in unless (()# peepingIds) act
          , fs <- [ retainedMsg targetId ms           . T.concat $ [ promoteDemoteColor
                                                                   , selfSing
                                                                   , " has "
                                                                   , verb
                                                                   , " you "
                                                                   , toFrom
                                                                   , " admin status."
                                                                   , dfltColor ]
                  , sendFun                           . T.concat $ [ "You have ",       verb, " ", targetSing, "." ]
                  , bcastAdminsExcept [ i, targetId ] . T.concat $ [ selfSing, " has ", verb, " ", targetSing, "." ]
                  , logNotice fn                      . T.concat $ [ selfSing, " ",     verb, " ", targetSing, "." ]
                  , logPla    fn i                    . T.concat $ [ verb, " ",    targetSing, "." ]
                  , logPla    fn targetId             . T.concat $ [ verb, " by ", selfSing,   "." ]
                  , handleIncog
                  , handlePeep ]
          -> if | targetId   == i      -> (ms, pure . sendFun $ sorrySudoerDemoteSelf)
                | targetSing == "Root" -> (ms, pure . sendFun $ sorrySudoerDemoteRoot)
                | otherwise            -> (ms & plaTbl.ind targetId %~ setPlaFlag IsAdmin      (not ia)
                                              & plaTbl.ind targetId %~ setPlaFlag IsTunedAdmin (not ia), fs)
        xs -> patternMatchFail "adminSudoer helper" [ showText xs ]
adminSudoer p = advise p [] adviceASudoerExcessArgs


-----


adminTelePC :: Action
adminTelePC p@AdviseNoArgs                    = advise p [ prefixAdminCmd "telepc" ] adviceATelePCNoArgs
adminTelePC p@(OneArgNubbed i mq cols target) = modifyState helper >>= sequence_
  where
    helper ms =
        let SingleTarget { .. } = mkSingleTarget mq cols target "The name of the PC to which you want to teleport"
            idSings             = [ idSing | idSing@(api, _) <- mkAdminPlaIdSingList ms, isLoggedIn . getPla api $ ms ]
            originId            = getRmId i ms
            found (flip getRmId ms -> destId, targetSing)
              | targetSing == getSing i ms = (ms, pure .  sendFun $ sorryTelePCSelf)
              | destId     == originId     = (ms, pure .  sendFun $ sorryTeleAlready)
              | otherwise = teleHelper i ms p { args = [] } originId destId targetSing consSorryBroadcast
            notFound = (ms, pure . sendFun . sorryPCNameLoggedIn $ strippedTarget)
        in findFullNameForAbbrev strippedTarget idSings |&| maybe notFound found
adminTelePC (ActionParams { plaMsgQueue, plaCols }) = wrapSend plaMsgQueue plaCols adviceATelePCExcessArgs


teleHelper :: Id
           -> MudState
           -> ActionParams
           -> Id
           -> Id
           -> T.Text
           -> (Id -> [Broadcast] -> [Broadcast])
           -> (MudState, [MudStack ()])
teleHelper i ms p originId destId name f =
    let originDesig = mkStdDesig i ms Don'tCap
        originPCIds = i `delete` pcIds originDesig
        s           = fromJust . stdPCEntSing $ originDesig
        destDesig   = mkSerializedNonStdDesig i ms s A Don'tCap
        destPCIds   = findPCIds ms $ ms^.invTbl.ind destId
        ms'         = ms & pcTbl .ind i.rmId   .~ destId
                         & invTbl.ind originId %~ (i `delete`)
                         & invTbl.ind destId   %~ (sortInv ms . (++ pure i))
    in (ms', [ bcastIfNotIncog i . f i $ [ (nlnl   teleDescMsg,                             pure i     )
                                         , (nlnl . teleOriginMsg . serialize $ originDesig, originPCIds)
                                         , (nlnl . teleDestMsg               $ destDesig,   destPCIds  ) ]
             , look p
             , rndmDos [ (calcProbTeleVomit   i ms, mkExpAction "vomit"   p)
                       , (calcProbTeleShudder i ms, mkExpAction "shudder" p) ]
             , logPla "telehelper" i $ "teleported to " <> dblQuote name <> "." ])


-----


adminTeleRm :: Action
adminTeleRm (NoArgs i mq cols) = (multiWrapSend mq cols =<< mkTxt) >> logPlaExecArgs (prefixAdminCmd "telerm") [] i
  where
    mkTxt  = views rmTeleNameTbl ((header :) . styleAbbrevs Don'tQuote . IM.elems) <$> getState
    header = "You may teleport to the following rooms:"
adminTeleRm p@(OneArgLower i mq cols target) = modifyState helper >>= sequence_
  where
    helper ms =
        let SingleTarget { .. } = mkSingleTarget mq cols target "The name of the room to which you want to teleport"
            originId            = getRmId i ms
            found (destId, rmTeleName)
              | destId == originId = (ms, pure . sendFun $ sorryTeleAlready)
              | otherwise          = teleHelper i ms p { args = [] } originId destId rmTeleName consSorryBroadcast
            notFound               = (ms, pure . sendFun . sorryTeleRmName $ strippedTarget')
        in (findFullNameForAbbrev strippedTarget' . views rmTeleNameTbl IM.toList $ ms) |&| maybe notFound found
adminTeleRm p = advise p [] adviceATeleRmExcessArgs


-----


adminTime :: Action
adminTime (NoArgs i mq cols) = do
    (ct, zt) <- liftIO $ (,) <$> formatThat `fmap` getCurrentTime <*> formatThat `fmap` getZonedTime
    multiWrapSend mq cols [ "At the tone, the time will be...", ct, zt ]
    logPlaExec (prefixAdminCmd "time") i
  where
    formatThat (T.words . showText -> wordy@(headLast -> (date, zone))) =
        let time = T.init . T.dropWhileEnd (/= '.') . head . tail $ wordy in T.concat [ zone, ": ", date, " ", time ]
adminTime p = withoutArgs adminTime p


-----


adminTypo :: Action
adminTypo (NoArgs i mq cols) = (withDbExHandler "adminTypo" . getDbTblRecs $ "typo") >>= \case
  Just xs -> dumpDbTblHelper mq cols (xs :: [TypoRec]) >> logPlaExec (prefixAdminCmd "typo") i
  Nothing -> wrapSend mq cols dbErrorMsg
adminTypo p = withoutArgs adminTypo p


-----


adminUptime :: Action
adminUptime (NoArgs i mq cols) = do
    send mq . nl =<< liftIO uptime |&| try >=> eitherRet ((sendGenericErrorMsg mq cols >>) . logIOEx "adminUptime")
    logPlaExec (prefixAdminCmd "uptime") i
  where
    uptime = T.pack <$> readProcess "uptime" [] ""
adminUptime p = withoutArgs adminUptime p


-----


adminWhoIn :: Action
adminWhoIn = whoHelper LoggedIn "whoin"


whoHelper :: LoggedInOrOut -> T.Text -> Action
whoHelper inOrOut cn (NoArgs i mq cols) = do
    pager i mq =<< [ concatMap (wrapIndent 20 cols) charListTxt | charListTxt <- mkCharListTxt inOrOut <$> getState ]
    logPlaExecArgs (prefixAdminCmd cn) [] i
whoHelper inOrOut cn p@(ActionParams { plaId, args }) =
    (dispMatches p 20 =<< mkCharListTxt inOrOut <$> getState) >> logPlaExecArgs (prefixAdminCmd cn) args plaId


mkCharListTxt :: LoggedInOrOut -> MudState -> [T.Text]
mkCharListTxt inOrOut ms = let is               = IM.keys . IM.filter predicate $ ms^.plaTbl
                               (is', ss)        = unzip [ (i, s) | i <- is, let s = getSing i ms, then sortWith by s ]
                               ias              = zip is' . styleAbbrevs Don'tQuote $ ss
                               mkCharTxt (i, a) = let (s, r, l) = mkPrettifiedSexRaceLvl i ms
                                                      name      = mkAnnotatedName i a
                                                  in T.concat [ padName name
                                                              , padSex  s
                                                              , padRace r
                                                              , l ]
                               nop              = length is
                           in mkWhoHeader ++ map mkCharTxt ias ++ [ T.concat [ showText nop
                                                                             , " "
                                                                             , pluralize ("person", "people") nop
                                                                             , " "
                                                                             , showText inOrOut
                                                                             , "." ] ]
  where
    predicate           = case inOrOut of LoggedIn  -> isLoggedIn
                                          LoggedOut -> not . isLoggedIn
    mkAnnotatedName i a = let p     = getPla i ms
                              admin = isAdmin p     |?| asterisk
                              incog = isIncognito p |?| (asteriskColor <> "@" <> dfltColor)
                          in a <> admin <> incog


-----


adminWhoOut :: Action
adminWhoOut = whoHelper LoggedOut "whoout"


-----


adminWire :: Action
adminWire p@AdviseNoArgs          = advise p [ prefixAdminCmd "wiretap" ] adviceAWireNoArgs
adminWire (WithArgs i mq cols as) = views chanTbl IM.size <$> getState >>= \case
  0 -> informNoChans mq cols
  _ -> helper |&| modifyState >=> \(msgs, logMsgs) ->
           multiWrapSend mq cols msgs >> logMsgs |#| logPlaOut (prefixAdminCmd "wiretap") i
  where
    helper ms = let (ms', msgs) = foldl' helperWire (ms, []) as
                in (ms', (map fromEither msgs, rights msgs))
    helperWire (ms, msgs) a =
        let (ms', msg) = case reads . T.unpack $ a :: [(Int, String)] of
                           [(ci, "")] | ci < 0                                -> sorry sorryWtf
                                      | ci `notElem` (ms^.chanTbl.to IM.keys) -> sorry . sorryParseChanId $ a
                                      | otherwise                             -> toggle ms ci & _2 %~ Right
                           _                                                  -> sorry . sorryParseChanId $ a
            sorry = (ms, ) . Left
        in (ms', msgs ++ pure msg)
    toggle ms ci = let s        = getSing i ms
                       (cn, ss) = ms^.chanTbl.ind ci.to ((view chanName *** view wiretappers) . dup)
                   in if s `elem` ss
                     then ( ms & chanTbl.ind ci.wiretappers .~ s `delete` ss
                          , "You stop tapping the "  <> dblQuote cn <> " channel." )
                     else ( ms & chanTbl.ind ci.wiretappers <>~ pure s
                          , "You start tapping the " <> dblQuote cn <> " channel." )
adminWire p = patternMatchFail "adminWire" [ showText p ]
