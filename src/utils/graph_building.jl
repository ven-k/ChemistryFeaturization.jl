module GraphBuilding

export build_graph
export weights_voronoi, weights_cutoff
export inverse_square, exp_decay

using PyCall
using ChemistryFeaturization
using Serialization
using Xtals
using NearestNeighbors
rc[:paths][:crystals] = @__DIR__ # because Xtals has a silly default thing

# options for decay of bond weights with distance...
# user can of course write their own as well
inverse_square(x) = x^-2.0
exp_decay(x) = exp(-x)

"""
Build graph from a file storing a crystal structure (currently supports anything ase.io.read can read in). Returns an AtomGraph object.

# Arguments
## Required Arguments
- `file_path::String`: Path to ASE-readable file containing a molecule/crystal structure

## Keyword Arguments
- `use_voronoi::bool`: if true, use Voronoi method for neighbor lists, if false use cutoff method

    (The rest of these parameters are only used if `use_voronoi==false`)

- `cutoff_radius::Real=8.0`: cutoff radius for atoms to be considered neighbors (in angstroms)
- `max_num_nbr::Integer=12`: maximum number of neighbors to include (even if more fall within cutoff radius)
- `dist_decay_func::Function=inverse_square`: function to determine falloff of graph edge weights with neighbor distance
"""
function build_graph(
    file_path::String;
    use_voronoi::Bool = false,
    cutoff_radius::Real = 8.0,
    max_num_nbr::Integer = 12,
    dist_decay_func::Function = inverse_square,
)
    c = Crystal(file_path)
    atom_ids = String.(c.atoms.species)

    if use_voronoi
        @info "Note that building neighbor lists and edge weights via the Voronoi method requires the assumption of periodic boundaries. If you are building a graph for a molecule, you probably do not want this..."
        s = pyimport_conda("pymatgen.core.structure", "pymatgen", "conda-forge")
        struc = s.Structure.from_file(file_path)
        weight_mat = weights_voronoi(struc)
        return weight_mat, atom_ids
    else
        build_graph(
            c;
            cutoff_radius = cutoff_radius,
            max_num_nbr = max_num_nbr,
            dist_decay_func = dist_decay_func,
        )
    end

end

"""
Build graph from a Crystal object. Currently only supports the "cutoff" method of neighbor list/weight calculation (not Voronoi).
This dispatch exists to support autodiff of graph-building.

# Arguments
## Required Arguments
- `crys::Crystal`: Crystal object representing the atomic geometry from which to build a graph

## Keyword Arguments
- `cutoff_radius::Real=8.0`: cutoff radius for atoms to be considered neighbors (in angstroms)
- `max_num_nbr::Integer=12`: maximum number of neighbors to include (even if more fall within cutoff radius)
- `dist_decay_func::Function=inverse_square`: function to determine falloff of graph edge weights with neighbor distance
"""
function build_graph(
    crys::Crystal;
    cutoff_radius::Real = 8.0,
    max_num_nbr::Integer = 12,
    dist_decay_func::Function = inverse_square,
)

    is, js, dists = neighbor_list(crys; cutoff_radius = cutoff_radius)
    weight_mat = weights_cutoff(
        is,
        js,
        dists;
        max_num_nbr = max_num_nbr,
        dist_decay_func = dist_decay_func,
    )
    return weight_mat, String.(crys.atoms.species)
end

