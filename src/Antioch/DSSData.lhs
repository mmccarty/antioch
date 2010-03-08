> module Antioch.DSSData where

> import Antioch.DateTime
> import Antioch.Types
> import Antioch.Score
> import Antioch.Reservations
> import Antioch.Settings                (dssDataDB)
> import Antioch.Utilities
> import Control.Monad.Trans             (liftIO)
> import Data.List                       (sort, nub, find)
> import Data.Char                       (toUpper)
> import Maybe                           (fromJust)
> import Database.HDBC
> import Database.HDBC.PostgreSQL

> connect :: IO Connection
> connect = handleSqlError $ connectPostgreSQL cnnStr 
>   where
>     cnnStr = "dbname=" ++ dssDataDB ++ " user=dss"

> getProjects :: IO [Project]
> getProjects = do
>     cnn <- connect
>     projs' <- fetchProjectData cnn
>     projs <- mapM (populateProject cnn) projs' 
>     return projs

TBF: get rid of the allotment table join here, and refactor it out to a 
separate query, to deal with multiple allotments (different grades)

> fetchProjectData :: Connection -> IO [Project]
> fetchProjectData cnn = handleSqlError $ do
>   result <- quickQuery' cnn query []
>   return $ toProjectDataList result
>     where
>       query = "SELECT p.id, p.pcode, s.semester, p.thesis, p.complete FROM semesters AS s, projects AS p WHERE s.id = p.semester_id ORDER BY p.pcode"
>       toProjectDataList = map toProjectData
>       toProjectData (id:pcode:semester:thesis:comp:[]) = 
>         defaultProject {
>             pId = fromSql id 
>           , pName = fromSql pcode 
>           , semester = fromSql semester  
>           , thesis = fromSql thesis 
>           , pClosed = fromSql comp
>         }

> populateProject :: Connection -> Project -> IO Project
> populateProject cnn project = do
>     sessions <- getSessions (pId project) cnn
>     sessions' <- mapM (populateSession cnn) sessions
>     -- project times
>     allotments <- getProjectAllotments (pId project) cnn
>     let project' = setProjectAllotments project allotments
>     -- project observers (will include observer blackouts!)
>     observers <- getProjectObservers (pId project) cnn
>     let project'' = setProjectObservers project' observers
>     return $ makeProject project'' (pAllottedT project'') sessions'

The scheduling algorithm does not need to know all the details about the observers
on a project - it only needs a few key facts, which are defined in the Observer
data structure.  These facts come from two sources:
   1. DSS Database:
      * observer sanctioned flag 
      * observer black out dates
   2. BOS web service:
      * observer on site dates (GB reservation date)

TBF: currently no observer black out date tables
TBF: We currently cannot link info in the DSS database to the id's used in the
BOS web services to retrieve reservation dates.

TBF: Beware original_id, pst_id, username, and contact_instructions
in the User table can be null.

> getProjectObservers :: Int -> Connection -> IO [Observer]
> getProjectObservers projId cnn = handleSqlError $ do
>     -- 0. Get basic info on observers: username, pst id, sanctioned
>     observers' <- getObservers projId cnn
>     -- 1. Use these to lookup the needed info from the BOS web service.
>     -- 1. Use these to lookup the needed info from the DSS database
>     observers <- mapM (populateObserver cnn) observers'
>     -- return obs
>     return observers 

> setProjectObservers :: Project -> [Observer] -> Project
> setProjectObservers proj obs = proj { observers = obs }

Sets the basic Observer Data Structure info

> getObservers :: Int -> Connection -> IO [Observer]
> getObservers projId cnn = do
>   result <- quickQuery' cnn query xs 
>   return $ toObserverList result 
>     where
>       xs = [toSql projId]
>       query = "SELECT u.id, u.first_name, u.last_name, u.sanctioned, u.username, u.pst_id FROM investigators AS inv, users AS u WHERE u.id = inv.user_id AND inv.observer AND inv.project_id = ?"
>       toObserverList = map toObserver
>       toObserver (id:first:last:sanc:uname:pid:[]) = 
>         defaultObserver 
>           { oId = fromSql id
>           , firstName = fromSql first
>           , lastName = fromSql last
>           , sanctioned = fromSql sanc
>           , username = fromSqlUserName uname
>           , pstId = fromSqlInt pid }

