using Test
using LightGraphs
include("../src/pmg_graphs.jl")
include("../src/atomgraph.jl")

@testset "graph-building" begin
    wm, atoms = build_graph(joinpath(@__DIR__, "./test_data/mp-195.cif"))
    wm_true = [0.0 1.0 1.0 1.0; 1.0 0.0 1.0 1.0; 1.0 1.0 0.0 1.0; 1.0 1.0 1.0 0.0]
    @test wm == wm_true
    @test atoms == ["Ho", "Pt", "Pt", "Pt"]
    wm, atoms = build_graph(joinpath(@__DIR__, "./test_data/mp-195.cif"); use_voronoi=false)
    @test wm == wm_true
    @test atoms == ["Ho", "Pt", "Pt", "Pt"]
end

@testset "AtomGraph" begin
    # build a silly little triangle graph
    g = SimpleWeightedGraph{Int32}(Float32.([0 1 1; 1 0 1; 1 1 0]))

    # add an element list that doesn't make sense
    @test_throws AssertionError AtomGraph(g, ["C"])

    # okay, now do it right, start with no features
    ag = AtomGraph(g, ["C", "C", "C"])

    # check LightGraphs fcns
    @test eltype(ag)==Int32
    @test edgetype(ag)==SimpleWeightedEdge{Int32,Float32}
    @test ne(ag)==3
    @test nv(ag)==3
    @test !is_directed(ag)
    # not sure the best way to test the ones that return iterators, e.g. edges
    @test outneighbors(ag,1)==inneighbors(ag,1)==[2,3]
    @test has_vertex(ag,1)
    @test !has_vertex(ag,4)
    @test has_edge(ag,1,2)

    # add some features
    bad_fmat = Float32.([1 2; 3 4])
    good_fmat = Float32.([1 2 3; 4 5 6])
    featurization = [AtomFeat(:feat, true, 2, false, ['a','b'])]
    @test_throws AssertionError add_features!(ag, bad_fmat, featurization)
    add_features!(ag, good_fmat, featurization)
    @test ag.features==good_fmat
end