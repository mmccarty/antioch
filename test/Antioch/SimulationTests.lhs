> module Antioch.SimulationTests where

> import Antioch.DateTime
> import Antioch.Types
> import Antioch.Weather    (getWeatherTest)
> import Antioch.Utilities
> import Antioch.PProjects
> import Antioch.Simulate
> import Antioch.Filters       -- debug
> import Antioch.Debug
> import Antioch.Statistics (scheduleHonorsFixed)
> import Data.List (sort, find)
> import Data.Maybe
> import Test.HUnit
> import System.Random

> tests = TestList [ 
>     test_simulateDailySchedule
>   , test_exhaustive_history
>   , test_updateHistory
>   , test_updateSessions
>                  ]

Attempt to see if the old test_sim_pack still works:

> test_simulateDailySchedule = TestCase $ do
>     w <- getWeatherTest $ Just dt
>     (result, t) <- simulateDailySchedule rs dt packDays simDays history ss True [] []
>     --print $ take 4 $ map duration result
>     --print $ take 4 $ map (toSqlString . startTime) result
>     --print $ take 4 $ map (sName . session) result
>     assertEqual "SimulationTests_test_sim_pack" (take 4 exp) (take 4 result)
>   where
>     rs  = []
>     dt = fromGregorian 2006 2 1 0 0 0
>     simDays = 2
>     packDays = 2
>     history = []
>     ss = getOpenPSessions
>     expSs = [gb, cv, va, tx, tx, gb, lp, cv, tx, cv, as]
>     dts = [ fromGregorian 2006 2 1  1 30 0
>           , fromGregorian 2006 2 1  6 15 0
>           , fromGregorian 2006 2 1  8 15 0
>           , fromGregorian 2006 2 1 12 15 0
>           , fromGregorian 2006 2 1 18  0 0
>           , fromGregorian 2006 2 1 22 45 0
>           , fromGregorian 2006 2 2  6 45 0
>           , fromGregorian 2006 2 2 12 45 0
>           , fromGregorian 2006 2 2 14 45 0
>           , fromGregorian 2006 2 3  5  0 0
>           , fromGregorian 2006 2 3 18 15 0
>            ]
>     durs = [285, 120, 240, 345, 240, 480, 360, 120, 285, 195, 480]
>     scores = replicate 10 0.0
>     exp = zipWith9 Period (repeat 0) expSs dts durs scores (repeat Pending) dts (repeat False) durs
>     

Attempt to see if old test still works:
Test to make sure that our time accounting isn't screwed up by the precence 
of pre-scheduled periods (history)

> test_exhaustive_history = TestCase $ do
>     w <- getWeatherTest $ Just dt
>     -- first, a test where the history uses up all the time
>     (result, t) <- simulateDailySchedule rs dt packDays simDays h1 ss1 True [] []
>     assertEqual "SimulationTests_test_sim_schd_pack_ex_hist_1" True (scheduleHonorsFixed h1 result)
>     assertEqual "SimulationTests_test_sim_schd_pack_ex_hist_2" h1 result
>     -- now, if history only takes some of the time, make sure 
>     -- that the session's time still gets used up
>     (result, t) <- simulateDailySchedule rs dt packDays simDays h2 ss2 True [] []
>     assertEqual "SimulationTests_test_sim_schd_pack_ex_hist_3" True (scheduleHonorsFixed h2 result)
>     let observedTime = sum $ map duration result
>     -- This will fail until we use 'updateSession' in simulate
>     assertEqual "SimulationTests_test_sim_schd_pack_ex_hist_4" True (abs (observedTime - (sAllottedT s2)) <= (minDuration s2))
>   where
>     rs  = []
>     dt = fromGregorian 2006 2 1 0 0 0
>     simDays = 7
>     packDays = 2
>     ds = defaultSession { frequency = 2.0, receivers = [[Rcvr1_2]] }
>     -- a period that uses up all the sessions' time (480)
>     f1 = Period 0 ds {sId = sId cv} (fromGregorian 2006 2 4 3 0 0) 480 0.0 Pending dt False 480
>     h1 = [f1]
>     -- make sure that this session knows it's used up it's time
>     s1 = makeSession (cv { sAllottedT = 480, sAllottedS = 480}) [] h1
>     ss1 = [s1]
>
>     -- a period that uses MOST of the sessions' time (375)
>     f2 = Period 0 ds {sId = sId cv} (fromGregorian 2006 2 4 3 0 0) 375 0.0 Pending dt False 375
>     h2 = [f2]
>     -- make sure that this session knows it's used up MOST of it's time
>     s2 = makeSession (cv { sAllottedT = 480, sAllottedS = 480}) [] h1
>     ss2 = [s2]

