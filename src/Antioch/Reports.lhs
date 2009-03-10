> module Antioch.Reports where

> import Antioch.DateTime
> import Antioch.Generators (internalConflicts, endTime, genProjects, genSessions, genPeriods, generateVec)
> import Antioch.Plots
> import Antioch.Score
> import Antioch.Schedule
> import Antioch.Simulate
> import Antioch.Statistics
> import Antioch.Types
> import Antioch.Utilities (rad2deg, rad2hr)
> import Antioch.Weather
> import Antioch.Debug
> import Control.Monad      (liftM)
> import Text.Printf
> import System.Random
> import System.CPUTime
> import Test.QuickCheck hiding (promote, frequency)
> import Graphics.Gnuplot.Simple

simDecFreq (stars, crosses)

> plotDecFreq          :: StatsPlot
> plotDecFreq fn ss ps =
>      scatterPlots (scatterAttrs t x y fn) $ [[(x, rad2deg y) | (x, y) <- sessionDecFreq ss]
>                                            , [(x, rad2deg y) | (x, y) <-  periodDecFreq ps]]
>   where
>     t   = "Dec vs Freq"
>     x   = "Frequency [GHz]"
>     y   = "Declination [deg]"

simDecRA (stars, crosses)

> plotDecVsRA          :: StatsPlot
> plotDecVsRA fn ss ps =
>     scatterPlots (scatterAttrs t x y fn) $ [[(rad2hr x, rad2deg y) | (x, y) <- sessionDecRA ss]
>                                           , [(rad2hr x, rad2deg y) | (x, y) <-  periodDecRA ps]]
>   where
>     t = "Dec vs RA"
>     x = "Right Ascension [hr]"
>     y = "Declination [deg]"

simEffFreq (error bars, crosses, line plot) - Need stats from Dana

> plotEffVsFreq'         :: StatsPlot
> plotEffVsFreq' fn _ ps = do
>   w    <- getWeather Nothing
>   effs <- historicalObsEff w ps
>   plotEffVsFreq'' fn effs ps

> plotEffVsFreq'' fn effs ps =
>     scatterPlot attrs $ zip (historicalFreq ps) effs
>   where
>     t     = "Observing Efficiency vs Frequency"
>     x     = "Frequency [GHz]"
>     y     = "Observing Efficiency"
>     attrs = (scatterAttrs t x y fn) ++ [XRange (0, 51)] ++ [YRange (-0.1, 1.1)]


> plotEffVsFreq fn effs ps =
>     errorBarPlot (scatterAttrs t x y fn) $ zip3 meanEffFreq frequencyBins sdomEffFreq
>   where
>     meanEffFreq = meanObsEffByBin $ zip effs (map (frequency . session) ps)
>     sdomEffFreq = sdomObsEffByBin $ zip effs (map (frequency . session) ps)
>     t = "Observing Efficiency vs Frequency"
>     x = "Frequency [GHz]"
>     y = "Observing Efficiency"

simMeanEffFreq (error bars, crosses, line plot) - Need stats from Dana
simFreqTime (circles, dt on x-axis)

