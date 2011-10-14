{-# LANGUAGE GADTs                      #-}
{-# LANGUAGE QuasiQuotes                #-}
{-# LANGUAGE TypeFamilies               #-}
{-# LANGUAGE TemplateHaskell            #-}
{-# LANGUAGE OverloadedStrings          #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
module Model where

import Yesod
import Yesod.Goodies
import Database.Persist.Base
import Data.Ord  (comparing)
import Data.Time (UTCTime(..))
import Data.Text (Text)
import qualified Data.Text as T

data Grade = Aplus | A | Aminus
           | Bplus | B | Bminus
           | Cplus | C | Cminus
           | Dplus | D | Dminus
           | F deriving (Eq, Ord, Read, Show)

derivePersistField "Grade"

share [mkPersist sqlSettings, mkMigrate "migrateAll"] $(persistFile "config/models")

data Document = Document
    { reviewId :: ReviewId
    , review   :: Review
    , landlord :: Landlord
    , user     :: User
    }

-- | To search a "document" as text is to search its landlord's name and 
--   the single-string address info
instance TextSearch Document where
    toText d@(Document _ _ l _) = landlordName l `append` formatAddress d

        where
            append :: Text -> Text -> Text
            a `append` b = a `T.append` " " `T.append` b

-- | Search by keyword and lend preference to more recent reviews
instance Search Document where
    preference = comparing (reviewCreatedDate . review . searchResult)
    match      = keywordMatch

showName :: User -> Text
showName (User _         (Just un) _ _ _) = shorten 40 un
showName (User (Just fn) _         _ _ _) = shorten 40 fn
showName _                                = "anonymous"

formatAddress :: Document -> Text
formatAddress (Document _ r _ _) = T.map go . T.filter (/= '\r') . unTextarea $ reviewAddress r

    where
        go :: Char -> Char
        go '\n' = ' '
        go x    = x

docsByLandlordId :: LandlordId -> [Document] -> [Document]
docsByLandlordId lid = filter ((== lid) . reviewLandlord . review)

docByReviewId:: ReviewId -> [Document] -> Maybe Document
docByReviewId rid docs =
    case filter ((== rid) . reviewId) docs of
        []    -> Nothing
        (x:_) -> Just x

gpa :: [Grade] -> Double
gpa = mean . map toNumeric

    where
        -- http://cgi.cse.unsw.edu.au/~dons/blog/2008/05/16#fast
        mean :: [Double] -> Double
        mean = go 0 0
            where
                go :: Double -> Int -> [Double] -> Double
                go s l []     = s / fromIntegral l
                go s l (x:xs) = go (s+x) (l+1) xs

        toNumeric :: Grade -> Double
        toNumeric Aplus  = 4.5
        toNumeric A      = 4.0
        toNumeric Aminus = 3.75
        toNumeric Bplus  = 3.5
        toNumeric B      = 3.0
        toNumeric Bminus = 2.75
        toNumeric Cplus  = 2.5
        toNumeric C      = 2.0
        toNumeric Cminus = 1.75
        toNumeric Dplus  = 1.5
        toNumeric D      = 1.0
        toNumeric Dminus = 0.75
        toNumeric F      = 0.0

prettyGrade :: Grade -> Text
prettyGrade Aplus  = "A+"
prettyGrade A      = "A"
prettyGrade Aminus = "A-"
prettyGrade Bplus  = "B+"
prettyGrade B      = "B"
prettyGrade Bminus = "B-"
prettyGrade Cplus  = "C+"
prettyGrade C      = "C"
prettyGrade Cminus = "C-"
prettyGrade Dplus  = "D+"
prettyGrade D      = "D"
prettyGrade Dminus = "D-"
prettyGrade F      = "F"
