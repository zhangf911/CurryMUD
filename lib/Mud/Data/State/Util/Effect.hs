{-# LANGUAGE LambdaCase, OverloadedStrings #-}

module Mud.Data.State.Util.Effect ( procEffectList
                                  , procInstaEffect ) where

import Mud.Data.Misc
import Mud.Data.State.MudData
import Mud.Data.State.Util.Get
import Mud.Data.State.Util.Misc
import Mud.Data.State.Util.Random
import Mud.Threads.Effect
import Mud.Threads.FeelingTimer
import Mud.Util.Misc
import qualified Mud.Misc.Logging as L (logPla)

import Control.Lens.Operators ((&), (.~), (^.))
import Control.Monad (when)
import Data.Either (partitionEithers)
import Data.Monoid ((<>))
import Data.Text (Text)


logPla :: Text -> Id -> Text -> MudStack ()
logPla = L.logPla "Mud.Data.State.Util.Effect"


-- ==================================================


procEffectList :: Id -> EffectList -> MudStack ()
procEffectList i (EffectList xs) = let (ies, es) = partitionEithers xs
                                   in mapM_ (procInstaEffect i) ies >> mapM_ (startEffect i) es


-----


procInstaEffect :: Id -> InstaEffect -> MudStack ()
procInstaEffect i ie@(InstaEffect sub val feel) = getState >>= \ms -> do
    case sub of
      EntInstaEffectFlags         -> undefined -- TODO
      (MobInstaEffectPts ptsType) -> maybeVoid (effectPts ptsType) val
      RmInstaEffectFlags          -> undefined -- TODO
      (InstaEffectOther fn)       -> getInstaEffectFun fn ms i >> startFeeling i feel NoVal
    logHelper ms
  where
    effectPts ptsType   = (helper ptsType =<<) . \case DefiniteVal x -> return x
                                                       RangeVal    r -> rndmR r
    helper    ptsType x = let (getCur, getMax, setCur) = snd . head . filter ((== ptsType) . fst) $ assocs
                          in do { diff <- modifyState $ \ms -> let curPts = ms^.myMobGet.getCur
                                                                   maxPts = ms^.myMobGet.getMax
                                                                   newPts = (curPts + x) `min` maxPts
                                                                   diff   = newPts - curPts
                                                               in (ms & myMobSet.setCur .~ newPts, diff)
                                ; startFeeling i feel . IntVal $ diff }
    assocs       = [ (CurHp, (curHp, maxHp, curHp))
                   , (CurMp, (curMp, maxMp, curMp))
                   , (CurPp, (curPp, maxPp, curPp))
                   , (CurFp, (curFp, maxFp, curFp)) ]
    myMobGet     = mobTbl.ind i
    myMobSet     = mobTbl.ind i
    logHelper ms = when (getType i ms == PCType) . logPla  "procInstaEffect" i $ "applying instantaneous effect: " <> pp ie