> fromSqlUserName :: SqlValue -> String
> fromSqlUserName SqlNull = ""
> fromSqlUserName name    = fromSql name

Takes Observers with basic info and gets the extras: blackouts, reservations

> populateObserver :: Connection -> Observer -> IO Observer
> populateObserver cnn observer = do
>     bs <- getObserverBlackouts cnn observer
>     res <- getObserverReservations cnn observer
>     return observer { blackouts = bs, reservations = res }

> getObserverBlackouts :: Connection -> Observer -> IO [DateRange]
> getObserverBlackouts cnn obs = do
>   result <- quickQuery' cnn query xs
>   return $ toBlackoutDatesList result
>     where
>       xs = [toSql . oId $ obs]
>       query = "SELECT b.start_date, b.end_date, r.repeat, b.until FROM blackouts AS b, repeats AS r WHERE r.id = b.repeat_id AND user_id = ?"
>       toBlackoutDatesList = concatMap toBlackoutDates
>       toBlackoutDates (s:e:r:u:[]) = toDateRangesFromInfo (sqlToBlackoutStart s) (sqlToBlackoutEnd e) (fromSql r) (sqlToBlackoutEnd u)


When converting repeats to a list of dates, when do these dates start and end?

> blackoutsStart = fromGregorian 2009 9 1 0 0 0
> blackoutsEnd   = fromGregorian 2010 2 1 0 0 0

These two methods define the start and end of blackouts in case of NULLs in the
DB.  TBF: this is only good for 09C.

> sqlToBlackoutStart :: SqlValue -> DateTime
> sqlToBlackoutStart SqlNull = blackoutsStart
> sqlToBlackoutStart dt = sqlToDateTime dt 

> sqlToBlackoutEnd :: SqlValue -> DateTime
> sqlToBlackoutEnd SqlNull = blackoutsEnd
> sqlToBlackoutEnd dt = sqlToDateTime dt 

Convert from a description of the blackout to the actual dates

> toDateRangesFromInfo :: DateTime -> DateTime -> String -> DateTime -> [DateRange]
> toDateRangesFromInfo start end repeat until | repeat == "Once" = [(start, end)]
>                                             | repeat == "Weekly" = toWeeklyDateRanges start end until
>                                             | repeat == "Monthly" = toMonthlyDateRanges start end until
>                                             | otherwise = [(start, end)] -- WTF

> toWeeklyDateRanges :: DateTime -> DateTime -> DateTime -> [DateRange]
> toWeeklyDateRanges start end until | start > until = []
>                                    | otherwise = (start, end):(toWeeklyDateRanges (nextWeek start) (nextWeek end) until)
>   where
>     nextWeek dt = addMinutes weekMins dt
>     weekMins = 7 * 24 * 60

> toMonthlyDateRanges :: DateTime -> DateTime -> DateTime -> [DateRange]
> toMonthlyDateRanges start end until | start > until = []
>                                     | otherwise = (start, end):(toMonthlyDateRanges (addMonth start) (addMonth end) until)

TBF: the BOS service still isn't working!  So, instead of investing more time
into a dead language, we are simply reading these from an intermediate table
in the DSS DB.

> getObserverReservations :: Connection -> Observer -> IO [DateRange]
> getObserverReservations cnn obs = do 
>   result <- quickQuery' cnn query xs
>   return $ toResDatesList result
>     where
>       xs = [toSql . oId $ obs]
>       query = "SELECT start_date, end_date FROM reservations WHERE user_id = ?"
>       toResDatesList = concatMap toResDates
>       toResDates (s:e:[]) = [(sqlToDateTime s, sqlToDateTime e)]

We must query for the allotments separately, because if a Project has alloted
time for more then one grade (ex: 100 A hrs, 20 B hrs), then that will be
two allotments, and querying w/ a join will duplicate the project.
TBF: field ignore_grade in Allotment table can be null.

