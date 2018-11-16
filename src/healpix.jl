
struct HpxPix{Nside} <: Pix end

struct GradientCache{Nside, T, Nobs, Ntot, NB, W}
    neighbors :: NB
    W_covariant      :: W
    W_contravariant  :: W
    Wᵀ_covariant     :: W
    Wᵀ_contravariant :: W
    
    function GradientCache{Nside,T}(Nobs, order=Val(1)) where {Nside,T}
        N_coeffs    = (order == Val(1)) ? 3 : 6
        N_neighbors = (order == Val(1)) ? 4 : 8
        
        # this uses the pixel itself, but that gives us a non-zero trace
        # neighbors_mat = [(0:(Nobs-1))'; hp.get_all_neighbours(Nside,collect(0:(Nobs-1)))[(order == Val(1) ? (1:2:end) : 1:end),:]::Matrix{Int}] .+ 1
        neighbors_mat = hp.get_all_neighbours(Nside,collect(0:(Nobs-1)))[(order == Val(1) ? (2:2:end) : 1:end),:]::Matrix{Int} .+ 1
        Ntot = maximum(neighbors_mat)
        neighbors = SVector{N_neighbors}.(eachcol(Int32.(neighbors_mat)))

        (θs, ϕs) = convert.(Vector{T}, hp.pix2ang(Nside,collect(0:Ntot))::Tuple{Vector{Float64},Vector{Float64}})
        
        # derivative
        W_covariant, W_contravariant = [], []
        @showprogress 1 "∇  precomputation: " for (i,(ni,θ,ϕ)) in enumerate(zip(neighbors, θs, ϕs))
            Δθ = @.     θs[ni]-θ
            Δϕ = @. rem(ϕs[ni]-ϕ+T(π), T(2π), RoundDown) - T(π)
            if order == Val(1)
                P = @. [Δθ Δϕ ones(T,N_neighbors)]
            else
                P = @. [Δθ Δϕ ones(T,N_neighbors) Δθ^2 Δϕ^2 Δθ*Δϕ]
            end
            Q,R = qr(P)
            W = inv(R)[1:2,:]*Q'
            push!(W_covariant,     SMatrix{2,N_neighbors}(W .* [1, sin(θ)]))
            push!(W_contravariant, SMatrix{2,N_neighbors}(W ./ [1, sin(θ)]))
        end
        _W_covariant     = collect(typeof(W_covariant[1]),    W_covariant)
        _W_contravariant = collect(typeof(W_contravariant[1]),W_contravariant)
        
        # transpose derivative
        Wᵀ_covariant     = fill(NaN, length(neighbors), 2, N_neighbors)
        Wᵀ_contravariant = fill(NaN, length(neighbors), 2, N_neighbors)
        @showprogress 1 "∇' precomputation: " for (i,Ni) in collect(enumerate(neighbors))
            for (j,Nij) in enumerate(Ni)
                if Nij<=length(neighbors)
                    j′ = first(indexin(i,neighbors[Nij]))
                    Wᵀ_covariant[i,:,j]     = _W_covariant[Nij][:,j′]
                    Wᵀ_contravariant[i,:,j] = _W_contravariant[Nij][:,j′]
                end
            end
        end
        _Wᵀ_covariant     = SMatrix{2,N_neighbors,T}.(@views [Wᵀ_covariant[i,:,:]     for i=1:length(neighbors)])
        _Wᵀ_contravariant = SMatrix{2,N_neighbors,T}.(@views [Wᵀ_contravariant[i,:,:] for i=1:length(neighbors)])
        
        new{Nside,T,Nobs,Ntot,typeof(neighbors),typeof(_W_covariant)}(neighbors, _W_covariant, _W_contravariant, _Wᵀ_covariant, _Wᵀ_contravariant)
    end
    
end


struct MaskedHpxS0Map{Nside, T, Nobs, Ntot, GC<:GradientCache{Nside, T, Nobs, Ntot}} <: Field{Map, S0, HpxPix{Nside}}
    Tx::Vector{T}
    gradient_cache::GC
    
    function MaskedHpxS0Map(m::Vector, gc::GC) where {Nside,T,Nobs,Ntot,GC<:GradientCache{Nside,T,Nobs,Ntot}}
        if length(m)!=Ntot; m = m[1:Ntot]; end
        m[Nobs+1:end] .= NaN
        new{Nside,T,Nobs,Ntot,GC}(convert(Vector{T}, m) , gc)
    end
    function MaskedHpxS0Map{Nside,T,Nobs,Ntot,GC}(m::Vector{T}, gc::GC) where {Nside,T,Nobs,Ntot,GC<:GradientCache{Nside,T,Nobs,Ntot}}
        new{Nside,T,Nobs,Ntot,GC}(m,gc)
    end
end
function MaskedHpxS0Map(m::Vector{T}) where {T}
    Nside = hp.npix2nside(length(m))
    Nobs = maximum(findall(!isnan,m))
    MaskedHpxS0Map(m, GradientCache{Nside,T}(Nobs))
