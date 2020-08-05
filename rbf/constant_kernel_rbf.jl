"Constant coalescence kernel example"

using Plots
using Cloudy.KernelTensors
using Cloudy.ParticleDistributions
using Cloudy.Sources
using Cloudy.BasisFunctions
using Cloudy.Galerkin
using DifferentialEquations
using QuadGK

function main()
  # Numerical parameters
  FT = Float64
  tol = 1e-8

  # Physicsal parameters
  coalescence_coeff = 1/3.14/4
  kernel_func = x -> coalescence_coeff

  # Initial condition: any function; here we choose a lognormal distribution
  N = 150.0
  mu = 1.5
  sigma = 0.5
  dist_init = x-> N/x/sigma/sqrt(2*pi)*exp(-(log.(x)-mu)^2/(2*sigma^2))

  # Choose the basis functions
  Nb = 3
  rbf_mu = [3.0, 5.0, 10.0]
  rbf_sigma = [exp(sigma), exp(sigma), exp(sigma)]
  basis = Array{PrimitiveUnivariateBasisFunc}(undef, Nb)
  for i = 1:Nb
    basis[i] = GaussianBasisFunction(rbf_mu[i], rbf_sigma[i])
  end

  println("Basis:  ", basis)

  # Precompute the various matrices
  A = get_rbf_inner_products(basis)
  c0 = get_IC_vec(dist_init, basis, A)
  Source = get_kernel_rbf_source(basis, kernel_func)
  Sink = get_kernel_rbf_sink(basis, kernel_func)

  # set up the ODE
  tspan = (0.0, 1.0)
  rhs(c, par, t) = collision_coaelescence(c, A, Source, Sink)
  prob = ODEProblem(rhs, c0, tspan)
  sol = solve(prob, reltol=tol, abstol=tol)

  # plot the initial distribution
  x = range(1.0, stop=25.0, step=0.1) |> collect
  dist_exact = dist_init.(x)
  dist_galerkin = evaluate(basis, c0, x)
  pyplot()
  plot(x, dist_exact, label="Exact", title="Constant Kernel")
  plot!(x, dist_galerkin, label="Galerkin approximation")

  # plot the final distribution
  c_final = sol.u[end,:][1]
  dist_galerkin = evaluate(basis, c_final, x)
  plot!(x, dist_galerkin, label="Galerkin approximation: final state")
  savefig("rbf/plot.png")


  mass_dist0 = x->evaluate(basis,c0,x)*x
  mass_distf = x->evaluate(basis,c_final,x)*x

  xstart = eps()
  xstop = 1000.0
  m0 = quadgk(mass_dist0, xstart, xstop)[1]
  mf = quadgk(mass_distf, xstart, xstop)[1]
  println("Starting mass: ", m0)
  println("Ending mass: ", mf)
end

function collision_coaelescence(c, A, M, N)
  Nb = length(c)

  # compute F, the quadratic vector for source/sink
  F = zeros(FT, Nb)
  for i=1:Nb
    F[i] = c'*M[i,:,:]*c - c'*N[i,:,:]*c
  end

  g = A \ F
  return g
end

main()