> getProjectAllotments :: Int -> Connection -> IO [(Minutes, Grade)]
> getProjectAllotments projId cnn = handleSqlError $ do 
>   result <- quickQuery' cnn query xs 
>   return $ toAllotmentList result 
>     where
>       query = "SELECT a.total_time, a.grade FROM allotment AS a, projects AS p, projects_allotments AS pa WHERE p.id = pa.project_id AND a.id = pa.allotment_id AND p.id = ?"
>       xs = [toSql projId]
>       toAllotmentList = map toAllotment
>       toAllotment (ttime:grade:[]) = (fromSqlMinutes ttime, fromSql grade)

TBF: WTF! In Antioch, do we need to be taking into account grades at the 
project level?  For now, we are ignoring grade and summing the different
hours togethor to get the total time.

> setProjectAllotments :: Project -> [(Minutes, Grade)] -> Project
> setProjectAllotments p [] = p
> setProjectAllotments p (x:xs) = setProjectAllotments (p {pAllottedT = (pAllottedT p) + (fst x)} ) xs

TBF: if a session is missing any of the tables in the below query, it won't
get picked up!!!
TBF, BUG: Session (17) BB261-01 has no target, so is not getting imported.

> getSessions :: Int -> Connection -> IO [Session]
> getSessions projId cnn = handleSqlError $ do 
>   result <- quickQuery' cnn query xs 
>   let ss' = toSessionDataList result
>   ss <- mapM (updateRcvrs cnn) ss' 
>   return ss
>     where
>       query = "SELECT DISTINCT s.id, s.name, s.min_duration, s.max_duration, s.time_between, s.frequency, a.total_time, a.max_semester_time, a.grade, t.horizontal, t.vertical, st.enabled, st.authorized, st.backup, st.complete, stype.type FROM sessions AS s, allotment AS a, targets AS t, status AS st, session_types AS stype, observing_types AS otype WHERE a.id = s.allotment_id AND t.session_id = s.id AND s.status_id = st.id AND s.session_type_id = stype.id AND s.observing_type_id = otype.id AND otype.type != 'maintenance' AND s.frequency IS NOT NULL AND t.horizontal IS NOT NULL AND t.vertical IS NOT NULL AND s.project_id = ?;"
>       xs = [toSql projId]
>       toSessionDataList = map toSessionData
>       toSessionData (id:name:mind:maxd:between:freq:ttime:stime:grade:h:v:e:a:b:c:sty:[]) = 
>         defaultSession {
>             sId = fromSql id 
>           , sName = fromSql name
>           , frequency   = fromSql freq
>           , minDuration = fromSqlMinutes' mind 3
>           , maxDuration = fromSqlMinutes' maxd 12
>           , timeBetween = fromSqlMinutes' between 0
>           , sAllottedT  = fromSqlMinutes ttime
>           , sAllottedS  = fromSqlMinutes stime
>           , ra = fromSql h 
>           , dec = fromSql v  
>           , grade = fromSql grade
>           , receivers = [] 
>           , periods = [] -- no history in Carl's DB
>           , enabled = fromSql e
>           , authorized = fromSql a
>           , backup = fromSql b
>           , band = deriveBand $ fromSql freq
>           , sClosed = fromSql c
>           , sType = toSessionType sty
>         }

