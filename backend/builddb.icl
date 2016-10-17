module builddb

// Project libraries
import qualified TypeDB as DB
from TypeDB import ::TypeExtras{..}, instance zero TypeExtras, ::Macro{..}

// StdEnv
import StdFile, StdList, StdMisc, StdArray, StdBool, StdString, StdTuple

// CleanPlatform
import Data.Maybe, Data.Either, Data.Error, Data.Func, Data.Tuple, Data.Functor
import Control.Applicative, Control.Monad
from Text import class Text(concat,replaceSubString,indexOf), instance Text String
import System.Directory, System.CommandLine

// CleanTypeUnifier
import qualified Type as T
from Type import class print(print), instance print [a], instance print String,
	instance print Type, instance print Priority
from Type import qualified ::TypeDef{..}, ::Constructor{..}
import CoclUtils

// CleanPrettyPrint
import CleanPrettyPrint

// frontend
import Heap
from hashtable import ::HashTable, ::QualifiedIdents(NoQualifiedIdents),
	::IdentClass(IC_Module), ::BoxedIdent{..}, putIdentInHashTable
from predef import init_identifiers
from compile import empty_cache, ::DclCache{hash_table}
from general import ::Optional(..)
from syntax import ::SymbolTable, ::SymbolTableEntry, ::Ident{..}, ::SymbolPtr,
	::Position(..), ::LineNr, ::FileName, ::FunctName,
	::Module{mod_ident,mod_defs},
	::ParsedDefinition(PD_TypeSpec,PD_Instance,PD_Class,PD_Type,PD_Generic,PD_Derive,PD_Function),
	::FunSpecials, ::Priority, ::ParsedModule, ::SymbolType,
	::ParsedInstanceAndMembers{..}, ::ParsedInstance{pi_ident,pi_pos,pi_types},
	::Type, ::ClassDef{class_ident,class_pos,class_args,class_context},
	::TypeVar, ::ParsedTypeDef, ::TypeDef{td_pos},
	::GenericDef{gen_ident,gen_pos,gen_type,gen_vars},
	::GenericCaseDef{gc_type,gc_pos,gc_gcf}, ::GenericCaseFunctions(GCF), ::GCF,
	::FunKind(FK_Macro),
	::Rhs, ::ParsedExpr
from scanner import ::Priority(..), ::Assoc(..)
from parse import wantModule

:: CLI = { help    :: Bool
         , version :: Bool
         , root    :: String
         , libs    :: [String]
         , exclude :: [String]
         }

instance zero CLI where
	zero = { version = False
	       , help    = False
	       , root    = "/opt/clean/lib/"
	       , libs    = [ "StdEnv"
	                   , "StdLib"
	                   , "ArgEnv"
	                   , "Directory"
	                   , "Dynamics"
	                   , "Gast"
	                   , "Generics"
	                   , "MersenneTwister"
	                   , "TCPIP"
	                   , "clean-platform/OS-Independent"
	                   , "clean-platform/OS-Linux"
	                   , "clean-platform/OS-Linux-32"
	                   , "clean-platform/OS-Linux-64"
	                   , "clean-platform/OS-Mac"
	                   , "clean-platform/OS-Posix"
	                   , "clean-platform/OS-Windows"
	                   , "clean-platform/OS-Windows-32"
	                   , "clean-platform/OS-Windows-64"
	                   , "iTasks-SDK/Dependencies/graph_copy"
	                   , "iTasks-SDK/Dependencies/clean-sapl/src"
	                   , "iTasks-SDK/Server"
	                   , "iTasks-SDK/Tests"
	                   , "SoccerFun/Game"
	                   , "SoccerFun/Gui"
	                   , "SoccerFun/StdLibExt"
	                   , "SoccerFun/StdReferee"
	                   , "SoccerFun/StdTeam"
	                   ]
	       , exclude = [ "StdEnv/_startup"
	                   , "StdEnv/_system"
	                   , "clean-platform/OS-Independent/Deprecated"
	                   , "iTasks-SDK/Server/lib"
	                   , "SoccerFun/StdReferee/RefereeCoach_"
	                   , "SoccerFun/StdTeam/Team_"
	                   ]
	       }


VERSION :== "Cloogle's builddb version 0.1\n"
USAGE :== concat [
	VERSION, "\n",
	"Usage: ./builddb [opts] > types.json\n\n",
	"\t-h, --help Show this help\n",
	"\t-r PATH    Change the library root to PATH\n",
	"\t-l PATH    Add PATH to the librarypaths relative to the root\n"]

