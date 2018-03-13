import Text.ParserCombinators.Parsec hiding (spaces)
import System.Environment
import Control.Monad
import Control.Monad.Except

data LispVal = Atom   String
             | List   [LispVal]
             | DottedList [LispVal] LispVal
             | Number Integer
             | Str    String
             | Bool   Bool
             deriving (Eq)

instance Show LispVal where
  show = renderVal
             
data LispError = NumArgs Integer [LispVal]
               | TypeMismatch String LispVal
               | Parser ParseError
               | BadSpecialForm String LispVal
               | NotFunction String String
               | UnboundVar String String
               | Default String

showError :: LispError -> String
showError (UnboundVar message varname)  = message ++ ": " ++ varname
showError (BadSpecialForm message form) = message ++ ": " ++ show form
showError (NotFunction message func)    = message ++ ": " ++ show func
showError (NumArgs expected found)      = "Expected " ++ show expected 
                                       ++ " args; found values " ++ unwordsList found
showError (TypeMismatch expected found) = "Invalid type: expected " ++ expected
                                       ++ ", found " ++ show found
showError (Parser parseErr)             = "Parse error at " ++ show parseErr

instance Show LispError where show = showError

type ThrowsError = Either LispError

trapError action = catchError action (return . show)

extractValue :: ThrowsError a -> a
extractValue (Right val) = val

symbol :: Parser Char
symbol = oneOf "!#$%&|*+-/:<=>?@^_~"

spaces :: Parser ()
spaces = skipMany1 space

parseString :: Parser LispVal
parseString = do
                char '"'
                x <- many (noneOf "\"")
                char '"'
                return $ Str x

parseAtom :: Parser LispVal
parseAtom = do 
              first <- letter <|> symbol
              rest <- many (letter <|> digit <|> symbol)
              let atom = first:rest
              return $ case atom of 
                         "#t" -> Bool True
                         "#f" -> Bool False
                         _    -> Atom atom

parseNumber :: Parser LispVal
parseNumber = liftM (Number . read) $ many1 digit

{-readExpr :: String -> String
readExpr input = case parse parseExpr "lisp" input of
    Left err  -> "No match: " ++ show err
    Right val -> "Found value: `" ++ (show val) ++"'"

readExpr :: String -> LispVal
readExpr input = case parse parseExpr "lisp" input of
    Left err  -> Str $ "No match: " ++ show err
    Right val -> val-}
readExpr :: String -> ThrowsError LispVal
readExpr input = case parse parseExpr "lisp" input of
     Left err  -> throwError $ Parser err
     Right val -> return val
     
parseList :: Parser LispVal
parseList = liftM List $ sepBy parseExpr spaces

parseDottedList :: Parser LispVal
parseDottedList = do
    head <- endBy parseExpr spaces
    tail <- char '.' >> spaces >> parseExpr
    return $ DottedList head tail

parseQuoted :: Parser LispVal
parseQuoted = do
    char '\''
    x <- parseExpr
    return $ List [Atom "quote", x]

parseExpr :: Parser LispVal
parseExpr = parseAtom
         <|> parseString
         <|> parseNumber
         <|> parseQuoted
         <|> do char '('
                x <- try parseList <|> parseDottedList
                char ')'
                return x

renderVal :: LispVal -> String
renderVal (Str contents)         = "\"" ++ contents ++ "\""
renderVal (Atom name)            = name
renderVal (Number contents)      = show contents
renderVal (Bool True)            = "#t"
renderVal (Bool False)           = "#f"
renderVal (List contents)        = "(" ++ unwordsList contents ++ ")"
renderVal (DottedList head tail) = "(" ++ unwordsList head ++ " . " ++ renderVal tail ++ ")"

unwordsList :: [LispVal] -> String
unwordsList = unwords . map renderVal

eval :: LispVal -> ThrowsError LispVal
eval val@(Str _)                = return val
eval val@(Number _)             = return val
eval val@(Bool _)               = return val
eval (List [Atom "quote", val]) = return val
eval (List (Atom func : args))  = mapM eval args >>= apply func
eval badForm = throwError $ BadSpecialForm "Unrecognized special form" badForm

apply :: String -> [LispVal] -> ThrowsError LispVal
apply func args = maybe (throwError $ NotFunction "Unrecognized primitive function args" func)
                        ($ args)
                        (lookup func primitives)

primitives :: [(String, [LispVal] -> ThrowsError LispVal)]
primitives = [("+", numericBinop (+)),
              ("-", numericBinop (-)),
              ("*", numericBinop (*)),
              ("/", numericBinop div),
              ("mod", numericBinop mod),
              ("quotient", numericBinop quot),
              ("%", numericBinop rem)]

numericBinop :: (Integer -> Integer -> Integer) -> [LispVal] -> ThrowsError LispVal
numericBinop op           []  = throwError $ NumArgs 2 []
numericBinop op singleVal@[_] = throwError $ NumArgs 2 singleVal
numericBinop op params        = mapM unpackNum params >>= return . Number . foldl1 op

unpackNum :: LispVal -> ThrowsError Integer
unpackNum (Number n) = return n
unpackNum (Str n)    = let parsed = reads n in 
                           if null parsed 
                             then throwError $ TypeMismatch "number" $ Str n
                             else return $ fst $ parsed !! 0
unpackNum (List [n]) = unpackNum n
unpackNum notNum     = throwError $ TypeMismatch "number" notNum

main :: IO ()
--main = do 
--         (expr:_) <- getArgs
--         putStrLn (readExpr expr)
--main = getArgs >>= print . eval . readExpr . head
main = do
     args <- getArgs
     evaled <- return $ liftM show $ readExpr (args !! 0) >>= eval
     putStrLn $ extractValue $ trapError evaled