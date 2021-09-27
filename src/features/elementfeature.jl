using ..ChemistryFeaturization.Utils.ElementFeatureUtils
using DataFrames
using ..ChemistryFeaturization: elements
using ..ChemistryFeaturization.AbstractType: AbstractCodec, AbstractAtoms
using ..ChemistryFeaturization.Codec: OneHotOneCold

include("abstractfeatures.jl")

# TODO - consider edge cases in constructor. add this stuff into modulify.

# TODO: figure out what scheme would look like that is flexible to direct-value encoding (may just need a different feature type since it'll have to handle normalization, etc. too)
"""
    ElementFeatureDescriptor

Describe features associated with individual atoms that depend only upon their elemental identity

## Fields
- `name::String`: Name of the feature
- `encoder_decoder::AbstractCodec`: Codec defined which handles the feature's encoding and decoding logic
- `categorical::Bool`: flag for whether the feature is categorical or continuous-valued
- `lookup_table::DataFrame`: table containing values of feature for every encodable element
"""
struct ElementFeatureDescriptor <: AbstractAtomFeatureDescriptor
    name::String
    encoder_decoder::AbstractCodec
    categorical::Bool
    lookup_table::DataFrame
end

function ElementFeatureDescriptor(feature_name::String, encoder_decoder::AbstractCodec)
    lookup_table = atom_data_df

    colnames = names(lookup_table)
    @assert feature_name in colnames && "Symbol" in colnames "Your lookup table must have a column called :Symbol and one with the same name as your feature to be usable!"

    lookup_table = lookup_table[:, ["Symbol", feature_name]]
    dropmissing!(lookup_table)

    ElementFeatureDescriptor(
        feature_name,
        encoder_decoder,
        default_categorical(feature_name, lookup_table),
        lookup_table,
    )
end

"""
    ElementFeatureDescriptor(feature_name, lookup_table, categorical, contextual, length, encodable_elements)

Construct a feature object that encodes features associated with individual atoms that depend only upon their elemental identity.
If a Codec isn't explicity specified, [OneHotOneCold](@ref) with [default_efd_encode](@ref) and [default_efd_decode](@ref)
as the encoding and decoding functions respectively is the default choice.

## Arguments
- `name::String`: the name of the feature
- `lookup_table::DataFrame`: table containing values of feature for every encodable element
- `nbins::Integer`: Number of bins to use for one-cold decoding of continuous-valued features
- `logspaced::Bool`: whether onehot-style bins should be logarithmically spaced or not
- `categorical::Bool`: flag for whether the feature is categorical or continuous-valued
"""
function ElementFeatureDescriptor(
    feature_name::String,
    lookup_table::DataFrame = atom_data_df;
    nbins::Integer = default_nbins,
    logspaced::Bool = default_log(feature_name, lookup_table),
    categorical::Bool = default_categorical(feature_name, lookup_table),
)
    colnames = names(lookup_table)
    @assert feature_name in colnames && "Symbol" in colnames "Your lookup table must have a column called :Symbol and one with the same name as your feature to be usable!"

    lookup_table = lookup_table[:, ["Symbol", feature_name]]
    dropmissing!(lookup_table)

    bins = get_bins(
        feature_name,
        lookup_table;
        nbins = nbins,
        logspaced = logspaced,
        categorical = categorical,
    )

    ElementFeatureDescriptor(
        feature_name,
        OneHotOneCold(categorical, bins),
        categorical,
        lookup_table,
    )
end

# pretty printing, short version
Base.show(io::IO, efd::ElementFeatureDescriptor) = print(io, "ElementFeature $(efd.name)")

# pretty printing, long version
function Base.show(io::IO, ::MIME"text/plain", efd::ElementFeatureDescriptor)
    st = "ElementFeature $(efd.name):\n   categorical: $(efd.categorical)\n   encoded length: $(output_shape(efd))"
    print(io, st)
end

encodable_elements(efd::ElementFeatureDescriptor) = efd.lookup_table[:, :Symbol]

function encodable_elements(feature_name::String, lookup_table::DataFrame = atom_data_df)
    info = lookup_table[:, [Symbol(feature_name), :Symbol]]
    return info[
        findall(x -> !ismissing(x), getproperty(info, Symbol(feature_name))),
        :Symbol,
    ]
end

function get_value(efd::ElementFeatureDescriptor, a::AbstractAtoms)
    @assert all([el in encodable_elements(efd) for el in elements(a)]) "Feature $(efd.name) cannot encode some element(s) in this structure!"

    colnames = names(efd.lookup_table)
    @assert (efd.name in colnames) && ("Symbol" in colnames) "Your lookup table must have a column called :Symbol and one with the same name as your feature to be usable!"

    feature_vals = efd.lookup_table[:, [:Symbol, Symbol(efd.name)]]
    map(
        el ->
            getproperty(feature_vals[feature_vals.Symbol.==el, :][1, :], Symbol(efd.name)),
        elements(a),
    )
end

"""
    output_shape(efd::ElementFeatureDescriptor)

Get the output-shape for an ElementFeatureDescriptor object using the logic assoicated with its
Codec.
"""
function output_shape(efd::ElementFeatureDescriptor, ed::OneHotOneCold)
    return efd.categorical ? length(unique(efd.lookup_table[:, Symbol(efd.name)])) :
           length(ed.bins) - 1
end
