# ---------------
# QualifiedType
# ---------------

function Base.parse(::Type{QualifiedType}, spec::AbstractString)
    if haskey(QUALIFIED_TYPE_SHORTHANDS.forward, spec)
        return QUALIFIED_TYPE_SHORTHANDS.forward[spec]
    end
    components, parameters = let cbsplit = split(spec, '{', limit=2)
        if length(cbsplit) == 1
            split(cbsplit[1], '.'), Tuple{}()
        else
            split(cbsplit[1], '.'),
            let typeparams = Meta.parse(spec[1+length(cbsplit[1]):end])
                destruct(param) = if param isa Number
                    param
                elseif param isa QuoteNode
                    param.value
                elseif param isa Expr && param.head == :tuple
                    Tuple(destruct.(param.args))
                elseif param isa Symbol
                    if haskey(QUALIFIED_TYPE_SHORTHANDS.forward, string(param))
                        QUALIFIED_TYPE_SHORTHANDS.forward[string(param)]
                    else
                        QualifiedType(Symbol(Base.binding_module(Main, param)),
                                      param, Tuple{}())
                    end
                elseif param isa Expr && param.head == :.
                    parse(QualifiedType, string(param))
                elseif param isa Expr && param.head == :<: && last(param.args) isa Symbol
                    TypeVar(if length(param.args) == 2
                                first(param.args)
                            else :T end,
                            getfield(Main, last(param.args)))
                else
                    throw(ArgumentError("Invalid QualifiedType parameter $(sprint(show, param)) in $(sprint(show, spec))"))
                end
                Tuple(destruct.(typeparams.args))
            end
        end
    end
    parentmodule, name = if length(components) == 1
        n = Symbol(components[1])
        Symbol(Base.binding_module(Main, n)), n
    elseif length(components) == 2
        Symbol.(components)
    else
        Symbol.(components[end-1:end])
    end
    QualifiedType(parentmodule, name, parameters)
end

# ---------------
# Identifier
# ---------------

function Base.parse(::Type{Identifier}, spec::AbstractString; advised::Bool=false)
    collection, rest::SubString{String} = match(r"^(?:([^:]+):)?([^:].*)?$", spec).captures
    collection_isuuid = !isnothing(collection) && !isnothing(match(r"^[0-9a-f]{8}-[0-9a-f]{4}$", collection))
    if !isnothing(collection) && !advised
        @advise getlayer(collection) parse(Identifier, spec, advised=true)
    end
    dataset, rest = match(r"^([^:]+)(.*)$", rest).captures
    dtype = match(r"^(?:::([A-Za-z0-9{, }\.]+)|::)?$", rest).captures[1]
    Identifier(if collection_isuuid; UUID(collection) else collection end,
               something(tryparse(UUID, dataset), dataset),
               if !isnothing(dtype) parse(QualifiedType, dtype) end,
               Dict{String,Any}())
end

# ---------------
# DataTransformers
# ---------------

"""
    supportedtypes(ADT::Type{<:AbstractDataTransformer})::Vector{QualifiedType}

Return a list of types supported by the data transformer `ADT`.

This is used as the default value for the `type` key in the Data TOML.
The list of types is dynamically generated based on the availible methods for
the data transformer.

In some cases, it makes sense for this to be explicitly defined for a particular
transformer. """
function supportedtypes end # See `interaction/externals.jl` for method definitions.

supportedtypes(ADT::Type{<:AbstractDataTransformer}, spec::Dict{String, Any}, _::DataSet) =
    supportedtypes(ADT, spec)

supportedtypes(ADT::Type{<:AbstractDataTransformer}, _::Dict{String, Any}) =
    supportedtypes(ADT)

(ADT::Type{<:AbstractDataTransformer})(dataset::DataSet, spec::Dict{String, Any}) =
    @advise fromspec(ADT, dataset, spec)

(ADT::Type{<:AbstractDataTransformer})(dataset::DataSet, spec::String) =
    ADT(dataset, Dict{String, Any}("driver" => spec))

function fromspec(ADT::Type{<:AbstractDataTransformer}, dataset::DataSet, spec::Dict{String, Any})
    driver = if ADT isa DataType
        first(ADT.parameters)
    elseif haskey(spec, "driver")
        Symbol(lowercase(spec["driver"]))
    else
        @warn "$ADT for $(sprint(show, dataset.name)) has no driver!"
        :MISSING
    end
    if !(ADT isa DataType)
        ADT = ADT{driver}
    end
    ttype = let spec_type = get(spec, "type", nothing)
        if isnothing(spec_type)
            supportedtypes(ADT, spec, dataset)
        elseif spec_type isa Vector
            parse.(QualifiedType, spec_type)
        elseif spec_type isa String
            [parse(QualifiedType, spec_type)]
        else
            @warn "Invalid ADT type '$spec_type', ignoring"
        end
    end
    if isempty(ttype)
        @warn """Could not find any types that $ADT of $(sprint(show, dataset.name)) supports.
                 Consider adding a 'type' parameter."""
    end
    priority = get(spec, "priority", DEFAULT_DATATRANSFORMER_PRIORITY)
    parameters = copy(spec)
    delete!(parameters, "driver")
    delete!(parameters, "type")
    delete!(parameters, "priority")
    @advise dataset identity(
        ADT(dataset, ttype, priority,
            dataset_parameters(dataset, Val(:extract), parameters)))
