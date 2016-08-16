module builddb

// Project libraries
import qualified TypeDB as DB
from TypeDB import ::TypeExtras{..}, instance zero TypeExtras, ::Macro{..}

// StdEnv
import StdFile, StdList, StdMisc, StdArray, StdBool, StdString, StdTuple

// CleanPlatform
import Data.Maybe, Data.Either, Data.Error, Data.Func, Data.Tuple, Data.Functor
from Text import class Text(concat), instance Text String
import System.Directory, System.CommandLine

// CleanTypeUnifier
import qualified Type as T
from Type import class print(print), instance print [a], instance print String
import CoclUtils

// CleanPrettyPrint
import CleanPrettyPrint

// frontend
//import Heap, compile, parse, predef
import Heap
from hashtable import ::HashTable, ::QualifiedIdents(NoQualifiedIdents),
	::IdentClass(IC_Module), ::BoxedIdent{..}, putIdentInHashTable
from predef import init_identifiers
from compile import empty_cache, ::DclCache{hash_table}
from general import ::Optional(..)
from syntax import ::SymbolTable, ::SymbolTableEntry, ::Ident{..}, ::SymbolPtr,
	::Position(NoPos), ::Module{mod_ident,mod_defs},
	::ParsedDefinition(PD_TypeSpec,PD_Instance,PD_Class,PD_Type,PD_Generic,PD_Derive,PD_Function),
	::FunSpecials, ::Priority, ::ParsedModule, ::SymbolType,
	::ParsedInstanceAndMembers{..}, ::ParsedInstance{pi_ident,pi_types},
	::Type, ::ClassDef{class_ident,class_args,class_context},
	::TypeVar, ::ParsedTypeDef, ::TypeDef,
	::GenericDef{gen_ident,gen_type,gen_vars},
	::GenericCaseDef{gc_type,gc_gcf}, ::GenericCaseFunctions(GCF), ::GCF,
	::FunKind(FK_Macro),
	::Rhs, ::ParsedExpr
from scanner import ::Priority(..), ::Assoc(..)
from parse import wantModule

:: CLI = { help :: Bool
         , version :: Bool
         , root :: String
         , libs :: [String]
         }