> getSessionFromPeriod :: Int -> Connection -> IO Session
> getSessionFromPeriod periodId cnn = handleSqlError $ do 
>   result <- quickQuery' cnn query xs 
>   let s' = toSessionData . head $ result
>   s <- updateRcvrs cnn s' 
>   return s
>     where
>       query = "SELECT s.id, s.name, s.min_duration, s.max_duration, s.time_between, s.frequency, a.total_time, a.max_semester_time, a.grade, t.horizontal, t.vertical, st.enabled, st.authorized, st.backup, st.complete, type.type FROM sessions AS s, allotment AS a, targets AS t, status AS st, session_types AS type, periods AS p WHERE s.id = p.session_id AND a.id = s.allotment_id AND t.session_id = s.id AND s.status_id = st.id AND s.session_type_id = type.id AND s.frequency IS NOT NULL AND t.horizontal IS NOT NULL AND t.vertical IS NOT NULL AND p.id = ?"
>       xs = [toSql periodId]
>       toSessionDataList = map toSessionData
>       toSessionData (id:name:mind:maxd:between:freq:ttime:stime:grade:h:v:e:a:b:c:sty:[]) = 
>         defaultSession {
>             sId = fromSql id 
>           , sName = fromSql name
>           , frequency   = fromSql freq
>           , minDuration = fromSqlMinutes' mind 3
>           , maxDuration = fromSqlMinutes' maxd 12
>           , timeBetween = fromSqlMinutes' between 0
>           , sAllottedT  = fromSqlMinutes ttime 
>           , sAllottedS  = fromSqlMinutes stime 
>           , ra = fromSql h -- TBF: assume all J200? For Carl's DB, YES!
>           , dec = fromSql v  
>           , grade = fromSql grade
>           , receivers = [] -- TBF: does scoring support the logic structure!
>           , periods = [] -- TBF, no history in Carl's DB
>           , enabled = fromSql e
>           , authorized = fromSql a
>           , backup = fromSql b
>           , band = deriveBand $ fromSql freq
>           , sClosed = fromSql c
>           , sType = toSessionType sty
>         }

> getSession :: Int -> Connection -> IO Session
> getSession sessionId cnn = handleSqlError $ do 
>   result <- quickQuery' cnn query xs 
>   let s' = toSessionData $ result!!0
>   s <- updateRcvrs cnn s' 
>   return s
>     where
>       query = "SELECT s.id, s.name, s.min_duration, s.max_duration, s.time_between, s.frequency, a.total_time, a.max_semester_time, a.grade, t.horizontal, t.vertical, st.enabled, st.authorized, st.backup, st.complete, type.type FROM sessions AS s, allotment AS a, targets AS t, status AS st, session_types AS type WHERE a.id = s.allotment_id AND t.session_id = s.id AND s.status_id = st.id AND s.session_type_id = type.id AND s.id = ?"
>       xs = [toSql sessionId]
>       toSessionData (id:name:mind:maxd:between:freq:ttime:stime:grade:h:v:e:a:b:c:sty:[]) = 
>         defaultSession {
>             sId = fromSql id 
>           , sName = fromSql name
>           , frequency   = fromSql freq
>           , minDuration = fromSqlMinutes' mind 3
>           , maxDuration = fromSqlMinutes' maxd 12
>           , timeBetween = fromSqlMinutes' between 0
>           , sAllottedT  = fromSqlMinutes ttime
>           , sAllottedS  = fromSqlMinutes stime
>           , ra = fromSql h 
>           , dec = fromSql v  
>           , grade = fromSql grade
>           , receivers = [] 
>           , periods = [] -- no history in Carl's DB
>           , enabled = fromSql e
>           , authorized = fromSql a
>           , backup = fromSql b
>           , band = deriveBand $ fromSql freq
>           , sClosed = fromSql c
>           , sType = toSessionType sty
>         }