> plotFreqVsTime         :: StatsPlot
> plotFreqVsTime fn _ ps =
>     scatterPlot (scatterAttrs t x y fn) $ zip (map fromIntegral $ historicalTime' ps) (historicalFreq ps)
>   where
>     t = "Frequency vs Time"
>     x = "Time [days]"
>     y = "Frequency [GHz]"

simSatisfyFreq (error bars)

> plotSatRatioVsFreq          :: StatsPlot
> plotSatRatioVsFreq fn ss ps =
>     errorBarPlot (scatterAttrs t x y fn) $ satisfactionRatio ss ps
>   where
>     t = "Satisfaction Ratio vs Frequency"
>     x = "Frequency [GHz]"
>     y = "Satisfaction Ratio"

simEffElev

> plotEffElev'         :: StatsPlot
> plotEffElev' fn _ ps = do
>   w    <- getWeather Nothing
>   effs <- historicalObsEff w ps
>   plotEffElev fn effs ps

> plotEffElev fn effs ps = scatterPlot (scatterAttrs t x y fn) $ zip (map elevationFromZenith ps) effs
>   where
>     t = "Efficiency vs Elevation"
>     x = "Elevation [deg]"
>     y = "Observing Efficiency"

> plotMinObsEff        :: StatsPlot
> plotMinObsEff fn _ _ = plotFunc [] (linearScale 1000 (0, 50)) minObservingEff

simEffLST

> plotEffLst'         :: StatsPlot
> plotEffLst' fn _ ps = do
>   w    <- getWeather Nothing
>   effs <- historicalObsEff w ps
>   plotEffLst fn effs ps

> plotEffLst fn effs ps =
>     scatterPlot (scatterAttrs t x y fn) $ zip (historicalLST ps) effs
>   where
>     t = "Efficiency vs LST"
>     x = "LST [hours]"
>     y = "Observing Efficiency"

simElevDec

> plotElevDec'         :: StatsPlot
> plotElevDec' fn _ ps = do
>   w    <- getWeather Nothing
>   effs <- historicalObsEff w ps
>   plotElevDec fn effs ps
>
> plotElevDec fn effs ps =
>     scatterPlot (scatterAttrs t x y fn) $ [(x, rad2deg y) | (x, y) <- decVsElevation ps effs]
>   where
>     t = "Elevation vs Dec"
>     x = "Declination [deg]"
>     y = "Elevation [deg]"

simPFLST - need pressure history

simScoreElev


> plotScoreElev'         :: StatsPlot
> plotScoreElev' fn _ ps = do
>   w       <- getWeather Nothing
>   --sf <- genScore $ map session ps
>   scores  <- historicalObsScore w ps
>   plotScoreElev fn scores ps

> plotScoreElev fn scores ps =
>     scatterPlot (scatterAttrs t x y fn) $ zip (map elevationFromZenith ps) scores
>   where
>     t = "Score vs Elevation"
>     x = "Elevation [deg]"
>     y = "Score"

simScoreLST

> plotLstScore'         :: StatsPlot
> plotLstScore' fn _ ps = do
>   w       <- getWeather Nothing
>   --sf <- genScore $ map session ps
>   scores  <- historicalObsScore w ps
>   plotLstScore fn scores ps
>
> plotLstScore fn scores ps =
>     scatterPlot (scatterAttrs t x y fn) $ zip (historicalLST ps) scores
>   where
>     t = "Score vs LST"
>     x = "LST [hours]"
>     y = "Score"

simBandPFTime

> 
> plotBandPressureTime fn trace = 
>     linePlots (scatterAttrs t x y fn) $ zip titles $ bandPressuresByTime trace 
>   where
>     t = "Band Preassure vs Time"
>     x = "Time [days]"
>     y = "Band Preassure"
>     titles = [Just "L", Just "S", Just "C", Just "X", Just "U", Just "K", Just "A", Just "Q"]
> 

simLSTPFTime1

> plotRAPressureTime1 fn trace =
>     linePlots (scatterAttrs t x y fn) $ take 8 $ zip titles $ raPressuresByTime trace 
>   where
>     t = "Ra Preassure vs Time"
>     x = "Time [days]"
>     y = "Ra Preassure"
>     titles = [Just (show a) | a <- [0 .. 7]]

simLSTPFTime2 - need pressure history

> plotRAPressureTime2 fn trace =
>     linePlots (scatterAttrs t x y fn) $ zip titles $ radata
>   where
>     (_, radata) = splitAt 8 $ raPressuresByTime trace
>     t = "Ra Preassure vs Time"
>     x = "Time [days]"
>     y = "Ra Preassure"
>     titles = [Just (show a) | a <- [8 .. 15]]

simLSTPFTime3 - need pressure history

> plotRAPressureTime3 fn trace =
>     linePlots (scatterAttrs t x y fn) $ zip titles $ radata
>   where
>     (_, radata) = splitAt 16 $ raPressuresByTime trace 
>     t = "Ra Preassure vs Time"
>     x = "Time [days]"
>     y = "Ra Preassure"
>     titles = [Just (show a) | a <- [16 .. 23]]

simHistRA

> histSessRA          :: StatsPlot
> histSessRA fn ss ps =
>     histogramPlots (histAttrs t x y fn) $ zip titles [sessionRAHrs ss, periodRAHrs ps]
>   where
>     t = "Right Ascension Histogram"
>     x = "RA [hr]"
>     y = "Counts [Hours]"
>     titles = [Just "Available", Just "Observed"]

simHistEffHr

> histEffHrBand'         :: StatsPlot
> histEffHrBand' fn _ ps = do
>   w    <- getWeather Nothing
>   effs <- historicalObsEff w ps
>   histEffHrBand fn effs ps
        
> histEffHrBand fn effs ps =
>     histogramPlots (histAttrs t x y fn) $ zip titles [pBand, effByBand]
>       where
>         pBand     = [(fromIntegral . fromEnum $ b, d) | (b, d) <- periodBand ps]
>         effByBand = [(fromIntegral . fromEnum $ b, e) | (b, e) <- periodEfficiencyByBand ps effs]
>         t = "Hours by Band Histogram"
>         x = "Band [L, S, C, X, U, K, A, Q]"
>         y = "Counts [Scheduled Hours]"
>         titles = [Just "Observed", Just "Obs * Eff"]

simHistFreq

> histSessFreq          :: StatsPlot
> histSessFreq fn ss ps =
>     histogramPlots (histAttrs t x y fn) $ zip titles [sessionFreqHrs ss, periodFreqHrs ps, periodFreqBackupHrs ps]
>   where
>     t = "Frequency Histogram"
>     x = "Frequency [GHz]"
>     y = "Counts [Hours]"
>     titles = [Just "Available", Just "Observed", Just "Obs. Backup"]

simHistCanceledFreq

> histCanceledFreqRatio fn ps trace =
>     histogramPlot (histAttrs t x y fn) $ periodCanceledFreqRatio ps trace
>   where
>     t = "Scheduled/Canceled Frequency Histogram"
>     x = "Frequency [GHz]"
>     y = "Scheduled/Canceled [Hours]"

simHistDec

> histSessDec          :: StatsPlot
> histSessDec fn ss ps =
>     histogramPlots (histAttrs t x y fn) $ zip titles [sessionDecHrs ss, periodDecHrs ps]
>   where
>     t = "Declination Histogram"
>     x = "Declination [deg]"
>     y = "Counts [Hours]"
>     titles = [Just "Available", Just "Observed"]

simHistPFHours - need pressure history
simHistPF - need pressure history
simHistTP

> histSessTP         :: StatsPlot
> histSessTP fn _ ps =
>     histogramPlot (tail $ histAttrs t x y fn) $ [(fromIntegral x, fromIntegral y) | (x, y) <- sessionTP ps]
>   where
>     t = "Telescope Period Histogram"
>     x = "Session TP [Hours]"
>     y = "Counts"

simHistTPQtrs 

> histSessTPQtrs :: StatsPlot
> histSessTPQtrs fn ss ps = 
>     histogramPlot (histAttrs t x y fn) tpDurs
>   where
>     tpDurs  = [(fromIntegral x, fromIntegral y) | (x, y) <- sessionTPQtrs ps]
>     t = "TP Counts Historgram"
>     x = "Duration [Minutes]"
>     y = "Counts"

simHistTPDurs - how are Session minDuratin and Period duration distributed in terms of actual minutes?

> histSessTPDurs :: StatsPlot
> histSessTPDurs fn ss ps = 
>     histogramPlots (histAttrs t x y fn) $ zip titles [tpDurs, maxTPTime]
>   where
>     tpDurs  = [(fromIntegral x, fromIntegral y) | (x, y) <- periodDuration ps]
>     maxTPTime  = [(fromIntegral x, fromIntegral y) | (x, y) <- sessionMinDurMaxTime ss]
>     t = "TP Minutes & Max TP Minutes Historgram"
>     x = "Duration [Minutes]"
>     y = "Counts [Minutes]"
>     titles = [Just "Observed", Just "Available"]

Utilities

> getEfficiency w p = do
>     let now' = (replaceYear 2006 (startTime p))
>     w'     <- newWeather w $ Just now'
>     result <- runScoring w' [] (efficiency now' (session p))
>     case result of
>         Nothing     -> return 0.0
>         Just result -> return result