end

# function (ADT::Type{<:AbstractDataTransformer})(collection::DataCollection, spec::Dict{String, Any})
#     @advise fromspec(ADT, collection, spec)
# end

DataStorage{driver}(dataset::Union{DataSet, DataCollection},
                    type::Vector{<:QualifiedType}, priority::Int,
                    parameters::Dict{String, Any}) where {driver} =
                        DataStorage{driver, typeof(dataset)}(dataset, type, priority, parameters)

# ---------------
# DataCollection
# ---------------

DataCollection(name::Union{String, Nothing}=nothing; path::Union{String, Nothing}=nothing) =
    DataCollection(LATEST_DATA_CONFIG_VERSION, name, uuid4(), String[],
                   Dict{String, Any}(), DataSet[], path,
                   DataAdviceAmalgamation(String[]), Main)

function DataCollection(spec::Dict{String, Any}; path::Union{String, Nothing}=nothing, mod::Module=Base.Main)
    plugins::Vector{String} = get(get(spec, "config", Dict("config" => Dict())), "plugins", String[])
    DataAdviceAmalgamation(plugins)(fromspec, DataCollection, spec; path, mod)
end

function fromspec(::Type{DataCollection}, spec::Dict{String, Any};
                  path::Union{String, Nothing}=nothing, mod::Module=Base.Main)
    version = get(spec, "data_config_version", LATEST_DATA_CONFIG_VERSION)
    if version != LATEST_DATA_CONFIG_VERSION
        # NOTE this cannot be a multi-line string with trailing \ lines, as
        # that is not supported in Julia 1.6.
        @error string("The data collection specificaton uses the v$version format ",
                      "when the v$LATEST_DATA_CONFIG_VERSION format is expected.\n",
                      "In the future conversion facilities may be implemented,\n",
                      "but for now you'll need to manually upgrade the format.")
        error("Version mismatch")
    end
    name = @something(get(spec, "name", nothing),
                      if !isnothing(path)
                          toml_name = path |> basename |> splitext |> first
                          if toml_name != "Data"
                              toml_name
                          else
                              basename(dirname(path))
                          end
                      end,
                      string(gensym("unnamed"))[3:end])
    uuid = UUID(@something get(spec, "uuid", nothing) begin
                    @info "Data collection '$(something(name, "<unnamed>"))' had no UUID, one has been generated."
                    uuid4()
                end)
    plugins::Vector{String} = get(spec, "plugins", String[])
    parameters = get(spec, "config", Dict{String, Any}())
    stores = get(parameters, "store", Dict{String, Any}())
    for reserved in ("store")
        delete!(parameters, reserved)
    end
    unavailible_plugins = setdiff(plugins, getproperty.(PLUGINS, :name))
    if length(unavailible_plugins) > 0
        @warn string("The ", join(unavailible_plugins, ", ", ", and "),
                     " plugin", if length(unavailible_plugins) == 1
                         " is" else "s are" end,
                     " not availible at the time of loading '$name'.",
                     "\n It is highly recommended that all plugins are loaded",
                     " prior to DataCollections.")
    end
    collection = DataCollection(version, name, uuid, plugins,
                                parameters, DataSet[], path,
                                DataAdviceAmalgamation(plugins),
                                mod)
    # Construct the data sets
    datasets = copy(spec)
    for reservedname in DATA_CONFIG_RESERVED_ATTRIBUTES[:collection]
        delete!(datasets, reservedname)
    end
    for (name, dspecs) in datasets
        for dspec in if dspecs isa Vector dspecs else [dspecs] end
            push!(collection.datasets, DataSet(collection, name, dspec))
        end
    end
    @advise identity(collection)
end

# ---------------
# DataSet
# ---------------

function DataSet(collection::DataCollection, name::String, spec::Dict{String, Any})
    @advise fromspec(DataSet, collection, name, spec)
end

function fromspec(::Type{DataSet}, collection::DataCollection, name::String, spec::Dict{String, Any})
    uuid = UUID(@something get(spec, "uuid", nothing) begin
                    @info "Data set '$name' had no UUID, one has been generated."
                    uuid4()
                end)
    store = get(spec, "store", "DEFAULTSTORE")
    parameters = copy(spec)
    for reservedname in DATA_CONFIG_RESERVED_ATTRIBUTES[:dataset]
        delete!(parameters, reservedname)
    end
    dataset = DataSet(collection, name, uuid,
                      dataset_parameters(collection, Val(:extract), parameters),
                      DataStorage[], DataLoader[], DataWriter[])
    for (attr, afield, atype) in [("storage", :storage, DataStorage),
                                  ("loader", :loaders, DataLoader),
                                  ("writer", :writers, DataWriter)]
        specs = get(spec, attr, Dict{String, Any}[]) |>
            s -> if s isa Vector s else [s] end
        for aspec::Union{String, Dict{String, Any}} in specs
            push!(getfield(dataset, afield), atype(dataset, aspec))
        end
        sort!(getfield(dataset, afield), by=a->a.priority)
    end
    @advise identity(dataset)
end
