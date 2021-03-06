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

> {-# OPTIONS -XMultiParamTypeClasses -XScopedTypeVariables #-}

> module Antioch.ReceiverTemperatures where

> import Antioch.DateTime
> import Antioch.Types
> import Antioch.Settings                (dssDataDB, dssHost, databasePort)
> import Antioch.Utilities
> import Control.Monad.Trans             (liftIO)
> import Data.Convertible
> import Data.List                       (sort, nub, find)
> import Data.Char                       (toUpper)
> import Database.HDBC
> import Database.HDBC.PostgreSQL
> import Data.IORef
> import System.IO.Unsafe  (unsafePerformIO)
> import qualified Data.Map as M

This module's only responsibility is for maintaining a cache of the each
rcvr's temperatures.

> data ReceiverTemperatures = ReceiverTemperatures {
>     temperatures :: Receiver -> IO ([(Float, Float)])
>   , temperature  :: Receiver -> Float -> [(Float, Float)] -> IO (Float)
> }

The "unsafePerformIO hack" is a way of emulating global variables in GHC.

> {-# NOINLINE globalConnection #-}
> globalConnection :: IORef Connection
> globalConnection = unsafePerformIO $ connect >>= newIORef

> getReceiverTemperatures :: IO ReceiverTemperatures
> getReceiverTemperatures = readIORef globalConnection >>= \cnn -> updateReceiverTemperatures cnn

I'm really getting tired of typing that long-ass name:

> getRT = getReceiverTemperatures

> getRcvrTemps = do
>     cache <- newIORef M.empty
>     return $ getRcvrTemps' cache

> getRcvrTemp = do
>     cache <- newIORef M.empty
>     return $ getRcvrTemp' cache

> updateReceiverTemperatures :: Connection -> IO ReceiverTemperatures
> updateReceiverTemperatures conn = do
>     temperaturesf   <- getRcvrTemps
>     temperaturef    <- getRcvrTemp
>     return ReceiverTemperatures { temperatures = temperaturesf conn 
>                                 , temperature  = temperaturef conn }

> connect :: IO Connection 
> connect = handleSqlError $ connectPostgreSQL cnnStr 
>   where
>     cnnStr = "host=" ++ dssHost ++ " dbname=" ++ dssDataDB ++ " port=" ++ databasePort ++ " user=dss"

> getRcvrTemps' ::  IORef (M.Map (String) ([(Float,Float)])) -> Connection -> Receiver -> IO ([(Float, Float)])
> getRcvrTemps' cache cnn rcvr = withCache key cache $ fetchRcvrTemps cnn rcvr 
>   where 
>     key = show rcvr 

> fetchRcvrTemps ::  Connection -> Receiver -> IO [(Float, Float)]
> fetchRcvrTemps cnn rcvr = do
>     result <- quickQuery' cnn query [toSql . show $ rcvr]
>     return $ toRcvrTempList result
>   where
>     query = "SELECT rt.frequency, rt.temperature FROM receiver_temperatures as rt, receivers as r WHERE r.id = rt.receiver_id AND r.name = ? ORDER BY rt.frequency"
>     toRcvrTempList = map toRcvrTemp
>     toRcvrTemp (freq:temp:[]) = (fromSql freq, fromSql temp)

> getRcvrTemp' ::  IORef (M.Map (String, Float) (Float)) -> Connection -> Receiver -> Frequency -> [(Float, Float)] -> IO (Float)
> getRcvrTemp' cache cnn rcvr freq temps = withCache key cache $ findRcvrTemp rcvr freq temps
>   where 
>     key = (show rcvr, freq) 

> findRcvrTemp ::  Receiver -> Frequency -> [(Float, Float)] -> IO (Float)
> findRcvrTemp rcvr freq temps = do
>     return $ snd . last $ takeWhile (findFreq freq'') temps
>   where
>     findFreq f freqTemp = f >= (fst freqTemp)
>     freq' = (/1000.0) . fromIntegral . freq2HistoryIndex rcvr $ freq
>     freq'' = nearestNeighbor freq' . map fst $ temps

I can't believe I couldn't steal code from somebody else to do 
the nearest neighbor calculation.  So here it is:

> nns :: Ord a => a -> [a] -> (Maybe a, Maybe a)
> nns v []     = (Nothing, Nothing)
> nns v (x:[]) = (Nothing, Just x)
> nns v (x:y:xs) | v < x = (Just x, Nothing)
>                | x <= v && v < y = (Just x, Just y)
>                | otherwise = nns v (y:xs)

Given a value and it's two nearest neighbors, return the neighbor that
is closest.

> nn :: (Num a, Ord a) => a -> (Maybe a, Maybe a) -> a
> nn v (Nothing, Nothing) = v
> nn v (Just x, Nothing) = x
> nn v (Nothing, Just y) = y
> nn v (Just x, Just y) | abs (v - x) <= abs (v - y) = x
>                       | otherwise                  = y

> nearestNeighbor :: (Num a, Ord a) => a -> [a] -> a
> nearestNeighbor v xs = nn v $ nns v xs

> withCache :: Ord k => k -> IORef (M.Map k a) -> IO a -> IO a
> withCache key cache action = do
>     map <- readIORef cache
>     case M.lookup key map of
>         Just val -> return val
>         Nothing  -> do
>             val <- action
>             modifyIORef cache $ M.insert key val
>             return val