Since the Session data structure does not support Nothing, when we get NULLs
from the DB (Carl didn't give it to us), then we need some kind of default
value of the right type.

> fromSqlInt :: SqlValue -> Int
> fromSqlInt SqlNull = 0
> fromSqlInt x       = fromSql x

> fromSqlMinutes :: SqlValue -> Minutes
> fromSqlMinutes x               = sqlHrsToMinutes x

> fromSqlMinutes' :: SqlValue -> Minutes -> Minutes
> fromSqlMinutes' SqlNull def     = def
> fromSqlMinutes' x _             = sqlHrsToMinutes x

> sqlHrsToHrs' :: SqlValue -> Float
> sqlHrsToHrs' hrs = fromSql hrs

> hrsToMinutes :: Float -> Minutes
> hrsToMinutes hrs = floor $ 60.0 * hrs

> sqlHrsToMinutes :: SqlValue -> Minutes
> sqlHrsToMinutes hrs = hrsToMinutes . sqlHrsToHrs' $ hrs

TBF: is this totaly legit?  and should it be somewhere else?

> deriveBand :: Float -> Band
> deriveBand freq |                freq <= 2.0   = L
> deriveBand freq | freq > 2.0  && freq <= 3.0   = S
> deriveBand freq | freq > 3.0  && freq <= 7.0   = C
> deriveBand freq | freq > 7.0  && freq <= 11.0  = X
> deriveBand freq | freq > 11.0 && freq <= 17.0  = U
> deriveBand freq | freq > 17.0 && freq <= 26.0  = K
> deriveBand freq | freq > 26.0 && freq <= 40.0  = A
> deriveBand freq | freq > 40.0 && freq <= 50.0  = Q
> deriveBand freq | otherwise                    = W

> deriveState :: String -> StateType
> deriveState s
>   | s == "P"  = Pending
>   | s == "S"  = Scheduled
>   | s == "C"  = Complete
>   | otherwise = Deleted

> toSessionType :: SqlValue -> SessionType
> toSessionType val = read . toUpperFirst $ fromSql val
>   where
>     toUpperFirst x = [toUpper . head $ x] ++ tail x

Given a Session, find the Rcvrs for each Rcvr Group.
This is a separate func, and not part of the larger SQL in getSessions
in part because if there are *no* rcvrs, that larger SQL would not return
*any* result (TBF: this bug is still there w/ the tragets)
Note, start_date in Receiver_Schedule table can be null.

> updateRcvrs :: Connection -> Session -> IO Session
> updateRcvrs cnn s = do
>   rcvrGroups <- getRcvrGroups cnn s
>   cnfRcvrs <- mapM (getRcvrs cnn s) rcvrGroups
>   return $ s {receivers = cnfRcvrs}

> getRcvrGroups :: Connection -> Session -> IO [Int]
> getRcvrGroups cnn s = do
>   result <- quickQuery' cnn query xs 
>   return $ toRcvrGrpIds result
>   where
>     xs = [toSql . sId $ s]
>     query = "SELECT rg.id FROM receiver_groups AS rg WHERE rg.session_id = ?"
>     toRcvrGrpIds = map toRcvrGrpId 
>     toRcvrGrpId [x] = fromSql x

> getRcvrs :: Connection -> Session -> Int -> IO ReceiverGroup
> getRcvrs cnn s id = do
>   result <- quickQuery' cnn query xs 
>   return $ toRcvrList s result
>   where
>     xs = [toSql id]
>     query = "SELECT r.name FROM receivers as r, receiver_groups_receivers as rgr WHERE rgr.receiver_id = r.id AND rgr.receiver_group_id = ?"
>     toRcvrList s = map (toRcvr s)
>     toRcvr s [x] = toRcvrType s x

> toRcvrType :: Session -> SqlValue -> Receiver
> toRcvrType s val = read . fromSql $ val

Here, we gather additional information about a session: periods, windows,
observing parameters, etc.
TBF: why aren't we getting the rcvr info here?

> populateSession :: Connection -> Session -> IO Session
> populateSession cnn s = do
>     s' <- setObservingParameters cnn s
>     ps <- getPeriods cnn s'
>     ws <- getWindows cnn s'
>     return $ makeSession s' ws ps

The following recursive patterns work for setting the observing params
that are one-to-one between the DB and the Session (ex: Night Time -> low rfi).  However,
we'll need to handle as a special case some params that we want to take from
the DB and collapse into simpler Session params (ex: LST ranges).

> setObservingParameters :: Connection -> Session -> IO Session
> setObservingParameters cnn s = do
>   result <- quickQuery' cnn query xs 
>   let s' = setObservingParameters' s result
>   s'' <- setLSTExclusion cnn s'
>   return s''
>     where
>       xs = [toSql . sId $ s]
>       query = "SELECT p.name, p.type, op.string_value, op.integer_value, op.float_value, op.boolean_value, op.datetime_value FROM observing_parameters AS op, parameters AS p WHERE p.id = op.parameter_id AND op.session_id = ?" 

> setObservingParameters' :: Session -> [[SqlValue]] -> Session
> setObservingParameters' s sqlRows = foldl setObservingParameter s sqlRows 

For now, just set:
   * low rfi flag
   * transit flag

> setObservingParameter :: Session -> [SqlValue] -> Session
> setObservingParameter s (pName:pType:pStr:pInt:pFlt:pBool:pDT) | n == "Night-time Flag" = s { lowRFI = fromSql pBool }    
>                                                                | n == "Transit" = s { transit = toTransit pBool }
>                                                                | otherwise = s
>   where
>     n = fromSql pName
>     toTransit t = toTransitType . toTransitBool $ t 

> toTransitBool :: SqlValue -> Bool
> toTransitBool t = fromSql t

> toTransitType :: Bool -> TransitType
> toTransitType t = if t then Center else Optional

The DB's observing parameters may support both LST Exclusion flags *and*
LST Inclusion flags, where as our Session's only support the LST Exclusion
flags - so we'll have to collapse the DB's 2 types into our 1.

> setLSTExclusion :: Connection -> Session -> IO Session
> setLSTExclusion cnn s = do
>   result <- quickQuery' cnn query xs --Exclusion
>   let s' = addLSTExclusion' True s result
>   result <- quickQuery' cnn query' xs --Inclusion
>   return $ addLSTExclusion' False s' result
>     where
>       -- TBF: for some reason, I need to have 'Exclude' & 'Include' in
>       -- the query strings: putting it in xs causes an SQL error ???
>       xs = [toSql . sId $ s]
>       query = "SELECT p.name, op.float_value FROM observing_parameters AS op, parameters AS p WHERE p.id = op.parameter_id AND p.name LIKE 'LST Exclude%' AND op.session_id = ?" 
>       query' = "SELECT p.name, op.float_value FROM observing_parameters AS op, parameters AS p WHERE p.id = op.parameter_id AND p.name LIKE 'LST Include%' AND op.session_id = ?" 

The 'ex' flag determines whether we are importing LST Exclusion ranges
or Inclusion ranges.

> addLSTExclusion' :: Bool -> Session -> [[SqlValue]] -> Session
> addLSTExclusion' _ s []        = s
> addLSTExclusion' ex s sqlValues = s { lstExclude = (lstExclude s) ++ [lstRange ex sqlValues] }  

If we are importing the inclusion range, then reversing the endpoints makes
it an exclusion range.

> lstRange :: Bool -> [[SqlValue]] -> (Float, Float)
> lstRange ex sqlValues = if ex then (low, hi) else (hi, low) 
>   where
>     (low, hi) = lstRangeLow ex sqlValues $ lstRangeHi ex sqlValues

> lstRangeHi :: Bool -> [[SqlValue]] -> Float
> lstRangeHi ex sqlValues = lstRangeHi' . head $ filter (isLSTName n) sqlValues
>   where
>     n = if ex then "LST Exclude Hi" else "LST Include Hi"
>     lstRangeHi' (pName:pHi:[]) = fromSql pHi

> isLSTName :: String -> [SqlValue] -> Bool
> isLSTName name (pName:pFloat:[]) = (fromSql pName) == name

> lstRangeLow :: Bool -> [[SqlValue]] -> Float -> (Float, Float)
> lstRangeLow ex sqlValues hiValue = (lowValue, hiValue)
>   where
>     n = if ex then "LST Exclude Low" else "LST Include Low"
>     lowValue = lstRangeLow' . head $ filter (isLSTName n) sqlValues
>     --isLow (pName:pFloat:[]) = (fromSql pName) == "LST Exclude Low"
>     lstRangeLow' (pName:pLow:[]) = fromSql pLow

> getWindows :: Connection -> Session -> IO [Window]
> getWindows cnn s = do
>     dbWindows <- fetchWindows cnn s 
>     return $ sort $ dbWindows

> fetchWindows :: Connection -> Session -> IO [Window]
> fetchWindows cnn s = do 
>   result <- quickQuery' cnn query xs 
>   return $ toWindowList result
>   where
>     xs = [toSql . sId $ s]
>     query = "SELECT w.id, w.start_date, w.duration, p.id FROM windows as w, periods as p, period_states as s WHERE w.default_period_id = p.id AND w.period_id is NULL AND p.state_id = s.id AND s.abbreviation = 'P' AND w.session_id = ?;"
>     toWindowList = map toWindow
>     toWindow(id:strt:dur:pid:[]) =
>       defaultWindow { wId       = fromSql id
>                     , wStart    = sqlToDate strt
>                     , wDuration = 24*60*(fromSql dur)
>                     , wPeriodId = fromSql pid
>                     }

> getPeriods :: Connection -> Session -> IO [Period]
> getPeriods cnn s = do
>     dbPeriods <- fetchPeriods cnn s 
>     return $ sort $ dbPeriods

> fetchPeriods :: Connection -> Session -> IO [Period]
> fetchPeriods cnn s = do 
>   result <- quickQuery' cnn query xs 
>   return $ toPeriodList result
>   where
>     xs = [toSql . sId $ s]
>     -- don't pick up deleted periods!
>     query = "SELECT p.id, p.session_id, p.start, p.duration, p.score, state.abbreviation, p.forecast, p.backup, pa.scheduled, pa.not_billable, pa.other_session_weather, pa.other_session_rfi, other_session_other, pa.lost_time_weather, pa.lost_time_rfi, pa.lost_time_other FROM periods AS p, period_states AS state, periods_accounting AS pa WHERE state.id = p.state_id AND state.abbreviation != 'D' AND pa.id = p.accounting_id AND p.session_id = ?;"
>     toPeriodList = map toPeriod
>     toPeriod (id:sid:start:durHrs:score:state:forecast:backup:sch:nb:osw:osr:oso:ltw:ltr:lto:[]) =
>       defaultPeriod { peId = fromSql id
>                     , startTime = sqlToDateTime start --fromSql start
>                     , duration = fromSqlMinutes durHrs
>                     , pScore = fromSql score
>                     , pState = deriveState . fromSql $ state
>                     , pForecast = sqlToDateTime forecast
>                     , pBackup = fromSql backup
>                     --, pTimeBilled = fromSqlMinutes durHrs  -- db simulation
>                     , pTimeBilled = (fromSqlMinutes sch)  - (fromSqlMinutes nb) - (fromSqlMinutes osw) - (fromSqlMinutes osr) - (fromSqlMinutes oso) - (fromSqlMinutes ltw) -  (fromSqlMinutes ltr) - (fromSqlMinutes lto)
>                     }

> fetchPeriod :: Int -> Connection -> IO Period
> fetchPeriod id cnn = do
>   result <- quickQuery' cnn query xs
>   return . toPeriod . head $ result
>   where
>     xs = [toSql id]
>     query = "SELECT p.id, p.session_id, p.start, p.duration, p.score, state.abbreviation, p.forecast, p.backup, pa.scheduled, pa.not_billable, pa.other_session_weather, pa.other_session_rfi, other_session_other, pa.lost_time_weather, pa.lost_time_rfi, pa.lost_time_other FROM periods AS p, periods_accounting AS pa WHERE pa.id = p.accounting_id AND p.id = ?"
>     toPeriod (id:sid:start:durHrs:score:state:forecast:backup:sch:nb:osw:osr:oso:ltw:ltr:lto:[]) =
>       defaultPeriod { peId = fromSql id
>                     , startTime = sqlToDateTime start --fromSql start
>                     , duration = fromSqlMinutes durHrs
>                     , pScore = fromSql score
>                     , pState = deriveState . fromSql $ state
>                     , pForecast = sqlToDateTime forecast
>                     , pBackup = fromSql backup
>                     --, pTimeBilled = fromSqlMinutes durHrs  -- db simulation
>                     , pTimeBilled = (fromSqlMinutes sch)  - (fromSqlMinutes nb) - (fromSqlMinutes osw) - (fromSqlMinutes osr) - (fromSqlMinutes oso) - (fromSqlMinutes ltw) -  (fromSqlMinutes ltr) - (fromSqlMinutes lto)
>                     } 

> sqlToDateTime :: SqlValue -> DateTime
> sqlToDateTime dt = fromJust . fromSqlString . fromSql $ dt

> sqlToDate :: SqlValue -> DateTime
> sqlToDate dt = fromJust . fromSqlDateString . fromSql $ dt

> putPeriods :: [Period] -> IO ()
> putPeriods ps = do
>   cnn <- connect
>   result <- mapM (putPeriod cnn) ps
>   return ()

Here we add a new period to the database.  
Initialize the Period in the Pending state (state_id = 1)
Since Antioch is creating it
we will set the Period_Accounting.scheduled field

> putPeriod :: Connection -> Period -> IO ()
> putPeriod cnn p = do
>   accounting_id <- putPeriodAccounting cnn (duration p)
>   quickQuery' cnn query (xs accounting_id) 
>   commit cnn
>   updateWindow cnn p
>   commit cnn
>     where
>       xs a = [toSql . sId . session $ p
>             , toSql $ (toSqlString . startTime $ p) 
>             , minutesToSqlHrs . duration $ p
>             , toSql . pScore $ p
>             , toSql . toSqlString . pForecast $ p
>             , toSql . pBackup $ p
>             , toSql a
>             ]
>       query = "INSERT INTO periods (session_id, start, duration, score, forecast, backup, accounting_id, state_id, moc_ack) VALUES (?, ?, ?, ?, ?, ?, ?, 1, false);"

> updateWindow :: Connection -> Period -> IO ()
> updateWindow cnn p = handleSqlError $ do
>   -- select the period to get its period id
>   result <- quickQuery' cnn pquery pxs 
>   let periodId = fromSqlInt . head . head $ result
>   -- search session's windows for first intersecting window
>   let window = find (\w -> overlie (wStart w) (wDuration w) p) (windows . session $ p)
>   if window == Nothing then return ()
>                        -- update window with the period_id
>                        else updateWindow' cnn periodId (wId . fromJust $ window)
>     where
>       pquery = "SELECT p.id FROM periods AS p WHERE p.session_id = ? AND p.start = ? AND p.duration = ?;"
>       pxs = [toSql . sId . session $ p
>            , toSql . toSqlString . startTime $ p
>            , minutesToSqlHrs . duration $ p
>             ]

> updateWindow' :: Connection -> Int -> Int -> IO ()
> updateWindow' cnn periodId windowId = handleSqlError $ do
>   result <- quickQuery' cnn wquery wxs
>   return ()
>     where
>       wquery = "UPDATE windows SET period_id = ? WHERE id = ?;"
>       wxs = [toSql periodId, toSql windowId]

> setPeriodScore :: Connection -> Score -> Int -> IO ()
> setPeriodScore cnn v pid = do
>   ct <- getCurrentTime
>   let dt = toSql . toSqlString $ ct
>   quickQuery' cnn query [value, dt, id]
>   commit cnn
>     where
>       query = "UPDATE periods SET score = ?, forecast = ? WHERE id = ?;"
>       value = toSql v
>       id = toSql pid


> minutesToSqlHrs :: Minutes -> SqlValue
> minutesToSqlHrs mins = toSql $ (/(60.0::Float)) . fromIntegral $ mins 

Creates a new period accounting row, and returns this new rows ID

> putPeriodAccounting :: Connection -> Int -> IO Int
> putPeriodAccounting cnn scheduled = do
>   quickQuery' cnn query xs
>   result <- quickQuery' cnn queryId xsId
>   return $ toId result
>     where
>       -- now, scheduled gets set when period is published
>       xs = [] --[minutesToSqlHrs scheduled]
>       query = "INSERT INTO periods_accounting (scheduled, not_billable, other_session_weather, other_session_rfi, other_session_other, lost_time_weather, lost_time_rfi, lost_time_other, short_notice, description) VALUES (0.0, 0.0, 0.0, 0.0, 0.0,  0.0, 0.0, 0.0, 0.0, '')"
>       xsId = []
>       queryId = "SELECT MAX(id) FROM periods_accounting"
>       toId [[x]] = fromSql x