end


    
ringinfo(Nside) = ringinfo(Val(Nside))
@generated function ringinfo(::Val{Nside}) where {Nside}
    r = hp.ringinfo(Nside, collect(1:4Nside-1))
    ring_lengths = r[2]
    ring_starts = [1; cumsum(ring_lengths)[1:end-1] .+ 1]
    ring_ranges = [range(a,length=b) for (a,b) in tuple.(ring_starts, ring_lengths)]
    (ring_lengths=ring_lengths, ring_starts=ring_starts, ring_ranges=ring_ranges, cosθ=r[3], sinθ=r[4], θ=acos.(r[3]))
end

similar(f::F) where {F<:MaskedHpxS0Map} = F(similar(f.Tx), f.gradient_cache)
copy(f::F) where {F<:MaskedHpxS0Map} = F(copy(f.Tx), f.gradient_cache)

## derivatives
function mul!(∇f::FieldVector, ∇Op::Union{∇Op{covariant},Adjoint{∇i,∇Op{covariant}}}, f::MaskedHpxS0Map) where {covariant}
    gc = f.gradient_cache
    if ∇Op isa Adjoint
        W = covariant ? gc.Wᵀ_covariant : gc.Wᵀ_contravariant
    else
        W = covariant ? gc.W_covariant : gc.W_contravariant
    end
    @inbounds for i in eachindex(gc.neighbors)
        Tx = @view f.Tx[gc.neighbors[i]]
        ∇f[1].Tx[i], ∇f[2].Tx[i] = W[i] * Tx
    end
    imax = gc.neighbors[end][1] + 1
    ∇f[1].Tx[imax:end] .= ∇f[2].Tx[imax:end] .= NaN
    ∇f
end
*(∇Op::Union{∇Op,Adjoint{∇i,<:∇Op}}, f::MaskedHpxS0Map) where {B} =  mul!(allocate_result(∇Op,f),∇Op,f)
DerivBasis(::Type{<:MaskedHpxS0Map}) = Map


dot(a::MaskedHpxS0Map, b::MaskedHpxS0Map) = dot(nan2zero.(a.Tx),nan2zero.(b.Tx))


function plot(f::MaskedHpxS0Map, args...; plot_type=:mollzoom, cmap="RdBu_r", vlim=nothing, kwargs...)
    kwargs = Dict(kwargs...)
    cmap = get_cmap(cmap)
    cmap[:set_bad]("lightgray")
    cmap[:set_under]("w")
    if vlim!=nothing
        kwargs["min"], kwargs["max"] = -vlim, vlim
    end
    getproperty(hp,plot_type)(full(f), args...; cmap=cmap, kwargs...)
end

## conversion to flat sky maps
function azeqproj(f::MaskedHpxS0Map{<:Any,T}, θpix, Nside) where {T}
    wasinteractive = pylab.isinteractive()
    try
        pylab.ioff()
        Tx = hp.azeqview(full(f), rot=(0,90), reso=θpix, xsize=Nside, return_projected_map=true)
        close()
        FlatS0Map{T,Flat{θpix,Nside,fourier∂}}(Tx)
    finally
        wasinteractive && pylab.ion()
    end
end

## broadcasting
broadcast_data(::Type{F}, f::F) where {F<:MaskedHpxS0Map} = (f.Tx,)
metadata(::Type{F}, f::F) where {F<:MaskedHpxS0Map} = (f.gradient_cache,)
metadata_reduce((m1,)::Tuple{GC}, (m2,)::Tuple{GC}) where {GC<:GradientCache} = (m1,)
metadata_reduce((m1,)::Tuple{GradientCache}, (m2,)::Tuple{GradientCache}) = error()


LenseBasis(::Type{<:MaskedHpxS0Map}) = Map

adjoint(f::MaskedHpxS0Map) = f

@generated function sqrt_gⁱⁱ(f::MaskedHpxS0Map{Nside,T,Nobs,Ntot}) where {Nside,T,Nobs,Ntot}
    quote
        gθθ = MaskedHpxS0Map($(ones(T,Ntot)), f.gradient_cache)
        gϕϕ = MaskedHpxS0Map($(1 ./ ringinfo(Nside).sinθ[hp.pix2ring(Nside,collect(0:Ntot-1))::Vector{Int}]), f.gradient_cache)
        @SMatrix[gθθ 0f; 0f gϕϕ]
    end
end

function full(f::MaskedHpxS0Map{Nside,T}) where {Nside,T}
    Tx = fill(T(NaN),12*Nside^2)
    Tx[1:length(f.Tx)] .= f.Tx
    Tx
end

## this will eventually go elsewhere

function load_s4_map(filename, Nside=2048, ::Type{T}=Float64) where {T}
    m = hp.read_map(filename, verbose=false)
    m = hp.ud_grade(m, Nside)
    m = hp.Rotator((0,-135,0),eulertype="ZYX")[:rotate_map](m)
    m = convert(Vector{T}, m)
    m[@. abs(m)>1e20] .= NaN
    MaskedHpxS0Map(m)
end