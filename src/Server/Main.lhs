#! /usr/bin/env runhaskell

> module Main where

> import Control.Concurrent.STM              (atomically, newTVar)
> import Control.Monad.Trans                 (liftIO)
> -- import Database.HDBC                       (disconnect, handleSqlError)
> import Database.HDBC                       
> import Database.HDBC.PostgreSQL            (Connection, connectPostgreSQL)
> import Network.Salvia.Handlers.Default     (hDefault)
> import Network.Salvia.Handlers.Error       (hError)
> import Network.Salvia.Handlers.PathRouter  (hPrefixRouter)
> import Network.Salvia.Handlers.Session     (SessionHandler, mkSessions)
> import Network.Salvia.Handlers.Redirect    (hRedirect)
> import Network.Protocol.Http               (Status(..))
> import Network.Protocol.Uri              
> import Network.Salvia.Httpd
> import Network.Socket                      (inet_addr)
> import Server.JPeriods
> import Server.RunScheduler
> import Maybe

> connect = handleSqlError $ connectPostgreSQL "dbname=dss_pmargani2 user=dss"

> main = do
>     print "starting server"
>     addr <- inet_addr "127.0.0.1"
>     cfg  <- defaultConfig
>     let cfg' = cfg {
>         hostname   = "localhost"
>       , email      = "nubgames@gmail.com"
>       , listenAddr = addr
>       , listenPort = 9099
>       }
>     mkHandler >>= start cfg'

> discardSession           :: Handler a -> SessionHandler () a
> discardSession handler _ = handler

> mkHandler = do
>     counter  <- atomically $ newTVar 0
>     sessions <- mkSessions
>     return $ hDefault counter sessions handler

> getSchedulingURI = fromJust $ parseURI "http://trent.gb.nrao.edu:8001/runscheduler"
> --getSchedulingURI =  mkURI --URI False mkScheme mkAuthority getSchedulingPath mkQuery mkFragment

> --getSchedulingPath = p' { absolute = False }
> --  where 
> --    p' = mkPath

> -- Path { _absolute = False, _segments = ["/periods"] }

> handler = discardSession $ do
>     cnn <- liftIO connect
>     hPrefixRouter [
>           ("/redirect", hRedirect getSchedulingURI) --"/runscheduler") --periodsHandler cnn)
>         , ("/runscheduler", runSchedulerHandler)
>         , ("/schedule", scheduleAndRedirectHandler)
>         , ("/periods", periodsHandler cnn)
>       ] $ hError NotFound
>     liftIO $ disconnect cnn




