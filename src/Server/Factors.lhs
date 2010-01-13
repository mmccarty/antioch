> module Server.Factors (
>     getFactorsHandler
>   , getFactors
>   ) where
 
> import Control.Monad      (liftM)
> import Control.Monad.Trans                   (liftIO)
> import Control.Monad.State.Lazy              (StateT)
> import Control.Monad.RWS.Strict
> import Data.Record.Label
> import Data.List                             (find, intercalate, sortBy)
> import Data.Maybe                            (maybeToList)
> import Data.Time                             (getCurrentTimeZone, localTimeToUTC)
> import Database.HDBC
> import Database.HDBC.PostgreSQL              (Connection)
> import Network.Protocol.Http
> import Network.Protocol.Uri
> import Network.Salvia.Handlers.PathRouter    (hParameters)
> import Network.Salvia.Handlers.Error         (hError)
> import Network.Salvia.Handlers.MethodRouter  (hMethodRouter)
> import Network.Salvia.Httpd
> import qualified Data.ByteString.Lazy.Char8 as L
> import Server.Json
> import Server.List
> import Antioch.Reports
> import Network.Protocol.Uri 
> import Network.Salvia.Handlers.Redirect      (hRedirect)
> --import Data.Time.LocalTime                   (utcToLocalTime)
> import Text.Printf
> import Maybe
> import Antioch.DateTime
> import Antioch.DSSData                       (getProjects, getSession)
> import Antioch.HardwareSchedule              (getReceiverSchedule)
> import Antioch.Score
> import Antioch.Settings                      (proxyListenerPort)
> import Antioch.Simulate
> import Antioch.Types
> import Antioch.Utilities                     (readMinutes, rad2deg, rad2hrs)
> import Antioch.Weather                       (getWeather)

> getFactorsHandler :: Connection -> Handler()
> getFactorsHandler cnn = hMethodRouter [
>       (GET,  getFactors cnn)
>     -- , (POST, getFactors)
>     ] $ hError NotFound

> getFactors :: Connection -> StateT Context IO ()
> getFactors cnn = do
>     params <- hParameters
>     liftIO $ print params
>     -- Interpret options: id, start, tz, duration
>     let id       = read . fromJust . fromJust . lookup "id" $ params
>     let startStr = fromJust . fromJust . lookup "start" $ params
>     -- timezone
>     let timezone = fromJust . fromJust . lookup "tz" $ params
>     -- start at ...
>     let startStr = fromJust . fromJust . lookup "start" $ params
>     edt <- liftIO getCurrentTimeZone
>     let utc  | timezone == "ET" = localTimeToUTC edt . fromJust . parseLocalTime httpFormat $ startStr
>              | otherwise        = fromJust . parseUTCTime httpFormat $ startStr
>     let dt = toSeconds utc
>     let dur = read . fromJust . fromJust . lookup "duration" $ params
>     -- get target session, and scoring sessions
>     projs <- liftIO getProjects
>     let ss = scoringSessions dt . concatMap sessions $ projs
>     let s = head $ filter (\s -> (sId s) == id) $ concatMap sessions $ projs
>     w <- liftIO $ getWeather Nothing
>     rs <- liftIO $ getReceiverSchedule $ Just dt
>     factors' <- liftIO $ scoreFactors s w ss dt dur rs
>     let scores = map (\x -> [x]) . zip (repeat "score") . map Just . map eval $ factors'
>     factors <- liftIO $ scoreElements s w ss dt dur rs
>     let scoresNfactors = zipWith (++) scores factors
>     jsonHandler $ makeObj [("ra", showJSON . take 5 . show . rad2hrs . ra $ s)
>                          , ("dec", showJSON . take 5 . show . rad2deg . dec $ s)
>                          , ("freq", showJSON . take 4 . show . frequency $ s)
>                          , ("alive", showJSON . schedulableSession dt $ s)
>                          , ("open", showJSON . isTypeOpen dt $ s)
>                          , ("time", showJSON . hasTimeSchedulable dt $ s)
>                          , ("not_complete", showJSON . isNotComplete dt $ s)
>                          , ("enabled", showJSON . not .enabled $ s)
>                          , ("authorized", showJSON . not .authorized $ s)
>                          , ("observers", showJSON . hasObservers dt $ s)
>                          , ("factors", factorsListToJSValue scoresNfactors)]

> data JFactor = JFactor {
>       fName     :: String
>     , fScore    :: Maybe Score
> } deriving Show

> defaultJFactor = JFactor {
>       fName     =  ""
>     , fScore    =  Nothing
> }

> toJFactor :: Factor -> JFactor
> toJFactor f = defaultJFactor {
>                   fName = fst f
>                 , fScore = snd f
>                              }

> instance JSON JFactor where
>     readJSON = jsonToJFactor
>     showJSON = jFactorToJson

> jsonToJFactor _ = undefined

> factorsToJSValue :: [Factor] -> JSValue
> factorsToJSValue = JSArray . map showJSON

> factorsListToJSValue :: [[Factor]] -> JSValue
> factorsListToJSValue = JSArray . map factorsToJSValue

> jFactorToJson :: JFactor -> JSValue
> jFactorToJson jfactor = makeObj $
>       [
>           ("name",  showJSON  . fName $ jfactor)
>         , ("score", showJSON  . fScore $ jfactor)
>       ]
