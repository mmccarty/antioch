> module Antioch.Types where

> import Antioch.DateTime
> import Data.Function (on)
> import Data.List     (find)
> import Data.Ix

> type Frequency = Float
> type Minutes   = Int
> type Score     = Float
> type Radians   = Float
> type Grade     = Float

> quarter = 15 :: Minutes

> data Receiver = NoiseSource
>               | Rcvr_RRI
>               | Rcvr_342
>               | Rcvr_450
>               | Rcvr_600
>               | Rcvr_800
>               | Rcvr_1070
>               | Rcvr1_2
>               | Rcvr2_3
>               | Rcvr4_6
>               | Rcvr8_10
>               | Rcvr12_18
>               -- | Rcvr18_22
>               -- | Rcvr22_26 -- these 2 rcvrs wrapped in one like in DB 
>               | Rcvr18_26
>               | Rcvr26_40
>               | Rcvr40_52
>               | Rcvr_PAR
>               | Zpectrometer
>               | Holography
>               | RcvrArray18_26
>               deriving (Eq, Show, Read)

Sessions store their desired Rcvrs in Conjugate Normal Form (CNF).
Ex: [K or L] and [K or S], or [[Receiver]].  In this form, all
'or' receiver groups must evaluate as True.

> type ReceiverGroup = [Receiver]

> data Band = L | S | C | X | U | K | A | Q | W
>           deriving (Bounded, Enum, Eq, Ix, Ord, Read, Show)
> data SessionType = Open | Fixed | Windowed deriving (Eq, Show, Read)
> data TransitType = Optional | Partial | Center deriving (Eq, Show, Read)

TBF: Initially, Open, Fixed, and Windowed all share the same contents.
Ideally, we need to evolve these as we go and add new items and remove
useless items. Until the need arises to use different types, we will
use a single data structure for all sessions.

> data Session = Session {
>     sId         :: Int
>   , sName       :: String
>   , sAlloted    :: Minutes
>   , sClosed     :: Bool
>   , project     :: Project
>   , windows     :: [Window]
>   , periods     :: [Period]
>   , minDuration :: Minutes
>   , maxDuration :: Minutes
>   , timeBetween :: Minutes
>   , frequency   :: Float
>   , ra          :: Radians
>   , dec         :: Radians
>   , backup      :: Bool
>   , receivers   :: [ReceiverGroup]
>   , enabled     :: Bool
>   , authorized  :: Bool
>   , grade       :: Grade
>   , band        :: Band
>   , lowRFI      :: Bool
>   , lstExclude  :: [(Float, Float)]
>   , sType       :: SessionType
>   , transit     :: TransitType
>   } deriving Show

> instance Eq Session where
>     (==) = (==) `on` sId

> instance Ord Session where
>     compare = compare `on` sId

> -- TBF ??? sure looks like legacy code to me!
> --periods' s@(Fixed { }) = [period s]
> periods' s             = periods s

> data Window  = Window {
>     wSession     :: Session
>   , wStart       :: DateTime   -- date
>   , wDuration    :: Minutes    -- from day count
>   , wPeriodId    :: Int        -- default period id
>    }

> instance Show Window where
>     show w = "Window for: " ++ printName w ++ " from " ++ toSqlString (wStart w) ++ " for " ++ show (wDuration w) ++ " days; Period: " ++ show (wPeriod w)
>       where 
>         n = sName . wSession $ w
>         printName w = if n == "" then show . sId . wSession $ w else n

> instance Ord Window where
>     (<) = (<) `on` wStart
>     (>) = (>) `on` wStart
>     (<=) = (<=) `on` wStart
>     (>=) = (>=) `on` wStart

> instance Eq Window where
>     (==) = windowsEqual

> wPeriod :: Window -> Maybe Period
> wPeriod w = find (\p -> (wPeriodId w) == (peId p)) (periods . wSession $ w)

> hasWindows :: Session -> Bool
> hasWindows s = (sType s) == Windowed && (windows s) /= []

> windowsEqual :: Window -> Window -> Bool
> windowsEqual w1 w2 = eqIds w1 w2 &&
>                      eqStarts w1 w2 &&
>                      eqDurs w1 w2 
>   where
>     eqIds    = (==) `on` wSession
>     eqStarts = (==) `on` wStart
>     eqDurs   = (==) `on` wDuration

Need to calculate a windowed session's opportunities from its observation details.

Tying the knot.

> makeSession      :: Session -> [Window] -> [Period] -> Session
> makeSession s ws ps = s'
>   where
>     s' = s { windows = map (\w -> w { wSession = s'}) ws
>            , periods = map (\p -> p { session = s' }) ps
>            }

> updateSession      :: Session -> [Period] -> Session
> updateSession s ps = makeSession s (windows s) $ periods' s ++ ps

> data Project = Project {
>     pId             :: !Int
>   , pName           :: !String
>   , pAlloted        :: !Minutes
>   , pClosed         :: !Bool
>   , semester        :: !String
>   , sessions        :: [Session]
>   , thesis          :: !Bool
>   , maxSemesterTime :: !Minutes
>   , observers       :: [Observer]
>   } deriving Eq

> makeProject :: Project -> Minutes -> [Session] -> Project
> makeProject p tt ss = p'
>   where
>     p' = p { pAlloted = tt, sessions = map (\s -> s { project = p' }) ss }
>     t  = sum . map sAlloted $ ss