"""
Build graph using neighbor number cutoff method adapted from original CGCNN. Note that `max_num_nbr` is a "soft" max, in that if there are more of the same distance as the last, all of those will be added.
"""
function weights_cutoff(is, js, dists; max_num_nbr = 12, dist_decay_func = inverse_square)
    # sort by distance
    ijd = sort([t for t in zip(is, js, dists)], by = t -> t[3])

    # initialize neighbor counts
    num_atoms = maximum(is)
    local nb_counts = Dict(i => 0 for i = 1:num_atoms)
    local longest_dists = Dict(i => 0.0 for i = 1:num_atoms)

    # iterate over list of tuples to build edge weights...
    # note that neighbor list double counts so we only have to increment one counter per pair
    weight_mat = zeros(Float32, num_atoms, num_atoms)
    for (i, j, d) in ijd
        # if we're under the max OR if it's at the same distance as the previous one
        if nb_counts[i] < max_num_nbr || isapprox(longest_dists[i], d)
            weight_mat[i, j] += dist_decay_func(d)
            longest_dists[i] = d
            nb_counts[i] += 1
        end
    end

    # average across diagonal, just in case
    weight_mat = 0.5 .* (weight_mat .+ weight_mat')

    # normalize weights
    weight_mat = weight_mat ./ maximum(weight_mat)
end

"""
Build graph using neighbors from faces of Voronoi polyedra and weights from areas. Based on the approach from https://github.com/ulissigroup/uncertainty_benchmarking/blob/aabb407807e35b5fd6ad06b14b440609ae09e6ef/BNN/data_pyro.py#L268
"""
function weights_voronoi(struc)
    num_atoms = size(struc)[1]
    sa = pyimport_conda("pymatgen.analysis.structure_analyzer", "pymatgen", "conda-forge")
    vc = sa.VoronoiConnectivity(struc)
    conn = vc.connectivity_array
    weight_mat = zeros(Float32, num_atoms, num_atoms)
    # loop over central atoms
    for atom_ind = 1:size(conn)[1]
        # loop over neighbor atoms
        for nb_ind = 1:size(conn)[2]
            # loop over each possible PBC image for chosen image
            for image_ind = 1:size(conn)[3]
                # only add as neighbor if atom is not current center one AND there is connectivity to image
                if (atom_ind != image_ind) && (conn[atom_ind, nb_ind, image_ind] != 0)
                    weight_mat[atom_ind, nb_ind] +=
                        conn[atom_ind, nb_ind, image_ind] / maximum(conn[atom_ind, :, :])
                end
            end
        end
    end

    # average across diagonal (because neighborness isn't strictly symmetric in the way we're defining it here)
    weight_mat = 0.5 .* (weight_mat .+ weight_mat')

    # normalize weights
    weight_mat = weight_mat ./ maximum(weight_mat)
end


"""
Find all lists of pairs of atoms in `crys` that are within a distance of `cutoff_radius` of each other, respecting periodic boundary conditions.

Returns as is, js, dists to be compatible with ASE's output format for the analogous function.
"""
function neighbor_list(crys::Crystal; cutoff_radius::Real = 8.0)
    n_atoms = crys.atoms.n

    # make 3 x 3 x 3 supercell and find indices of "middle" atoms
    # as well as index mapping from outer -> inner
    supercell = replicate(crys, (3, 3, 3))

    # TODO: add check for size of cutoff radius relative to size of sc

    # todo: try BallTree, also perhaps other leafsize values
    #tree = BruteTree(sc.atoms.coords.xf, PeriodicEuclidean([1.0, 1.0, 1.0]))
    tree = BruteTree(Cart(supercell.atoms.coords, supercell.box).x)

    is_raw = 13*n_atoms+1:14*n_atoms
    js_raw =
        inrange(tree, Cart(supercell.atoms.coords[is_raw], supercell.box).x, cutoff_radius)

    index_map(i) = (i - 1) % n_atoms + 1 # I suddenly understand why some people dislike 1-based indexing

    local is = Int[]
    local js = Int[]
    local dists = Float64[]

    # process into is, (mapped) js, compute dists, impose number cutoffs
    for i = 1:n_atoms
        local i_raw_here = is_raw[i]
        js_raw_here = [j for j in js_raw[i] if j != i_raw_here] # exclude self
        for j in js_raw_here
            push!(is, i)
            push!(js, index_map(j))
            push!(dists, distance(supercell.atoms, supercell.box, i_raw_here, j, false))
        end
    end

    return is, js, dists
end

# TODO: graphs from SMILES via OpenSMILES.jl

end
