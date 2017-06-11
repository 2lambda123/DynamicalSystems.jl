using StaticArrays, ForwardDiff, Requires

export DiscreteDS, DiscreteDS1D, evolve, jacobian, timeseries, setu, dimension

abstract type DiscreteDynamicalSystem <: DynamicalSystem end
#######################################################################################
#                                     Constructors                                    #
#######################################################################################
function test_functions(u0, eom, jac)
  is1D(u0) || throw(ArgumentError("Initial condition must a Vector"))
  D = length(u0)
  su0 = SVector{D}(u0); sun = eom(u0);
  length(sun) == length(s) ||
  throw(DimensionMismatch("E.o.m. does not give same sized vector as initial condition"))
  if !issubtype((typeof(sun)), SVector)
    throw(ArgumentError("E.o.m. should create an SVector (from StaticArrays)"))
  end
  J1 = jac(u0); J2 = jac(SVector{length(u0)}(u0))
  if !issubtype((typeof(J1)), SMatrix) || !issubtype((typeof(J2)), SMatrix)
    throw(ArgumentError("Jacobian function should create an SMatrix (from StaticArrays)!"))
  end
  return true
end
function test_functions(u0, eom)
  jac = (x) -> ForwardDiff.jacobian(eom, x)
  test_discrete(u0, eom, fd_jac)
end

"""
    DiscreteDS <: DynamicalSystem
Immutable (for efficiency reasons) structure representing a `D`-dimensional
discrete dynamical system.
# Fields:
* `state::SVector{D}` : Current state-vector of the system, stored in the data format
  of `StaticArray`'s `SVector`.
* `eom::F` (function) : The function that represents the system's equations of motion
  (also called vector field). The function is of the format: `eom(u) -> SVector`
  which means that given a state-vector `u` it returns an `SVector` containing the
  next state.
* `jacob::J` (function) : A function that calculates the system's jacobian matrix,
  based on the format: `jacob(u) -> SMatrix` which means that given a state-vector
  `u` it returns an `SMatrix` containing the Jacobian at that state.

The function `DynamicalBilliards.test_functions(u0, eom[, jac])` is provided to help
you ensure that your setup is correct.
# Constructors:
* `DiscreteDS(u0, eom, jac)` : The default constructor.
* `DiscreteDS(u0, eom)` : The Jacobian function is created with *tremendous* efficiency
  using the module `ForwardDiff`. Most of the time, for low dimensional systems, this
  Jacobian is within a few % of speed of a user-defined one.
"""
struct DiscreteDS{D, T<:Real, F, J} <: DiscreteDynamicalSystem
  state::SVector{D,T}
  eom::F
  jacob::J
end
# constsructor without jacobian (uses ForwardDiff)
function DiscreteDS(u0::AbstractVector, eom)
  su0 = SVector{length(u0)}(u0)
  @inline ForwardDiff_jac(x) = ForwardDiff.jacobian(eom, x)
  return DiscreteDS(su0, eom, ForwardDiff_jac)
end
function DiscreteDS(u0::AbstractVector, eom, jac)
  su0 = SVector{length(u0)}(u0)
  return DiscreteDS(su0, eom, jac)
end

"""
    DiscreteDS1D <: DynamicalSystem
Immutable structure representing an one-dimensional Discrete dynamical system.
# Fields:
* `state::Real` : Current state of the system.
* `eom::F` (function) : The function that represents the system's equations of motion:
  `eom(x) -> Real`.
* `deriv::D` (function) : A function that calculates the system's derivative given
  a state: `deriv(x) -> Real`.
# Constructors:
* `DiscreteDS1D(x0, eom, deriv)` : The default constructor with user-provided
  derivative function (most efficient)
* `DiscreteDS1d(x0, eom)` : The derivative function is created
  automatically using the module `ForwardDiff`.
"""
struct DiscreteDS1D{S<:Real, F, D} <: DiscreteDynamicalSystem
  state::S
  eom::F
  deriv::D
end
function DiscreteDS1D(x0, eom)
  fd_deriv(x) = ForwardDiff.derivative(eom, x)
  DiscreteDS1D(x0, eom, fd_deriv)
end