> instance Show Project where
>     show p = "Project: " ++ pName p ++ ", " ++ semester p ++ " Time: ("++ (show . pAlloted $ p) ++ ") Sessions: " ++ show [ sAlloted s | s <- sessions p] 

> type DateRange = (DateTime, DateTime)

> inDateRange :: DateTime -> DateRange -> Bool
> inDateRange dt r = start < dt && dt < end
>   where
>     start = fst r
>     end   = snd r

> data Observer = Observer {
>     oId          :: Int
>   , firstName    :: String -- for debugging
>   , lastName     :: String -- for debugging
>   , username     :: String
>   , pstId        :: Int
>   , sanctioned   :: Bool
>   , reservations :: [DateRange]
>   , blackouts    :: [DateRange]
> } deriving (Eq, Show, Read)

> data Period  = Period  {
>     peId        :: Int
>   , session     :: Session
>   , startTime   :: DateTime
>   , duration    :: Minutes
>   , pScore      :: Score  -- Average forecasted score
>   , pForecast   :: DateTime
>   , pBackup     :: Bool
>   , pTimeBilled :: Minutes
>   } 

> instance Show Period where
>     show p = "Period: " ++ printName p ++ " (" ++ show (peId p) ++ ") at " ++ toSqlString (startTime p) ++ " for " ++ show (duration p) ++ " (" ++ show (pTimeBilled p) ++ ") with score of " ++ show (pScore p) ++ " from " ++ (toSqlString . pForecast $ p)
>       where 
>         n = sName . session $ p
>         printName p = if n == "" then show . sId . session $ p else n

> instance Ord Period where
>     (<) = (<) `on` startTime
>     (>) = (>) `on` startTime
>     (<=) = (<=) `on` startTime
>     (>=) = (>=) `on` startTime

TBF: Until scoring settles down, we want an equality operator for periods that
ignores their numerical scores.  Note that equality between different periods
is slightly arbitrary.

> instance Eq Period where
>     (==) = periodsEqual

> periodsEqual :: Period -> Period -> Bool
> periodsEqual p1 p2 = eqIds p1 p2 &&
>                      eqStarts p1 p2 &&
>                      eqDurs p1 p2 
>   where
>     eqIds    = (==) `on` session
>     eqStarts = (==) `on` startTime
>     eqDurs   = (==) `on` duration

Simple Functions for Periods:

> periodHalfTime :: Period -> DateTime
> periodHalfTime p = addMinutes' (duration p `div` 2) $ startTime p

> periodEndTime :: Period -> DateTime
> periodEndTime p = addMinutes' (duration p) $ startTime p

> defaultSession = Session {
>     sId         = 0
>   , sName       = ""
>   , project     = defaultProject 
>   , windows     = []
>   , periods     = [defaultPeriod]
>   , sAlloted    = 0
>   , minDuration = 0
>   , maxDuration = 0
>   , timeBetween = 0
>   , frequency   = 0.0
>   , ra          = 0.0
>   , dec         = 0.0
>   , backup      = False
>   , receivers   = [[Rcvr12_18]]
>   , enabled     = True
>   , authorized  = True
>   , grade       = 4.0
>   , band        = L
>   , lowRFI      = False
>   , lstExclude  = []
>   , sClosed     = False
>   , sType       = Open
>   , transit     = Optional
>   }

> defaultObserver = Observer {
>     oId          = 0 
>   , firstName    = "" -- for debugging
>   , lastName     = "" -- for debugging
>   , username     = ""
>   , pstId        = 0 
>   , sanctioned   = True
>   , reservations = []
>   , blackouts    = []
> }

> defaultProject = Project {
>     pId             = 0
>   , pName           = ""
>   , semester        = ""
>   , sessions        = [defaultSession]
>   , thesis          = False
>   , pAlloted        = 0
>   , maxSemesterTime = 10000000 -- more then enough time
>   , observers       = [defaultObserver]
>   , pClosed         = False
>   }

> defaultPeriod = Period {
>     peId        = 0
>   , session     = defaultSession
>   , startTime   = fromGregorian' 2008 1 1
>   , duration    = 0
>   , pScore      = 0.0
>   , pForecast   = fromGregorian' 2008 1 1
>   , pBackup     = False
>   , pTimeBilled = 0
>   }

> defaultWindow  = Window {
>     wSession     = defaultSession
>   , wStart       = fromGregorian' 2008 1 1
>   , wDuration    = 0
>   , wPeriodId    = 0
>    }
