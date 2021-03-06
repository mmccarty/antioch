#!/home/dss/conundrum/bin/runhaskell
import System.Cmd
import System.Environment
import Text.ParserCombinators.Parsec
import Text.Printf
import Data.List

-- TBF: this whole script is a shambles. Its using Parsec, but not taking 
-- advantage of it, and could be refactored to be a lot smaller.

main :: IO ()
main = do 
  as <- getArgs
  let filename = head as
  fileContent <- readFile filename
  case parseQC fileContent of
    Left msg -> putStrLn $ show msg
    Right lns -> putStrLn $ (reportErrors lns) ++ "\n" ++  (reportTests lns) 
  
-- TBF: should the parser be doing this work?

reportErrors :: [[String]] -> String
reportErrors lines = if errors == "" then "No Failing Quick Check Properties" else printf "%d Failing Quick Check Properties: \n%s\n" numErrors errors
  where
    errors = concat . reportErrors' $ lines
    numErrors = length $ elemIndices '\n' errors

reportTests :: [[String]] -> String
reportTests lines = printf "%d Quick Check Properties" numTests 
  where
    tests = concat . reportTests' $ lines
    numTests = length $ elemIndices '\n' tests
    

reportTests' :: [[String]] -> [String]
reportTests' [] = []
reportTests' (x:xs) = (reportTest x) :(reportTests' xs)

reportTest :: [String] -> String
reportTest line | isInfixOf "prop_" (head line) = (head line) ++ "\n"
                 | otherwise = ""

reportErrors' :: [[String]] -> [String]
reportErrors' [] = []
reportErrors' (x:xs) = (reportError x) :(reportErrors' xs)
--reportErrors' lines = foldr reportError [] lines


reportError :: [String] -> String
reportError line | isInfixOf "prop_" (head line) = checkForError line
                 | otherwise = ""

checkForError :: [String] -> String
checkForError line | not $ isInfixOf "OK" (head line) = printf "Error: %s\n" (head line)
                   | otherwise = ""

parseQC :: String -> Either ParseError [[String]]
parseQC input = parse qcFile "(unknown)" input

qcFile = endBy line eol 
line = sepBy cell (char ',') 
eol = char '\n'  
cell = many (noneOf "\n")


