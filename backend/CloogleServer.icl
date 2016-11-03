module CloogleServer

import StdArray, StdBool, StdFile, StdList, StdOrdList, StdOverloaded, StdTuple
from StdFunc import o, flip, const
from StdMisc import abort

from TCPIP import :: IPAddress, :: Port, instance toString IPAddress

from Data.Func import $
import Data.List
import Data.Tuple
import Data.Maybe
import System.CommandLine
import Text.JSON
import Data.Functor
import Control.Applicative
import Control.Monad
from Text import class Text(concat,trim,indexOf,toLowerCase),
	instance Text String, instance + String

import System.Time

import qualified Regex

from SimpleTCPServer import :: LogMessage{..}, serve, :: Logger
import TypeDB
import Type
import Cache

:: Request = { unify     :: Maybe String
             , name      :: Maybe String
             , className :: Maybe String
             , typeName  :: Maybe String
             , modules   :: Maybe [String]
             , libraries :: Maybe ([String], Bool)
             , page      :: Maybe Int
             }

:: Response = { return         :: Int
              , data           :: [Result]
              , msg            :: String
              , more_available :: Maybe Int
              , suggestions    :: Maybe [(Request, Int)]
              }

:: Result = FunctionResult FunctionResult
          | TypeResult TypeResult
          | ClassResult ClassResult
          | MacroResult MacroResult

:: BasicResult = { library  :: String
                 , filename :: String
                 , modul    :: String
                 , dcl_line :: Maybe Int
                 , distance :: Int
                 , builtin  :: Maybe Bool
                 }

:: FunctionResult :== (BasicResult, FunctionResultExtras)
:: FunctionResultExtras = { func                :: String
                          , unifier             :: Maybe StrUnifier
                          , cls                 :: Maybe ShortClassResult
                          , constructor_of      :: Maybe String
                          , recordfield_of      :: Maybe String
                          , generic_derivations :: Maybe [(String, [LocationResult])]
                          }

:: TypeResult :== (BasicResult, TypeResultExtras)
:: TypeResultExtras = { type             :: String
                      , type_instances   :: [(String, [String], [LocationResult])]
                      , type_derivations :: [(String, [LocationResult])]
                      }

:: ClassResult :== (BasicResult, ClassResultExtras)
:: ClassResultExtras = { class_name      :: String
                       , class_heading   :: String
                       , class_funs      :: [String]
                       , class_instances :: [([String], [LocationResult])]
                       }

:: MacroResult :== (BasicResult, MacroResultExtras)
:: MacroResultExtras = { macro_name           :: String
                       , macro_representation :: String
                       }

:: LocationResult :== (String, String, Maybe Int)

:: StrUnifier :== ([(String,String)], [(String,String)])

:: ErrorResult = MaybeError Int String

:: ShortClassResult = { cls_name :: String, cls_vars :: [String] }

derive JSONEncode Request, Response, Result, ShortClassResult, BasicResult,
	FunctionResultExtras, TypeResultExtras, ClassResultExtras, MacroResultExtras
derive JSONDecode Request, Response, Result, ShortClassResult, BasicResult,
	FunctionResultExtras, TypeResultExtras, ClassResultExtras, MacroResultExtras

instance zero Request
where
	zero = { unify     = Nothing
	       , name      = Nothing
	       , className = Nothing
	       , typeName  = Nothing
	       , modules   = Nothing
	       , libraries = Nothing
	       , page      = Nothing
	       }

instance toString Response where toString r = toString (toJSON r) + "\n"
instance toString Request where toString r = toString $ toJSON r

instance fromString (Maybe Request) where fromString s = fromJSON $ fromString s

instance < BasicResult where (<) r1 r2 = r1.distance < r2.distance
instance < Result
where
	(<) r1 r2 = basic r1 < basic r2
	where
		basic :: Result -> BasicResult
		basic (FunctionResult (br,_)) = br
		basic (TypeResult     (br,_)) = br
		basic (ClassResult    (br,_)) = br
		basic (MacroResult    (br,_)) = br

