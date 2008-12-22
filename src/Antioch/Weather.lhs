> module Antioch.Weather where

> import Antioch.DateTime
> import Antioch.Types
> import Antioch.Utilities
> import Control.Exception (IOException, bracketOnError, catch)
> import Data.IORef
> import Data.List (elemIndex)
> import Data.Maybe (fromJust, isNothing)
> import Database.HDBC
> import Database.HDBC.ODBC
> import Prelude hiding (catch)
> import System.IO.Unsafe (unsafePerformIO)
> import Test.QuickCheck

> data Weather = Weather {
>     wind            :: DateTime -> (Maybe Float) -- m/s
>   , tatm            :: DateTime -> (Maybe Float) -- Kelvin
>   , opacity         :: DateTime -> Float -> (Maybe Float)
>   , tsys            :: DateTime -> Float -> (Maybe Float)
>   , totalStringency :: Float -> Radians -> (Maybe Float)
>   , minOpacity      :: Float -> Radians -> (Maybe Float)
>   , minTSys'        :: Float -> Radians -> (Maybe Float)
>   }

> getWeather     :: Maybe DateTime -> IO Weather
> getWeather now = bracketOnError connect disconnect $ \conn' -> do
>     now' <- case now of
>         Nothing -> getCurrentTime
>         Just n  -> return n
>     conn' <- connect
>     conn  <- newIORef conn'
>     return Weather {
>         wind            = getWind conn now'
>       , tatm            = getTAtm conn now'
>       , opacity         = getOpacity conn now'
>       , tsys            = getTSys conn now'
>       , totalStringency = getTotalStringency conn
>       , minOpacity      = getMinOpacity conn
>       , minTSys'        = getMinTSys' conn
>       }

> instance SqlType Float where
>     toSql x   = SqlDouble ((realToFrac x) :: Double)
>     fromSql x = realToFrac ((fromSql x) :: Double) :: Float

Both wind speed and atmospheric temperature are values forecast independently
of frequency.

> getWind :: IORef Connection -> DateTime -> DateTime -> Maybe Float
> getWind conn now target = getWind' conn target (determineFType target now)

> getWind'               :: IORef Connection -> DateTime -> Int -> Maybe Float
> getWind' conn dt ftype =
>     getFloat conn query [toSql . toSqlString $ dt, toSql ftype]
>   where query = "SELECT wind_speed FROM forecasts\n\
>                  \WHERE date = ? AND forecast_type_id = ?"

> getTAtm :: IORef Connection -> DateTime -> DateTime -> Maybe Float
> getTAtm conn now target = getTAtm' conn target (determineFType target now)

> getTAtm' :: IORef Connection -> DateTime -> Int -> Maybe Float
> getTAtm' conn dt ftype =
>     getFloat conn query [toSql . toSqlString $ dt, toSql ftype]
>   where query = "SELECT tatm FROM forecasts\n\
>                  \WHERE date = ? AND forecast_type_id = ?"

However, opacity and system temperature (tsys) are values forecast dependent
on frequency.

> getOpacity :: IORef Connection -> DateTime -> DateTime -> Float -> Maybe Float
> getOpacity conn now target frequency = 
>     getOpacity' conn target (determineFType target now) frequency

> getOpacity' :: IORef Connection -> DateTime -> Int -> Float -> Maybe Float
> getOpacity' conn dt ftype frequency = 
>     getFloat conn query [toSql . toSqlString $ dt
>                        , toSql (round frequency :: Int)
>                        , toSql ftype]
>   where query = "SELECT opacity\n\
>                  \FROM forecasts, forecast_by_frequency\n\
>                  \WHERE date = ? AND\n\
>                  \frequency = ? AND\n\
>                  \forecast_type_id = ? AND\n\
>                  \forecasts.id = forecast_by_frequency.forecast_id"

