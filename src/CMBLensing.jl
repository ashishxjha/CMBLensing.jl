module CMBLensing

using Adapt
using Base.Broadcast: AbstractArrayStyle, ArrayStyle, Broadcasted, broadcasted,
    DefaultArrayStyle, preprocess_args, Style
using Base.Iterators: repeated, product
using Base.Threads
using Base: @kwdef, @propagate_inbounds, Bottom, OneTo, showarg, show_datatype,
    show_default, show_vector, typed_vcat
using Combinatorics
using DataStructures
using DelimitedFiles
using Distributed: pmap, nworkers, myid, workers
using FFTW
using InteractiveUtils
using Interpolations
using KahanSummation
using Loess
using LinearAlgebra
using LinearAlgebra: diagzero
using MacroTools: @capture, combinedef, isdef, isexpr, postwalk, splitdef
using Match
using Markdown
using Measurements
using Memoization
using Parameters
using Printf
using ProgressMeter
using Random
using Random: seed!
using Roots
using Requires
using Setfield
using StaticArrays: @SMatrix, @SVector, SMatrix, StaticArray, StaticArrayStyle,
    StaticMatrix, StaticVector, SVector
using Statistics
using StatsBase
using Strided: capturestridedargs, make_capture, _mapreduce_fuse!, promoteshape, maybestrided, StridedView

import Adapt: adapt_structure
import Base: +, -, *, \, /, ^, ~, ≈,
    abs, adjoint, axes, broadcast, broadcastable, BroadcastStyle, conj, convert,
    copy, copyto!, eltype, fill!, getindex, getproperty, hash, hcat, hvcat, inv,
    iterate, keys, lastindex, length, literal_pow, mapreduce, materialize!,
    materialize, one, permutedims, print_array, promote, promote_rule,
    promote_rule, promote_type, propertynames, real, setindex!, show,
    show_datatype, show_vector, similar, size, sqrt, string, summary, transpose,
    zero
import Base.Broadcast: instantiate, preprocess
import LinearAlgebra: diag, dot, isnan, ldiv!, logdet, mul!, pinv,
    StructuredMatrixStyle, structured_broadcast_alloc, tr
import Measurements: ±
import Statistics: std


export
    @namedtuple, @repeated, @unpack, animate, argmaxf_lnP, BandPassOp, cache,
    CachedLenseFlow, camb, cov_to_Cℓ, Cℓ_2D, Cℓ_to_Cov, DataSet, DerivBasis,
    diag, Diagonal, DiagOp, dot, EBFourier, EBMap, Field, FieldArray, fieldinfo,
    FieldMatrix, FieldOrOpArray, FieldOrOpMatrix, FieldOrOpRowVector,
    FieldOrOpVector, FieldRowVector, FieldTuple, FieldVector, FieldVector, Flat,
    FlatEB, FlatEBFourier, FlatEBMap, FlatFieldMap, FlatFieldFourier, FlatField,
    FlatFourier, FlatIEBCov, FlatIEBFourier, FlatIEBMap, FlatIQUFourier,
    FlatIQUMap, FlatMap, FlatQU, FlatQUFourier, FlatQUMap, FlatS0, FlatS02,
    FlatS2, FlatS2Fourier, FlatS2Map, Fourier, fourier∂, FuncOp, FΦTuple,
    get_Cℓ, get_Cℓ, get_Dℓ, get_αℓⁿCℓ, get_ρℓ, get_ℓ⁴Cℓ, gradhess, HighPass,
    IdentityOp, IEBFourier, IEBMap, InterpolatedCℓs, IQUFourier, IQUMap,
    LazyBinaryOp, LenseBasis, LenseFlow, LenseOp, LinOp, lnP, load_camb_Cℓs,
    load_sim_dataset, LowPass, make_mask, Map, MAP_joint, MAP_marg, map∂,
    MidPass, mix, nan2zero, noiseCℓs, NoLensing, OuterProdOp, ParamDependentOp,
    pixwin, PowerLens, QUFourier, QUMap, resimulate, RK4Solver, S0, S02, S2,
    sample_joint, shiftℓ, simulate, symplectic_integrate, Taylens, toCℓ, toDℓ,
    tuple_adjoint, ud_grade, unmix, Ð, Ł, δf̃ϕ_δfϕ, δfϕ_δf̃ϕ, ℓ², ℓ⁴, ∇, ∇², ∇¹,
    ∇ᵢ, ∇⁰, ∇ⁱ, ∇₀, ∇₁, ⋅, ⨳
    
# generic stuff
include("util.jl")
include("util_fft.jl")
include("numerical_algorithms.jl")
include("generic.jl")
include("cls.jl")
include("field_tuples.jl")
include("field_vectors.jl")
include("specialops.jl")

# lensing
include("lensing.jl")
include("lenseflow.jl")
include("powerlens.jl")

# flat-sky maps
include("flat_fftgrid.jl")
include("flat_s0.jl")
include("flat_s2.jl")
include("flat_s0s2.jl")
include("flat_generic.jl")
include("masking.jl")
include("taylens.jl")

# plotting
isjuno = false
function animate end
@init @require Juno="e5e0dc1b-0480-54bc-9374-aad01c23163d" isjuno=Juno.isactive()
@init @require PyPlot="d330b81b-6aea-500a-939a-2ce795aea3ee" include("plotting.jl")

# sampling and maximizing the posteriors
include("dataset.jl")
include("posterior.jl")
include("maximization.jl")
include("sampling.jl")

# other estimates
include("quadratic_estimate.jl")

# curved-sky (not yet upgraded to new system)
# include("healpix.jl")

@init @require Zygote="e88e6eb3-aa80-5325-afca-941959d7151f" include("zygote.jl")

# gpu
@init @require CuArrays="3a865a2d-5b23-5a0f-bc46-62713ec82fae" include("gpu.jl")

end
