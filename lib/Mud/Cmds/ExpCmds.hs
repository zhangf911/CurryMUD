{-# OPTIONS_GHC -fno-warn-type-defaults #-}
{-# LANGUAGE NamedFieldPuns, OverloadedStrings, PatternSynonyms, ViewPatterns #-}

module Mud.Cmds.ExpCmds ( expCmdSet
                        , expCmdNames
                        , expCmds
                        , getExpCmdByName
                        , mkExpAction ) where

import Mud.Cmds.Msgs.Advice
import Mud.Cmds.Msgs.Sorry
import Mud.Cmds.Util.Misc
import Mud.Cmds.Util.Pla
import Mud.Data.Misc
import Mud.Data.State.ActionParams.ActionParams
import Mud.Data.State.MudData
import Mud.Data.State.Util.Calc
import Mud.Data.State.Util.Get
import Mud.Data.State.Util.Misc
import Mud.Data.State.Util.Output
import Mud.Data.State.Util.Random
import Mud.Misc.LocPref
import Mud.Util.Misc hiding (patternMatchFail)
import Mud.Util.Operators
import Mud.Util.Quoting
import Mud.Util.Text
import qualified Mud.Misc.Logging as L (logPlaOut)
import qualified Mud.Util.Misc as U (patternMatchFail)

import Control.Arrow ((&&&), first)
import Control.Lens (_3, _4, view)
import Control.Lens.Operators ((&), (.~), (<>~), (?~))
import Control.Monad ((>=>))
import Data.List ((\\), delete)
import Data.Maybe (fromMaybe)
import Data.Monoid ((<>))
import Data.Text (Text)
import qualified Data.Set as S (Set, filter, foldr, fromList, map, toList)
import qualified Data.Text as T
import qualified Data.Vector.Unboxed as V (head)


patternMatchFail :: (Show a) => PatternMatchFail a b
patternMatchFail = U.patternMatchFail "Mud.Cmds.ExpCmds"


-----


logPlaOut :: Text -> Id -> [Text] -> MudStack ()
logPlaOut = L.logPlaOut "Mud.Cmds.ExpCmds"


-- ==================================================


expCmdSet :: S.Set ExpCmd
expCmdSet = S.fromList
    [ ExpCmd "admire"       (HasTarget "You admire @."
                                       "% admires you."
                                       "% admires @.")
                            Nothing Nothing
    , ExpCmd "applaud"      (Versatile "You applaud enthusiastically."
                                       "% applauds enthusiastically."
                                       "You applaud enthusiastically for @."
                                       "% applauds enthusiastically for you."
                                       "% applauds enthusiastically for @.")
                            Nothing Nothing
    , ExpCmd "astonished"   (Versatile "You are absolutely astonished."
                                       "% is absolutely astonished."
                                       "You stare at @ with an astonished expression on your face."
                                       "% stares at you with an astonished expression on & face."
                                       "% stares at @ with an astonished expression on & face.")
                            Nothing Nothing
    , ExpCmd "astounded"    (Versatile "You are altogether astounded."
                                       "% is altogether astounded."
                                       "You are altogether astounded at @."
                                       "% is altogether astounded at you."
                                       "% is altogether astounded at @.")
                            Nothing Nothing
    , ExpCmd "avert"        (Versatile "You avert your eyes."
                                       "% averts & eyes."
                                       "You avert your eyes from @."
                                       "% averts & eyes from you."
                                       "% averts & eyes from @.")
                            Nothing Nothing
    , ExpCmd "barf"         (Versatile "You barf loudly."
                                       "% barfs loudly."
                                       "You loudly barf all over @."
                                       "% loudly barfs all over you."
                                       "% loudly barfs all over @.")
                            (Just vomit) Nothing
    , ExpCmd "bawl"         (NoTarget  "You bawl like a baby."
                                       "% bawls like a baby.")
                            Nothing Nothing
    , ExpCmd "beam"         (Versatile "You beam cheerfully."
                                       "% beams cheerfully."
                                       "You beam cheerfully at @."
                                       "% beams cheerfully at you."
                                       "% beams cheerfully at @.")
                            Nothing Nothing
    , ExpCmd "belch"        (Versatile "You let out a deep belch."
                                       "% lets out a deep belch."
                                       "You belch purposefully at @."
                                       "% belches purposefully at you."
                                       "% belches purposefully at @.")
                            Nothing Nothing
    , ExpCmd "bewildered"   (Versatile "You are hopelessly bewildered."
                                       "% is hopelessly bewildered."
                                       "You are hopelessly bewildered by @'s behavior."
                                       "% is hopelessly bewildered by your behavior."
                                       "% is hopelessly bewildered by @'s behavior.")
                            Nothing Nothing
    , ExpCmd "blank"        (Versatile "You have a blank expression on your face."
                                       "% has a blank expression on & face."
                                       "You look blankly at @."
                                       "% looks blankly at you."
                                       "% looks blankly at @.")
                            Nothing Nothing
    , ExpCmd "blink"        (Versatile "You blink."
                                       "% blinks."
                                       "You blink at @."
                                       "% blinks at you."
                                       "% blinks at @.")
                            Nothing Nothing
    , ExpCmd "blush"        (NoTarget  "You blush."
                                       "% blushes.")
                            Nothing Nothing
    , ExpCmd "boggle"       (NoTarget  "You boggle at the concept."
                                       "% boggles at the concept.")
                            Nothing Nothing
    , ExpCmd "bow"          (Versatile "You bow."
                                       "% bows."
                                       "You bow before @."
                                       "% bows before you."
                                       "% bows before @.")
                            Nothing Nothing
    , ExpCmd "burp"         (Versatile "You burp."
                                       "% burps."
                                       "You burp rudely at @."
                                       "% burps rudely at you."
                                       "% burps rudely at @.")
                            Nothing Nothing
    , ExpCmd "burstlaugh"   (Versatile "You abruptly burst into laughter."
                                       "% abruptly bursts into laughter."
                                       "You abruptly burst into laughter in reaction to @."
                                       "% abruptly bursts into laughter in reaction to you."
                                       "% abruptly bursts into laughter in reaction to @.")
                            Nothing Nothing
    , ExpCmd "calm"         (NoTarget  "You appear calm and collected."
                                       "% appears calm and collected.")
                            Nothing Nothing
    , ExpCmd "caresscheek"  (HasTarget "You caress @'s cheek'."
                                       "% caresses your cheek."
                                       "% caresses @'s cheek.")
                            Nothing Nothing
    , ExpCmd "cheer"        (Versatile "You cheer eagerly."
                                       "% cheers eagerly."
                                       "You eagerly cheer for @."
                                       "% eagerly cheers for you."
                                       "% eagerly cheers for @.")
                            Nothing Nothing
    , ExpCmd "chortle"      (Versatile "You chortle gleefully."
                                       "% chortles gleefully."
                                       "You chortle gleefully at @."
                                       "% chortles gleefully at you."
                                       "% chortles gleefully at @.")
                            Nothing Nothing
    , ExpCmd "chuckle"      (Versatile "You chuckle."
                                       "% chuckles."
                                       "You chuckle at @."
                                       "% chuckles at you."
                                       "% chuckles at @.")
                            Nothing Nothing
    , ExpCmd "clap"         (Versatile "You clap."
                                       "% claps."
                                       "You clap for @."
                                       "% claps for you."
                                       "% claps for @.")
                            Nothing Nothing
    , ExpCmd "closeeyes"    (NoTarget  "You close your eyes."
                                       "% closes & eyes.")
                            Nothing Nothing
    , ExpCmd "coldsweat"    (NoTarget  "You break out in a cold sweat."
                                       "% breaks out in a cold sweat.")
                            Nothing Nothing
    , ExpCmd "comfort"      (HasTarget "You comfort @."
                                       "% comforts you."
                                       "% comforts @.")
                            Nothing Nothing
    , ExpCmd "confused"     (Versatile "You look utterly confused."
                                       "% looks utterly confused."
                                       "Utterly confused, you look fixedly at @."
                                       "Utterly confused, % looks fixedly at you."
                                       "Utterly confused, % looks fixedly at @.")
                            Nothing Nothing
    , ExpCmd "cough"        (Versatile "You cough."
                                       "% coughs."
                                       "You cough loudly at @."
                                       "% coughs loudly at you."
                                       "% coughs loudly at @.")
                            Nothing Nothing
    , ExpCmd "coverears"    (NoTarget  "You cover your ears."
                                       "% covers & ears.")
                            Nothing Nothing
    , ExpCmd "covereyes"    (NoTarget  "You cover your eyes."
                                       "% covers & eyes.")
                            Nothing Nothing
    , ExpCmd "covermouth"   (NoTarget  "You cover your mouth."
                                       "% covers & mouth.")
                            Nothing Nothing
    , ExpCmd "cower"        (Versatile "You cower in fear."
                                       "% cowers in fear."
                                       "You cower in fear before @."
                                       "% cowers in fear before you."
                                       "% cowers in fear before @.")
                            Nothing Nothing
    , ExpCmd "cringe"       (Versatile "You cringe."
                                       "% cringes."
                                       "You cringe at @."
                                       "% cringes at you."
                                       "% cringes at @.")
                            Nothing Nothing
    , ExpCmd "crossarms"    (NoTarget  "You cross your arms."
                                       "% crosses & arms.")
                            Nothing Nothing
    , ExpCmd "crossfingers" (NoTarget  "You cross your fingers."
                                       "% crosses & fingers.")
                            Nothing Nothing
    , ExpCmd "cry"          (NoTarget  "You cry."
                                       "% cries.")
                            Nothing Nothing
    , ExpCmd "cryanger"     (Versatile "You cry out in anger."
                                       "% cries out in anger."
                                       "You cry out in anger at @."
                                       "% cries out in anger at you."
                                       "% cries out in anger at @.")
                            Nothing Nothing
    , ExpCmd "cuddle"       (HasTarget "You cuddle @."
                                       "% cuddles you."
                                       "% cuddles @.")
                            Nothing Nothing
    , ExpCmd "curious"      (Versatile "You have a curious expression on your face."
                                       "% has a curious expression on & face."
                                       "Interested in knowing more, you flash a curious expression at @."
                                       "Interested in knowing more, % flashes a curious expression at you."
                                       "Interested in knowing more, % flashes a curious expression at @.")
                            Nothing Nothing
    , ExpCmd "curse"        (Versatile "You curse."
                                       "% curses."
                                       "You curse at @."
                                       "% curses at you."
                                       "% curses at @.")
                            Nothing Nothing
    , ExpCmd "curtsey"      (Versatile "You curtsey."
                                       "% curtseys."
                                       "You curtsey to @."
                                       "% curtseys to you."
                                       "% curtseys to @.")
                            Nothing Nothing
    , ExpCmd "curtsy"       (Versatile "You curtsy."
                                       "% curtsies."
                                       "You curtsy to @."
                                       "% curtsies to you."
                                       "% curtsies to @.")
                            Nothing Nothing
    , ExpCmd "dance"        (Versatile "You dance around."
                                       "% dances around."
                                       "You dance with @."
                                       "% dances with you."
                                       "% dances with @.")
                            Nothing Nothing
    , ExpCmd "daydream"     (NoTarget  "Staring off into the distance, you indulge in a daydream."
                                       "Staring off into the distance, % indulges in a daydream.")
                            Nothing Nothing
    , ExpCmd "deepbreath"   (NoTarget  "You take a deep breath."
                                       "% takes a deep breath.")
                            Nothing Nothing
    , ExpCmd "disappoint"   (Versatile "You are clearly disappointed."
                                       "% is clearly disappointed."
                                       "You are clearly disappointed in @."
                                       "% is clearly disappointed in you."
                                       "% is clearly disappointed in @.")
                            Nothing Nothing
    , ExpCmd "dizzy"        (NoTarget  "Dizzy and reeling, you look as though you might pass out."
                                       "Dizzy and reeling, % looks as though ^ might pass out.")
                            Nothing Nothing
    , ExpCmd "doublelaugh"  (Versatile "You double over with laughter."
                                       "% doubles over with laughter."
                                       "You double over with laughter in reaction to @."
                                       "% doubles over with laughter in reaction to you."
                                       "% doubles over with laughter in reaction to @.")
                            Nothing Nothing
    , ExpCmd "drool"        (NoTarget  "You drool."
                                       "% drools.")
                            Nothing Nothing
    , ExpCmd "droop"        (NoTarget  "Your eyes droop."
                                       "%'s eyes droop.")
                            Nothing Nothing
    , ExpCmd "duck"         (Versatile "You duck."
                                       "% ducks."
                                       "You duck away from @."
                                       "% ducks away from you."
                                       "% ducks away from @.")
                            Nothing Nothing
    , ExpCmd "embrace"      (HasTarget "You warmly embrace @."
                                       "% embraces you warmly."
                                       "% embraces @ warmly.")
                            Nothing Nothing
    , ExpCmd "exhausted"    (NoTarget  "Exhausted, your face displays a weary expression."
                                       "Exhausted, %'s face displays a weary expression.")
                            Nothing Nothing
    , ExpCmd "facepalm"     (NoTarget  "You facepalm."
                                       "% facepalms.")
                            Nothing Nothing
    , ExpCmd "faint"        (NoTarget  "You faint."
                                       "% faints.")
                            Nothing (Just "fainted")
    , ExpCmd "fistpump"     (NoTarget  "You pump your fist in the air triumphantly."
                                       "% pumps & fist in the air triumphantly.")
                            Nothing Nothing
    , ExpCmd "flex"         (Versatile "You flex your muscles."
                                       "%'s flexes & muscles."
                                       "You flex your muscles at @."
                                       "% flexes & muscles at you."
                                       "% flexes & muscles at @.")
                            Nothing Nothing
    , ExpCmd "flinch"       (NoTarget  "You flinch."
                                       "% flinches.")
                            Nothing Nothing
    , ExpCmd "flop"         (NoTarget  "You flop down on the ground."
                                       "% flops down on the ground.")
                            Nothing Nothing
    , ExpCmd "flustered"    (NoTarget  "You look entirely flustered."
                                       "% looks entirely flustered.")
                            Nothing Nothing
    , ExpCmd "frown"        (Versatile "You frown."
                                       "% frowns."
                                       "You frown at @."
                                       "% frowns at you."
                                       "% frowns at @.")
                            Nothing Nothing
    , ExpCmd "funnyface"    (Versatile "You make a funny face."
                                       "% makes a funny face."
                                       "You make a funny face at @."
                                       "% makes a funny face at you."
                                       "% makes a funny face at @.")
                            Nothing Nothing
    , ExpCmd "gape"         (Versatile "You gape."
                                       "% gapes."
                                       "You gape at @."
                                       "% gapes at you."
                                       "% gapes at @.")
                            Nothing Nothing
    , ExpCmd "gasp"         (Versatile "You gasp."
                                       "% gasps."
                                       "You gasp at @."
                                       "% gasps at you."
                                       "% gasps at @.")
                            Nothing Nothing
    , ExpCmd "gawk"         (HasTarget "You gawk at @."
                                       "% gawks at you."
                                       "% gawks at @.")
                            Nothing Nothing
    , ExpCmd "gaze"         (HasTarget "You gaze longingly at @."
                                       "% gazes longingly at you."
                                       "% gazes longingly at @.")
                            Nothing Nothing
    , ExpCmd "giggle"       (Versatile "You giggle."
                                       "% giggles."
                                       "You giggle at @."
                                       "% giggles at you."
                                       "% giggles at @.")
                            Nothing Nothing
    , ExpCmd "glance"       (Versatile "You glance around."
                                       "% glances around."
                                       "You glance at @."
                                       "% glances at you."
                                       "% glances at @.")
                            Nothing Nothing
    , ExpCmd "glare"        (HasTarget "You glare at @."
                                       "% glares at you."
                                       "% glares at @.")
                            Nothing Nothing
    , ExpCmd "greet"        (HasTarget "You greet @."
                                       "% greets you."
                                       "% greets @.")
                            Nothing Nothing
    , ExpCmd "grimace"      (Versatile "You grimace disapprovingly."
                                       "% grimaces disapprovingly."
                                       "You grimace disapprovingly at @."
                                       "% grimaces disapprovingly at you."
                                       "% grimaces disapprovingly at @.")
                            Nothing Nothing
    , ExpCmd "grin"         (Versatile "You grin."
                                       "% grins."
                                       "You grin at @."
                                       "% grins at you."
                                       "% grins at @.")
                            Nothing Nothing
    , ExpCmd "groan"        (Versatile "You groan."
                                       "% groans."
                                       "You groan at @."
                                       "% groans at you."
                                       "% groans at @.")
                            Nothing Nothing
    , ExpCmd "grovel"       (HasTarget "You grovel before @."
                                       "% grovels before you."
                                       "% grovels before @.")
                            Nothing Nothing
    , ExpCmd "growl"        (Versatile "You growl menacingly."
                                       "% growls menacingly."
                                       "You growl menacingly at @."
                                       "% growls menacingly at you."
                                       "% growls menacingly at @.")
                            Nothing Nothing
    , ExpCmd "grumble"      (NoTarget  "You grumble to yourself."
                                       "% grumbles to *.")
                            Nothing Nothing
    , ExpCmd "guffaw"       (Versatile "You guffaw boisterously."
                                       "% guffaws boisterously."
                                       "You guffaw boisterously at @."
                                       "% guffaws boisterously at you."
                                       "% guffaws boisterously at @.")
                            Nothing Nothing
    , ExpCmd "gulp"         (NoTarget  "You gulp."
                                       "% gulps.")
                            Nothing Nothing
    , ExpCmd "handhips"     (NoTarget  "You put your hands on your hips."
                                       "% puts & hands on & hips.")
                            Nothing Nothing
    , ExpCmd "hesitate"     (NoTarget  "You hesitate."
                                       "% hesitates.")
                            Nothing Nothing
    , ExpCmd "hiccup"       (NoTarget  "You hiccup involuntarily."
                                       "% hiccups involuntarily.")
                            Nothing Nothing
    , ExpCmd "highfive"     (HasTarget "You give @ a high five."
                                       "% gives you a high five."
                                       "% gives @ a high five.")
                            Nothing Nothing
    , ExpCmd "hmm"          (NoTarget  "You say, \"Hmm...\" and think about it."
                                       "% says, \"Hmm...\" and thinks about it.")
                            Nothing Nothing
    , ExpCmd "holdhand"     (HasTarget "You hold @'s hand."
                                       "% holds your hand."
                                       "% holds @'s hand.")
                            Nothing Nothing
    , ExpCmd "hop"          (NoTarget  "You hop up and down excitedly."
                                       "% hops up and down excitedly.")
                            Nothing Nothing
    , ExpCmd "horf"         (Versatile "You horf with reckless abandon."
                                       "% horfs with reckless abandon."
                                       "You horf all over @ with reckless abandon."
                                       "% horfs all over you with reckless abandon."
                                       "% horfs all over @ with reckless abandon.")
                            (Just vomit) Nothing
    , ExpCmd "howllaugh"    (Versatile "You howl with laughter."
                                       "% howls with laughter."
                                       "You howl with laughter at @."
                                       "% howls with laughter at you."
                                       "% howls with laughter at @.")
                            Nothing Nothing
    , ExpCmd "hug"          (HasTarget "You hug @."
                                       "% hugs you."
                                       "% hugs @.")
                            Nothing Nothing
    , ExpCmd "hum"          (NoTarget  "You hum a merry tune."
                                       "% hums a merry tune.")
                            Nothing Nothing
    , ExpCmd "innocent"     (NoTarget  "You try to look innocent."
                                       "% tries to look innocent.")
                            Nothing Nothing
    , ExpCmd "inquisitive"  (Versatile "You have an inquisitive expression on your face."
                                       "% has an inquisitive expression on & face."
                                       "You flash an inquisitive expression at @."
                                       "% flashes an inquisitive expression at you."
                                       "% flashes an inquisitive expression at @.")
                            Nothing Nothing
    , ExpCmd "jig"          (Versatile "You dance a lively jig."
                                       "% dances a lively jig."
                                       "You dance a lively jig with @."
                                       "% dances a lively jig with you."
                                       "% dances a lively jig with @.")
                            Nothing Nothing
    , ExpCmd "joytears"     (NoTarget  "You are overcome with tears of joy."
                                       "% is overcome with tears of joy.")
                            Nothing Nothing
    , ExpCmd "jump"         (NoTarget  "You jump up and down excitedly."
                                       "% jumps up and down excitedly.")
                            Nothing Nothing
    , ExpCmd "kiss"         (HasTarget "You kiss @."
                                       "% kisses you."
                                       "% kisses @.")
                            Nothing Nothing
    , ExpCmd "kisscheek"    (HasTarget "You kiss @ on the cheek."
                                       "% kisses you on the cheek."
                                       "% kisses @ on the cheek.")
                            Nothing Nothing
    , ExpCmd "kisspassion"  (HasTarget "You kiss @ passionately."
                                       "% kisses you passionately."
                                       "% kisses @ passionately.")
                            Nothing Nothing
    , ExpCmd "kneel"        (Versatile "You kneel down."
                                       "% kneels down."
                                       "You kneel down before @."
                                       "% kneels down before you."
                                       "% kneels down before @.")
                            Nothing (Just "kneeling down")
    , ExpCmd "laugh"        (Versatile "You laugh."
                                       "% laughs."
                                       "You laugh at @."
                                       "% laughs at you."
                                       "% laughs at @.")
                            Nothing Nothing
    , ExpCmd "laughheart"   (Versatile "You laugh heartily."
                                       "% laughs heartily."
                                       "You laugh heartily at @."
                                       "% laughs heartily at you."
                                       "% laughs heartily at @.")
                            Nothing Nothing
    , ExpCmd "laydown"      (Versatile "You lay down."
                                       "% lays down."
                                       "You lay down next to @."
                                       "% lays down next to you."
                                       "% lays down next to @.")
                            Nothing (Just "laying down")
    , ExpCmd "leap"         (NoTarget  "You leap into the air."
                                       "% leaps into the air.")
                            Nothing Nothing
    , ExpCmd "leer"         (HasTarget "You leer at @."
                                       "% leers at you."
                                       "% leers at @.")
                            Nothing Nothing
    , ExpCmd "licklips"     (NoTarget  "You lick your lips."
                                       "% licks & lips.")
                            Nothing Nothing
    , ExpCmd "livid"        (NoTarget  "You are positively livid."
                                       "% is positively livid.")
                            Nothing Nothing
    , ExpCmd "longingly"    (HasTarget "You gaze longingly at @."
                                       "% gazes longingly at you."
                                       "% gazes longingly at @.")
                            Nothing Nothing
    , ExpCmd "losswords"    (NoTarget  "You appear to be at a loss for words."
                                       "% appears to be at a loss for words.")
                            Nothing Nothing
    , ExpCmd "massage"      (HasTarget "You massage @."
                                       "% massages you."
                                       "% massages @.")
                            Nothing Nothing
    , ExpCmd "moan"         (NoTarget  "You moan."
                                       "% moans.")
                            Nothing Nothing
    , ExpCmd "mumble"       (Versatile "You mumble to yourself."
                                       "% mumbles to *."
                                       "You mumble something to @."
                                       "% mumbles something to you."
                                       "% mumbles something to @.")
                            Nothing Nothing
    , ExpCmd "muscles"      (Versatile "You flex your muscles."
                                       "%'s flexes & muscles."
                                       "You flex your muscles at @."
                                       "% flexes & muscles at you."
                                       "% flexes & muscles at @.")
                            Nothing Nothing
    , ExpCmd "mutter"       (Versatile "You mutter to yourself."
                                       "% mutters to *."
                                       "You mutter something to @."
                                       "% mutters something to you."
                                       "% mutters something to @.")
                            Nothing Nothing
    , ExpCmd "nod"          (Versatile "You nod."
                                       "% nods."
                                       "You nod to @."
                                       "% nods to you."
                                       "% nods to @.")
                            Nothing Nothing
    , ExpCmd "nodagree"     (Versatile "You nod in agreement."
                                       "% nods in agreement."
                                       "You nod in agreement to @."
                                       "% nods in agreement to you."
                                       "% nods in agreement to @.")
                            Nothing Nothing
    , ExpCmd "noexpress"    (NoTarget  "Your face is entirely expressionless."
                                       "%'s face is entirely expressionless.")
                            Nothing Nothing
    , ExpCmd "nudge"        (HasTarget "You nudge @."
                                       "% nudges you."
                                       "% nudges @.")
                            Nothing Nothing
    , ExpCmd "nuzzle"       (HasTarget "You nuzzle @ lovingly."
                                       "% nuzzles you lovingly."
                                       "% nuzzles @ lovingly.")
                            Nothing Nothing
    , ExpCmd "openeyes"     (NoTarget  "You open your eyes."
                                       "% opens & eyes.")
                            Nothing Nothing
    , ExpCmd "openmouth"    (Versatile "Your mouth hangs open."
                                       "%'s mouth hangs open."
                                       "Your mouth hangs open in response to @."
                                       "%'s mouth hangs open in response to you."
                                       "%'s mouth hangs open in response to @.")
                            Nothing Nothing
    , ExpCmd "pace"         (NoTarget  "You pace around nervously."
                                       "% paces around nervously.")
                            Nothing Nothing
    , ExpCmd "pant"         (NoTarget  "You pant."
                                       "% pants.")
                            Nothing Nothing
    , ExpCmd "pat"          (HasTarget "You pat @ on the back."
                                       "% pats you on the back."
                                       "% pats @ on the back.")
                            Nothing Nothing
    , ExpCmd "peer"         (HasTarget "You peer at @."
                                       "% peers at you."
                                       "% peers at @.")
                            Nothing Nothing
    , ExpCmd "pensive"      (Versatile "Your wistful expression suggests a pensive mood."
                                       "%'s wistful expression suggests a pensive mood."
                                       "You gaze pensively at @."
                                       "% gazes pensively at you."
                                       "% gazes pensively at @.")
                            Nothing Nothing
    , ExpCmd "perplexed"    (NoTarget  "You are truly perplexed by the situation."
                                       "% is truly perplexed by the situation.")
                            Nothing Nothing
    , ExpCmd "pet"          (HasTarget "You pet @."
                                       "% pets you."
                                       "% pets @.")
                            Nothing Nothing
    , ExpCmd "picknose"     (NoTarget  "You pick your nose."
                                       "% picks & nose.")
                            Nothing Nothing
    , ExpCmd "pinch"        (HasTarget "You pinch @."
                                       "% pinches you."
                                       "% pinches @.")
                            Nothing Nothing
    , ExpCmd "point"        (HasTarget "You point to @."
                                       "% points to you."
                                       "% points to @.")
                            Nothing Nothing
    , ExpCmd "poke"         (HasTarget "You poke @."
                                       "% pokes you."
                                       "% pokes @.")
                            Nothing Nothing
    , ExpCmd "ponder"       (NoTarget  "You ponder the situation."
                                       "% ponders the situation.")
                            Nothing Nothing
    , ExpCmd "pose"         (Versatile "You strike a pose."
                                       "% strikes a pose."
                                       "You strike a pose before @."
                                       "% strikes a pose before you."
                                       "% strikes a pose before @.")
                            Nothing Nothing
    , ExpCmd "pounce"       (HasTarget "You pounce on @."
                                       "% pounces on you."
                                       "% pounces on @.")
                            Nothing Nothing
    , ExpCmd "pout"         (Versatile "You pout."
                                       "% pouts."
                                       "You pout at @."
                                       "% pouts at you."
                                       "% pout at @.")
                            Nothing Nothing
    , ExpCmd "prance"       (Versatile "You prance around."
                                       "% prances around."
                                       "You prance around @."
                                       "% prances around you."
                                       "% prances around @.")
                            Nothing Nothing
    , ExpCmd "puke"         (Versatile "You puke violently."
                                       "% pukes violently."
                                       "You puke violently on @."
                                       "% pukes violently on you."
                                       "% pukes violently on @.")
                            (Just vomit) Nothing
    , ExpCmd "purr"         (NoTarget  "You purr."
                                       "% purrs.")
                            Nothing Nothing
    , ExpCmd "questioning"  (Versatile "You have a questioning expression on your face."
                                       "% has a questioning expression on & face."
                                       "You flash a questioning expression at @."
                                       "% flashes a questioning expression at you."
                                       "% flashes a questioning expression at @.")
                            Nothing Nothing
    , ExpCmd "raisebrow"    (Versatile "You raise an eyebrow."
                                       "% raises an eyebrow."
                                       "You raise an eyebrow at @."
                                       "% raises an eyebrow at you."
                                       "% raises an eyebrow at @.")
                            Nothing Nothing
    , ExpCmd "raisehand"    (NoTarget  "You raise your hand."
                                       "% raises & hand.")
                            Nothing Nothing
    , ExpCmd "reeling"      (NoTarget  "Dizzy and reeling, you look as though you might pass out."
                                       "Dizzy and reeling, % looks as though ^ might pass out.")
                            Nothing Nothing
    , ExpCmd "relieved"     (NoTarget  "You look relieved."
                                       "% looks relieved.")
                            Nothing Nothing
    , ExpCmd "rock"         (NoTarget  "You rock back and forth."
                                       "% rocks back and forth.")
                            Nothing Nothing
    , ExpCmd "rolleyes"     (Versatile "You roll your eyes."
                                       "% rolls & eyes."
                                       "You roll your eyes at @."
                                       "% rolls & eyes at you."
                                       "% rolls & eyes at @.")
                            Nothing Nothing
    , ExpCmd "rubeyes"      (NoTarget  "You rub your eyes."
                                       "% rubs & eyes.")
                            Nothing Nothing
    , ExpCmd "ruffle"       (HasTarget "You ruffle @'s hair."
                                       "% ruffles your hair."
                                       "% ruffles @'s hair.")
                            Nothing Nothing
    , ExpCmd "satisfied"    (NoTarget  "You look satisfied."
                                       "% looks satisfied.")
                            Nothing Nothing
    , ExpCmd "scowl"        (Versatile "You scowl with contempt."
                                       "% scowls with contempt."
                                       "You scowl with contempt at @."
                                       "% scowls with contempt at you."
                                       "% scowls with contempt at @.")
                            Nothing Nothing
    , ExpCmd "scratchchin"  (NoTarget  "You scratch your chin."
                                       "% scratches & chin.")
                            Nothing Nothing
    , ExpCmd "scratchhead"  (NoTarget  "You scratch your head."
                                       "% scratches & head.")
                            Nothing Nothing
    , ExpCmd "scream"       (Versatile "You unleash a high-pitched scream."
                                       "% unleashes high-pitched scream."
                                       "You scream at @."
                                       "% screams at you."
                                       "% screams at @.")
                            Nothing Nothing
    , ExpCmd "shake"        (Versatile "You shake your head."
                                       "% shakes & head."
                                       "You shake your head at @."
                                       "% shakes & head at you."
                                       "% shakes & head at @.")
                            Nothing Nothing
    , ExpCmd "shiver"       (NoTarget  "You shiver."
                                       "% shivers.")
                            Nothing Nothing
    , ExpCmd "shriek"       (NoTarget  "You let out a shriek."
                                       "% lets out a shriek.")
                            Nothing Nothing
    , ExpCmd "shrieklaugh"  (Versatile "You shriek with laughter."
                                       "% shrieks with laughter."
                                       "You shriek with laughter at @."
                                       "% shrieks with laughter at you."
                                       "% shrieks with laughter at @.")
                            Nothing Nothing
    , ExpCmd "shrug"        (NoTarget  "You shrug your shoulders."
                                       "% shrugs & shoulders.")
                            Nothing Nothing
    , ExpCmd "shudder"      (NoTarget  "You shudder."
                                       "% shudders.")
                            Nothing Nothing
    , ExpCmd "shush"        (HasTarget "You shush @."
                                       "% shushes you."
                                       "% shushed @.")
                            Nothing Nothing
    , ExpCmd "sigh"         (NoTarget  "You sigh."
                                       "% sighes.")
                            Nothing Nothing
    , ExpCmd "sighrelief"   (NoTarget  "You sigh in relief."
                                       "% sighes in relief.")
                            Nothing Nothing
    , ExpCmd "sighsadly"    (NoTarget  "You sigh sadly."
                                       "% sighes sadly.")
                            Nothing Nothing
    , ExpCmd "sighwearily"  (NoTarget  "You sigh wearily."
                                       "% sighes wearily.")
                            Nothing Nothing
    , ExpCmd "sit"          (Versatile "You sit down."
                                       "% sits down."
                                       "You sit down next to @."
                                       "% sits down next to you."
                                       "% sit down next to @.")
                            Nothing (Just "sitting down")
    , ExpCmd "sleepy"       (NoTarget  "You look sleepy."
                                       "% looks sleepy.")
                            Nothing Nothing
    , ExpCmd "slowclap"     (Versatile "You clap slowly, with a mocking lack of enthusiasm."
                                       "% claps slowly, with a mocking lack of enthusiasm."
                                       "With a mocking lack of enthusiasm, you clap slowly for @."
                                       "With a mocking lack of enthusiasm, % claps slowly for you."
                                       "With a mocking lack of enthusiasm, % claps slowly for @.")
                            Nothing Nothing
    , ExpCmd "smacklips"    (NoTarget  "You smack your lips."
                                       "% smacks & lips.")
                            Nothing Nothing
    , ExpCmd "smile"        (Versatile "You smile."
                                       "% smiles."
                                       "You smile at @."
                                       "% smiles at you."
                                       "% smiles at @.")
                            Nothing Nothing
    , ExpCmd "smirk"        (Versatile "You smirk."
                                       "% smirks."
                                       "You smirk at @."
                                       "% smirks at you."
                                       "% smirks at @.")
                            Nothing Nothing
    , ExpCmd "snap"         (Versatile "You snap your fingers."
                                       "% snaps & fingers."
                                       "You snap your fingers at @."
                                       "% snaps & fingers at you."
                                       "% snaps & fingers at @.")
                            Nothing Nothing
    , ExpCmd "snarl"        (Versatile "You snarl."
                                       "% snarls."
                                       "You snarl at @."
                                       "% snarls at you."
                                       "% snarls at @.")
                            Nothing Nothing
    , ExpCmd "sneeze"       (NoTarget  "You sneeze."
                                       "% sneezes.")
                            Nothing Nothing
    , ExpCmd "snicker"      (Versatile "You snicker derisively."
                                       "% snickers derisively."
                                       "You snicker derisively at @."
                                       "% snickers derisively at you."
                                       "% snickers derisively at @.")
                            Nothing Nothing
    , ExpCmd "sniff"        (NoTarget  "You sniff the air."
                                       "% sniffs the air.")
                            Nothing Nothing
    , ExpCmd "sniffle"      (NoTarget  "You sniffle."
                                       "% sniffles.")
                            Nothing Nothing
    , ExpCmd "snore"        (NoTarget  "You snore loudly."
                                       "% snores loudly.")
                            Nothing Nothing
    , ExpCmd "snort"        (Versatile "You snort."
                                       "% snorts."
                                       "You snort at @."
                                       "% snorts at you."
                                       "% snorts at @.")
                            Nothing Nothing
    , ExpCmd "sob"          (NoTarget  "You sob."
                                       "% sobs.")
                            Nothing Nothing
    , ExpCmd "spit"         (Versatile "You spit."
                                       "% spits."
                                       "You spit on @."
                                       "% spits on you."
                                       "% spits on @.")
                            Nothing Nothing
    , ExpCmd "stagger"      (NoTarget  "You stagger around."
                                       "% staggers around.")
                            Nothing Nothing
    , ExpCmd "stamp"        (NoTarget  "Your stamp your feet."
                                       "% stamps & feet.")
                            Nothing Nothing
    , ExpCmd "stand"        (NoTarget  "You stand up."
                                       "% stands up.")
                            Nothing (Just "")
    , ExpCmd "stare"        (HasTarget "You stare at @."
                                       "% stares at you."
                                       "% stares at @.")
                            Nothing Nothing
    , ExpCmd "stiflelaugh"  (NoTarget  "You try hard to stifle a laugh."
                                       "% tries hard to stifle a laugh.")
                            Nothing Nothing
    , ExpCmd "stifletears"  (NoTarget  "You try hard to stifle your tears."
                                       "% tries hard to stifle & tears.")
                            Nothing Nothing
    , ExpCmd "stomach"      (NoTarget  "Your stomach growls."
                                       "%'s stomach growls.")
                            Nothing Nothing
    , ExpCmd "stomp"        (NoTarget  "Your stomp your feet."
                                       "% stomps & feet.")
                            Nothing Nothing
    , ExpCmd "stretch"      (NoTarget  "You stretch your muscles."
                                       "% stretches & muscles.")
                            Nothing Nothing
    , ExpCmd "strokehair"   (HasTarget "You stroke @'s hair."
                                       "% strokes your hair."
                                       "% strokes @'s hair.")
                            Nothing Nothing
    , ExpCmd "strut"        (NoTarget  "Your strut your stuff."
                                       "% struts & stuff.")
                            Nothing Nothing
    , ExpCmd "stumble"      (NoTarget  "Your stumble and almost fall over."
                                       "% strumbles and almost falls over.")
                            Nothing Nothing
    , ExpCmd "suckthumb"    (NoTarget  "You suck your thumb."
                                       "% sucks & thumb.")
                            Nothing Nothing
    , ExpCmd "sulk"         (NoTarget  "You sulk."
                                       "% sulks.")
                            Nothing Nothing
    , ExpCmd "sweat"        (NoTarget  "You break out in a sweat."
                                       "% breaks out in a sweat.")
                            Nothing Nothing
    , ExpCmd "tap"          (HasTarget "You tap @ on the shoulder."
                                       "% taps you on the shoulder."
                                       "% taps @ on the shoulder.")
                            Nothing Nothing
    , ExpCmd "taunt"        (HasTarget "You taunt @."
                                       "% taunts you."
                                       "% taunts @.")
                            Nothing Nothing
    , ExpCmd "think"        (NoTarget  "You say, \"Hmm...\" and think about it."
                                       "% says, \"Hmm...\" and thinks about it.")
                            Nothing Nothing
    , ExpCmd "throat"       (NoTarget  "You clear your throat."
                                       "% clears & throat.")
                            Nothing Nothing
    , ExpCmd "thumbsdown"   (Versatile "You give a thumbs down."
                                       "% gives a thumbs down."
                                       "You give a thumbs down to @."
                                       "% gives a thumbs down to you."
                                       "% gives a thumbs down to @.")
                            Nothing Nothing
    , ExpCmd "thumbsup"     (Versatile "You give a thumbs up."
                                       "% gives a thumbs up."
                                       "You give a thumbs up to @."
                                       "% gives a thumbs up to you."
                                       "% gives a thumbs up to @.")
                            Nothing Nothing
    , ExpCmd "tickle"       (HasTarget "You tickle @."
                                       "% tickles you."
                                       "% tickles @.")
                            Nothing Nothing
    , ExpCmd "tongue"       (Versatile "You stick your tongue out."
                                       "% sticks & tongue out."
                                       "You stick your tongue out at @."
                                       "% sticks & tongue out at you."
                                       "% sticks & tongue out at @.")
                            Nothing Nothing
    , ExpCmd "tremble"      (Versatile "You tremble in fear."
                                       "% trembles in fear."
                                       "You tremble in fear of @."
                                       "% trembles in fear of you."
                                       "% trembles in fear of @.")
                            Nothing Nothing
    , ExpCmd "turnhead"     (HasTarget "You turn your head to look at @."
                                       "% turns & head to look at you."
                                       "% turns & head to look at @.")
                            Nothing Nothing
    , ExpCmd "twiddle"      (NoTarget  "You twiddle your thumbs."
                                       "% twiddles & thumbs.")
                            Nothing Nothing
    , ExpCmd "twirl"        (NoTarget  "You twirl around."
                                       "% twirls around.")
                            Nothing Nothing
    , ExpCmd "twitch"       (NoTarget  "You twitch nervously."
                                       "% twitches nervously.")
                            Nothing Nothing
    , ExpCmd "unamused"     (Versatile "You are plainly unamused."
                                       "% is plainly unamused."
                                       "You are plainly unamused by @'s antics."
                                       "% is plainly unamused by your antics."
                                       "% is plainly unamused by @'s antics.")
                            Nothing Nothing
    , ExpCmd "vomit"        (Versatile "You vomit."
                                       "% vomits."
                                       "You vomit on @."
                                       "% vomits on you."
                                       "% vomits on @.")
                            (Just vomit) Nothing
    , ExpCmd "watch"        (HasTarget "You watch @ with interest."
                                       "% watches you with interest."
                                       "% watches @ with interest.")
                            Nothing Nothing
    , ExpCmd "wave"         (Versatile "You wave."
                                       "% waves."
                                       "You wave at @."
                                       "% waves at you."
                                       "% waves at @.")
                            Nothing Nothing
    , ExpCmd "weary"        (Versatile "Exhausted, your face displays a weary expression."
                                       "Exhausted, %'s face displays a weary expression."
                                       "You cast @ a weary glance."
                                       "% casts you a weary glance."
                                       "% casts @ a weary glance.")
                            Nothing Nothing
    , ExpCmd "whimper"      (Versatile "You whimper."
                                       "% whimpers."
                                       "You whimper at @."
                                       "% whimpers at you."
                                       "% whimpers at @.")
                            Nothing Nothing
    , ExpCmd "whistle"      (NoTarget  "You whistle."
                                       "% whistles.")
                            Nothing Nothing
    , ExpCmd "wiggle"       (NoTarget  "You wiggle around."
                                       "% wiggles around.")
                            Nothing Nothing
    , ExpCmd "wince"        (NoTarget  "You wince in pain."
                                       "% winces in pain.")
                            Nothing Nothing
    , ExpCmd "wink"         (Versatile "You wink."
                                       "% winks."
                                       "You wink at @."
                                       "% winks at you."
                                       "% winks at @.")
                            Nothing Nothing
    , ExpCmd "wipeface"     (NoTarget  "You wipe your face."
                                       "% wipes & face.")
                            Nothing Nothing
    , ExpCmd "wistful"      (Versatile "Your wistful expression suggests a pensive mood."
                                       "%'s wistful expression suggests a pensive mood."
                                       "You gaze wistfully at @."
                                       "% gazes wistfully at you."
                                       "% gazes wistfully at @.")
                            Nothing Nothing
    , ExpCmd "worried"      (Versatile "You look genuinely worried."
                                       "% looks genuinely worried."
                                       "You look genuinely worried for @."
                                       "% looks genuinely worried for you."
                                       "% looks genuinely worried for @.")
                            Nothing Nothing
    , ExpCmd "yawn"         (NoTarget  "You yawn."
                                       "% yawns.")
                            Nothing Nothing ]


expCmds :: [Cmd]
expCmds = S.foldr helper [] expCmdSet
  where
    helper ec@(ExpCmd expCmdName _ _ _) = do
        let theCmd = Cmd { cmdName           = expCmdName
                         , cmdPriorityAbbrev = Nothing
                         , cmdFullName       = expCmdName
                         , cmdAction         = Action (expCmd ec) True
                         , cmdDesc           = "" }
        (theCmd :)


expCmdNames :: [Text]
expCmdNames = S.toList . S.map (\(ExpCmd n _ _ _) -> n) $ expCmdSet


getExpCmdByName :: ExpCmdName -> ExpCmd
getExpCmdByName cn = head . S.toList . S.filter (\(ExpCmd cn' _ _ _) -> cn' == cn) $ expCmdSet


-----


expCmd :: ExpCmd -> ActionFun
expCmd (ExpCmd ecn HasTarget {} _  _   ) p@NoArgs {}        = advise p [] . sorryExpCmdRequiresTarget $ ecn
expCmd (ExpCmd ecn ect          mf desc) (NoArgs i mq cols) = case ect of
  (NoTarget  toSelf toOthers      ) -> helper toSelf toOthers
  (Versatile toSelf toOthers _ _ _) -> helper toSelf toOthers
  _                                 -> patternMatchFail "expCmd" . showText $ ect
  where
    helper toSelf toOthers = getState >>= \ms ->
        let d                           = mkStdDesig i ms DoCap
            serialized                  = mkSerializedDesig d toOthers
            (heShe, hisHer, himHerself) = mkPros . getSex i $ ms
            substitutions               = [ ("%", serialized), ("^", heShe), ("&", hisHer), ("*", himHerself) ]
            toOthersBcast               = pure (nlnl . replace substitutions $ toOthers, i `delete` desigIds d)
            tuple                       = (toSelf, toOthersBcast, desc, toSelf)
        in ((i, mq, cols, ecn, tuple) |&|) . uncurry5 . fromMaybe expCmdHelper $ mf
expCmd (ExpCmd ecn NoTarget {} _  _   ) p@(WithArgs     _ _  _    (_:_) ) = advise p [] . sorryExpCmdIllegalTarget $ ecn
expCmd (ExpCmd ecn ect         mf desc)   (OneArgNubbed i mq cols target) = case ect of
  (HasTarget     toSelf toTarget toOthers) -> helper toSelf toTarget toOthers
  (Versatile _ _ toSelf toTarget toOthers) -> helper toSelf toTarget toOthers
  _                                        -> patternMatchFail "expCmd" . showText $ ect
  where
    helper toSelf toTarget toOthers = getState >>= \ms -> case singleArgInvEqRm InRm target of
      (InRm, target') ->
          let d                                = mkStdDesig i ms DoCap
              (first (i `delete`) -> invCoins) = getMobRmInvCoins i ms
          in if ()!# invCoins
            then case uncurry (resolveRmInvCoins i ms . pure $ target') invCoins of
              (_,                    [Left [sorryMsg]]) -> wrapSend mq cols sorryMsg
              (_,                    Right _:_        ) -> wrapSend mq cols sorryExpCmdCoins
              ([Left sorryMsg   ], _                  ) -> wrapSend mq cols sorryMsg
              ([Right (_:_:_)   ], _                  ) -> wrapSend mq cols adviceExpCmdExcessArgs
              ([Right [targetId]], _                  ) ->
                let ioHelper targetDesigTxt =
                        let (toSelf', toOthers', logMsg, substitutions) = mkBindings targetDesigTxt
                            toTarget'     = replace substitutions toTarget
                            toTargetBcast = (nlnl toTarget', pure targetId)
                            toOthersBcast = (nlnl toOthers', desigIds d \\ [ i, targetId ])
                            tuple         = (toSelf', [ toTargetBcast, toOthersBcast ], desc, logMsg)
                        in ((i, mq, cols, ecn, tuple) |&|) . uncurry5 . fromMaybe expCmdHelper $ mf
                    mkBindings targetTxt =
                        let msg                         = replace (pure ("@", targetTxt)) toSelf
                            toSelf'                     = parseDesig       i ms msg
                            logMsg                      = parseExpandDesig i ms msg
                            serialized                  = mkSerializedDesig d toOthers
                            (heShe, hisHer, himHerself) = mkPros . getSex i $ ms
                            toOthers'                   = replace substitutions toOthers
                            substitutions               = [ ("@", targetTxt)
                                                          , ("%", serialized)
                                                          , ("^", heShe)
                                                          , ("&", hisHer)
                                                          , ("*", himHerself) ]
                        in (toSelf', toOthers', logMsg, substitutions)
                in if getType targetId ms `elem` [ PCType, NpcType ]
                  then ioHelper . serialize . mkStdDesig targetId ms $ Don'tCap
                  else wrapSend mq cols sorryExpCmdTargetType
              x -> patternMatchFail "expCmd helper" . showText $ x
            else wrapSend mq cols sorryNoOneHere
      (x, _) -> wrapSend mq cols . sorryExpCmdInInvEq $ x
expCmd _ p = advise p [] adviceExpCmdExcessArgs


mkSerializedDesig :: Desig -> Text -> Text
mkSerializedDesig d toOthers = serialize (T.head toOthers == '%' ? d :? d { desigShouldCap = Don'tCap })


expCmdHelper :: ExpCmdFun
expCmdHelper i mq cols ecn (toSelf, bs, desc, logMsg) = do
    wrapSend mq cols toSelf
    bcastIfNotIncog i bs
    mobRmDescHelper i desc
    logPlaOut ecn i . pure $ logMsg


mobRmDescHelper :: Id -> MobRmDesc -> MudStack ()
mobRmDescHelper _ Nothing    = unit
mobRmDescHelper i (Just "" ) = tweak $ mobTbl.ind i.mobRmDesc .~ Nothing
mobRmDescHelper i (Just txt) = tweak $ mobTbl.ind i.mobRmDesc ?~ txt


-----


mkExpAction :: Text -> ActionFun
mkExpAction name = expCmd . head . S.toList . S.filter helper $ expCmdSet
  where
    helper (ExpCmd ecn _ _ _) = ecn == name


-----


vomit :: ExpCmdFun
vomit i mq cols ecn a = getState >>= \ms -> case getStomach i ms of
  []   -> let txt = "You dry heave."
              d   = mkStdDesig i ms DoCap
              bs' = pure . (nlnl . (<> " dry heaves.") . serialize &&& (i `delete`) . desigIds) $ d
          in expCmdHelper i mq cols ecn (txt, bs', view _3 a, txt)
  cont -> let baseSize = calcStomachSizeForRace Human `divideRound` 4
          in rndmVector (baseSize + 4) >>= \v -> helper v cont baseSize |&| modifyState >=> sequence_
  where
    helper v cont baseSize ms =
        let vomitAmt  = baseSize + rndmIntToRange (V.head v) (0, 6) - 3
            contAmt   = length cont
            remainder = contAmt - vomitAmt
            actualAmt = remainder >= 0 ? vomitAmt :? contAmt
            isEmptied = remainder <= 0
            amtTxt    = spcL . parensQuote . T.concat $ [ "Vomited ", showText actualAmt, " mouthfuls", rest, "." ]
            rest      = isEmptied |?| "; stomach emptied"
            a'        = a & _4 <>~ amtTxt
            fs        = pure . expCmdHelper i mq cols ecn $ a'
            cont'     = not isEmptied |?| dropRndmElems v actualAmt cont
        in (ms & mobTbl.ind i.stomach .~ cont', fs :: Funs)