> getTSys :: IORef Connection -> DateTime -> DateTime -> Float -> Maybe Float
> getTSys conn now target frequency = 
>     getTSys' conn target (determineFType target now) frequency

> getTSys' :: IORef Connection -> DateTime -> Int -> Float -> Maybe Float
> getTSys' conn dt ftype frequency = 
>     getFloat conn query [toSql . toSqlString $ dt
>                        , toSql (round frequency :: Int)
>                        , toSql ftype]
>   where query = "SELECT tsys\n\
>                  \FROM forecasts, forecast_by_frequency\n\
>                  \WHERE date = ? AND frequency = ? AND\n\
>                  \forecast_type_id = ? AND\n\
>                  \forecasts.id = forecast_by_frequency.forecast_id"

> getTotalStringency :: IORef Connection -> Float -> Radians -> Maybe Float
> getTotalStringency conn f e = 
>     getFloat conn query [toSql (round f :: Int)
>                        , toSql (round . rad2deg $ e :: Int)]
>   where query = "SELECT total FROM stringency\n\
>                  \WHERE frequency = ? AND elevation = ?"

> getMinOpacity :: IORef Connection -> Float -> Radians -> Maybe Float
> getMinOpacity conn f e = 
>     getFloat conn query [toSql (round f :: Int)
>                        , toSql (round . rad2deg $ e :: Int)]
>   where query = "SELECT opacity FROM min_weather\n\
>                  \WHERE frequency = ? AND elevation = ?"

> getMinTSys' :: IORef Connection -> Float -> Radians -> Maybe Float
> getMinTSys' conn f e = 
>     getFloat conn query [toSql (round f :: Int)
>                        , toSql (round . rad2deg $ e :: Int)]
>   where query = "SELECT prime FROM t_sys\n\
>                  \WHERE frequency = ? AND elevation = ?"

Creates a connection to the weather forecast database.

> connect :: IO Connection
> connect = handleSqlError $ do
>     conn <- connectODBC "dsn=DSS;password=asdf5!"
>     return conn

Helper function to determine the desired forecast type given two DateTimes.

> determineFType :: DateTime -> DateTime -> Int
> determineFType target now = 
>     case dropWhile (< difference) $ forecast_types of
>         []     -> length forecast_types
>         (x:xs) -> fromJust (elemIndex x forecast_types) + 1
>   where difference = (toSeconds target - toSeconds now) `div` 3600
>         forecast_types = [12, 24, 36, 48, 60]

> prop_constrained target now = determineFType target now `elem` forecast_types
>   where forecast_types = [1..5]

Helper function to get singular Float values out of the database.

> getFloat :: IORef Connection -> String -> [SqlValue] -> Maybe Float
> getFloat conn query xs = unsafePerformIO . handleSqlError $ do
>     result <- tryQuery conn query xs
>     case result of
>         [[SqlNull]] -> return Nothing
>         [[x]] -> return $ Just (fromSql x)
>         [[]]  -> return Nothing
>         []    -> return Nothing
>         x     -> fail "There is more than one forecast with that time stamp."

> tryQuery :: IORef Connection -> String -> [SqlValue] -> IO [[SqlValue]]
> tryQuery conn query xs = do
>     conn' <- readIORef conn
>     quickQuery' conn' query xs `catch` \e -> do
>         print (e :: IOException)
>         c' <- connect
>         writeIORef conn c'
>         quickQuery' c' query xs

Just some test functions to make sure things are working.

> testWeather = do
>     w <- getWeather now
>     return $ (wind w target
>             , tatm w target
>             , opacity w target frequency
>             , tsys w target frequency
>             , totalStringency w frequency elevation
>             , minOpacity w frequency elevation
>             , minTSys' w frequency elevation)
>   where 
>     frequency = 2.0 :: Float
>     elevation = pi / 4.0 :: Radians
>     now       = Just (fromGregorian 2004 05 03 12 00 00)
>     target    = fromGregorian 2004 05 03 12 00 00
