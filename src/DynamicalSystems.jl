__precompile__()

"""
A Julia package for the exploration of continuous
and discrete dynamical systems.
"""
module DynamicalSystems

"""
Abstract type representing a dynamical system.
"""
abstract type DynamicalSystem end

export DynamicalSystem, Systems

# Mathematics:
include("systems/dataset.jl")
include("mathfun.jl")

# System definition and evolution:
include("systems/discrete.jl")
include("systems/continuous.jl")
include("systems/famous_systems.jl")

# Lyapunovs:
include("lyapunovs.jl")

# Entropies and Dimension Estimation:
include("dimensions/entropies.jl")
include("dimensions/dims.jl")

# Nonlinear Timeseries Analysis:
include("delay_coords.jl")

# Periodicity:
include("periodic.jl")

hen = Systems.henon()
lor = Systems.lorenz()
lyapunov(hen, 1000)
lyapunov(lor, 1000.0)

end # module
