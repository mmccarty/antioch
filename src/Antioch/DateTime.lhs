> module Antioch.DateTime where

> import Data.Fixed                 (div')
> import Data.Function              (on)
> import Data.Time.Calendar hiding  (fromGregorian, toGregorian)
> import Data.Time.Clock hiding     (getCurrentTime)
> import Data.Time.Format
> import Data.Time.LocalTime
> import Database.HDBC
> import Numeric                    (fromRat)
> import System.Locale
> import System.Time hiding         (toClockTime)
> import Test.QuickCheck
> import Text.Printf

> import qualified Data.Time.Calendar as Calendar
> import qualified Data.Time.Clock as Clock

> type DateTime = Int

> -- edt <- getCurrentTimeZone     -- if running in Green Bank then EDT

> instance Arbitrary UTCTime where
>     arbitrary       = do
>         offset <- choose (0, 20000) :: Gen Float
>         return . fromMJD' $ offset + fromRational startOfTimeMJD
>     coarbitrary _ b = b

So that we can use our UTCTime class with HDBC.

> -- instance SqlType UTCTime where
> --     toSql   = toSql . toClockTime
> --     fromSql = fromClockTime . fromSql

Defined here so that users don't need to know about Data.Time.Clock.

> getCurrentTime :: IO DateTime
> getCurrentTime = fmap toSeconds Clock.getCurrentTime

> secondsToMJD   :: Int -> Float
> secondsToMJD s = 40587.0 + (fromIntegral s / 86400.0)

> secondsToMJD'   :: Int -> Double
> secondsToMJD' s = 40587.0 + (fromIntegral s / 86400.0)

> prop_secondsToMJD = invariant $ fromMJD' . secondsToMJD . toSeconds

Conversion back and forth between UTCTime and MJD.

> toMJD :: UTCTime -> Rational
> toMJD = getModJulianDate . toUniversalTime

> toMJD' :: RealFloat a => UTCTime -> a
> toMJD' = fromRat . toMJD

> fromMJD :: Rational -> UTCTime
> fromMJD = fromUniversalTime . ModJulianDate

> fromMJD' :: RealFloat a => a -> UTCTime
> fromMJD' = fromMJD . realToFrac

> invariant f x = f x == x
  
> prop_MJD  = invariant $ fromMJD  . toMJD
> prop_MJD' = invariant $ fromMJD' . toMJD'

Because UTCTime is opaque, we need to convert to UniversalTime in
order to do anything with it, but these functions are mainly of
interest internally.

> toUniversalTime :: UTCTime -> UniversalTime
> toUniversalTime = localTimeToUT1 0 . utcToLocalTime utc

> fromUniversalTime :: UniversalTime -> UTCTime
> fromUniversalTime = localTimeToUTC utc . ut1ToLocalTime 0

> prop_Universal = invariant $ fromUniversalTime . toUniversalTime

> replaceYear :: Int -> DateTime -> DateTime
> replaceYear yyyy dt = fromGregorian yyyy m d h mm s
>    where
>      (_, m, d, h, mm, s) = toGregorian dt

> replaceMonth :: Int -> DateTime -> DateTime
> replaceMonth month dt = fromGregorian y month d h mm s
>    where
>      (y, _, d, h, mm, s) = toGregorian dt

> setHour :: Int -> DateTime -> DateTime
> setHour hour dt = fromGregorian y m d hour 0 0
>   where
>      (y, m, d, _, _, _) = toGregorian dt
   
Takes into account 12 months a year and wrap-around

> addMonth :: DateTime -> DateTime
> addMonth dt | month == 12 = replaceYear nextYear $ replaceMonth 1 dt
>             | otherwise   = replaceMonth nextMonth dt
>   where
>      (y, month, d, h, mm, s) = toGregorian dt
>      nextMonth = month + 1
>      nextYear = y + 1

Take apart a UTCTime into pieces and parts.
  
> toGregorian'    :: DateTime -> (Int, Int, Int)
> toGregorian' dt = (y, m, d)
>   where
>     (y, m, d, _, _, _) = toGregorian dt

> toGregorian    :: DateTime -> (Int, Int, Int, Int, Int, Int)
> toGregorian dt = (fromIntegral year, month, day', hours, minutes, seconds `div'` 1)
>   where
>     LocalTime day tod   = utcToLocalTime utc . fromSeconds $ dt
>     (year, month, day') = Calendar.toGregorian day
>     TimeOfDay hours minutes seconds = tod

Combine pieces and parts to produce a UTCTime.
      
> fromGregorian'       :: Int -> Int -> Int -> DateTime
> fromGregorian' y m d = fromGregorian y m d 0 0 0

> fromGregorian :: Int -> Int -> Int -> Int -> Int -> Int -> DateTime
> fromGregorian year month day hours minutes seconds = toSeconds $
>     UTCTime day' (secondsToDiffTime . fromIntegral $ seconds')
>   where
>     day'     = Calendar.fromGregorian (fromIntegral year) month day
>     seconds' = 3600 * hours + 60 * minutes + seconds

> roundToHour dt = 3600 * ((dt + 1800) `div` 3600)

Getting closer to the machine: Not all the functionality of
System.Time is available in Data.Time, and the only way we can convert
back and forth is to go through seconds.

> toSeconds    :: UTCTime -> Int
> toSeconds dt = floor $
>     86400.0 * fromRational (toMJD dt - startOfTimeMJD)

> fromSeconds   :: Int -> UTCTime
> fromSeconds s = fromMJD $
>     fromIntegral s / 86400 + startOfTimeMJD

> toClockTime    :: UTCTime -> ClockTime
> toClockTime dt = TOD (fromIntegral . toSeconds $ dt) 0

> fromClockTime           :: ClockTime -> UTCTime
> fromClockTime (TOD s _) = fromSeconds . fromIntegral $ s

> startOfTime :: DateTime
> startOfTime = 0

> startOfTimeMJD :: Rational
> startOfTimeMJD = toMJD $ UTCTime (Calendar.fromGregorian 1970 1 1) 0

Formatting and parsing, with special attention to the format used by
ODBC and MySQL.

> toSqlString    :: DateTime -> String
> toSqlString dt = printf "%04d-%02d-%02d %02d:%02d:%02d" year month day hours minutes seconds
>   where
>     (year, month, day, hours, minutes, seconds) = toGregorian dt

> toHttpString    :: DateTime -> String
> toHttpString dt = formatUTCTime httpFormat . fromSeconds $ dt

> fromSqlString :: String -> Maybe DateTime
> fromSqlString = fmap toSeconds . parseUTCTime sqlFormat

> fromSqlDateString :: String -> Maybe DateTime
> fromSqlDateString = fmap toSeconds . parseUTCTime sqlDateFormat

> fromHttpString :: String -> Maybe DateTime
> fromHttpString = fmap toSeconds . parseUTCTime httpFormat

The string conversions may loss precision at the level of a second.  This is
close enough for our purposes (TBF)?

> prop_SqlString dt = diffSeconds dt dt' <= 1
>   where
>     Just dt' = fromSqlString . toSqlString $ dt

> prop_SqlStartOfTime _ = toSqlString startOfTime == "1970-01-01 00:00:00"

> formatUTCTime :: String -> UTCTime -> String
> formatUTCTime = formatTime defaultTimeLocale

> parseUTCTime :: String -> String -> Maybe UTCTime
> parseUTCTime = parseTime defaultTimeLocale

> formatLocalTime :: String -> LocalTime -> String
> formatLocalTime = formatTime defaultTimeLocale

> parseLocalTime :: String -> String -> Maybe LocalTime
> parseLocalTime = parseTime defaultTimeLocale

> sqlFormat = iso8601DateFormat (Just "%T")

> sqlDateFormat = iso8601DateFormat (Just "")

> httpFormat = iso8601DateFormat (Just " %HA%MA%S") -- TBF space needed?

Simple arithmetic.

> addHours :: Int -> DateTime -> DateTime
> addHours = addMinutes . (60 *)

> diffHours :: Int -> DateTime -> DateTime
> diffHours x = (`div` 60) . diffMinutes x

> addMinutes' :: Int -> DateTime -> DateTime
> addMinutes' = addMinutes
  
> addMinutes :: Int -> DateTime -> DateTime
> addMinutes = addSeconds . (60 *)

> diffMinutes' :: DateTime -> DateTime -> Int
> diffMinutes' = diffMinutes

> diffMinutes   :: DateTime -> DateTime -> Int
> diffMinutes x = (`div` 60) . diffSeconds x
  
> addSeconds :: Int -> DateTime -> DateTime
> addSeconds = (+)

> diffSeconds :: DateTime -> DateTime -> Int
> diffSeconds = (-)

> isDayTime    :: DateTime -> Bool
> isDayTime dt = rise <= dt && dt < set
>   where
>     (rise, set) = sunRiseAndSet dt

PTCS Version 1.0:

> isPTCSDayTime    :: DateTime -> Bool
> isPTCSDayTime dt = rise + 3600 * 2 <= dt && dt < set + 3600 * 3
>   where
>     (rise, set) = sunRiseAndSet dt

PTCS Version 2.0:

> isPTCSDayTime_V2    :: DateTime -> Bool
> isPTCSDayTime_V2 dt = rise <= dt && dt < set + 3600 * 3
>   where
>     (rise, set) = sunRiseAndSet dt

TBF use ET and translate to UT

> isHighRFITime :: DateTime -> Bool
> isHighRFITime dt = badRFIStart dt <= dt && dt <= badRFIEnd dt
>   where
>     badRFIStart dt = 86400 * (dt `div` 86400) + 12 * 3600  -- 8 AM ET
>     badRFIEnd dt   = 86400 * (dt `div` 86400) + 24 * 3600  -- 8 PM ET

Accurate to about 12 min. Only works for Green Bank.

You can also check this code against various resources, including:
http://aa.usno.navy.mil/data/docs/RS_OneYear.php

> years = map (\y -> fromGregorian' y 1 1) [2011, 2010 .. 2006]

> dayOfYear dt = (dt - year) `div` 86400
>   where
>     (year : _) = dropWhile (dt <) years

> (a, b, c, d, e) = (11.2178,  1.2754, -0.0915, 0.0673, 0.1573)
> (l, m, n, o, p) = (23.3553, -1.3304,  0.3406, 0.0525, 0.1520)

> hoursToSeconds hours = floor $ 86400.0 * (hours / 24.0)

> sunRiseAndSet    :: DateTime -> (DateTime, DateTime)
> sunRiseAndSet dt = (midnight + hoursToSeconds rise, midnight + hoursToSeconds set)
>   where
>     midnight = 86400 * (dt `div` 86400)
>     day = dayOfYear midnight
>     g   = 2.0 * pi * (fromIntegral day / 365.0)
>     cosg  = cos g
>     sing  = sin g
>     cos2g = 2.0 * cosg * cosg - 1.0
>     sin2g = 2.0 * cosg * sing
>     rise  = a + (b * cosg) + (c * sing) + (d * cos2g) + (e * sin2g)
>     set   = l + (m * cosg) + (n * sing) + (o * cos2g) + (p * sin2g)