"""
    setu(u, ds::DynamicalSystem) -> new_ds
Create a new system, identical to `ds` but with state `u`.
"""
setu(u0, ds::DiscreteDS) = DiscreteDS(u0, ds.eom, ds.jacob)
setu(x0, ds::DiscreteDS1D) = DiscreteDS1D(x0, ds.eom, ds.deriv)

"""
    jacobian(ds::DynamicalSystem)
Return the Jacobian matrix of the system at the current state.
"""
jacobian(s::DynamicalSystem) = s.jacob(s.state)

is1D(::DiscreteDS1D) = true

dimension(::DiscreteDS{D, T, F, J})  where {D<:ANY, T<:ANY, F<:ANY, J<:ANY} = D
dimension(::DiscreteDS1D) = 1
#######################################################################################
#                                 System Evolution                                    #
#######################################################################################
"""
```julia
evolve(state, ds::DynamicalSystem, T [, diff_eq_kwargs])
evolve(ds::DynamicalSystem, T [, diff_eq_kwargs])
```
Evolve a `state` (or a system `ds`) under the dynamics
of `ds` for total "time" `T`. For discrete systems `T` corresponds to steps and
thus it must be integer. Because both `state` and `ds` are immutable,
call as: `st = evolve(st, ds, T)` or `ds = evolve(ds, T)`.

The last **optional** argument `diff_eq_kwargs` is a `Dict{Symbol, Any}` and is only
applicable for continuous systems. It contains keyword arguments passed into the
`solve` of the `DifferentialEquations` package, like for
example `:abstol => 1e-9`. If you want to specify the solving algorithm,
do so by using `:solver` as one of your keywords, like `:solver => DP5()`.

This function *does not store* any information about intermediate steps.
Use `timeseries` if you want to produce timeseries of the system.
"""
function evolve(ds::DiscreteDynamicalSystem, N::Int = 1)
  st = deepcopy(ds.state)
  st = evolve(st, ds, N)
  return setu(st, ds)
end
function evolve(state, ds::DiscreteDynamicalSystem, N::Int = 1)
  f = ds.eom
  for i in 1:N
    state = f(state)
  end
  return state
end


"""
```julia
timeseries(ds::DiscreteDS, N::Int)
```
Create a `N×D` matrix that will contain the timeseries of the sytem, after evolving it
for `N` steps (`D` is the system dimensionality). Returns a `Vector` for `DiscreteDS1D`.

*Each column corresponds to one dynamic variable.*
"""
function timeseries(s::DiscreteDS, N::Int)
  d = s
  T = eltype(d.state)
  D = length(d.state)
  ts = Array{T}(N, D)
  ts[1,:] .= d.state
  for i in 2:N
    d = evolve(d)
    ts[i, :] .= d.state
  end
  return ts
end

function timeseries(s::DiscreteDS1D, N::Int)
  x = deepcopy(s.state)
  f = s.eom
  ts = Vector{eltype(x)}(N)
  ts[1] = x
  for i in 2:N
    x = f(x)
    ts[i] = x
  end
  return ts
end

#######################################################################################
#                                 Pretty-Printing                                     #
#######################################################################################
import Base.show
function Base.show(io::IO, s::DiscreteDS{N, S, F, J}) where {N<:ANY, S<:ANY, F<:ANY, J<:ANY}
  print(io, "$N-dimensional discrete dynamical system:\n",
  "state: $(s.state)\n", "e.o.m.: $F\n", "jacobian: $J")
end

@require Juno begin
  function Juno.render(i::Juno.Inline, s::DiscreteDS{N, S, F, J}) where {N<:ANY, S<:ANY, F<:ANY, J<:ANY}
    t = Juno.render(i, Juno.defaultrepr(s))
    t[:head] = Juno.render(i, Text("$N-dimensional discrete dynamical system"))
    t
  end
end

# 1-D
function Base.show(io::IO, s::DiscreteDS1D{S, F, J}) where {S<:ANY, F<:ANY, J<:ANY}
  print(io, "1-dimensional discrete dynamical system:\n",
  "state: $(s.state)\n", "e.o.m.: $F\n", "jacobian: $J")
end
@require Juno begin
  function Juno.render(i::Juno.Inline, s::DiscreteDS1D{S, F, J}) where {S<:ANY, F<:ANY, J<:ANY}
    t = Juno.render(i, Juno.defaultrepr(s))
    t[:head] = Juno.render(i, Text("1-dimensional discrete dynamical system"))
    t
  end
end