> historicalObsEff w = mapM (getEfficiency w)

This function is only temporary until we get simulations integrated
TBF: how does this give us the score at the time that a period ran?
The weather is using (2006 1 1), so as year progresses, what forecast
will they be using?

> getScore      :: ScoreFunc -> Period -> Scoring Score
> getScore sf p = liftM eval . sf dt . session $ p
>   where
>     dt = replaceYear 2006 . startTime $ p

> --historicalObsScore :: Weather -> [Period] -> IO [Score]
> historicalObsScore w ps = do
>     w' <- newWeather w . Just $ fromGregorian' 2006 1 1
>     runScoring w' [] $ genScore (map session ps) >>= \sf -> mapM (getScore sf) ps

Attributes

> scatterAttrs title xlab ylab fpath =
>     [Title title
>    , XLabel xlab
>    , YLabel ylab
>     ] ++ if fpath == "" then [] else [PNG fpath]

> histAttrs title xlab ylab fpath =
>     [LogScale "y"
>    , Title title
>    , XLabel xlab
>    , YLabel ylab
>     ] ++ if fpath == "" then [] else [PNG fpath]

Testing Harness

> testPlot      :: StatsPlot -> String -> IO ()
> testPlot plot fn = do
>     (sessions, periods) <- getData
>     plot fn sessions periods

