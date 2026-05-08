-- Conformance shim for the ansi-terminal Haskell package.
--
-- Public detection surface used here:
--   hSupportsANSI      :: Handle -> IO Bool   (binary ANSI support gate)
--   hSupportsANSIColor :: Handle -> IO Bool   (binary "any color" gate)
--
-- Plus terminal-size:
--   size               :: IO (Maybe (Window Int))   (TIOCGWINSZ + fallbacks)
--
-- Detection mechanism: env-var heuristic (TERM, NO_COLOR) + isatty checks.
-- Binary-only color detection; same mapping policy as kleur/colorette/pastel
-- (true -> ansi16 floor, false -> none).

{-# LANGUAGE OverloadedStrings #-}
module Main where

import qualified System.Console.ANSI as ANSI
import qualified System.Console.Terminal.Size as TS
import           System.IO            (stdout, hPutStrLn, stderr)
import           System.Environment   (lookupEnv, getArgs, getProgName)
import           System.Exit          (exitWith, ExitCode(..))
import           Data.List            (intercalate)

main :: IO ()
main = do
  envelopePath <- lookupEnv "CONFORMANCE_ENVELOPE"
  case envelopePath of
    Nothing -> do
      hPutStrLn stderr "ansi-terminal-shim: $CONFORMANCE_ENVELOPE not set"
      exitWith (ExitFailure 2)
    Just p  -> run p

run :: FilePath -> IO ()
run envelopePath = do
  envelopeStr <- readFile envelopePath
  args <- getArgs
  let outputPath = case args of
        (a:_) -> a
        _     -> "ansi-terminal.json"

  ansiSupported    <- ANSI.hSupportsANSI stdout
  ansiColor        <- ANSI.hSupportsANSIColor stdout
  windowSize       <- TS.size

  let colorValue = if ansiColor then "ansi16" else "none"
      sizeFields = case (windowSize :: Maybe (TS.Window Int)) of
        Just w  -> Just (TS.width w, TS.height w)
        Nothing -> Nothing

  let dimCap = case sizeFields of
        Just (cols, rows) ->
          "{\"supported\": true, \"value\": {\"cols\": " ++ show cols
            ++ ", \"rows\": " ++ show rows
            ++ ", \"pixel_width\": 0, \"pixel_height\": 0},"
            ++ " \"method\": \"terminal-size Haskell pkg (TIOCGWINSZ + fallbacks)\"}"
        Nothing -> "{\"supported\": false, \"raw\": \"terminal-size returned Nothing\"}"

  let ttyCap = "{\"supported\": true, \"value\": " ++ lowerBool ansiSupported
        ++ ", \"method\": \"ansi-terminal hSupportsANSI stdout (env+isatty heuristic)\"}"

  let colorCap = "{\"supported\": true, \"value\": \"" ++ colorValue ++ "\""
        ++ ", \"method\": \"ansi-terminal hSupportsANSIColor (binary -> ansi16 floor)\""
        ++ ", \"raw\": {\"hSupportsANSI\": " ++ lowerBool ansiSupported
        ++ ", \"hSupportsANSIColor\": " ++ lowerBool ansiColor
        ++ ", \"mapping_note\": \"ansi-terminal does not measure depth\"}}"

  let json = unlines
        [ "{"
        , "  \"schema_version\": \"0.1.0\","
        , "  \"run\": " ++ trimTrailingNewline envelopeStr ++ ","
        , "  \"lib\": {\"name\": \"ansi-terminal\", \"version\": \"1.1.2\", \"language\": \"haskell\", \"tier\": \"passive\"},"
        , "  \"capabilities\": {"
        , "    \"tty_stdin\": {\"supported\": false},"
        , "    \"tty_stdout\": " ++ ttyCap ++ ","
        , "    \"tty_stderr\": {\"supported\": false},"
        , "    \"color_depth\": " ++ colorCap ++ ","
        , "    \"windows_console_color\": {\"supported\": false},"
        , "    \"dimensions\": " ++ dimCap ++ ","
        , "    \"unicode\": {\"supported\": false},"
        , "    \"terminal_kind\": {\"supported\": false},"
        , "    \"multiplexer\": {\"supported\": false},"
        , "    \"theme\": {\"supported\": false},"
        , "    \"background\": {\"supported\": false},"
        , "    \"hyperlinks\": {\"supported\": false},"
        , "    \"mouse\": {\"supported\": false},"
        , "    \"keyboard\": {\"supported\": false},"
        , "    \"clipboard_osc52\": {\"supported\": false},"
        , "    \"graphics_sixel\": {\"supported\": false},"
        , "    \"graphics_kitty\": {\"supported\": false},"
        , "    \"xtversion\": {\"supported\": false},"
        , "    \"da1_attributes\": {\"supported\": false},"
        , "    \"ci_detected\": {\"supported\": false}"
        , "  }"
        , "}"
        ]
  writeFile outputPath json
  hPutStrLn stderr $ "ansi-terminal-shim: wrote " ++ outputPath
                    ++ " (ansi=" ++ show ansiSupported
                    ++ " color=" ++ colorValue
                    ++ " size=" ++ show sizeFields ++ ")"

lowerBool :: Bool -> String
lowerBool True  = "true"
lowerBool False = "false"

trimTrailingNewline :: String -> String
trimTrailingNewline = reverse . dropWhile (\c -> c == '\n' || c == '\r' || c == ' ' || c == '\t') . reverse