Here we attempt to schedule only a single high-frequency session - if it does
get on, it has a high chance of being canceled.

> test_cancelations = TestCase $ do
>     (result, tr) <- simulateDailySchedule [] start 2 15 [] ss True [] []
>     let cs = getCanceledPeriods $ tr
>     assertEqual "test_cancelations_1" exp result
>     assertEqual "test_cancelations_2" 15 (length cs)
>   where
>     ss = [va]
>     start = fromGregorian 2006 6 1 0 0 0 -- summer time
>     p1 = defaultPeriod { session = va
>                        , startTime = fromGregorian 2006 6 15 0 30 0
>                        , duration = 255 }
>     p2 = defaultPeriod { session = va
>                        , startTime = fromGregorian 2006 6 15 22 30 0
>                        , duration = 360 }
>     exp = [p1, p2]
>     

> test_updateHistory = TestCase $ do
>     assertEqual "test_updateHistory_1" r1 (updateHistory h1 s1 dt1)
>     assertEqual "test_updateHistory_2" r2 (updateHistory h1 s1 dt2)
>     assertEqual "test_updateHistory_3" r1 (updateHistory h3 s3 dt2)
>     assertEqual "test_updateHistory_2" r2 (updateHistory h3 s1 dt2)
>   where
>     mkDts start num = map (\i->(i*dur) `addMinutes'` start) [0 .. (num-1)] 
>     mkPeriod dt = defaultPeriod { startTime = dt, duration = dur }
>     dur = 120 -- two hours
>     -- first test 
>     h1_start = fromGregorian 2006 2 1 0 0 0
>     h1 = map mkPeriod $ mkDts h1_start 5
>     s1_start = fromGregorian 2006 2 1 10 0 0
>     s1 = map mkPeriod $ mkDts s1_start 3
>     dt1 = fromGregorian 2006 2 1 10 0 0
>     r1 = h1 ++ s1
>     -- second test
>     dt2 = fromGregorian 2006 2 1 9 0 0
>     r2 = (init h1) ++ s1
>     -- third
>     h3 = init h1
>     s3 = [(last h1)] ++ s1

> test_updateSessions = TestCase $ do
>     -- test initial conditions
>     let psIds = getPeriodIds ss 
>     assertEqual "test_updateSessions_1" [1] psIds
>     -- now test an update w/ out canceled periods
>     let updatedSess = updateSessions ss new_ps []
>     let newPsIds = getPeriodIds updatedSess 
>     assertEqual "test_updateSessions_2" [1,2,3] newPsIds
>     -- now test an update *with* canceled periods
>     let updatedSess = updateSessions ss new_ps canceled 
>     let newPsIds = getPeriodIds updatedSess 
>     assertEqual "test_updateSessions_3" [2,3] newPsIds
>     -- now test an update *with* canceled periods, but no new periods
>     let updatedSess = updateSessions ss [] canceled 
>     let newPsIds = getPeriodIds updatedSess 
>     assertEqual "test_updateSessions_4" [] newPsIds
>   where
>     lp_ps = [defaultPeriod { peId = 1, session = lp }]
>     canceled = lp_ps
>     lp' = makeSession lp [] lp_ps
>     ss = [lp', cv]
>     new_lp_period = defaultPeriod { peId = 2, session = lp }
>     new_cv_period = defaultPeriod { peId = 3, session = cv }
>     new_ps = [new_lp_period, new_cv_period]
>     getPeriodIds sess = sort $ map peId $ concatMap periods sess

Test Utilities:

> lp  = findPSessionByName "LP"
> cv  = findPSessionByName "CV"
> as  = findPSessionByName "AS"
> gb  = findPSessionByName "GB"
> mh  = findPSessionByName "MH"
> va  = findPSessionByName "VA"
> tx  = findPSessionByName "TX"
> wv  = findPSessionByName "WV"
> tw1 = findPSessionByName "TestWindowed1"
> tw2 = findPSessionByName "TestWindowed2"