Start w
# (args, w) = getCommandLine w
# (f, w) = stdio w
# (ok, w) = case parseCLI (tl args) of
	(Left e) = fclose (f <<< e) w
	(Right cli)
	| cli.help    = fclose (f <<< USAGE) w
	| cli.version = fclose (f <<< VERSION) w
	# (modss, w)  = mapSt (\l -> findModules cli.exclude cli.root l "") cli.libs w
	# mods        = flatten modss
	# (st, w)     = init_identifiers newHeap w
	# cache       = empty_cache st
	# (db, w)     = loop cli.root mods 'DB'.newDb cache w
	# db          = 'DB'.putFunctions predefFunctions db
	# db          = 'DB'.putTypes predefTypes db
	# f           = 'DB'.saveDb db f
	= fclose f w
| not ok = abort "Couldn't close stdio"
= w
where
	loop :: String [(String,String)] 'DB'.TypeDB *DclCache *World -> *('DB'.TypeDB, *World)
	loop _ [] db _ w = (db,w)
	loop root [(lib,mod):list] db cache w
	# (db, cache, w) = getModuleTypes root mod lib cache db w
	# w = snd (fclose (stderr <<< lib <<< ": " <<< mod <<< "\n") w)
	= loop root list db cache w

	parseCLI :: [String] -> Either String CLI
	parseCLI [] = Right zero
	parseCLI [x:a] = case (x,a) of
		("--help", xs) = (\c->{c & help=True}) <$> parseCLI xs
		("--version", xs) = (\c->{c & version=True}) <$> parseCLI xs
		("-l", []) = Left "'-l' requires an argument"
		("-r", []) = Left "'-r' requires an argument"
		("-r", [x:xs]) = (\c->{c & root=x}) <$> parseCLI xs
		("-l", [x:xs]) = (\c->{c & libs=[x:c.libs]}) <$> parseCLI xs
		(x, _) = Left $ "Unknown option '" +++ x +++ "'"

predefFunctions :: [('DB'.Location, 'DB'.ExtendedType)]
predefFunctions
	= [ ( 'DB'.Builtin "if"
	    , 'DB'.ET ('T'.Func ['T'.Type "Bool" [], 'T'.Var "a", 'T'.Var "a"] ('T'.Var "a") []) zero
	    )
	  ]

predefTypes :: [('DB'.Location, 'T'.TypeDef)]
predefTypes
	= [ ( 'DB'.Builtin "Bool"
	    , { deft
	      & 'Type'.td_name = "Bool"
	      , 'Type'.td_rhs  = 'T'.TDRCons False
	        [ { defc & 'Type'.cons_name="False" }
	        , { defc & 'Type'.cons_name="True" }
	        ]
	      }
	    )
	  , ( 'DB'.Builtin "Int",     { deft & 'Type'.td_name = "Int"     } )
	  , ( 'DB'.Builtin "Real",    { deft & 'Type'.td_name = "Real"    } )
	  , ( 'DB'.Builtin "Char",    { deft & 'Type'.td_name = "Char"    } )
	  , ( 'DB'.Builtin "String",  { deft & 'Type'.td_name = "String",
	      'Type'.td_rhs = 'T'.TDRSynonym ('T'.Type "_#Array" ['T'.Type "Char" []]) } )
	  , ( 'DB'.Builtin "Dynamic", { deft & 'Type'.td_name = "Dynamic" } )
	  , ( 'DB'.Builtin "File",    { deft & 'Type'.td_name = "File"    } )
	  , ( 'DB'.Builtin "World",   { deft & 'Type'.td_name = "World",
	                                       'Type'.td_uniq = True      } )
	  ]
where
	deft = {'Type'.td_name="", 'Type'.td_uniq=False, 'Type'.td_args=[], 'Type'.td_rhs='T'.TDRAbstract}
	defc = {'Type'.cons_name="", 'Type'.cons_args=[], 'Type'.cons_exi_vars=[], 'Type'.cons_context=[], 'Type'.cons_priority=Nothing}

