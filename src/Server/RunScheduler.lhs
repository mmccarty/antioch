Copyright (C) 2011 Associated Universities, Inc. Washington DC, USA.

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

Correspondence concerning GBT software should be addressed as follows:
      GBT Operations
      National Radio Astronomy Observatory
      P. O. Box 2
      Green Bank, WV 24944-0002 USA

> module Server.RunScheduler where

> import Control.Monad.Trans                   (liftIO)
> import Data.Record.Label
> import Data.List                             (find, intercalate)
> import Data.Maybe                            (maybeToList)
> import Data.Time                             (getCurrentTimeZone, localTimeToUTC)
> import Database.HDBC
> import Control.Monad.State.Lazy              (StateT)
> import Database.HDBC.PostgreSQL              (Connection)
> import Network.Protocol.Http
> import Network.Protocol.Uri
> import Network.Salvia.Handlers.Error         (hError)
> import Network.Salvia.Handlers.MethodRouter  (hMethodRouter)
> import Network.Salvia.Httpd
> import qualified Data.ByteString.Lazy.Char8 as L
> import Server.Json
> import Server.List
> --import Antioch.Reports
> import Network.Protocol.Uri 
> import Network.Salvia.Handlers.Redirect      (hRedirect)
> import Maybe
> import Antioch.Settings                      (proxyListenerPort)
> import Antioch.DateTime
> import Antioch.RunDailySchedule
> import Control.OldException
> import Data.Either

Get params from the URL that can then be used to run the simulator
for the given date range.

> runSchedule :: StateT Context IO ()
> runSchedule = do
>     -- parse params; Note: this look different from other param parsing.
>     bytes <- contents
>     let params   = maybe [] id $ bytes >>= parseQueryParams . L.unpack
>     let params'  = getKeyValuePairs params
>     liftIO $ print params'
>     let tz       = getParam "tz" params'
>     let days'    = read (getParam "duration" params')::Int
>     let days     = if (days' == 0) then 0 else (days' - 1)
>     let startStr = (take 10 $ getParam "start" params') ++ " 00A00A00"
>     liftIO $ print startStr
>     edt <- liftIO getCurrentTimeZone
>     liftIO $ print edt
>     liftIO $ print (parseUTCTime httpFormat startStr)
>     let utc  | tz == "ET" = localTimeToUTC edt . fromJust . parseLocalTime httpFormat $ startStr
>              | otherwise  = fromJust . parseUTCTime httpFormat $ startStr
>     liftIO $ print utc
>     let start = toSeconds utc
>     liftIO $ print start
>
>     -- schedule something! check for errors 
>     liftIO $ print (fromSeconds start)
>     result <- liftIO $ try $ runDailySchedulePack start days
>     case result of
>         Left e -> jsonError e
>         Right x -> jsonSuccess x
>   where
>     getKeyValuePairs pairs = [(key, value) | (key, Just value) <- pairs]
>     wittyMsg = "Unexpected error encounted in service runschedule: " 
>     jsonError e = jsonHandler $ makeObj [("error", showJSON (wittyMsg ++ (show e)))]
>     jsonSuccess x = jsonHandler . makeObj $ objs x
>     objs (schedule, deleted) = [("success", showJSON "ok")]

> getParam :: String -> [(String, String)] -> String
> getParam key params = case pair of
>              Just pair -> snd pair
>              _      -> ""
>   where
>     pair = find (\x -> ((fst x) == key)) params 

> runSchedulerHandler :: Handler ()
> runSchedulerHandler         = hMethodRouter [
>       (POST, runSchedule)
>       --, (GET,  runSchedule)
>     ] $ hError NotFound


