#=
This module houses the built-in feature values for a variety of non-contextual atom features and also some convenience functions for constructing them easily.
=#
module ElementFeatureUtils

using DataFrames
using ...ChemistryFeaturization.Data: atom_data_df, feature_info

# export things
export default_nbins, oom_threshold_log
export atom_data_df, avail_feature_names
export categorical_feature_names, categorical_feature_vals, continuous_feature_names
export default_log, fea_minmax, default_categorical, default_nbins
export get_bins, get_param_vec

# default number of bins for continuous features, if unspecified
const default_nbins = 10
# if values of a feature span more than this many orders of magnitude, log-space it by default (open to better names for this...)
const oom_threshold_log = 2

# read in features...
const categorical_feature_names = feature_info["categorical"]
const categorical_feature_vals = Dict(
    fea => sort(collect(Set(skipmissing(atom_data_df[:, fea])))) for
    fea in categorical_feature_names
)
# but I want blocks to be in my order
categorical_feature_vals["Block"] = ["s", "p", "d", "f"]
const continuous_feature_names = feature_info["continuous"]
const avail_feature_names =
    cat(categorical_feature_names, continuous_feature_names; dims = 1)

"Compute the minimum and maximum possible values of a feature."
function fea_minmax(feature_name::String, lookup_table::DataFrame = atom_data_df)
    @assert feature_name in names(lookup_table) "Feature $feature_name isn't in the lookup table!"
    return [
        f(skipmissing(lookup_table[:, Symbol(feature_name)])) for f in [minimum, maximum]
    ]
end

"""
    default_log(feature_name, lookup_table = atom_data_df; threshold = oom_threshold_log)

Determine whether a continuous-valued feature should have logarithmically spaced bins. 

Operates by finding the minimum and maximum values the feature can take on and comparing their ratio to a specified order-of-magnitude threshold that defaults to a package constant if not provided.
"""
function default_log(
    feature_name::String,
    lookup_table::DataFrame = atom_data_df;
    threshold::Real = oom_threshold_log,
)
    min_val, max_val = fea_minmax(feature_name, lookup_table)
    local log
    if typeof(min_val) <: Number
        signs = sign.([min_val, max_val])
        same_sign = all(x -> x == signs[1], signs)
        if same_sign
            oom_arg = sign(min_val) < 0 ? min_val / max_val : max_val / min_val
            oom = log10(oom_arg)
            log = oom > threshold
        else
            log = false
        end
    else
        log = false
    end
    return log
end

"""
    default_categorical(feature_name, lookup_table = atom_data_df)

Determine if a feature should be treated as categorical or continuous-valued.

If the value type is not a number, always returns true. If it is, checks whether it is in the built-in list of categorical features.

TODO: possibly add behavior where it will default to categorical if there is below some threshold number of discrete values?
"""
function default_categorical(feature_name::String, lookup_table::DataFrame = atom_data_df)
    local categorical
    if feature_name in avail_feature_names
        if feature_name in categorical_feature_names
            categorical = true
        else
            categorical = false
        end
    else
        feature_type = eltype(skipmissing(lookup_table[:, Symbol(feature_name)]))
        if feature_type <: Number
            categorical = false
        else
            categorical = true
        end
    end
    return categorical
end

"Little helper function to check that the logspace/categorical vector/boolean is appropriate and convert it to a vector as needed."
function get_param_vec(vec, num_features::Integer; pad_val = false)
    if !(typeof(vec) <: Vector)
        output_vec = [vec for i = 1:num_features]
    elseif length(vec) == num_features # specified properly
        output_vec = vec
    elseif length(vec) < num_features
        @info "Parameter vector too short. Padding end with $pad_val."
        output_vec = vcat(vec, [pad_val for i = 1:num_features-size(vec, 1)])
    elseif size(vec, 1) > num_features
        @info "Parameter vector too long. Cutting off at appropriate length."
        output_vec = vec[1:num_features]
    end
    return output_vec
end

"Helper function for encoder and decoder...(nbins is ignored for categorical=true)"
function get_bins(
    feature_name::String,
    lookup_table::DataFrame = atom_data_df;
    nbins::Integer = default_nbins,
    logspaced::Bool = default_log(feature_name, lookup_table),
    categorical::Bool = default_categorical(feature_name, lookup_table),
)
    colnames = names(lookup_table)
    @assert feature_name in colnames && "Symbol" in colnames "Your lookup table must have a column called :Symbol and one with the same name as your feature ($(feature_name)) to be usable!"
    local bins, min_val, max_val

    if categorical
        if feature_name in categorical_feature_names
            bins = categorical_feature_vals[feature_name]
        else
            bins = sort(unique(skipmissing(lookup_table[:, Symbol(feature_name)])))
        end
    else
        min_val, max_val = fea_minmax(feature_name, lookup_table)

        if isapprox(min_val, max_val)
            @warn "It looks like the minimum and maximum possible values of $feature_name are approximately equal. This could cause numerical issues with binning, and also this feature is likely uninformative. Perhaps reconsider if it needs to be included?"
        end

        if logspaced
            @assert all(x -> sign(x) == sign(min_val), [min_val, max_val]) "I don't know how to do a logarithmically spaced feature whose value can be zero! :("
            if sign(min_val) > 0
                bins = 10 .^ range(log10(min_val), log10(max_val), length = nbins + 1)
            else
                bins =
                    -1 .* (
                        10 .^
                        range(log10(abs(min_val)), log10(abs(max_val)), length = nbins + 1)
                    )
            end
        else
            bins = range(min_val, max_val, length = nbins + 1)
        end
    end
    return bins
end

end
