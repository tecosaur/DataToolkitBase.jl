Identifier(ident::Identifier, params::Dict{String, Any}; replace::Bool=false) =
    Identifier(ident.collection,
               ident.dataset,
               ident.type,
               if replace; params else merge(ident.parameters, params) end)

Identifier(spec::AbstractString) = parse(Identifier, spec)

Identifier(spec::AbstractString, params::Dict{String, Any}) =
    Identifier(Identifier(spec), params)

function Base.string(ident::Identifier)
    string(if !isnothing(ident.collection)
               string(ident.collection, ':')
            else "" end,
           ident.dataset,
           if !isnothing(ident.type)
               "::" * string(ident.type)
           else "" end)
end

function resolve(collection::DataCollection, ident::Identifier; resolvetype::Bool=true)
    collection_mismatch = !isnothing(ident.collection) &&
        if ident.collection isa UUID
            collection.uuid != ident.collection
        else
            collection.name != ident.collection
        end
    if collection_mismatch
        return resolve(getlayer(ident.collection), ident)
    end
    filter_nameid(datasets) =
        if ident.dataset isa UUID
            filter(d -> d.uuid == ident.dataset, datasets)
        else
            filter(d -> d.name == ident.dataset, datasets)
        end
    filter_type(datasets) =
        if isnothing(ident.type)
            datasets
        else
            filter(d -> any(l -> any(t -> t ⊆ ident.type, l.supports),
                                  d.loaders), datasets)
        end
    filter_parameters(datasets) =
        filter(datasets) do d
            all((param, value)::Pair -> d.parameters[param] == value,
                ident.parameters)
        end
    matchingdatasets = collection.datasets |>
        filter_nameid |> filter_type |> filter_parameters
    # TODO non-generic errors
    if length(matchingdatasets) == 0
        throw(error("No datasets from '$(collection.name)' matched the identifier $ident"))
    elseif length(matchingdatasets) > 1
        throw(error("Multiple datasets from '$(collection.name)' matched the identifier $ident"))
    else
        dataset = first(matchingdatasets)
        if !isnothing(ident.type) && resolvetype
            read(dataset, convert(Type, ident.type))
        else
            dataset
        end
    end
end

resolve(ident::Identifier; resolvetype::Bool=true) =
    resolve(getlayer(ident.collection), ident; resolvetype)