//             Exclude   Root    Library Base module            Library Module
findModules :: ![String] !String !String !String !*World -> *(![(String,String)], !*World)
findModules ex root lib base w
| any (\e -> indexOf e path <> -1) ex = ([], w)
#! (fps, w)   = readDirectory path w
| isError fps = ([], w)
#! fps        = fromOk fps
#! mods       = map (\s -> (lib, basedot +++ s % (0, size s - 5))) $ filter included $ filter isDclModule fps
#! (moremodss,w) = mapSt (\d -> findModules ex root lib (basedot +++ d)) (filter isDirectory fps) w
= (removeDup (mods ++ flatten moremodss), w)
where
	path = root +++ "/" +++ lib +++ if (base == "") "" "/" +++ replaceSubString "." "/" base
	basedot = if (base == "") "" (base +++ ".")

	included :: String -> Bool
	included s = not (any (\e -> indexOf e (path +++ "/" +++ s) <> -1) ex)

	isDclModule :: String -> Bool
	isDclModule s = s % (size s - 4, size s - 1) == ".dcl"

	isDirectory :: String -> Bool
	isDirectory s = not $ isMember '.' $ fromString s

getModuleTypes :: String String String *DclCache 'DB'.TypeDB *World -> *('DB'.TypeDB, *DclCache, *World)
getModuleTypes root mod lib cache db w
# filename = root +++ "/" +++ lib +++ "/" +++ mkdir mod +++ ".dcl"
# (ok,f,w) = fopen filename FReadText w
| not ok = abort ("Couldn't open file " +++ filename +++ ".\n")
# (mod_id, ht) = putIdentInHashTable mod (IC_Module NoQualifiedIdents) cache.hash_table
  cache = {cache & hash_table=ht}
# ((b1,b2,pm,ht,f),w) = accFiles (wantModule` f "" False mod_id.boxed_ident NoPos True cache.hash_table stderr) w
  cache = {cache & hash_table=ht}
