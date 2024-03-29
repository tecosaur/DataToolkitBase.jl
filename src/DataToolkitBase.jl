module DataToolkitBase

using UUIDs, TOML, Dates

using PrecompileTools
using Compat

# For general usage
export loadcollection!, dataset

# For extension packages
export AbstractDataTransformer, DataStorage, DataLoader, DataWriter,
    DataSet, DataCollection, QualifiedType, Identifier, FilePath, SmallDict,
    LintItem, LintReport
export load, storage, getstorage, putstorage, save, getlayer, resolve, refine,
    parse_ident, supportedtypes, typeify, create, createpriority, lint
export IdentifierException, UnresolveableIdentifier, AmbiguousIdentifier,
    PackageException, UnregisteredPackage, MissingPackage,
    DataOperationException, CollectionVersionMismatch, EmptyStackError,
    ReadonlyCollection, TransformerError, UnsatisfyableTransformer,
    OrphanDataSet, InvalidParameterType
export STACK, DATA_CONFIG_RESERVED_ATTRIBUTES
export @import, @addpkg, @dataplugin, @advise, @getparam

# For plugin packages
export PLUGINS, PLUGINS_DOCUMENTATION, DEFAULT_PLUGINS, Plugin,
    fromspec, tospec, Advice, AdviceAmalgamation
export ReplCmd, REPL_CMDS, help, completions, allcompletions,
    prompt, prompt_char, confirm_yn, peelword

include("model/types.jl")
include("model/globals.jl")
include("model/utils.jl")
include("model/advice.jl")
include("model/errors.jl")

include("model/smalldict.jl")
include("model/qualifiedtype.jl")
include("model/identification.jl")
include("model/parameters.jl")
include("model/stack.jl")
include("model/parser.jl")
include("model/writer.jl")
include("model/usepkg.jl")
include("model/dataplugin.jl")

include("interaction/externals.jl")
include("interaction/display.jl")
include("interaction/manipulation.jl")
include("interaction/repl.jl")
include("interaction/lint.jl")

include("precompile.jl")

function add_datasets! end # For `ext/AbstractTreesExt.jl`

function __init__()
    isinteractive() && init_repl()
end

end
