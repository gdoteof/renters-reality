{-# LANGUAGE QuasiQuotes                 #-}
{-# LANGUAGE OverloadedStrings           #-}
{-# OPTIONS -fno-warn-missing-signatures #-}
module Helpers.Forms
    ( runReviewFormNew
    , runReviewFormEdit
    , runProfileFormGet
    , runProfileFormPost
    ) where

import Foundation
import Helpers.Widgets
import Yesod.Goodies
import Control.Applicative ((<$>),(<*>))
import Data.Time           (getCurrentTime)
import Network.Wai         (remoteHost)

import Data.Text (Text)
import qualified Data.Text as T

data ReviewForm = ReviewForm
    { rfIp        :: Text
    , rfLandlord  :: Text
    , rfAddress   :: Textarea
    , rfTimeframe :: Text
    , rfGrade     :: Grade
    , rfReview    :: Markdown
    }

data ProfileEditForm = ProfileEditForm
    { eFullname :: Maybe Text
    , eUsername :: Maybe Text
    , eEmail    :: Maybe Text
    }

data MarkdownExample = MarkdownExample
    { mdText :: String
    , mdHtml :: Widget
    }

runProfileFormGet :: Widget
runProfileFormGet = do
    (_, u)               <- lift requireAuth
    ((_, form), enctype) <- lift . runFormPost $ profileEditForm u

    [whamlet|
        <h1>Edit profile
        <div .content>
            <div .profile>
                <p>
                    Reviews and comments will be tagged with your user 
                    name. If you leave it blank, your full name will be 
                    used in stead.

                <p>
                    Your email is not publicly displayed anywhere. It is 
                    used to find your gravatar image and may be used in 
                    an upcoming "notifications" feature of the site and 
                    even then, only if you opt-in.

                <hr>

                <form enctype="#{enctype}" method="post">
                    <table>
                        ^{form}
                        <tr>
                            <td>&nbsp;
                            <td .buttons>
                                <input type="submit" value="Save">

                <p .delete-button>
                    <a href="@{DeleteProfileR}">delete
        |]

runProfileFormPost :: Handler ()
runProfileFormPost = do
    (uid, u)          <- requireAuth
    ((res, _   ), _ ) <- runFormPost $ profileEditForm u
    case res of
        FormSuccess ef -> saveChanges uid ef
        _              -> return ()

    where
        saveChanges :: UserId -> ProfileEditForm -> Handler ()
        saveChanges uid ef = do
            runDB $ update uid 
                [ UserFullname =. eFullname ef
                , UserUsername =. eUsername ef
                , UserEmail    =. eEmail    ef
                ]

            tm <- getRouteToMaster
            redirect RedirectTemporary $ tm ProfileR

runReviewFormEdit :: Document -> Widget
runReviewFormEdit (Document rid r l _) = do
    ip <- lift $ return . T.pack . show . remoteHost =<< waiRequest
    ((res, form), enctype) <- lift . runFormPost $ reviewForm (Just r) (Just $ landlordName l) ip
    case res of
        FormMissing    -> return ()
        FormFailure _  -> return ()
        FormSuccess rf -> lift $ do
            tm  <- getRouteToMaster
            _   <- updateFromForm rf
            redirect RedirectTemporary $ tm (ReviewsR rid)

    [whamlet|<form enctype="#{enctype}" method="post">^{form}|]

    where
        updateFromForm :: ReviewForm -> Handler ReviewId
        updateFromForm  rf = do
            -- might've changed
            landlordId <- findOrCreate $ Landlord $ rfLandlord rf

            runDB $ update rid [ ReviewLandlord  =.landlordId
                               , ReviewGrade     =. rfGrade     rf
                               , ReviewAddress   =. rfAddress   rf
                               , ReviewTimeframe =. rfTimeframe rf
                               , ReviewContent   =. rfReview    rf
                               ]

            -- for type consistency
            return rid

runReviewFormNew :: UserId -> Maybe T.Text -> Widget
runReviewFormNew uid ml = do
    ip <- lift $ return . T.pack . show . remoteHost =<< waiRequest
    ((res, form), enctype) <- lift . runFormPost $ reviewForm Nothing ml ip
    case res of
        FormMissing    -> return ()
        FormFailure _  -> return ()
        FormSuccess rf -> lift $ do
            tm  <- getRouteToMaster
            rid <- insertFromForm rf
            redirect RedirectTemporary $ tm (ReviewsR rid)

    [whamlet|<form enctype="#{enctype}" method="post">^{form}|]

    where
        insertFromForm :: ReviewForm -> Handler ReviewId
        insertFromForm rf = do
            now        <- liftIO getCurrentTime
            landlordId <- findOrCreate $ Landlord $ rfLandlord rf

            runDB $ insert $ Review
                    { reviewCreatedDate = now
                    , reviewIpAddress   = rfIp rf
                    , reviewGrade       = rfGrade rf
                    , reviewAddress     = rfAddress rf
                    , reviewContent     = rfReview rf
                    , reviewTimeframe   = rfTimeframe rf
                    , reviewReviewer    = uid
                    , reviewLandlord    = landlordId
                    }

profileEditForm :: User -> Html -> MForm Renters Renters (FormResult ProfileEditForm, Widget)
profileEditForm u = renderTable $ ProfileEditForm
    <$> aopt textField "Full name" (Just $ userFullname u)
    <*> aopt textField "User name" (Just $ userUsername u)
    <*> aopt emailField "Email:"
        { fsTooltip = Just "never displayed, only used to find your gravatar"
        } (Just $ userEmail u)

reviewForm :: Maybe Review -- ^ for use in edit
           -> Maybe Text   -- ^ maybe landlord name (for use in new)
           -> Text         -- ^ IP address of submitter
           -> Html         -- ^ nonce fragment
           -> MForm Renters Renters (FormResult ReviewForm, Widget)
reviewForm mr ml ip fragment = do
    (fIp       , fiIp       ) <- mreq hiddenField   (ffs ""            "ip"       ) (Just ip                )
    (fLandlord , fiLandlord ) <- mreq textField     (ffs "Landlord:"   "landlord" ) (ml                     )
    (fAddress  , fiAddress  ) <- mreq textareaField (ffs "Address:"    "address"  ) (fmap reviewAddress   mr)
    (fTimeframe, fiTimeframe) <- mreq textField     (ffs "Time frame:" "timeframe") (fmap reviewTimeframe mr)
    (fGrade    , fiGrade    ) <- mreq selectGrade   (ffs "Grade:"      "grade"    ) (fmap reviewGrade     mr)
    (fReview   , fiReview   ) <- mreq markdownField (ffs "Review:"     "review"   ) (fmap reviewContent   mr)

    return (ReviewForm 
        <$> fIp      <*> fLandlord  
        <*> fAddress <*> fTimeframe  
        <*> fGrade   <*> fReview, [whamlet|
            #{fragment}
            <table .review-form>
                <tr #ip>^{fieldCell 4 fiIp}

                <tr #landlord-grade>
                    ^{fieldCell 1 fiLandlord}
                    ^{fieldCell 1 fiGrade}

                <tr #timeframe>
                    ^{fieldCell 4 fiTimeframe}
                    <td colspan=3>&nbsp;

                <tr #address>
                    ^{fieldCell 4 fiAddress}
                    <td colspan=3>&nbsp;

                <tr #review-help>
                    <td>&nbsp;
                    <td colspan="5">
                        <small>
                            <em>
                                Reviews are parsed as pandoc-style markdown. 
                                <a #open-help href="#">Tips.

                <tr #review>^{fieldCell 4 fiReview}

                <tr>
                    <td>&nbsp;
                    <td .buttons colspan="4">
                        <input type="submit" value="Save">
            |])

        where
            selectGrade = selectField gradesList
                where
                    gradesList :: [(Text, Grade)]
                    gradesList = [ ("A+", Aplus )
                                 , ("A" , A     )
                                 , ("A-", Aminus)
                                 , ("B+", Bplus )
                                 , ("B" , B     )
                                 , ("B-", Bminus)
                                 , ("C+", Cplus )
                                 , ("C" , C     )
                                 , ("C-", Cminus)
                                 , ("D+", Dplus )
                                 , ("D" , D     )
                                 , ("D-", Dminus)
                                 , ("F" , F     )
                                 ]

            ffs :: Text -> Text -> FieldSettings Text
            ffs label theId = FieldSettings label Nothing (Just theId) Nothing

            -- span for the input cell only
            fieldCell :: Int -> FieldView s m -> GWidget s m ()
            fieldCell colspan fv = [whamlet|
                <th>
                    <label for="#{fvId fv}">#{fvLabel fv}
                <td ##{fvId fv} colspan=#{show colspan}>^{fvInput fv}
                <td>
                    $maybe error <- fvErrors fv
                        #{error}
                    $nothing
                        &nbsp;
                |]

-- FIXME: kind mismatch?
--findOrCreate :: PersistEntity v => v -> Handler (Key Renters v)
findOrCreate v = return . either fst id =<< runDB (insertBy v)

helpBoxContents :: Widget
helpBoxContents = [whamlet|
        <h3>Some quick examples:

        $forall mdExample <- mdExamples
            <p .example>
                <code>#{mdText mdExample} 
                will render as ^{mdHtml mdExample}

        <p>
            <em>
                Additional documentation can be found 
                <a href="http://daringfireball.net/projects/markdown/syntax">here
                \.
    |]

mdExamples :: [MarkdownExample]
mdExamples = [ MarkdownExample "*italic text*"
                    [whamlet|<em>italic text|]

             , MarkdownExample "**bold text**"
                    [whamlet|<strong>bold text|]

             , MarkdownExample "[some link](http://example.com \"link title\")"
                    [whamlet|<a href="http://example.com" title="link title">some link|]

             , MarkdownExample "![even images](http://pbrisbin.com/static/images/feed.png)"
                    [whamlet|<img alt="even images" src="http://pbrisbin.com/static/images/feed.png">|]
             ]