# (ok,w) = fclose f w
| not ok = abort ("Couldn't close file " +++ filename +++ ".\n")
# mod = pm.mod_ident.id_name
# lib = cleanlib mod lib
# db = 'DB'.putFunctions (pd_typespecs lib mod pm.mod_defs) db
# db = 'DB'.putInstancess (pd_instances lib mod pm.mod_defs) db
# db = 'DB'.putClasses (pd_classes lib mod pm.mod_defs) db
# typedefs = pd_types lib mod pm.mod_defs
# db = 'DB'.putTypes typedefs db
# db = 'DB'.putFunctions (flatten $ map constructor_functions typedefs) db
# db = 'DB'.putFunctions (flatten $ map record_functions typedefs) db
# db = 'DB'.putFunctions (pd_generics lib mod pm.mod_defs) db
# db = 'DB'.putDerivationss (pd_derivations lib mod pm.mod_defs) db
# db = 'DB'.putMacros (pd_macros lib mod pm.mod_defs) db
= (db,cache,w)
where
	mkdir :: String -> String
	mkdir s = { if (c == '.') '/' c \\ c <-: s }

	cleanlib :: !String !String -> String // Remove module dirs from lib
	cleanlib mod lib = toString $ cl` (fromString $ mkdir mod) (fromString lib)
	where
		cl` :: ![Char] ![Char] -> [Char]
		cl` mod lib
			| not (isMember '/' mod) = lib
			# mod = reverse $ tl $ dropWhile ((<>)'/') $ reverse mod
			| drop (length lib - length mod) lib == mod
				= take (length lib - length mod - 1) lib
			= lib

	pd_macros :: String String [ParsedDefinition] -> [('DB'.Location, 'DB'.Macro)]
	pd_macros lib mod pds
		= [( 'DB'.Location lib mod (toLine pos) id.id_name
		   , { macro_as_string = priostring id +++ cpp pd
		     , macro_extras = {zero & te_priority = findPrio id >>= 'T'.toMaybePriority}
		     }
		   ) \\ pd=:(PD_Function pos id isinfix args rhs FK_Macro) <- pds]
	where
		priostring :: Ident -> String
		priostring id = case findTypeSpec id pds of
			Nothing    = ""
			(Just pri) = cpp pri +++ "\n"

		findPrio :: Ident -> Maybe Priority
		findPrio id = (\(PD_TypeSpec _ _ p _ _) -> p) <$> findTypeSpec id pds

		findTypeSpec :: Ident [ParsedDefinition] -> Maybe ParsedDefinition
		findTypeSpec _  []          = Nothing
		findTypeSpec id [pd=:(PD_TypeSpec _ id` prio _ _):pds]
		| id`.id_name == id.id_name = Just pd
		findTypeSpec id [_:pds]     = findTypeSpec id pds

	pd_derivations :: String String [ParsedDefinition]
		-> [('DB'.Name, [('DB'.Type, 'DB'.Location)])]
	pd_derivations lib mod pds
		= [( id.id_name
		   , [('T'.toType gc_type, 'DB'.Location lib mod (toLine gc_pos) "")]
		   ) \\ PD_Derive gcdefs <- pds, {gc_type,gc_pos,gc_gcf=GCF id _} <- gcdefs]

	pd_generics :: String String [ParsedDefinition]
		-> [('DB'.Location, 'DB'.ExtendedType)]
	pd_generics lib mod pds
		= [( 'DB'.Location lib mod (toLine gen_pos) id_name
		   , 'DB'.ET ('T'.toType gen_type)
		       {zero & te_generic_vars=Just $ map 'T'.toTypeVar gen_vars
		             , te_representation=Just $ cpp gen}
		   ) \\ gen=:(PD_Generic {gen_ident={id_name},gen_pos,gen_type,gen_vars}) <- pds]

	pd_typespecs :: String String [ParsedDefinition]
		-> [('DB'.Location, 'DB'.ExtendedType)]
	pd_typespecs lib mod pds
		= [( 'DB'.Location lib mod (toLine pos) id_name
		   , 'DB'.ET ('T'.toType t)
		       {zero & te_priority='T'.toMaybePriority p, te_representation=Just $ cpp ts}
		   ) \\ ts=:(PD_TypeSpec pos id=:{id_name} p (Yes t) funspecs) <- pds]

	pd_instances :: String String [ParsedDefinition]
		-> [('DB'.Class, [('DB'.Type, 'DB'.Location)])]
	pd_instances lib mod pds
		= [( pi_ident.id_name
		   , [('T'.toType t, 'DB'.Location lib mod (toLine pi_pos) "") \\ t <- pi_types]
		   ) \\ PD_Instance {pim_pi={pi_ident,pi_types,pi_pos}} <- pds]

	pd_classes :: String String [ParsedDefinition]
		-> [('DB'.Location, ['T'.TypeVar], 'T'.ClassContext,
			[('DB'.Name, 'DB'.ExtendedType)])]
	pd_classes lib mod pds
	# pds = filter (\pd->case pd of (PD_Class _ _)=True; _=False) pds
	= map (\(PD_Class {class_ident={id_name},class_pos,class_args,class_context} pds)
		-> let typespecs = pd_typespecs lib mod pds
		in ('DB'.Location lib mod (toLine class_pos) id_name, map 'T'.toTypeVar class_args,
		    flatten $ map 'T'.toClassContext class_context,
		    [(f,et) \\ ('DB'.Location _ _ _ f, et) <- typespecs])) pds

	pd_types :: String String [ParsedDefinition]
		-> [('DB'.Location, 'DB'.TypeDef)]
	pd_types lib mod pds
		= [('DB'.Location lib mod (toLine ptd.td_pos) ('T'.td_name td), td)
		   \\ PD_Type ptd <- pds, td <- ['T'.toTypeDef ptd]]

	constructor_functions :: ('DB'.Location, 'DB'.TypeDef)
		-> [('DB'.Location, 'DB'.ExtendedType)]
	constructor_functions ('DB'.Location lib mod line _, td)
		= [('DB'.Location lib mod line c, 'DB'.ET f
			{zero & te_isconstructor=True
			      , te_representation=Just $ concat $
				      [c] ++ print_prio p ++ [" :: "] ++ print False f//[c, " :: " : print False f]
			      , te_priority=p})
		   \\ (c,f,p) <- 'T'.constructorsToFunctions td]
	where
		print_prio :: (Maybe 'T'.Priority) -> [String]
		print_prio Nothing  = []
		print_prio (Just p) = [" "] ++ print False p

	record_functions :: ('DB'.Location, 'DB'.TypeDef)
		-> [('DB'.Location, 'DB'.ExtendedType)]
	record_functions ('DB'.Location lib mod line _, td)
		= [('DB'.Location lib mod line f, 'DB'.ET t
			{zero & te_isrecordfield=True
			      , te_representation=Just $ concat $ [".", f, " :: " : print False t]})
			\\ (f,t) <- 'T'.recordsToFunctions td]

	toLine :: Position -> 'DB'.LineNr
	toLine (FunPos _ l _) = Just l
	toLine (LinePos _ l)  = Just l
	toLine _              = Nothing

wantModule` :: !*File !{#Char} !Bool !Ident !Position !Bool !*HashTable !*File !*Files
	-> ((!Bool,!Bool,!ParsedModule, !*HashTable, !*File), !*Files)
wantModule` f s b1 i p b2 ht io fs
# (b1,b2,pm,ht,f,fs) = wantModule f s b1 i p b2 ht io fs
= ((b1,b2,pm,ht,f),fs)
