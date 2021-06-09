using ..ChemistryFeaturization.Utils.ElementFeatureUtils
using DataFrames


abstract type EncoderDecoder end

"""
    DummyED(encode_f, decode_f, nbins, logspaced)

EncoderDecoder type which uses a dummy variable (as defined in statistical literature), i.e., which employs
one-hot encoding and a one-cold decoding scheme.
"""
struct DummyED <: EncoderDecoder
    encode_f::Function
    decode_f::Function
    nbins::Integer
    logspaced::Bool
end

@enum EncodeOrDecode ENCODE DECODE

# TODO - consider edge cases in constructor. add this stuff into modulify.

# TODO: figure out what scheme would look like that is flexible to direct-value encoding (may just need a different feature type since it'll have to handle normalization, etc. too)
"""
    ElementFeatureDescriptor(feature_name, encode_f, decode_f, categorical, contextual, length, encodable_elements)

Construct a feature object that encodes features associated with individual atoms that depend only upon their elemental identity (if you want to encode a feature that depends upon an atom's environment, you shold use SpeciesFeatureDescriptor!)

## Arguments
- `name::String`: the name of the feature
- `categorical::Bool`: flag for whether the feature is categorical or continuous-valued
- `length::Int`: length of encoded vector
- `logspaced::Bool`: whether onehot-style bins should be logarithmically spaced or not
- `lookup_table::DataFrame`: table containing values of feature for every encodable element
"""
struct ElementFeatureDescriptor <: AbstractAtomFeatureDescriptor
    name::String
    length::Integer
    encoder_decoder::EncoderDecoder
    categorical::Bool
    lookup_table::DataFrame
end

function ElementFeatureDescriptor(
    feature_name::String,
    lookup_table::DataFrame = atom_data_df;
    nbins::Integer = default_nbins,
    logspaced::Bool = default_log(feature_name, lookup_table),
    categorical::Bool = default_categorical(feature_name, lookup_table),
)
    colnames = names(lookup_table)
    @assert feature_name in colnames && "Symbol" in colnames "Your lookup table must have a column called :Symbol and one with the same name as your feature to be usable!"

    local vector_length
    if categorical
        vector_length = length(unique(skipmissing(lookup_table[:, Symbol(feature_name)])))
    else
        vector_length = nbins
    end

    lookup_table = lookup_table[:, ["Symbol", feature_name]]
    dropmissing!(lookup_table)

    ElementFeatureDescriptor(
        feature_name,
        vector_length,
        DummyED(default_efd_encode, default_efd_decode, nbins, logspaced),
        categorical,
        lookup_table,
    )
end

# pretty printing, short version
Base.show(io::IO, af::ElementFeatureDescriptor) = print(io, "ElementFeature $(af.name)")

# pretty printing, long version
function Base.show(io::IO, ::MIME"text/plain", af::ElementFeatureDescriptor)
    st = "ElementFeature $(af.name):\n   categorical: $(af.categorical)\n   encoded length: $(af.length)"
    print(io, st)
end

encodable_elements(f::ElementFeatureDescriptor) = f.lookup_table[:, :Symbol]

function encodable_elements(feature_name::String, lookup_table::DataFrame = atom_data_df)
    info = lookup_table[:, [Symbol(feature_name), :Symbol]]
    return info[
        findall(x -> !ismissing(x), getproperty(info, Symbol(feature_name))),
        :Symbol,
    ]
end

function (f::ElementFeatureDescriptor)(a::AbstractAtoms)
    @assert all([el in encodable_elements(f) for el in a.elements]) "Feature $(f.name) cannot encode some element(s) in this structure!"
    f.encoder_decoder(f, a, ENCODE)
end


function (ed::DummyED)(e::ElementFeatureDescriptor, a::AbstractAtoms, e_or_d::EncodeOrDecode)
    if e_or_d == ENCODE
        ed.encode_f(e, a, ed.nbins, ed.logspaced)
    else
        ed.decode(e, a, ed.nbins, ed.logspaced)
    end
end

function (ed::DummyED)(e::ElementFeatureDescriptor, encoded_feature)
    ed.decode_f(e, encoded_feature)
end

decode(f::ElementFeatureDescriptor, encoded_feature) =
    f.encoder_decoder.decode_f(f, encoded_feature)

function default_efd_encode(
    f::ElementFeatureDescriptor,
    a::AbstractAtoms,
    nbins::Integer,
    logspaced::Bool,
)
    reduce(
        hcat,
        map(
            e -> onehot_lookup_encoder(
                e,
                f.name,
                f.lookup_table;
                nbins,
                logspaced,
                categorical = f.categorical,
            ),
            a.elements,
        ),
    )
end

default_efd_decode(e::ElementFeatureDescriptor, encoded_feature) = onecold_decoder(
    encoded_feature,
    e.name,
    e.lookup_table;
    e.encoder_decoder.nbins,
    e.encoder_decoder.logspaced,
    categorical = e.categorical,
)
