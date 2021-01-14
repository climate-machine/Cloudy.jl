# Single aerosol species MOM evolution: exponential distribution

using Test
using DifferentialEquations
using Plots
using Sundials

using Cloudy.ParticleDistributions

function main()
  # Numerical parameters
  FT = Float64
  tol = FT(1e-8)

  # Initial condition:
  S_init = FT(0.1)
  v_up = FT(1)
  dist_init = ExponentialPrimitiveParticleDistribution(FT(100), FT(50.0))
  dry_dist = dist_init
  kappa=0.6
  M3_dry = moment(dist_init, FT(3))/moment(dist_init, FT(0))
  println(M3_dry)
  tspan = (FT(0), FT(1e-6))

  # track only 0th and 1st moments
  moments_S_init = FT[0.0, 0.0, S_init]
  println("Initializing with moments:")
  for k in 0:1
    moments_S_init[k+1] = moment(dist_init, FT(k))
    println(moments_S_init[k+1])
  end
  println("Supersaturation: ", S_init)
  println()

  ODE_parameters = Dict(:dist => dist_init)
  println("coeffs: ", get_aerosol_coefficients(kappa, M3_dry))

  # implement callbacks to halt the integration: maximum step in parameter space
  function param_change2(m,t,integrator; max_param_change=[Inf, Inf]) 
    #println("Condition checked")
    
    # find the propose change
    dist_prev = deepcopy(integrator.p)
    dist_next = deepcopy(integrator.p)
    d_param = 0
    try
      dist_prev = update_params_from_moments(dist_prev, integrator.uprev[1:3])
      param_prev = get_params(dist_prev)[2]
    
      dist_next = update_params_from_moments(dist_next, integrator.u[1:3])
      param_next = get_params(dist_next)[2]

      d_param = minimum(max_param_change - abs.(param_prev - param_next))
    catch
      d_param = 0
    end
    return d_param
  end

  # enforce that the 1st moment (i.e. mass or mean radius) cannot decrease from the dry radius
  function mass_increase(m,t,integrator, M1_init)
    println("called")
    # find the proposed change
    M1_next = m[2]
    return M1_next - M1_init + 1e-10 # >= 0 is good
  end

  function affect1!(integrator) 
    integrator.set_proposed_dt!(integrator.get_proposed_dt/2)
  end

  function affect2!(integrator, M1_init)
    integrator.u[2] = M1_init
  end
  
  max_param_change1 = [NaN, 1.0]
  #condition(m, t, integrator) = param_change2(m, t, integrator; max_param_change=max_param_change1)
  #cb=ContinuousCallback(condition, affect1!)
  condition(m,t,integrator) = mass_increase(m,t,integrator, moments_S_init[2])
  affect!(integrator) = affect2!(integrator, moments_S_init[2])
  cb = ContinuousCallback(condition, affect!)

  # set up ODE
  rhs(m, par, t) = get_aerosol_growth_2mom(m, par, t, v_up, kappa, M3_dry)

  # solve the ODE
  println("Solving ODE...")
  prob = ODEProblem(rhs, moments_S_init, tspan, ODE_parameters)
  alg = CVODE_BDF()
  sol = solve(prob, alg, callbacks = cb)

  println("Finished solving")
  println("Final state:")
  println(sol.u[end,:])

  #for (tstep, ustep) in (sol.t, sol.u)
  #  println(tstep, ustep)
  #end
  for tstep in sol.t
    println(tstep, sol(tstep))
  end

  # Plot the solution for the 0th & 1st moment
  pyplot()
  time = sol.t
  mom = vcat(sol.u'...)
  moment_0 = mom[:, 1]
  moment_1 = mom[:, 2]
  S = vcat(sol.u'...)[:,3]

  plot(time,
      moment_0,
      linewidth=3,
      xaxis="time",
      yaxis="M\$_k\$(time)",
      label="M\$_0\$ CLIMA"
  )
  savefig("aerosols-emily/M0_exp.png")

  plot(time,
      moment_1,
      linewidth=3,
      label="M\$_1\$ CLIMA"
  )
  savefig("aerosols-emily/M1_exp.png")

  # Plot the solution for the supersaturation
  plot(time,
      S,
      linewidth=3,
      label="S CLIMA")
  savefig("aerosols-emily/S_exp.png")

  # Plot the initial and final Distribution
  tstops=[0, 1e-6, 1e-5, 1e-4, 1e-3, 1e-2, 1e-1, 1.0]
  x = range(1.0, stop=1000.0, step=1.0) |> collect
  dist_plot = dist_init
  ODE_parameters = Dict(:dist => dist_plot)
  for time in tstops
    moments = sol(time)
    dist_plot = update_params_from_moments(ODE_parameters, moments[1:2])
    println("time: ", time, ";   parameters: ", get_params(dist_plot)[2], ";    supersaturation: ", moments[3])
    pdf = ParticleDistributions.density(dist_plot, x)
    plot!(x,
        pdf,
        linewidth=3,
        label=time)
    savefig("aerosols-emily/distributionchange_exp.png")
  end

end

"""
get_aerosol_growth_2mom(mom_p::Array{Float64}, v_up::Float64=1)

  - 'T' - temperature in K
  - 'P' - pressure in Pa
  - 'V' - volume of box, m3
  - 'kappa' - hygroscopicity of particles
  - 'rd' - dry radius of particles, m
  Returns the coefficients for aerosol growth.
  - 'a' = [G, GA, -G k rd^3, alpha, gamma] [=] [m2/sec, m3/sec, m5/sec, 1/m2, 1/m3]

"""
function get_aerosol_growth_2mom(mom_p::Array{FT}, ODE_parameters::Dict, t::FT, v_up::FT, kappa::FT, M3_dry::FT) where {FT}
  #println("time: ", t)
  #println("prognostic moments: ", mom_p)
  #@show t
  #@show mom_p

  try
    dist = update_params_from_moments(ODE_parameters, mom_p[1:2])
    ODE_parameters[:dist] = dist
    #println("Distribution: ", dist)
  
    mom_d = Array{FT}(undef, 4)
    S = mom_p[end]
  
    # compute the diagnostic moments: M-1 through M-4
    s = 5; #add to moment indexing
    for k in -4:-1
      mom_d[k+s] = moment_num(dist, FT(k))
    end
    mom = vcat(mom_d, mom_p)
    #println("diagnostic moments: ", mom_d)
  
    coeffs = get_aerosol_coefficients(kappa, M3_dry)
    ddt = Array{FT}(undef,3)
  
    # compute the time rate of change
    ddt[1] = 0;
    ddt[2] = coeffs[1]*S*mom[-1+s] + coeffs[2]*mom[-2+s] + coeffs[3]*mom[-4+s]
    
    # dS/dt
    ddt[end] = coeffs[4]*v_up - coeffs[5]*(coeffs[1]*S*mom[1+s] + coeffs[2]*mom[0+s] + coeffs[3]*mom[-2+s])
    println("Derivative wrt  time: ", ddt)
    #println()
    return ddt
  catch e
    ddt = [Inf, Inf, Inf]
    #println("failed")
    return ddt
  end

end

"""
    get_aerosol_coefficients(kappa::FT=0.6, rd::FT=1; T::FT=285, P::FT=95000, V::FT=1) where {FT}

 - 'T' - temperature in K
 - 'P' - pressure in Pa
 - 'V' - volume of box, m3
 - 'kappa' - hygroscopicity of particles
 - 'rd' - dry radius of particles, m
 Returns the coefficients for aerosol growth.
 - 'a' = [G, GA, -G k rd^3, alpha, gamma] [=] [m2/sec, m3/sec, m5/sec, 1/m2, 1/m3]

"""
function get_aerosol_coefficients(kappa::FT, M3_dry::FT;
  T::FT=285.0,
  P::FT=95000.0,
  V::FT=1.0e-6
  ) where {FT}

  # specify physical constants
  cp = 1005               # Specific heat of air: J/kg K
  Mw = 0.018              # Molecular weight of water: kg/mol
  Ma = 0.029              # Molecular weight of dry air: kg/mol
  g = 9.8                 # acceleration due to gravity: m/s^2
  R = 8.314               # Universal gas constant: J/K mol
  sigma_water = 0.072225  # surface tension of water (N/m)
  rho_w = 997             # density of water (kg/m3)

  P_atm = P/101325        # Pressure (atm)
  Dv = (0.211/P_atm) * (T/273)^(1.94)*1e-4 # Mass diffusivity of water in air (m2/s or J/kg)

  # temperature-dependent parameters
  temp_c = T - 273.15
  a0 = 6.107799
  a1 = 4.436518e-1
  a2 = 1.428945e-2
  a3 = 2.650648e-4
  a4 = 3.031240e-6
  a5 = 2.034081e-8
  a6 = 6.136829e-11
  # vapor pressure of water (Pa)
  Po = 100*(a0+a1*temp_c+a2*(temp_c^2)+a3*(temp_c^3)+a4*(temp_c^4)+a5*(temp_c^5)+a6*(temp_c^6))
  # thermal conductivity of air (W/m K)
  ka = 1e-3*(4.39+0.071*T)
  # density of air (kg/m3)
  rho_a = P/(287.058*T)
  # latent heat of vaporization: J/kg
  Hv = (2.5*((273.15/T)^(0.167+3.67e-4*T)))*1e6

  # Generalized coefficients
  G = 1/((rho_w*R*T/Po/Dv/Mw) + (Hv*rho_w/ka/T*(Hv*Mw/T/R - 1))) * 1e18     #nm2/sec
  A = 2*Mw*sigma_water/R/T/rho_w *1e9                                       #nm
  alpha = Hv*Mw*g/cp/R/T^2 - g*Ma/R/T                                       #1/m
  gamma = P*Ma/Po/Mw + Hv^2*Mw/cp/R/T^2
  gamma2 = gamma*4*pi/rho_a/rho_w/V*1e-27                                   #1/nm3

  # 3-moment ODE coefficients
  a = Array{FT}(undef, 5)
  a[1] = G;               #nm2/sec
  a[2] = G*A;             #nm3/sec
  a[3] = -G*kappa*M3_dry; #nm5/sec
  a[4] = alpha;           #1/m
  a[5] = gamma2;          #1/nm3
  return a
end

@time main()