err :: Int String -> Response
err c m = { return         = c
          , data           = []
          , msg            = m
          , more_available = Nothing
          , suggestions    = Nothing
          }

E_NORESULTS    :== 127
E_INVALIDINPUT :== 128
E_INVALIDNAME  :== 129
E_INVALIDTYPE  :== 130

MAX_RESULTS    :== 15
CACHE_PREFETCH :== 5

Start w
# (io, w) = stdio w
# (cmdline, w) = getCommandLine w
| length cmdline <> 2 = help io w
# [_,port:_] = cmdline
# port = toInt port
# (db, io) = openDb io
# (_, w) = fclose io w
| isNothing db = abort "stdin does not have a TypeDB\n"
#! db = fromJust db
= serve (handle db) (Just log) port w
where
	help :: *File *World -> *World
	help io w
	# io = io <<< "Usage: ./CloogleServer <port>\n"
	= snd $ fclose io w

	handle :: !TypeDB !(Maybe Request) !*World -> *(!Response, CacheKey, !*World)
	handle _ Nothing w = (err E_INVALIDINPUT "Couldn't parse input", "", w)
	handle db (Just request=:{unify,name,page}) w
		//Check cache
		# (mbResponse, w) = readCache request w
		| isJust mbResponse
			# r = fromJust mbResponse
			= ({r & return = if (r.return == 0) 1 r.return}, cacheKey request, w)
		| isJust name && size (fromJust name) > 40
			= respond (err E_INVALIDNAME "Function name too long") w
		| isJust name && any isSpace (fromString $ fromJust name)
			= respond (err E_INVALIDNAME "Name cannot contain spaces") w
		| isJust unify && isNothing (parseType $ fromString $ fromJust unify)
			= respond (err E_INVALIDTYPE "Couldn't parse type") w
		// Results
		# drop_n = fromJust (page <|> pure 0) * MAX_RESULTS
		# results = drop drop_n $ sort $ search request db
		# more = max 0 (length results - MAX_RESULTS)
		// Suggestions
		# mbType = unify >>= parseType o fromString
		# suggestions
			= sortBy (\a b -> snd a > snd b) <$>
			  filter ((<)(length results) o snd) <$>
			  (mbType >>= \t -> suggs name t db)
		# (results,nextpages) = splitAt MAX_RESULTS results
		// Response
		# response = if (isEmpty results)
			(err E_NORESULTS "No results")
			{ return = 0
		    , msg = "Success"
		    , data           = results
		    , more_available = Just more
		    , suggestions    = suggestions
		    }
		// Save page prefetches
		# w = cachePages CACHE_PREFETCH 1 response nextpages w
		// Save cache file
		= respond response w
	where
		respond :: Response *World -> *(Response, CacheKey, *World)
		respond r w = (r, cacheKey request, writeCache LongTerm request r w)

		cachePages :: Int Int Response [Result] *World -> *World
		cachePages _ _  _ [] w = w
		cachePages 0 _  _ _  w = w
		cachePages npages i response results w
		# w = writeCache Brief req` resp` w
		= cachePages (npages - 1) (i + 1) response keep w
		where
			req` = { request & page = ((+) i) <$> request.page <|> pure 0 }
			resp` =
				{ response
				& more_available = Just $ max 0 (length results - MAX_RESULTS)
				, data = give
				}
			(give,keep) = splitAt MAX_RESULTS results

	suggs :: !(Maybe String) !Type !TypeDB -> Maybe [(Request, Int)]
	suggs n (Func is r cc) db
		| length is < 3
			= Just [let t` = concat $ print False $ Func is` r cc in
			        let request = {zero & name=n, unify=Just t`} in
			        (request, length $ search request db)
			        \\ is` <- permutations is | is` <> is]
	suggs _ _ _ = Nothing

	search :: !Request !TypeDB -> [Result]
	search {unify,name,className,typeName,modules,libraries,page} db
		# db = case libraries of
			(Just ls) = filterLocations (isLibMatch ls) db
			Nothing   = db
		# db = case modules of
			(Just ms) = filterLocations (isModMatch ms) db
			Nothing   = db
		| isJust className
			# className = fromJust className
			# classes = findClass className db
			= map (flip makeClassResult db) classes
		| isJust typeName
			# typeName = fromJust typeName
			# types = findType typeName db
			= [makeTypeResult (Just typeName) l td db \\ (l,td) <- types]
		# mbType = prepare_unification True <$> (unify >>= parseType o fromString)
		# mbName = name >>= 'Regex'.compile o fromString
		// Search normal functions
		# filts = catMaybes [ (\t _ -> isUnifiable t) <$> mbType
		                    , (\n loc _ -> isNameMatch n loc) <$> mbName
		                    ]
		# funs = map (\f -> makeFunctionResult name mbType Nothing f db) $ findFunction`` filts db
		// Search macros
		# macros = case (isNothing mbType, mbName) of
			(True, Just n) = findMacro` (\loc _ -> isNameMatch n loc) db
			_              = []
		# macros = map (\(lhs,rhs) -> makeMacroResult name lhs rhs) macros
		// Search class members
		# filts = catMaybes [ (\t _ _ _ _->isUnifiable t) <$> mbType
		                    , (\n (Location lib mod _ _) _ _ f _ -> isNameMatch
		                      n (Location lib mod Nothing f)) <$> mbName
		                    ]
		# members = findClassMembers`` filts db
		# members = map (\(Location lib mod line cls,vs,_,f,et) -> makeFunctionResult name mbType
			(Just {cls_name=cls,cls_vars=vs}) (Location lib mod line f,et) db) members
		// Search types
		# lcName = if (isJust mbType && isType (fromJust mbType))
			(let (Type name _) = fromJust mbType in Just $ toLowerCase name)
			(toLowerCase <$> name)
		# types = case (isNothing mbType,lcName) of
			(True,Just n) = findType` (\loc _ -> toLowerCase (getName loc) == n) db
			_             = []
		# types = map (\(tl,td) -> makeTypeResult name tl td db) types
		// Search classes
		# classes = case (isNothing mbType, toLowerCase <$> name) of
			(True, Just c) = findClass` (\loc _ _ _ -> toLowerCase (getName loc) == c) db
			_              = []
		# classes = map (flip makeClassResult db) classes
		// Merge results
		= sort $ funs ++ members ++ types ++ classes ++ macros

	makeClassResult :: (Location, [TypeVar], ClassContext, [(Name,ExtendedType)])
		TypeDB -> Result
	makeClassResult rec=:(Builtin _, _, _, _) db
		= ClassResult
		  ( { library  = ""
		    , filename = ""
		    , dcl_line = Nothing
		    , modul    = ""
		    , distance = -100
		    , builtin  = Just True
		    }
		  , makeClassResultExtras rec db
		  )
	makeClassResult rec=:(Location lib mod line cls, vars, cc, funs) db
		= ClassResult
		  ( { library  = lib
		    , filename = modToFilename mod
		    , dcl_line = line
		    , modul    = mod
		    , distance = -100
		    , builtin  = Nothing
		    }
		  , makeClassResultExtras rec db
		  )
	makeClassResultExtras :: (Location, [TypeVar], ClassContext, [(Name,ExtendedType)])
		TypeDB -> ClassResultExtras
	makeClassResultExtras (l, vars, cc, funs) db
		= { class_name = cls
		  , class_heading = foldl ((+) o (flip (+) " ")) cls vars +
		      if (isEmpty cc) "" " " + concat (print False cc)
		  , class_funs = [print_fun fun \\ fun <- funs]
		  , class_instances
		      = sortBy (\(a,_) (b,_) -> a < b)
		          [([concat (print False t) \\ t <- ts], map loc ls)
		          \\ (ts,ls) <- getInstances cls db]
		  }
	where
		cls = case l of
			Builtin c = c
			Location _ _ _ c = c

		print_fun :: (Name,ExtendedType) -> String
		print_fun f=:(_,ET _ et) = fromJust $
			et.te_representation <|> (pure $ concat $ print False f)

	makeTypeResult :: (Maybe String) Location TypeDef TypeDB -> Result
	makeTypeResult mbName (Location lib mod line t) td db
		= TypeResult
		  ( { library  = lib
		    , filename = modToFilename mod
		    , dcl_line = line
		    , modul    = mod
		    , distance
		        = if (isNothing mbName) -100 (levenshtein` t (fromJust mbName))
		    , builtin  = Nothing
		    }
		  , { type             = concat $ print False td
		    , type_instances   = map (appSnd3 (map (concat o (print False)))) $
		        map (appThd3 (map loc)) $ getTypeInstances t db
		    , type_derivations = map (appSnd (map loc)) $ getTypeDerivations t db
		    }
		  )
	makeTypeResult mbName (Builtin t) td db
		= TypeResult
		  ( { library  = ""
		    , filename = ""
		    , dcl_line = Nothing
		    , modul    = ""
		    , distance
		        = if (isNothing mbName) -100 (levenshtein` t (fromJust mbName))
		    , builtin  = Just True
		    }
		  , { type             = concat $ print False td
		    , type_instances   = map (appSnd3 (map (concat o (print False)))) $
		        map (appThd3 (map loc)) $ getTypeInstances t db
		    , type_derivations = map (appSnd (map loc)) $ getTypeDerivations t db
		    }
		  )

	makeMacroResult :: (Maybe String) Location Macro -> Result
	makeMacroResult mbName (Location lib mod line m) mac
		= MacroResult
		  ( { library  = lib
		    , filename = modToFilename mod
		    , dcl_line = line
		    , modul    = mod
		    , distance
		        = if (isNothing mbName) -100 (levenshtein` (fromJust mbName) m)
		    , builtin  = Nothing
		    }
		  , { macro_name = m
		    , macro_representation = mac.macro_as_string
		    }
		  )

	makeFunctionResult :: (Maybe String) (Maybe Type) (Maybe ShortClassResult)
		(Location, ExtendedType) TypeDB -> Result
	makeFunctionResult
		orgsearch orgsearchtype mbCls (fl, et=:(ET type tes)) db
		= FunctionResult
		  ( { library  = lib
		    , filename = modToFilename mod
		    , dcl_line = line
		    , modul    = mod
		    , distance = distance
		    , builtin  = builtin
		    }
		  , { func     = fromJust (tes.te_representation <|>
		                           (pure $ concat $ print False (fname,et)))
		    , unifier  = toStrUnifier <$> finish_unification <$>
		        (orgsearchtype >>= unify [] (prepare_unification False type))
		    , cls      = mbCls
		    , constructor_of = if tes.te_isconstructor
		        (let (Func _ r _) = type in Just $ concat $ print False r)
		        Nothing
		    , recordfield_of = if tes.te_isrecordfield
		        (let (Func [t:_] _ _) = type in Just $ concat $ print False t)
		        Nothing
		    , generic_derivations
		        = let derivs = getDerivations fname db in
		          const (sortBy (\(a,_) (b,_) -> a < b)
				    [(concat $ print False d, map loc ls) \\ (d,ls) <- derivs]) <$>
		          tes.te_generic_vars
		    }
		  )
	where
		(lib,mod,fname,line,builtin) = case fl of
			(Location l m ln f) = (l,  m,  f, ln,      Nothing)
			(Builtin f)         = ("", "", f, Nothing, Just True)

		toStrUnifier :: Unifier -> StrUnifier
		toStrUnifier (tvas1, tvas2) = (map toStr tvas1, map toStr tvas2)
		where toStr (var, type) = (var, concat $ print False type)

		toStrPriority :: (Maybe Priority) -> String
		toStrPriority p = case print False p of [] = ""; ss = concat [" ":ss]

		distance
			| isNothing orgsearch || fromJust orgsearch == ""
				| isNothing orgsearchtype = 0
				# orgsearchtype = fromJust orgsearchtype
				# (Just (ass1, ass2)) = finish_unification <$>
					unify [] orgsearchtype (prepare_unification False type)
				= penalty + toInt (sum [typeComplexity t \\ (_,t)<-ass1 ++ ass2 | not (isVar t)])
			# orgsearch = fromJust orgsearch
			= penalty + levenshtein` orgsearch fname
		where
			penalty
			| tes.te_isrecordfield = 2
			| tes.te_isconstructor = 1
			| otherwise            = 0

			typeComplexity :: Type -> Real
			typeComplexity (Type _ ts) = 1.2 * foldr ((+) o typeComplexity) 1.0 ts
			typeComplexity (Func is r _) = 2.0 * foldr ((+) o typeComplexity) 1.0 [r:is]
			typeComplexity (Var _) = 1.0
			typeComplexity (Cons _ ts) = 1.2 * foldr ((+) o typeComplexity) 1.0 ts
			typeComplexity (Uniq t) = 3.0 + typeComplexity t

	levenshtein` :: String String -> Int
	levenshtein` a b = if (indexOf a b == -1) 0 -100 + levenshtein [c \\ c <-: a] [c \\ c <-: b]

	modToFilename :: String -> String
	modToFilename mod = (toString $ reverse $ takeWhile ((<>)'.')
	                              $ reverse $ fromString mod) + ".dcl"

	isUnifiable :: Type ExtendedType -> Bool
	isUnifiable t1 (ET t2 _) = isJust (unify [] t1 (prepare_unification False t2))

	isNameMatch :: !'Regex'.Regex Location -> Bool
	isNameMatch r loc = not $ isEmpty $ 'Regex'.match r $ fromString $ getName loc

	isModMatch :: ![String] Location -> Bool
	isModMatch mods (Location _ mod _ _) = isMember mod mods
	isModMatch _    (Builtin _)          = False

	isLibMatch :: (![String], !Bool) Location -> Bool
	isLibMatch (libs,_) (Location lib _ _ _) = any (\l -> indexOf l lib == 0) libs
	isLibMatch (_,blti) (Builtin _)          = blti

	loc :: Location -> LocationResult
	loc (Location lib mod ln _) = (lib, mod, ln)

	log :: (LogMessage (Maybe Request) Response CacheKey) IPAddress *World
		-> *(IPAddress, *World)
	log msg s w
	| not needslog = (newS msg s, w)
	# (tm,w) = localTime w
	# (io,w) = stdio w
	# io = io <<< trim (toString tm) <<< " " <<< msgToString msg s
	= (newS msg s, snd (fclose io w))
	where
		needslog = case msg of (Received _) = True; (Sent _ _) = True; _ = False

	newS :: (LogMessage (Maybe Request) Response CacheKey) IPAddress -> IPAddress
	newS m s = case m of (Connected ip) = ip; _ = s

	msgToString :: (LogMessage (Maybe Request) Response CacheKey) IPAddress -> String
	msgToString (Received Nothing) ip
		= toString ip + " <-- Nothing\n"
	msgToString (Received (Just a)) ip
		= toString ip + " <-- " + toString a + "\n"
	msgToString (Sent {return,data,msg,more_available} ck) ip
		= toString ip + " --> " + toString (length data)
			+ " results (" + toString return + "; " + msg
			+ if (isJust more_available) ("; " + toString (fromJust more_available) + " more") ""
			+ "; cache: " + ck + ")\n"
	msgToString _ _ = ""
