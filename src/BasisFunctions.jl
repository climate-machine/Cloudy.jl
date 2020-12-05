module BasisFunctions

using QuadGK
using SpecialFunctions: gamma

export AbstractBasisFunc
export PrimitiveUnivariateBasisFunc
export GaussianBasisFunction
export LognormalBasisFunction
export GammaBasisFunction
export basis_func
export evaluate_rbf
export get_moment


"""
  AbstractBasisFunc{FT}

A basis function over R^d, which can take a variety of forms.
"""
abstract type AbstractBasisFunc{FT} end

"""
    PrimitiveUnivariateBasisFunc{FT}

A 1D basis function over R, which can take a variety of forms.
"""
abstract type PrimitiveUnivariateBasisFunc{FT} <: AbstractBasisFunc{FT} end

"""
   GaussianBasisFunction{FT}

A normal distribution.
"""
struct GaussianBasisFunction{FT} <: PrimitiveUnivariateBasisFunc{FT}
    "center of the basis function"
    μ::FT
    "width of the basis function"
    σ::FT

    function GaussianBasisFunction(μ::FT, σ::FT) where {FT <: Real}
        if σ <= 0
          error("σ needs to be positive")
        end
      
        new{FT}(μ, σ)
    end
end


"""
   LognormalBasisFunction{FT}

A lognormal distribution.
"""
struct LognormalBasisFunction{FT} <: PrimitiveUnivariateBasisFunc{FT}
    "mean of log(x)"
    μ::FT
    "std dev of log(x)"
    σ::FT

    function LognormalBasisFunction(μ::FT, σ::FT) where {FT <: Real}
        if σ <= 0
          error("σ needs to be positive")
        end
      
        new{FT}(μ, σ)
    end
end

"""
   GammaBasisFunction{FT}

A normal distribution.
"""
struct GammaBasisFunction{FT} <: PrimitiveUnivariateBasisFunc{FT}
    "shape parameter"
    k::FT
    "scale parameter"
    θ::FT

    function GammaBasisFunction(k::FT, θ::FT) where {FT <: Real}
        if θ <= 0
          error("θ needs to be positive")
        end
      
        new{FT}(k, θ)
    end
end


"""
  basis_func(dist)

  `rbf` - Radial Basis Function
Returns a function that computes the moments of `dist`.
"""
function basis_func(rbf::GaussianBasisFunction{FT}) where {FT <: Real}
    p = get_params(rbf)[2]
    μ = p[1]
    σ = p[2]
    function f(μ, σ, x)
        exp(-((x-μ)/σ)^2/2)/σ/sqrt(2*pi)
    end
    g = x-> f(μ, σ, x)
    return g
end

function basis_func(rbf::LognormalBasisFunction{FT}) where {FT <: Real}
  p = get_params(rbf)[2]
  μ = p[1]
  σ = p[2]
  function f(μ, σ, x)
      1/x/σ/sqrt(2*pi)*exp(-(log(x)-μ)^2/2/σ^2)
  end
  g = x-> f(μ, σ, x)
  return g
end

function basis_func(rbf::GammaBasisFunction{FT}) where {FT <: Real}
  p = get_params(rbf)[2]
  k = p[1]
  θ = p[2]
  function f(k, θ, x)
      x^(k-1)*exp(-x/θ)/θ^k/gamma(k)
  end
  g = x-> f(k, θ, x)
  return g
end

"""
  get_params(basis_func)

  - `basis_func` - is a basis function
Returns the names and values of settable parameters for a dist.
"""
function get_params(basis_func::AbstractBasisFunc{FT}) where {FT<:Real}
  params = Array{Symbol, 1}(collect(propertynames(basis_func)))
  values = Array{FT, 1}([getproperty(basis_func, p) for p in params])
  return params, values
end

function evaluate_rbf(basis::Array{PrimitiveUnivariateBasisFunc,1}, c::Array{FT}, x::Array{FT}) where {FT<:Real}
  Nb = length(basis)
  if (length(c) != Nb)
    error("Number of coefficients must match number of basis functions")
  end

  approx = zeros(FT, length(x))
  for i=1:Nb
    approx += c[i]*basis_func(basis[i]).(x)
  end

  return approx
end

function evaluate_rbf(basis::Array{PrimitiveUnivariateBasisFunc,1}, c::Array{FT}, x::FT) where {FT<:Real}
  Nb = length(basis)
  if (length(c) != Nb)
    error("Number of coefficients must match number of basis functions")
  end

  approx = 0
  for i=1:Nb
    approx += c[i]*basis_func(basis[i])(x)
  end

  return approx
end

function get_moment(basis::Array{PrimitiveUnivariateBasisFunc, 1}, q::FT; xstart::FT = eps(), xstop::FT = 1000.0) where {FT <: Real}
  Nb = length(basis)
  moms = zeros(FT, Nb)
  for i=1:Nb
    integrand = x-> basis_func(basis[i])(x)*x^q
    moms[i] = quadgk(integrand, xstart, xstop)[1]
  end

  return moms
end

function get_moment(basis::Array{LognormalBasisFunction, 1}, q::FT) where {FT <: Real}
  Nb = length(basis)
  moms = zeros(FT, Nb)
  for i=1:Nb
    params = get_params(basis[i])
    mu = params[1]
    sigma = params[2]
    moms[i] = exp(q*mu+q^2*sigma^2/2)
  end

  return moms
end

function get_moment(basis::Array{GammaBasisFunction, 1}, q::FT) where {FT <: Real}
  Nb = length(basis)
  moms = zeros(FT, Nb)
  for i=1:Nb
    params = get_params(basis[i])
    k = params[1]
    theta = params[2]
    moms[i] = gamma(k+q)/gamma(k)*theta^q
  end

  return moms
end

end