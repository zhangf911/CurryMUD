-- {-# OPTIONS_GHC -funbox-strict-fields -Wall -Werror #-}
{-# LANGUAGE OverloadedStrings, ScopedTypeVariables #-}

module Mud.Cmds (gameWrapper) where

import Data.Monoid ((<>))
import Mud.Logging hiding (logAndDispIOEx, logExMsg, logIOEx, logIOExRethrow, logNotice)
import Mud.MiscDataTypes
import Mud.StateDataTypes
import Mud.StateHelpers
import Mud.TheWorld
import Mud.TopLvlDefs
import Mud.Util hiding (patternMatchFail)
import qualified Mud.Logging as L (logAndDispIOEx, logExMsg, logIOEx, logIOExRethrow, logNotice)
import qualified Mud.Util as U (patternMatchFail)

import Control.Arrow (first)
import Control.Exception (fromException, IOException, SomeException)
import Control.Exception.Lifted (catch, finally, try)
import Control.Lens (_1, _2, at, both, dropping, folded, over, to)
import Control.Lens.Operators ((&), (.=), (?=),(?~), (^.), (^..))
import Control.Monad ((>=>), forM_, guard, mplus, unless, when)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.State (gets)
import Data.Char (isSpace, toUpper)
import Data.Foldable (traverse_)
import Data.Functor ((<$>))
import Data.List (delete, find, foldl', nub, nubBy, sort)
import Data.Maybe (fromJust, fromMaybe, isNothing)
import Data.Text.Read (decimal)
import Data.Text.Strict.Lens (packed, unpacked)
import Data.Time (getCurrentTime, getZonedTime)
import Data.Time.Format (formatTime)
import qualified Data.Map.Lazy as M (filter, toList)
import qualified Data.Text as T
import qualified Data.Text.IO as T (putStrLn)
import System.Console.Readline (readline)
import System.Directory (getDirectoryContents, getTemporaryDirectory, removeFile)
import System.Environment (getEnvironment)
import System.Exit (ExitCode(ExitSuccess), exitFailure, exitSuccess)
import System.IO (hClose, hGetBuffering, openTempFile)
import System.IO.Error (isDoesNotExistError, isPermissionError)
import System.Locale (defaultTimeLocale)
import System.Process (readProcess)
import System.Random (newStdGen, randomR) -- TODO: Use mwc-random or tf-random. QC uses tf-random.

{-# ANN module ("HLint: ignore Use camelCase" :: String) #-}


-- TODO: "desc" vs. "disp" vs "summarize"?

patternMatchFail :: T.Text -> [T.Text] -> a
patternMatchFail = U.patternMatchFail "Mud.Cmds"


logNotice :: String -> String -> IO ()
logNotice = L.logNotice "Mud.Cmds"


logIOEx :: String -> IOException -> IO ()
logIOEx = L.logIOEx "Mud.Cmds"


logAndDispIOEx :: String -> IOException -> MudStack ()
logAndDispIOEx = L.logAndDispIOEx "Mud.Cmds"


logIOExRethrow :: String -> IOException -> IO ()
logIOExRethrow = L.logIOExRethrow "Mud.Cmds"


logExMsg :: String -> String -> SomeException -> IO ()
logExMsg = L.logExMsg "Mud.Cmds"


-- ==================================================


cmdList :: [Cmd]
cmdList = [ Cmd { cmdName = prefixWizCmd "?", action = wizDispCmdList, cmdDesc = "Display this command list." }
          , Cmd { cmdName = prefixWizCmd "buffer", action = wizBuffCheck, cmdDesc = "Confirm the default buffering mode." }
          , Cmd { cmdName = prefixWizCmd "day", action = wizDay, cmdDesc = "Display the current day of week." }
          , Cmd { cmdName = prefixWizCmd "env", action = wizDispEnv, cmdDesc = "Display system environment variables." }
          , Cmd { cmdName = prefixWizCmd "okapi", action = wizMkOkapi, cmdDesc = "Make an okapi." }
          , Cmd { cmdName = prefixWizCmd "shutdown", action = wizShutdown, cmdDesc = "Shut down the game server." }
          , Cmd { cmdName = prefixWizCmd "time", action = wizTime, cmdDesc = "Display the current system time." }

          , Cmd { cmdName = [histChar]^.packed, action = histAction, cmdDesc = "Command history." }
          , Cmd { cmdName = [repChar]^.packed, action = rep, cmdDesc = "Repeat the last command." }

          , Cmd { cmdName = "?", action = dispCmdList, cmdDesc = "Display this command list." }
          , Cmd { cmdName = "about", action = about, cmdDesc = "About this MUD server." }
          , Cmd { cmdName = "d", action = go "d", cmdDesc = "Go down." }
          --, Cmd { cmdName = "drop", action = dropAction, cmdDesc = "Drop items on the ground." }
          , Cmd { cmdName = "e", action = go "e", cmdDesc = "Go east." }
          --, Cmd { cmdName = "equip", action = equip, cmdDesc = "Readied equipment." }
          , Cmd { cmdName = "exits", action = exits, cmdDesc = "Display obvious exits." }
          , Cmd { cmdName = "get", action = getAction, cmdDesc = "Pick items up off the ground." }
          , Cmd { cmdName = "help", action = help, cmdDesc = "Get help on a topic or command." }
          , Cmd { cmdName = "inv", action = inv, cmdDesc = "Inventory." }
          --, Cmd { cmdName = "look", action = look, cmdDesc = "Look." }
          , Cmd { cmdName = "motd", action = motd, cmdDesc = "Display the message of the day." }
          , Cmd { cmdName = "n", action = go "n", cmdDesc = "Go north." }
          , Cmd { cmdName = "ne", action = go "ne", cmdDesc = "Go northeast." }
          , Cmd { cmdName = "nw", action = go "nw", cmdDesc = "Go northwest." }
          --, Cmd { cmdName = "put", action = putAction, cmdDesc = "Put items in a container." }
          , Cmd { cmdName = "quit", action = quit, cmdDesc = "Quit." }
          --, Cmd { cmdName = "ready", action = ready, cmdDesc = "Ready items." }
          --, Cmd { cmdName = "remove", action = remove, cmdDesc = "Remove items from a container." }
          , Cmd { cmdName = "s", action = go "s", cmdDesc = "Go south." }
          , Cmd { cmdName = "se", action = go "se", cmdDesc = "Go southeast." }
          , Cmd { cmdName = "sw", action = go "sw", cmdDesc = "Go southwest." }
          , Cmd { cmdName = "u", action = go "u", cmdDesc = "Go up." }
          --, Cmd { cmdName = "unready", action = unready, cmdDesc = "Unready items." }
          , Cmd { cmdName = "uptime", action = uptime, cmdDesc = "Display game server uptime." }
          , Cmd { cmdName = "w", action = go "w", cmdDesc = "Go west." } ]
          --, Cmd { cmdName = "what", action = what, cmdDesc = "Disambiguate an abbreviation." } ]


prefixWizCmd :: T.Text -> T.Text
prefixWizCmd = ([wizChar]^.packed <>)


gameWrapper :: MudStack ()
gameWrapper = (initAndStart `catch` topLvlExHandler) `finally` closeLogs
  where
    initAndStart = do
        initLogging
        liftIO . logNotice "gameWrapper" $ "server started"
        initWorld >> liftIO newLine
        dispTitle >> liftIO newLine
        motd []   >> liftIO newLine
        game


topLvlExHandler :: SomeException -> MudStack ()
topLvlExHandler e = let oops msg = liftIO $ logExMsg "topLvlExHandler" msg e >> exitFailure
                    in case fromException e of
                      Just ExitSuccess -> liftIO . logNotice "topLvlExHandler" $ "exiting normally"
                      Just _           -> oops $ dblQuoteStr "ExitFailure" ++ " caught by the top level handler; rethrowing"
                      Nothing          -> oops "exception caught by the top level handler; exiting gracefully"


dispTitle :: MudStack ()
dispTitle = liftIO newStdGen >>= \g ->
    let range = (1, noOfTitles)
        n     = randomR range g^._1
        fn    = "title"^.unpacked ++ show n
    in (try . liftIO . takeADump $ fn) >>= either (liftIO . dispTitleExHandler) return
  where
    takeADump = dumpFileNoWrapping . (++) titleDir


dispTitleExHandler :: IOException -> IO ()
dispTitleExHandler e
  | isDoesNotExistError e = logIOEx "dispTitle" e
  | isPermissionError   e = logIOEx "dispTitle" e
  | otherwise             = logIOExRethrow "dispTitle" e


game :: MudStack ()
game = do
    ms <- liftIO . readline $ "> "
    let t = ms^.to fromJust.packed.to T.strip
    when (T.null t) game
    saveToHist t
    handleInp t
  where
    saveToHist t = do
        cs <- gets (^.hist.cmds)
        if length cs == histSize
          then hist.overflow .= last cs >> hist.cmds .= t : init cs
          else hist.cmds .= t : cs


handleInp :: T.Text -> MudStack ()
handleInp = maybe game dispatch . splitInp


splitInp :: T.Text -> Maybe Input
splitInp = splitUp . T.words
  where
    splitUp []     = Nothing
    splitUp [t]    = Just (t, [])
    splitUp (t:ts) = Just (t, ts)


dispatch :: Input -> MudStack ()
dispatch (cn, rest) = findAction cn >>= maybe (output "What?") (\act -> act rest) >> game


findAction :: CmdName -> MudStack (Maybe Action)
findAction cn = do
    cmdList' <- getPCRmId >>= mkCmdListWithRmLinks
    let cns = map cmdName cmdList'
    maybe (return Nothing)
          (\fn -> return . Just . findActionForFullName fn $ cmdList')
          (findFullNameForAbbrev (T.toLower cn) cns)
  where
    findActionForFullName fn = action . head . filter ((== fn) . cmdName)


mkCmdListWithRmLinks :: Id -> MudStack [Cmd]
mkCmdListWithRmLinks i = getRmLinks i >>= \rls ->
    return (cmdList ++ [ mkCmdForRmLink rl | rl <- rls, rl^.linkName `notElem` stdLinkNames ])
  where
    mkCmdForRmLink rl = let ln = rl^.linkName.to T.toLower
                        in Cmd { cmdName = ln, action = go ln, cmdDesc = "" }


-- ==================================================
-- Player commands:


about :: Action
about [] = (try . liftIO $ takeADump) >>= either (dumpExHandler "about") return
  where
    takeADump = dumpFile . (++) miscDir $ "about"
about rs = ignore rs >> about []


dumpExHandler :: String -> IOException -> MudStack ()
dumpExHandler fn e = liftIO handleThat >> dispGenericErrorMsg
  where
    handleThat
      | isDoesNotExistError e = logIOEx fn e
      | isPermissionError   e = logIOEx fn e
      | otherwise             = logIOExRethrow fn e


-----


motd :: Action
motd [] = (try . liftIO $ takeADump) >>= either (dumpExHandler "motd") return
  where
    takeADump = dumpFileWithDividers . (++) miscDir $ "motd"
motd rs = ignore rs >> motd []


-----


dispCmdList :: Action
dispCmdList []     = mapM_ (outputIndent 10) . cmdListText $ plaCmdPred
dispCmdList [r]    = mapM_ (outputIndent 10) . grepTextList r . cmdListText $ plaCmdPred
dispCmdList (r:rs) = dispCmdList [r] >> liftIO newLine >> dispCmdList rs


cmdListText :: (Cmd -> Bool) -> [T.Text]
cmdListText p = sort . T.lines . T.concat . foldl' mkTxtForCmd [] . filter p $ cmdList
  where
    mkTxtForCmd acc c = T.concat [ padOrTrunc 10 . cmdName $ c, cmdDesc c, "\n" ] : acc


plaCmdPred :: Cmd -> Bool
plaCmdPred = (/=) wizChar . T.head . cmdName


-----


help :: Action
help []     = (try . liftIO $ takeADump) >>= either (dumpExHandler "help") return
  where
    takeADump = dumpFile . (++) helpDir $ "root"
help [r]    = dispHelpTopicByName r
help (r:rs) = help [r] >> liftIO newLine >> help rs


dispHelpTopicByName :: HelpTopic -> MudStack ()
dispHelpTopicByName r = (liftIO . getDirectoryContents $ helpDir) >>= \fns ->
    let fns' = tail . tail . sort . delete "root" $ fns
        tns  = fns'^..folded.packed
    in maybe (liftIO sorry)
             ((try . liftIO . takeADump) >=> either (dumpExHandler "dispHelpTopicByName") return)
             (findFullNameForAbbrev r tns)
  where
    sorry     = mapM_ T.putStrLn . wordWrap cols $ "No help is available on that topic/command."
    takeADump = dumpFile . (++) helpDir . T.unpack


-----


rep :: Action
rep [] = gets (^.hist.cmds) >>= \cs ->
    case cs of [_] -> output "Your command history is empty." >> game
               _   -> let lastCmd = head . tail $ cs
                      in hist.cmds .= lastCmd : tail cs >> handleInp lastCmd
rep rs = ignore rs >> rep []


-----


histAction :: Action
histAction []   = dispHist
histAction [r]  = do
    cs <- gets (^.hist.cmds)
    o  <- gets (^.hist.overflow)
    let cs' = (if isMaxHist cs then o else "") : reverse cs
    case decimal r of Right (x, "") | isValidIndex x cs -> let c = cs' !! if isMaxHist cs then x - 1 else x
                                                           in hist.cmds .= c : tail cs >> output (dblQuote c) >> handleInp c
                                    | otherwise         -> sorry . showText $ x
                      _                                 -> sorry r
  where
    isMaxHist cs = length cs == histSize
    isValidIndex x cs = x > 0 && x <= length cs && x <= histSize
    sorry x = output $ dblQuote x <> " is not a valid index of your command history."
histAction (r:rs) = ignore rs >> histAction [r]


dispHist :: MudStack ()
dispHist = gets (^.hist.cmds) >>= \cs ->
    mapM_ disp (zip [1..] . reverse $ cs)
  where
    disp :: (Int, T.Text) -> MudStack ()
    disp (n, t) = let paddedNumText = padOrTrunc 4 . showText $ n
                  in outputIndent 4 $ paddedNumText <> t


ignore :: Rest -> MudStack ()
ignore rs = let ignored = dblQuote . T.unwords $ rs
            in output ("(Ignoring " <> ignored <> "...)")


-----

{-
what :: Action
what []      = advise ["what"] $ "Please specify one or more abbreviations to confirm, as in " <> dblQuote "what up" <> "."
what [r]     = whatCmd >> whatInv PCInv r >> whatInv PCEq r >> whatInv RmInv r
  where
    whatCmd  = (findFullNameForAbbrev (T.toLower r) <$> cs) >>= maybe notFound found
    cs       = filter ((/=) wizChar . T.head) <$> map cmdName <$> (getPCRmId >>= mkCmdListWithRmLinks)
    notFound = output $ dblQuote r <> " doesn't refer to any commands."
    found cn = outputCon [ dblQuote r, " may refer to the ", dblQuote cn, " command." ]
what (r:rs)  = what [r] >> liftIO newLine >> what rs
-}

advise :: [HelpTopic] -> T.Text -> MudStack ()
advise []  msg = output msg
advise [h] msg = output msg >> output ("Type " <> dblQuote ("help " <> h) <> " for more information.")
advise hs  msg = output msg >> output ("See also the following help topics: " <> helpTopics <> ".")
  where
    helpTopics = dblQuote . T.intercalate (dblQuote ", ") $ hs

{-
whatInv :: InvType -> T.Text -> MudStack ()
whatInv it r = do
    is   <- getLocInv
    gecr <- getEntsCoinsByName r is
    case gecr of
      (Mult _ n (Just es) _) | n == acp  -> output $ dblQuote acp <> " may refer to everything" <> locName
                             | otherwise ->
                               let e   = head es
                                   len = length es
                               in if len > 1
                                 then let ebgns  = take len [ getEntBothGramNos e' | e' <- es ]
                                          h      = head ebgns
                                          target = if all (== h) ebgns then mkPlurFromBoth h else e^.name.to bracketQuote <> "s"
                                      in outputCon [ dblQuote r, " may refer to the ", showText len, " ", target, locName ]
                                 else getEntNamesInInv is >>= \ens ->
                                     outputCon [ dblQuote r, " may refer to the ", checkFirst e ens ^.packed, e^.sing, locName ]
      (Indexed x _ (Right e)) -> outputCon [ dblQuote r, " may refer to the ", mkOrdinal x, " ", e^.name.to bracketQuote, " ", e^.sing.to parensQuote, locName ]
      _                       -> output $ dblQuote r <> " doesn't refer to anything" <> locName
  where
    getLocInv = case it of PCInv -> getInv 0
                           PCEq  -> getEq  0
                           RmInv -> fst <$> getPCRmInvCoins
    acp       = [allChar]^.packed
    locName   = case it of PCInv -> " in your inventory."
                           PCEq  -> " in your readied equipment."
                           RmInv -> " in this room."
    checkFirst e ens = let matches = filter (== e^.name) ens
                       in guard (length matches > 1) >> ("first "^.unpacked)
-}

-----


go :: T.Text -> Action
go dir [] = goDispatcher [dir]
go dir rs = goDispatcher $ dir : rs


goDispatcher :: Action
goDispatcher []     = return ()
goDispatcher [r]    = tryMove r
goDispatcher (r:rs) = tryMove r >> liftIO newLine >> goDispatcher rs


tryMove :: T.Text -> MudStack ()
tryMove dir = let dir' = T.toLower dir
              in getPCRmId >>= findExit dir' >>= maybe (sorry dir') movePC
  where
    sorry dir' = output $ if dir' `elem` stdLinkNames
                            then "You can't go that way."
                            else dblQuote dir <> " is not a valid direction."
    movePC i = pc.rmId .= i -- >> look [] -- TODO: Reinstate.


-----

{-
look :: Action
look [] = do
    getPCRm >>= \r -> output $ r^.name <> "\n" <> r^.desc
    exits []
    getPCRmInvCoins >>= dispRmInvCoins
look [r]    = getPCRmInvCoins >>= getEntsCoinsByName r >>= procGetEntsCoinsResRm >>= traverse_ (mapM_ descEnt)
look (r:rs) = look [r] >> look rs
-}

dispRmInvCoins :: InvCoins -> MudStack ()
dispRmInvCoins (is, c) = mkNameCountBothList is >>= mapM_ descEntInRm >> maybeSummarizeCoins
  where
    descEntInRm (en, c, (s, _))
      | c == 1 = outputIndent 2 $ aOrAn s <> " " <> bracketQuote en
    descEntInRm (en, c, b) = outputConIndent 2 [ showText c, " ", mkPlurFromBoth b, " ", bracketQuote en ]
    maybeSummarizeCoins    = when (c /= noCoins) (summarizeCoins c)


mkNameCountBothList :: Inv -> MudStack [(T.Text, Int, BothGramNos)]
mkNameCountBothList is = do
    ens <- getEntNamesInInv is
    ebgns <- getEntBothGramNosInInv is
    let cs = mkCountList ebgns
    return (nub . zip3 ens cs $ ebgns)


descEnt :: Ent -> MudStack ()
descEnt e = do
    e^.desc.to output
    t <- getEntType e
    when (t == ConType) $ descInvCoins i
    when (t == MobType) $ descEq i
  where
    i = e^.entId


descInvCoins :: Id -> MudStack ()
descInvCoins i = do
    hi <- hasInv   i
    hc <- hasCoins i
    case (hi, hc) of
      (False, False) -> if i == 0
                          then dudeYourHandsAreEmpty
                          else getEnt i >>= \e -> output $ "The " <> e^.sing <> " is empty."
      (True,  False) -> header >> descEntsInInv i
      (False, True ) -> header >> summarizeCoinsInInv
      (True,  True ) -> header >> descEntsInInv i >> summarizeCoinsInInv
  where
    header
      | i == 0 = output "You are carrying:"
      | otherwise = getEnt i >>= \e -> output $ "The " <> e^.sing <> " contains:"
    summarizeCoinsInInv = getCoins i >>= summarizeCoins


dudeYourHandsAreEmpty :: MudStack ()
dudeYourHandsAreEmpty = output "You aren't carrying anything."


descEntsInInv :: Id -> MudStack ()
descEntsInInv i = getInv i >>= mkNameCountBothList >>= mapM_ descEntInInv
  where
    descEntInInv (en, c, (s, _))
      | c == 1 = outputIndent ind $ nameCol en <> "1 " <> s
    descEntInInv (en, c, b) = outputConIndent ind [ nameCol en, showText c, " ", mkPlurFromBoth b ]
    nameCol = bracketPad ind
    ind     = 11


summarizeCoins :: Coins -> MudStack ()
summarizeCoins c = dispCoinsNameAmtList mkCoinsNameAmtList
  where
    dispCoinsNameAmtList     = output . T.intercalate ", " . filter (not . T.null) . map descCoinsNameAmt
    descCoinsNameAmt (cn, a) = if a == 0 then "" else showText a <> " " <> bracketQuote cn
    mkCoinsNameAmtList       = zip coinNames . mkCoinsAmtList $ c


-----


exits :: Action
exits [] = map (^.linkName) <$> (getPCRmId >>= getRmLinks) >>= \rlns ->
    let stdNames    = [ sln | sln <- stdLinkNames, sln `elem` rlns ]
        customNames = filter (`notElem` stdLinkNames) rlns
    in output . (<>) "Obvious exits: " . T.intercalate ", " . (++) stdNames $ customNames
exits rs = ignore rs >> exits []


-----


inv :: Action -- TODO: Give some indication of encumberance.
inv [] = descInvCoins 0
inv rs = do
    (gecrs, miss, gcr) <- getInvCoins 0 >>= resolveEntCoinNames rs
    mapM_ (procGecrMisPCInv descEnts) . zip gecrs $ miss
    procGcrPCInv descCoins gcr
  where
    descEnts :: Inv -> MudStack ()
    descEnts = mapM_ (\i -> getEnt i >>= descEnt >> liftIO newLine)
    {-descEnts []     = return () -- TODO: I bet there's other code similar to this that can simply be rewritten as a monadic map.
    descEnts [i]    = getEnt i >>= descEnt >> liftIO newLine
    descEnts (i:is) = descEnts [i] >> descEnts is-}


procGecrMisPCInv :: (Inv -> MudStack ()) -> (GetEntsCoinsRes, Maybe Inv) -> MudStack ()
procGecrMisPCInv _ (_,                     Just []) = return () -- Nothing left after eliminating duplicate IDs. -- TODO: Put this comment wherever appropriate.
procGecrMisPCInv _ (Mult 1 n Nothing  _,   Nothing) = output $ "You don't have " <> aOrAn n <> "."
procGecrMisPCInv _ (Mult _ n Nothing  _,   Nothing) = output $ "You don't have any " <> n <> "s."
procGecrMisPCInv f (Mult _ _ (Just _) _,   Just is) = f is
procGecrMisPCInv _ (Indexed _ n (Left ""), Nothing) = output $ "You don't have any " <> n <> "s."
procGecrMisPCInv _ (Indexed x _ (Left p),  Nothing) = outputCon [ "You don't have ", showText x, " ", p, "." ]
procGecrMisPCInv f (Indexed _ _ (Right _), Just is) = f is
procGecrMisPCInv _ (SorryIndexedCoins,     Nothing) = sorryIndexedCoins
procGecrMisPCInv _ (Sorry n,               Nothing) = output $ "You don't have " <> aOrAn n <> "."
procGecrMisPCInv _ gecrMis = patternMatchFail "procGecrMisPCInv" [ showText gecrMis ]


sorryIndexedCoins :: MudStack ()
sorryIndexedCoins = output $ "Sorry, but " <> dblQuote ([indexChar]^.packed) <> " cannot be used with coins."


procGcrPCInv :: (Coins -> MudStack ()) -> GetCoinsRes -> MudStack ()
procGcrPCInv f (cpRes, spRes, gpRes) = do
    mcp <- helper cpRes "copper pieces"
    msp <- helper spRes "silver pieces"
    mgp <- helper gpRes "gold pieces"
    f (fromMaybe 0 mcp, fromMaybe 0 msp, fromMaybe 0 mgp) -- TODO: Is there a nifty way to do this using lenses?
  where
    helper res cn = case res of
      (Left (actual, requested)) -> if actual == 0
                                      then output ("You don't have any " <> cn <> ".")                       >> return Nothing
                                      else outputCon [ "You don't have ", showText requested, " ", cn, "." ] >> return Nothing
      (Right requested)          -> return (Just requested)


descCoins :: Coins -> MudStack ()
descCoins (cop, sil, gol) = descCop >> descSil >> descGol -- TODO: Is there a nifty way to do this using lenses?
  where -- TODO: Come up with good descriptions.
    descCop = unless (cop == 0) (output "The copper piece is round and shiny." >> liftIO newLine)
    descSil = unless (sil == 0) (output "The silver piece is round and shiny." >> liftIO newLine)
    descGol = unless (gol == 0) (output "The gold piece is round and shiny."   >> liftIO newLine)


-----

{-
equip :: Action
equip []     = descEq 0
equip [r]    = getEq 0 >>= getEntsCoinsByName r >>= procGetEntsCoinsResPCInv >>= traverse_ (mapM_ descEnt)
equip (r:rs) = equip [r] >> equip rs
-}

descEq :: Id -> MudStack ()
descEq i = (mkEqDescList . mkSlotNameToIdList . M.toList =<< getEqMap i) >>= \edl ->
    if null edl then none else header >> forM_ edl (outputIndent 15)
  where
    mkSlotNameToIdList    = map (first pp)
    mkEqDescList          = mapM descEqHelper
    descEqHelper (sn, i') = let slotName = parensPad 15 noFinger
                                noFinger = T.breakOn " finger" sn ^._1
                            in getEnt i' >>= \e ->
                                return (T.concat [ slotName, e^.sing, " ", e^.name.to bracketQuote ])
    none
      | i == 0    = dudeYou'reNaked
      | otherwise = getEnt i >>= \e -> output $ "The " <> e^.sing <> " doesn't have anything readied."
    header
      | i == 0    = output "You have readied the following equipment:"
      | otherwise = getEnt i >>= \e -> output $ "The " <> e^.sing <> " has readied the following equipment:"


dudeYou'reNaked :: MudStack ()
dudeYou'reNaked = output "You don't have anything readied. You're naked!"


-----


getAction :: Action
getAction [] = advise ["get"] $ "Please specify one or more items to pick up, as in " <> dblQuote "get sword" <> "."
getAction rs = do
    (gecrs, miss, gcr) <- getPCRmInvCoins >>= resolveEntCoinNames rs
    mapM_ (procGecrMisPCInv shuffleInvGet) . zip gecrs $ miss -- TODO: Use "procGecrMisPCRm" instead of "procGecrMisPCInv".
    procGcrPCInv shuffleCoinsGet gcr  -- TODO: Use "procGcrPCRm" instead of "procGcrPCInv".


shuffleInvGet :: Inv -> MudStack ()
shuffleInvGet is = getPCRmId >>= \i ->
    moveInv is i 0 >> descGetDropEnts Get is


descGetDropEnts :: GetOrDrop -> Inv -> MudStack ()
descGetDropEnts god is = mkNameCountBothList is >>= mapM_ descGetDropHelper
  where
    descGetDropHelper (_, c, (s, _))
      | c == 1 = outputCon [ "You", verb, "the ", s, "." ]
    descGetDropHelper (_, c, b) = outputCon [ "You", verb, showText c, " ", mkPlurFromBoth b, "." ]
    verb = case god of Get  -> " pick up "
                       Drop -> " drop "


shuffleCoinsGet :: Coins -> MudStack ()
shuffleCoinsGet c = getPCRmId >>= \i ->
    moveCoins c i 0 -- >> descGetDropCoins Get c


-----

{-
dropAction :: Action
dropAction []   = advise ["drop"] $ "Please specify one or more items to drop, as in " <> dblQuote "drop sword" <> "."
dropAction rs = hasInv 0 >>= \hi ->
  if hi
    then getInv 0 >>= resolveEntsCoinsByName rs >>= mapM_ procGecrMisForDrop . uncurry zip
    else dudeYourHandsAreEmpty
-}

procGecrMisForDrop :: (GetEntsCoinsRes, Maybe Inv) -> MudStack ()
procGecrMisForDrop (_,                     Just []) = return ()
procGecrMisForDrop (Sorry n,               Nothing) = output $ "You don't have " <> aOrAn n <> "."
procGecrMisForDrop (Mult 1 n Nothing  _,   Nothing) = output $ "You don't have " <> aOrAn n <> "."
procGecrMisForDrop (Mult _ n Nothing  _,   Nothing) = output $ "You don't have any " <> n <> "s."
procGecrMisForDrop (Mult _ _ (Just _) _,   Just is) = shuffleInvDrop is
procGecrMisForDrop (Indexed _ n (Left ""), Nothing) = output $ "You don't have any " <> n <> "s."
procGecrMisForDrop (Indexed x _ (Left p),  Nothing) = outputCon [ "You don't have ", showText x, " ", p, "." ]
procGecrMisForDrop (Indexed _ _ (Right _), Just is) = shuffleInvDrop is
procGecrMisForDrop gecrMis = patternMatchFail "procGecrMisForDrop" [ showText gecrMis ]


shuffleInvDrop :: Inv -> MudStack ()
shuffleInvDrop is = getPCRmId >>= \i ->
    moveInv is 0 i >> descGetDropEnts Drop is


-----

{-
putAction :: Action
putAction []   = advise ["put"] $ "Please specify what you want to put, followed by where you want to put it, as in " <> dblQuote "put doll sack" <> "."
putAction [r]  = advise ["put"] $ "Please also specify where you want to put it, as in " <> dblQuote ("put " <> r <> " sack") <> "."
putAction rs   = hasInv 0 >>= \hi ->
    if hi then putRemDispatcher Put rs else dudeYourHandsAreEmpty
-}
{-
putRemDispatcher :: PutOrRem -> Action
putRemDispatcher por (r:rs) = findCon (last rs) >>= \mes ->
    case mes of Nothing -> return ()
                Just es -> case es of [e] -> getEntType e >>= \t ->
                                                 if t /= ConType
                                                   then output $ "The " <> e^.sing <> " isn't a container."
                                                   else e^.entId.to dispatchToHelper
                                      _   -> output onlyOneMsg
  where
    findCon cn
      | T.head cn == rmChar = do
          ic <- getPCRmInvCoins
          c  <- getPCRmId >>= getCoins
          getEntsCoinsByName (T.tail cn) ic >>= procGetEntsCoinsResRm
      | otherwise = do
          is <- getInv 0
          c  <- getCoins 0
          getEntsCoinsByName cn is c >>= procGetEntsCoinsResPCInv
    onlyOneMsg         = case por of Put -> "You can only put things into one container at a time."
                                     Rem -> "You can only remove things from one container at a time."
    dispatchToHelper i = case por of Put -> putHelper i restWithoutCon 
                                     Rem -> remHelper i restWithoutCon
    restWithoutCon = r : init rs
putRemDispatcher por rs = patternMatchFail "putRemDispatcher" [ showText por, showText rs ]
-}
{-
putHelper :: Id -> Rest -> MudStack ()
putHelper _  []   = return ()
putHelper ci (rs) = getPCRmInvCoins >>= resolveEntsCoinsByName rs >>= mapM_ (procGecrMisForPut ci) . uncurry zip
-}

procGecrMisForPut :: Id -> (GetEntsCoinsRes, Maybe Inv) -> MudStack ()
procGecrMisForPut _  (_,                     Just []) = return ()
procGecrMisForPut _  (Sorry n,               Nothing) = output $ "You don't have " <> aOrAn n <> "."
procGecrMisForPut _  (Mult 1 n Nothing  _,   Nothing) = output $ "You don't have " <> aOrAn n <> "."
procGecrMisForPut _  (Mult _ n Nothing  _,   Nothing) = output $ "You don't have any " <> n <> "s."
procGecrMisForPut ci (Mult _ _ (Just _) _,   Just is) = shuffleInvPut ci is
procGecrMisForPut _  (Indexed _ n (Left ""), Nothing) = output $ "You don't have any " <> n <> "s."
procGecrMisForPut _  (Indexed x _ (Left p),  Nothing) = outputCon [ "You don't have ", showText x, " ", p, "." ]
procGecrMisForPut ci (Indexed _ _ (Right _), Just is) = shuffleInvPut ci is
procGecrMisForPut ci gecrMis = patternMatchFail "procGecrMisForPut" [ showText ci, showText gecrMis ]


shuffleInvPut :: Id -> Inv -> MudStack ()
shuffleInvPut ci is = do
    cn <- (^.sing) <$> getEnt ci
    is' <- checkImplosion cn
    moveInv is' 0 ci
    descPutRem Put is' cn
  where
    checkImplosion cn = if ci `elem` is
                          then output ("You can't put the " <> cn <> " inside itself.") >> return (filter (/= ci) is)
                          else return is


descPutRem :: PutOrRem -> Inv -> ConName -> MudStack ()
descPutRem por is cn = mkNameCountBothList is >>= mapM_ descPutRemHelper
  where
    descPutRemHelper (_, c, (s, _))
      | c == 1                    = outputCon [ "You", verb, "the ", s, prep, cn, "." ]
    descPutRemHelper (_, c, b) = outputCon [ "You", verb, showText c, " ", mkPlurFromBoth b, prep, cn, "." ]
    verb = case por of Put -> " put "
                       Rem -> " remove "
    prep = case por of Put -> " in the "
                       Rem -> " from the "


-----

{-
remove :: Action
remove []  = advise ["remove"] $ "Please specify what you want to remove, followed by the container you want to remove it from, as in " <> dblQuote "remove doll sack" <> "."
remove [r] = advise ["remove"] $ "Please also specify the container you want to remove it from, as in " <> dblQuote ("remove " <> r <> " sack") <> "."
remove rs  = putRemDispatcher Rem rs
-}
{-
remHelper :: Id -> Rest -> MudStack ()
remHelper _  []   = return ()
remHelper ci (rs) = do
    cn <- (^.sing) <$> getEnt ci
    hi <- hasInv ci
    if hi
      then getInv ci >>= resolveEntsCoinsByName rs >>= mapM_ (procGecrMisForRem ci cn) . uncurry zip
      else output $ "The " <> cn <> " appears to be empty."
-}

procGecrMisForRem :: Id -> ConName -> (GetEntsCoinsRes, Maybe Inv) -> MudStack ()
procGecrMisForRem _  _  (_,                     Just []) = return ()
procGecrMisForRem _  cn (Sorry n,               Nothing) = outputCon [ "The ", cn, " doesn't contain ", aOrAn n, "." ]
procGecrMisForRem _  cn (Mult 1 n Nothing  _,   Nothing) = outputCon [ "The ", cn, " doesn't contain ", aOrAn n, "." ]
procGecrMisForRem _  cn (Mult _ n Nothing  _,   Nothing) = outputCon [ "The ", cn, " doesn't contain any ", n, "s." ] 
procGecrMisForRem ci cn (Mult _ _ (Just _) _,   Just is) = shuffleInvRem ci cn is
procGecrMisForRem _  cn (Indexed _ n (Left ""), Nothing) = outputCon [ "The ", cn, " doesn't contain any ", n, "s." ] 
procGecrMisForRem _  cn (Indexed x _ (Left p),  Nothing) = outputCon [ "The ", cn, " doesn't contain ", showText x, " ", p, "." ]
procGecrMisForRem ci cn (Indexed _ _ (Right _), Just is) = shuffleInvRem ci cn is
procGecrMisForRem ci cn gecrMis = patternMatchFail "procGecrMisForRem" [ showText ci, showText cn, showText gecrMis ]


shuffleInvRem :: Id -> ConName -> Inv -> MudStack ()
shuffleInvRem ci cn is = moveInv is ci 0 >> descPutRem Rem is cn


-----

{-
ready :: Action
ready []   = advise ["ready"] $ "Please specify one or more things to ready, as in " <> dblQuote "ready sword" <> "."
ready (rs) = hasInv 0 >>= \hi -> if not hi then dudeYourHandsAreEmpty else do
    is  <- getInv 0
    res <- mapM (`getEntsToReadyByName` is) rs
    let gecrs  = res^..folded._1
    let mrols = res^..folded._2
    mesmcs <- mapM gecrToMesmc gecrs
    let misList = pruneDupIds [] $ (fmap . fmap . fmap) (^.entId) mesmcs
    mapM_ procGecrMisMrolForReady $ zip3 gecrs misList mrols
-}
{-
getEntsToReadyByName :: T.Text -> Inv -> MudStack (GetEntsCoinsRes, Maybe RightOrLeft)
getEntsToReadyByName searchName is
  | slotChar `elem` searchName^.unpacked = let (a, b) = T.break (== slotChar) searchName
                                           in if T.length b == 1 then sorry else do
                                               gecr <- getEntsCoinsByName a is
                                               let parsed = reads (b^..unpacked.dropping 1 (folded.to toUpper)) :: [(RightOrLeft, String)]
                                               case parsed of [(rol, _)] -> return (gecr, Just rol)
                                                              _          -> sorry
  | otherwise = getEntsCoinsByName searchName is >>= \gecr -> return (gecr, Nothing)
  where
    sorry = return (Sorry searchName, Nothing)
-}

procGecrMisMrolForReady :: (GetEntsCoinsRes, Maybe Inv, Maybe RightOrLeft) -> MudStack ()
procGecrMisMrolForReady (_,                     Just [], _)    = return ()
procGecrMisMrolForReady (Sorry n,               Nothing, _)    = sorryCantReady n
procGecrMisMrolForReady (Mult 1 n Nothing  _,   Nothing, _)    = output $ "You don't have " <> aOrAn n <> "."
procGecrMisMrolForReady (Mult _ n Nothing  _,   Nothing, _)    = output $ "You don't have any " <> n <> "s."
procGecrMisMrolForReady (Mult _ _ (Just _) _,   Just is, mrol) = readyDispatcher mrol is
procGecrMisMrolForReady (Indexed _ n (Left ""), Nothing, _)    = output $ "You don't have any " <> n <> "s."
procGecrMisMrolForReady (Indexed x _ (Left p),  Nothing, _)    = outputCon [ "You don't have ", showText x, " ", p, "." ]
procGecrMisMrolForReady (Indexed _ _ (Right _), Just is, mrol) = readyDispatcher mrol is
procGecrMisMrolForReady gecrMisMrol = patternMatchFail "procGecrMisMrolForReady" [ showText gecrMisMrol ]


sorryCantReady :: T.Text -> MudStack ()
sorryCantReady n
  | slotChar `elem` n^.unpacked = outputCon [ "Please specify ", dblQuote "r", " or ", dblQuote "l", ".\n", ringHelp ]
  | otherwise = output $ "You don't have " <> aOrAn n <> "."


ringHelp :: T.Text
ringHelp = T.concat [ "For rings, specify ", dblQuote "r", " or ", dblQuote "l", " immediately followed by:\n"
                    , dblQuote "i", " for index finger,\n"
                    , dblQuote "m", " for middle finter,\n"
                    , dblQuote "r", " for ring finger,\n"
                    , dblQuote "p", " for pinky finger." ]


readyDispatcher :: Maybe RightOrLeft -> Inv -> MudStack ()
readyDispatcher mrol = mapM_ dispatchByType
  where
    dispatchByType i = do
        e <- getEnt i
        em <- getEqMap 0
        t <- getEntType e
        case t of ClothType -> getCloth i >>= \c -> readyCloth i e c em mrol
                  WpnType   -> readyWpn i e em mrol
                  _         -> output $ "You can't ready a " <> e^.sing <> "."


-- Helpers for the entity type-specific ready functions:


moveReadiedItem :: Id -> EqMap -> Slot -> MudStack ()
moveReadiedItem i em s = eqTbl.at 0 ?= (em & at s ?~ i) >> remFromInv [i] 0


otherGender :: Gender -> Gender
otherGender Male     = Female
otherGender Female   = Male
otherGender NoGender = NoGender


otherHand :: Hand -> Hand
otherHand RHand  = LHand
otherHand LHand  = RHand
otherHand NoHand = NoHand


isRingRol :: RightOrLeft -> Bool
isRingRol rol = case rol of R -> False
                            L -> False
                            _ -> True


rEarSlots, lEarSlots, noseSlots, neckSlots, rWristSlots, lWristSlots :: [Slot]
rEarSlots   = [REar1S, REar2S]
lEarSlots   = [LEar1S, LEar2S]
noseSlots   = [Nose1S, Nose2S]
neckSlots   = [Neck1S   .. Neck3S]
rWristSlots = [RWrist1S .. RWrist3S]
lWristSlots = [LWrist1S .. LWrist3S]


isSlotAvail :: EqMap -> Slot -> Bool
isSlotAvail em s = isNothing $ em^.at s


findAvailSlot :: EqMap -> [Slot] -> Maybe Slot
findAvailSlot em = find (isSlotAvail em)


sorryFullClothSlots :: Cloth -> MudStack ()
sorryFullClothSlots c = output $ "You can't wear any more " <> whatWhere
  where
    whatWhere = flip (<>) "." $ case c of EarC      -> aoy <> "ears"
                                          NoseC     -> "rings on your nose"
                                          NeckC     -> aoy <> "neck"
                                          WristC    -> aoy <> "wrists"
                                          FingerC   -> aoy <> "fingers"
                                          UpBodyC   -> coy <> "torso"
                                          LowBodyC  -> coy <> "legs"
                                          FullBodyC -> "clothing about your body"
                                          BackC     -> "on your back"
                                          FeetC     -> "footwear on your feet"
    aoy = "accessories on your "
    coy = "clothing on your "


sorryFullClothSlotsOneSide :: Slot -> MudStack ()
sorryFullClothSlotsOneSide s = output $ "You can't wear any more on your " <> pp s <> "."


-- Ready clothing:


readyCloth :: Int -> Ent -> Cloth -> EqMap -> Maybe RightOrLeft -> MudStack ()
readyCloth i e c em mrol = maybe (getAvailClothSlot c em) (getDesigClothSlot e c em) mrol >>= \ms ->
    maybe (return ())
          (\s -> moveReadiedItem i em s >> readiedMsg s)
          ms
  where
    readiedMsg s = case c of NoseC   -> putOnMsg
                             NeckC   -> putOnMsg
                             FingerC -> outputCon [ "You slide the ", e^.sing, " on your ", pp s, "." ]
                             _       -> wearMsg
      where
        putOnMsg = output $ "You put on the " <> e^.sing <> "."
        wearMsg  = outputCon [ "You wear the ",  e^.sing, " on your ", pp s, "." ]


getDesigClothSlot :: Ent -> Cloth -> EqMap -> RightOrLeft -> MudStack (Maybe Slot)
getDesigClothSlot e c em rol
  | c `elem` [NoseC, NeckC, UpBodyC, LowBodyC, FullBodyC, BackC, FeetC] = sorryCantWearThere
  | isRingRol rol && c /= FingerC           = sorryCantWearThere
  | c == FingerC && (not . isRingRol $ rol) = sorryNeedRingRol
  | otherwise = case c of EarC    -> maybe sorryFullEar   (return . Just) (findSlotFromList rEarSlots   lEarSlots)
                          WristC  -> maybe sorryFullWrist (return . Just) (findSlotFromList rWristSlots lWristSlots)
                          FingerC -> maybe (return (Just slotFromRol))
                                           (getEnt >=> sorry slotFromRol)
                                           (em^.at slotFromRol)
                          _       -> undefined -- TODO
  where
    sorryCantWearThere     = outputCon [ "You can't wear a ", e^.sing, " on your ", pp rol, "." ] >> return Nothing
    sorryNeedRingRol       = output ringHelp >> return Nothing
    findSlotFromList rs ls = findAvailSlot em $ case rol of R -> rs
                                                            L -> ls
                                                            _ -> patternMatchFail "getDesigClothSlot findSlotFromList" [ showText rol ]
    getSlotFromList rs ls  = head $ case rol of R -> rs
                                                L -> ls
                                                _ -> patternMatchFail "getDesigClothSlot getSlotFromList" [ showText rol ]
    sorryFullEar     = sorryFullClothSlotsOneSide (getSlotFromList rEarSlots   lEarSlots)          >> return Nothing
    sorryFullWrist   = sorryFullClothSlotsOneSide (getSlotFromList rWristSlots lWristSlots)        >> return Nothing
    slotFromRol      = fromRol rol :: Slot
    sorry s e'       = outputCon [ "You're already wearing a ", e'^.sing, " on your ", pp s, "." ] >> return Nothing


getAvailClothSlot :: Cloth -> EqMap -> MudStack (Maybe Slot)
getAvailClothSlot c em = do
    s <- getMobGender 0
    h <- getMobHand 0
    case c of EarC    -> procMaybe $ getEarSlotForGender s `mplus` (getEarSlotForGender . otherGender $ s)
              NoseC   -> procMaybe $ findAvailSlot em noseSlots
              NeckC   -> procMaybe $ findAvailSlot em neckSlots
              WristC  -> procMaybe $ getWristSlotForHand h `mplus` (getWristSlotForHand . otherHand $ h)
              FingerC -> procMaybe =<< getRingSlotForHand h
              _       -> undefined -- TODO
  where
    procMaybe             = maybe (sorryFullClothSlots c >> return Nothing) (return . Just)
    getEarSlotForGender s    = findAvailSlot em $ case s of Male   -> lEarSlots
                                                            Female -> rEarSlots
                                                            _      -> patternMatchFail "getAvailClothSlot getEarSlotForGender" [ showText s ]
    getWristSlotForHand h = findAvailSlot em $ case h of RHand  -> lWristSlots
                                                         LHand  -> rWristSlots
                                                         _      -> patternMatchFail "getAvailClothSlot getWristSlotForHand" [ showText h ]
    getRingSlotForHand h  = getMobGender 0 >>= \s ->
        return (findAvailSlot em $ case s of Male   -> case h of RHand -> [LRingFS, LIndexFS, RRingFS, RIndexFS, LMidFS, RMidFS, LPinkyFS, RPinkyFS]
                                                                 LHand -> [RRingFS, RIndexFS, LRingFS, LIndexFS, RMidFS, LMidFS, RPinkyFS, LPinkyFS]
                                                                 _     -> patternMatchFail "getAvailClothSlot getRingSlotForHand" [ showText h ]
                                             Female -> case h of RHand -> [LRingFS, LIndexFS, RRingFS, RIndexFS, LPinkyFS, RPinkyFS, LMidFS, RMidFS]
                                                                 LHand -> [RRingFS, RIndexFS, LRingFS, LIndexFS, RPinkyFS, LPinkyFS, RMidFS, LMidFS]
                                                                 _     -> patternMatchFail "getAvailClothSlot getRingSlotForHand" [ showText h ]
                                             _      -> patternMatchFail "getAvailClothSlot getRingSlotForHand" [ showText s ])


-- Ready weapons:


readyWpn :: Id -> Ent -> EqMap -> Maybe RightOrLeft -> MudStack ()
readyWpn i e em mrol
  | not . isSlotAvail em $ BothHandsS = output "You're already wielding a two-handed weapon."
  | otherwise = maybe (getAvailWpnSlot em) (getDesigWpnSlot e em) mrol >>= \ms ->
                    maybe (return ())
                          (\s -> getWpn i >>= readyHelper s)
                          ms
  where
    readyHelper s w = case w^.wpnSub of OneHanded -> moveReadiedItem i em s >> outputCon [ "You wield the ", e^.sing, " with your ", pp s, "." ]
                                        TwoHanded -> if all (isSlotAvail em) [RHandS, LHandS]
                                                       then moveReadiedItem i em BothHandsS >> output ("You wield the " <> e^.sing <> " with both hands.")
                                                       else output $ "Both hands are required to weild the " <> e^.sing <> "."


getDesigWpnSlot :: Ent -> EqMap -> RightOrLeft -> MudStack (Maybe Slot)
getDesigWpnSlot e em rol
  | isRingRol rol = sorryNotRing
  | otherwise     = maybe (return (Just desigSlot)) (getEnt >=> sorry) $ em^.at desigSlot
  where
    sorryNotRing = output ("You can't wield a " <> e^.sing <> " with your finger!") >> return Nothing
    sorry e'     = outputCon [ "You're already wielding a ", e'^.sing, " with your ", pp desigSlot, "." ] >> return Nothing
    desigSlot    = case rol of R -> RHandS
                               L -> LHandS
                               _ -> patternMatchFail "getDesigWpnSlot desigSlot" [ showText rol ]


getAvailWpnSlot :: EqMap -> MudStack (Maybe Slot)
getAvailWpnSlot em = getMobHand 0 >>= \h ->
    maybe sorry (return . Just) (findAvailSlot em . map getSlotForHand $ [ h, otherHand h ])
  where
    getSlotForHand h = case h of RHand -> RHandS
                                 LHand -> LHandS
                                 _     -> patternMatchFail "getAvailWpnSlot getSlotForHand" [ showText h ]
    sorry = output "You're already wielding two weapons." >> return Nothing


-- Ready armor:


-----

{-
unready :: Action
unready [] = advise ["unready"] $ "Please specify one or more things to unready, as in " <> dblQuote "unready sword" <> "."
unready rs = getEq 0 >>= \is ->
    if null is
      then dudeYou'reNaked
      else resolveEntsCoinsByName rs is >>= mapM_ procGecrMisForUnready . uncurry zip
-}

procGecrMisForUnready :: (GetEntsCoinsRes, Maybe Inv) -> MudStack ()
procGecrMisForUnready (_,                     Just []) = return ()
procGecrMisForUnready (Sorry n,               Nothing) = output $ "You don't have " <> aOrAn n <> " among your readied equipment."
procGecrMisForUnready (Mult 1 n Nothing  _,   Nothing) = output $ "You don't have " <> aOrAn n <> " among your readied equipment."
procGecrMisForUnready (Mult _ n Nothing  _,   Nothing) = output $ "You don't have any " <> n <> "s among your readied equipment."
procGecrMisForUnready (Mult _ _ (Just _) _,   Just is) = shuffleInvUnready is
procGecrMisForUnready (Indexed _ n (Left ""), Nothing) = output $ "You don't have any " <> n <> "s among your readied equipment."
procGecrMisForUnready (Indexed x _ (Left p),  Nothing) = outputCon [ "You don't have ", showText x, " ", p, " readied." ]
procGecrMisForUnready (Indexed _ _ (Right _), Just is) = shuffleInvUnready is
procGecrMisForUnready gecrMis = patternMatchFail "procGecrMisForUnready" [ showText gecrMis ]


shuffleInvUnready :: Inv -> MudStack ()
shuffleInvUnready is = M.filter (`notElem` is) <$> getEqMap 0 >>= (eqTbl.at 0 ?=) >> addToInv is 0 >> descUnready is


descUnready :: Inv -> MudStack ()
descUnready is = mkIdCountBothList is >>= mapM_ descUnreadyHelper
  where
    descUnreadyHelper (i, c, b@(s, _)) = verb i >>= \v ->
        outputCon $ if c == 1
          then [ "You ", v, "the ", s, "." ]
          else [ "You ", v, showText c, " ", mkPlurFromBoth b, "." ]
    verb i = getEnt i >>= getEntType >>= \t ->
        case t of ClothType -> getCloth i >>= \_ -> return unwearGenericVerb -- TODO
                  WpnType   -> return "stop wielding "
                  _         -> undefined -- TODO
    unwearGenericVerb = "take off "


mkIdCountBothList :: Inv -> MudStack [(Id, Int, BothGramNos)]
mkIdCountBothList is = getEntBothGramNosInInv is >>= \ebgns ->
    let cs = mkCountList ebgns
    in return (nubBy equalCountsAndBoths . zip3 is cs $ ebgns)
  where
    equalCountsAndBoths (_, c, b) (_, c', b') = c == c' && b == b'


-----


uptime :: Action
uptime [] = (try . output . parse =<< runUptime) >>= either uptimeExHandler return
  where
    runUptime = liftIO . readProcess "uptime" [] $ ""
    parse ut  = let (a, b) = span (/= ',') ut
                    a' = unwords . tail . words $ a
                    b' = dropWhile isSpace . takeWhile (/= ',') . tail $ b
                    c  = (toUpper . head $ a') : tail a'
                in T.concat [ c^.packed, " ", b'^.packed, "." ]
uptime rs = ignore rs >> uptime []


uptimeExHandler :: IOException -> MudStack ()
uptimeExHandler e = (liftIO . logIOEx "uptime" $ e) >> dispGenericErrorMsg


-----


quit :: Action
quit [] = output "Thanks for playing! See you next time." >> liftIO exitSuccess
quit _  = output $ "Type " <> dblQuote "quit" <> " with no arguments to quit the game."


-- ==================================================
-- Wizard commands:


wizDispCmdList :: Action
wizDispCmdList []     = mapM_ (outputIndent 10) . cmdListText $ wizCmdPred
wizDispCmdList [r]    = mapM_ (outputIndent 10) . grepTextList r . cmdListText $ wizCmdPred
wizDispCmdList (r:rs) = wizDispCmdList [r] >> liftIO newLine >> wizDispCmdList rs


wizCmdPred :: Cmd -> Bool
wizCmdPred = (==) wizChar . T.head . cmdName


-----


wizMkOkapi :: Action
wizMkOkapi [] = mkOkapi >>= \i ->
    output $ "Made okapi with id " <> showText i <> "."
wizMkOkapi rs = ignore rs >> wizMkOkapi []


-----


wizBuffCheck :: Action
wizBuffCheck [] = (try . liftIO $ buffCheckHelper) >>= either (logAndDispIOEx "wizBuffCheck") return
  where
    buffCheckHelper = do
        td <- getTemporaryDirectory
        (fn, h) <- openTempFile td "temp"
        bm <- hGetBuffering h
        mapM_ T.putStrLn . wordWrapIndent cols 2 . T.concat $ [ "(Default) buffering mode for temp file ", fn^.packed.to dblQuote, " is ", dblQuote . showText $ bm, "." ]
        hClose h
        removeFile fn
wizBuffCheck rs = ignore rs >> wizBuffCheck []


-----


wizDispEnv :: Action
wizDispEnv []  = liftIO $ getEnvironment >>= dispAssocList
wizDispEnv [r] = liftIO $ dispAssocList . filter grepPair =<< getEnvironment
  where
    grepPair = uncurry (||) . over both (^.packed.to grep)
    grep     = (r `T.isInfixOf`)
wizDispEnv (r:rs) = wizDispEnv [r] >> liftIO newLine >> wizDispEnv rs


-----


wizShutdown :: Action
wizShutdown [] = liftIO $ logNotice "wizShutdown" "shutting down" >> exitSuccess
wizShutdown _  = output $ "Type " <> (dblQuote . prefixWizCmd $ "shutdown") <> " with no arguments to shut down the game server."


-----


wizTime :: Action
wizTime [] = do
    output "At the tone, the time will be..."
    ct <- liftIO getCurrentTime
    zt <- liftIO getZonedTime
    output . formatThat . showText $ ct
    output . formatThat . showText $ zt
  where
    formatThat t = let wordy = T.words t
                       zone  = last wordy
                       date  = head wordy
                       time  = T.init . T.reverse . T.dropWhile (/= '.') . T.reverse . head . tail $ wordy
                   in T.concat [ zone, ": ", date, " ", time ]
wizTime rs = ignore rs >> wizTime []


-----


wizDay :: Action
wizDay [] = liftIO getZonedTime >>= \zt ->
    output $ formatTime defaultTimeLocale "%A %B %d" zt ^.packed
wizDay rs = ignore rs >> wizDay []