> getData :: IO ([Session], [Period])
> getData = do
>     g <- getStdGen
>     let sessions = generate 0 g $ genSessions 100
>     let periods  = generate 0 g $ genPeriods 100
>     return $ (sessions, periods)

> testPlots      :: [([Session] -> [Period] -> IO ())] -> IO [()]
> testPlots plots = do
>     (sessions, periods) <- getData
>     sequence (map (\f -> f sessions periods) plots)

Simulator Harness

> type StatsPlot = String -> [Session] -> [Period] -> IO ()

> statsPlots = [
>    plotDecFreq ""
>  , plotDecVsRA ""
>  , plotEffVsFreq' ""
>  , plotFreqVsTime "" 
>  , plotSatRatioVsFreq ""
>  , plotEffElev' ""
>  , plotEffLst' ""
>  , plotElevDec' ""
>  --, plotScoreElev' ""
>  --, plotLstScore' ""
>  , histSessRA "" 
>  , histEffHrBand' ""
>  , histSessFreq ""
>  , histSessDec ""
>  , histSessTP ""
>  , histSessTPQtrs ""
>  , histSessTPDurs ""
>   ]

> statsPlotsToFile rootPath = [
>    plotDecFreq        $ rootPath ++ "/simDecFreq.png"
>  , plotDecVsRA        $ rootPath ++ "/simDecRA.png"
>  , plotEffVsFreq'     $ rootPath ++ "/simEffFreq.png"
>  , plotFreqVsTime     $ rootPath ++ "/simFreqTime.png"
>  , plotSatRatioVsFreq $ rootPath ++ "/simSatisfyFreq.png"
>  , plotEffElev'       $ rootPath ++ "/simEffElev.png"
>  , plotEffLst'        $ rootPath ++ "/simEffLST.png"
>  , plotElevDec'       $ rootPath ++ "/simElevDec.png"
>  --, plotScoreElev'     $ rootPath ++ "/simScoreElev.png"
>  --, plotLstScore'      $ rootPath ++ "/simScoreLST.png"
>  , histSessRA         $ rootPath ++ "/simHistRA.png"
>  , histEffHrBand'     $ rootPath ++ "/simHistEffHr.png"
>  , histSessFreq       $ rootPath ++ "/simHistFreq.png"
>  --, histSessBackupFreq $ rootPath ++ "/simHistBackupFreq.png"
>  , histSessDec        $ rootPath ++ "/simHistDec.png"
>  , histSessTP         $ rootPath ++ "/simHistTP.png"
>  , histSessTPQtrs     $ rootPath ++ "/simHistTPQtrs.png"
>  , histSessTPDurs     $ rootPath ++ "/simHistTPDurs.png"
>   ]

