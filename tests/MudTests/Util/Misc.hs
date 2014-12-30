{-# OPTIONS_GHC -funbox-strict-fields -Wall -Werror #-}
{-# LANGUAGE OverloadedStrings, ViewPatterns #-}

module MudTests.Util.Misc where

import Mud.TopLvlDefs.Chars
import Mud.Util.Misc
import Mud.Util.Quoting

import Control.Applicative ((<$>), (<*>))
import Data.Char (chr, isSpace)
import Data.List (elemIndices, group, sort)
import Data.Maybe (isNothing)
import Data.Monoid ((<>))
import Test.QuickCheck.Instances ()
import Test.QuickCheck.Modifiers (NonEmptyList(..))
import Test.Tasty.QuickCheck ((==>), Property)
import qualified Data.Text as T


{-# ANN module ("HLint: ignore Use camelCase" :: String) #-}


-- ==================================================


prop_aOrAn :: T.Text -> Property
prop_aOrAn t = (not . T.null . T.strip $ t) ==>
  let (a, b) = T.break isSpace . aOrAn $ t
  in a == if isVowel . T.head . T.tail $ b then "an" else "a"


prop_countOcc :: Int -> [Int] -> Bool
prop_countOcc needle hay = countOcc needle hay == matches
  where
    matches = length . elemIndices needle $ hay


prop_deleteFirstOfEach :: [Int] -> [Int] -> Property
prop_deleteFirstOfEach delThese fromThis = all (\x -> countOcc x fromThis < 2) delThese ==>
  let res = deleteFirstOfEach delThese fromThis
  in all (`notElem` res) delThese


prop_findFullNameForAbbrev_findsNothing :: NonEmptyList Char -> [T.Text] -> Property
prop_findFullNameForAbbrev_findsNothing (NonEmpty (T.pack -> needle)) hay = any (not . T.null) hay &&
                                                                            all (not . (needle `T.isInfixOf`)) hay ==>
  isNothing . findFullNameForAbbrev needle $ hay


prop_findFullNameForAbbrev_findsMatch :: NonEmptyList Char -> [T.Text] -> Property
prop_findFullNameForAbbrev_findsMatch (NonEmpty (T.pack -> needle)) hay = any (not . T.null) hay &&
                                                                          all (not . (needle `T.isInfixOf`)) hay ==>
  let nonNull = head . filter (not . T.null) $ hay
      match   = needle <> nonNull
      hay'    = match : hay
  in findFullNameForAbbrev needle hay' == Just match


prop_mkCountList :: [Int] -> Bool
prop_mkCountList xs = mkCountList xs == mkCountList' xs
  where
    mkCountList' xs'@(group . sort -> grouped) | ((`map` grouped) -> elemCountList) <- (,) <$> head <*> length =
      let getCountForElem x = snd (head . filter ((== x) . fst) $ elemCountList)
      in map getCountForElem xs'


test_stripControl :: T.Text
test_stripControl = stripControl . quoteWith controlCodes $ "test"
  where
    controlCodes = T.pack $ [ '\0' .. '\31' ] ++ [ '\127' .. (maxBound :: Char) ]


test_stripTelnet_null :: T.Text
test_stripTelnet_null = stripTelnet ""


test_stripTelnet_telnetCodes :: T.Text
test_stripTelnet_telnetCodes = stripTelnet telnetCodes


telnetCodes :: T.Text
telnetCodes = T.pack . map chr $ [ 255, 252, 3, 255, 250, 201, 67, 111, 114, 101, 46, 83, 117, 112, 112, 111, 114, 116, 115, 46, 83, 101, 116, 32, 91, 93, 255, 240 ]


test_stripTelnet_leading :: T.Text
test_stripTelnet_leading = stripTelnet $ telnetCodes <> "test"


test_stripTelnet_trailing :: T.Text
test_stripTelnet_trailing = stripTelnet $ "test" <> telnetCodes


test_stripTelnet_leadingAndTrailing :: T.Text
test_stripTelnet_leadingAndTrailing = stripTelnet $ quoteWith telnetCodes "test"


test_stripTelnet_intercalated :: T.Text
test_stripTelnet_intercalated = stripTelnet $ T.intercalate telnetCodes [ "test1", "test2", "test3", "test4", "test5" ]


test_stripTelnet_malformed1 :: T.Text
test_stripTelnet_malformed1 = stripTelnet . T.singleton $ telnetIAC


test_stripTelnet_malformed2 :: T.Text
test_stripTelnet_malformed2 = stripTelnet . T.pack $ [ telnetIAC, telnetSB, 'a' ]


test_stripTelnet_malformed3 :: T.Text
test_stripTelnet_malformed3 = stripTelnet . T.pack $ telnetIAC : telnetSB : "test"


test_stripTelnet_malformed4 :: T.Text
test_stripTelnet_malformed4 = stripTelnet $ "test" `T.snoc` telnetIAC


test_stripTelnet_malformed5 :: T.Text
test_stripTelnet_malformed5 = stripTelnet $ "test" <> T.pack [ telnetIAC, telnetSB, 'a' ]


test_stripTelnet_malformed6 :: T.Text
test_stripTelnet_malformed6 = stripTelnet $ "test" <> T.pack (telnetIAC : telnetSB : "TEST")