instance zero CLI where
	zero = { version = False
	       , help = False
	       , root = "/opt/clean/lib/"
	       , libs = [ "StdEnv"
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
	| cli.help = fclose (f <<< USAGE) w
	| cli.version = fclose (f <<< VERSION) w
	# (mods, w) = findModules` cli.libs cli.root w
	# (st, w) = init_identifiers newHeap w
	# cache = empty_cache st
	# (db, w) = loop cli.root mods 'DB'.newDb cache w
	# f = 'DB'.saveDb db f
	= fclose f w
| not ok = abort "Couldn't close stdio"
= w
where
	loop :: String [(String,String)] 'DB'.TypeDB *DclCache *World -> *('DB'.TypeDB, *World)
	loop _ [] db _ w = (db,w)
	loop root [(lib,mod):list] db cache w
	# (db, cache, w) = getModuleTypes root mod lib cache db w
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

//              Libraries                Library Module
findModules` :: ![String] !String !*World -> *(![(String,String)], !*World)
findModules` [] _ w = ([], w)
findModules` [lib:libs] root w
#! (mods, w) = findModules lib root w
#! (moremods, w) = findModules` libs root w
= (removeDup (mods ++ moremods), w)

findModules :: !String !String !*World -> *(![(String,String)], !*World)
findModules lib root w
#! (fps, w) = readDirectory (root +++ "/" +++ lib) w
| isError fps = ([], w)
#! fps = fromOk fps
#! mods = map (\s->(lib, s%(0,size s-5))) $ filter isDclModule fps
#! (moremods, w) = findModules` (map ((+++) (lib+++"/")) (filter isDirectory fps)) root w
= (removeDup (mods ++ moremods), w)
where
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
# db = 'DB'.putInstancess (pd_instances pm.mod_defs) db
# db = 'DB'.putClasses (pd_classes lib mod pm.mod_defs) db
# typedefs = pd_types lib mod pm.mod_defs
# db = 'DB'.putTypes typedefs db
# db = 'DB'.putFunctions (flatten $ map constructor_functions typedefs) db
# db = 'DB'.putFunctions (pd_generics lib mod pm.mod_defs) db
# db = 'DB'.putDerivationss (pd_derivations pm.mod_defs) db
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

	pd_macros :: String String [ParsedDefinition] -> [('DB'.MacroLocation, 'DB'.Macro)]
	pd_macros lib mod pds
		= [( 'DB'.ML lib mod id.id_name
		   , { macro_rhs = cpp rhs
		     , macro_extras = zero
		     }
		   ) \\ PD_Function _ id isinfix args rhs FK_Macro <- pds]

	pd_derivations :: [ParsedDefinition] -> [('DB'.GenericName, ['DB'.Type])]
	pd_derivations pds
		= [(id.id_name, ['T'.toType gc_type])
		   \\ PD_Derive gcdefs <- pds, {gc_type,gc_gcf=GCF id _} <- gcdefs]

	pd_generics :: String String [ParsedDefinition]
		-> [('DB'.FunctionLocation, 'DB'.ExtendedType)]
	pd_generics lib mod pds
		= [( 'DB'.FL lib mod id_name
		   , 'DB'.ET ('T'.toType gen_type) {zero & te_generic_vars=Just $ map 'T'.toTypeVar gen_vars}
		   ) \\ PD_Generic {gen_ident={id_name},gen_type,gen_vars} <- pds]

	pd_typespecs :: String String [ParsedDefinition]
		-> [('DB'.FunctionLocation, 'DB'.ExtendedType)]
	pd_typespecs lib mod pds
		= [( 'DB'.FL lib mod id_name
		   , 'DB'.ET ('T'.toType t) {zero & te_priority=toPrio p}
		   ) \\ PD_TypeSpec pos id=:{id_name} p (Yes t) funspecs <- pds]
	where
		toPrio :: Priority -> Maybe 'DB'.TE_Priority
		toPrio (Prio LeftAssoc i)  = Just $ 'DB'.LeftAssoc i
		toPrio (Prio RightAssoc i) = Just $ 'DB'.RightAssoc i
		toPrio (Prio NoAssoc i)    = Just $ 'DB'.NoAssoc i
		toPrio _                   = Nothing

	pd_instances :: [ParsedDefinition] -> [('DB'.Class, ['DB'.Type])]
	pd_instances pds
		= [(pi_ident.id_name, map 'T'.toType pi_types)
		   \\ PD_Instance {pim_pi={pi_ident,pi_types}} <- pds]

	pd_classes :: String String [ParsedDefinition]
		-> [('DB'.ClassLocation, ['T'.TypeVar], 'T'.ClassContext,
			[('DB'.FunctionName, 'DB'.ExtendedType)])]
	pd_classes lib mod pds
	# pds = filter (\pd->case pd of (PD_Class _ _)=True; _=False) pds
	= map (\(PD_Class {class_ident={id_name},class_args,class_context} pds)
		-> let typespecs = pd_typespecs lib mod pds
		in ('DB'.CL lib mod id_name, map 'T'.toTypeVar class_args, 
		    flatten $ map 'T'.toClassContext class_context,
			[(f,et) \\ ('DB'.FL _ _ f, et) <- typespecs])) pds

	pd_types :: String String [ParsedDefinition]
		-> [('DB'.TypeLocation, 'DB'.TypeDef)]
	pd_types lib mod pds
		= [('DB'.TL lib mod ('T'.td_name td), td)
		   \\ PD_Type ptd <- pds, td <- ['T'.toTypeDef ptd]]

	constructor_functions :: ('DB'.TypeLocation, 'DB'.TypeDef)
		-> [('DB'.FunctionLocation, 'DB'.ExtendedType)]
	constructor_functions ('DB'.TL lib mod _, td)
		= [('DB'.FL lib mod c, 'DB'.ET f {zero & te_isconstructor=True})
		   \\ (c,f) <- 'T'.constructorsToFunctions td]

wantModule` :: !*File !{#Char} !Bool !Ident !Position !Bool !*HashTable !*File !*Files
	-> ((!Bool,!Bool,!ParsedModule, !*HashTable, !*File), !*Files)
wantModule` f s b1 i p b2 ht io fs
# (b1,b2,pm,ht,f,fs) = wantModule f s b1 i p b2 ht io fs
= ((b1,b2,pm,ht,f),fs)