> generatePlots :: Strategy -> [[Session] -> [Period] -> IO ()] -> Int -> IO ()
> generatePlots sched sps days = do
>     w <- getWeather Nothing
>     let g   = mkStdGen 1
>     let projs = generate 0 g $ genProjects 325 
>     let ss' = concatMap sessions projs
>     let ss  = zipWith (\s n -> s {sId = n}) ss' [0..]
>     putStrLn $ "Number of sessions: " ++ show (length ss)
>     putStrLn $ "Total Time: " ++ show (sum (map totalTime ss)) ++ " minutes"
>     start <- getCPUTime
>     (results, trace) <- simulate sched w rs dt dur int history [] ss
>     stop <- getCPUTime
>     putStrLn $ "Simulation Execution Speed: " ++ show (fromIntegral (stop-start) / 1.0e12) ++ " seconds"
>     let gaps = findScheduleGaps dt dur results
>     let canceled = getCanceledPeriods trace
>     -- text reports 
>     print "Simulation Schedule Checks: "
>     if (internalConflicts results) then print "  Overlaps in Schedule! " else print "  No overlaps in Schedule."
>     if (obeyDurations results) then print "  Min/Max Durations Honored" else print "  Min/Max Durations NOT Honored!"
>     if (validScores results) then print "  All scores >= 0.0" else print "  Socres < 0.0!"
>     if (gaps == []) then print "  No Gaps in Schedule." else print $ "  Gaps in Schedule: " ++ (show gaps)
>     reportSimulationInfo ss dt dur results canceled
>     reportSemesterInfo ss results 
>     -- create plots
>     mapM_ (\f -> f ss results) sps
>     -- create plots from trace; TBF : fold these into above
>     histCanceledFreqRatio "../myplots/simHistCanceledFreq.png" results trace
>     plotBandPressureTime "../myplots/simBandPFTime.png" trace
>     plotRAPressureTime1 "../myplots/simLSTPFTime1.png" trace
>     plotRAPressureTime2 "../myplots/simLSTPFTime2.png" trace
>     plotRAPressureTime3 "../myplots/simLSTPFTime3.png" trace
>   where
>     rs      = []
>     dt      = fromGregorian 2006 2 1 0 0 0
>     dur     = 60 * 24 * days
>     int     = 60 * 24 * 2
>     history = []

> reportSimulationInfo :: [Session] -> DateTime -> Minutes -> [Period] -> [Period] -> IO ()
> reportSimulationInfo ss dt dur observed canceled = do
>     putStrLn $ printf "%-9s %-9s %-9s %-9s %-9s" "simulated" "session" "backup" "scheduled" "observed" 
>     putStrLn $ printf "%-9.2f %-9.2f %-9.2f %-9.2f %-9.2f" t1 t2 t3 t4 t5 
>     putStrLn $ printf "%-9s %-9s %-9s %-9s %-9s"  "canceled" "obsBackup" "totalDead" "schedDead" "failedBckp"
>     putStrLn $ printf "%-9.2f %-9.2f %-9.2f %-9.2f %-9.2f" t6 t7 t8 t9 t10
>       where
>         (t1, t2, t3, t4, t5, t6, t7, t8, t9, t10) = breakdownSimulationTimes ss dt dur observed canceled

> reportSemesterInfo :: [Session] -> [Period] -> IO ()
> reportSemesterInfo ss ps = do
>     putStrLn $ printf "%s   %-9s %-9s %-9s %-9s" "Sem" "Total" "Backup" "Obs" "ObsBp" 
>     putStrLn $ reportSemesterHrs "05C" ss ps 
>     putStrLn $ reportSemesterHrs "06A" ss ps 
>     putStrLn $ reportSemesterHrs "06B" ss ps 
>     putStrLn $ reportSemesterHrs "06C" ss ps 

> reportSemesterHrs :: String -> [Session] -> [Period] -> String
> reportSemesterHrs sem ss ps  = printf "%s : %-9.2f %-9.2f %-9.2f %-9.2f" sem total totalBackup totalObs totalBackupObs  
>   where
>     total = totalHrs ss (\s -> isInSemester s sem) 
>     totalBackup = totalHrs ss (\s -> isInSemester s sem && backup s)
>     totalObs = totalPeriodHrs ps (\p -> isPeriodInSemester p sem)
>     totalBackupObs = totalPeriodHrs ps (\p -> isPeriodInSemester p sem && pBackup p)

> runSim days filepath = generatePlots scheduleMinDuration (statsPlotsToFile filepath) days
