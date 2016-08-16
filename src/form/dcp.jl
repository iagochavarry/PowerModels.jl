export 
    DCPPowerModel, DCPVars


abstract AbstractDCPForm <: AbstractPowerFormulation

type StandardDCPForm <: AbstractDCPForm end
typealias DCPPowerModel GenericPowerModel{StandardDCPForm}

# default DC constructor
function DCPPowerModel(data::Dict{AbstractString,Any}; kwargs...)
    return GenericPowerModel(data, StandardDCPForm(); kwargs...)
end

function init_vars(pm::DCPPowerModel)
    phase_angle_variables(pm)
    active_generation_variables(pm)

    p = active_line_flow_variables(pm; both_sides = false)
    p_expr = [(l,i,j) => 1.0*p[(l,i,j)] for (l,i,j) in pm.set.arcs_from]
    p_expr = merge(p_expr, [(l,j,i) => -1.0*p[(l,i,j)] for (l,i,j) in pm.set.arcs_from])

    pm.model.ext[:p_expr] = p_expr
end



function constraint_theta_ref(pm::DCPPowerModel)
    @constraint(pm.model, getvariable(pm.model, :t)[pm.set.ref_bus] == 0)
end

#constraint_active_kcl_shunt_const(pm.model, pm.var.p, pm.var.pg, bus, bus_branches, pm.set.bus_gens[i])
function constraint_active_kcl_shunt(pm::DCPPowerModel, bus)
    i = bus["index"]
    bus_branches = pm.set.bus_branches[i]
    bus_gens = pm.set.bus_gens[i]

    pg = getvariable(pm.model, :pg)
    p_expr = pm.model.ext[:p_expr]

    @constraint(pm.model, sum{p_expr[a], a in bus_branches} == sum{pg[g], g in bus_gens} - bus["pd"] - bus["gs"]*1.0^2)
end

function constraint_reactive_kcl_shunt(pm::DCPPowerModel, bus)
    # Do nothing, this model does not have reactive variables
end


# Creates Ohms constraints (yt post fix indicates that Y and T values are in rectangular form)
function constraint_active_ohms_yt(pm::DCPPowerModel, branch)
    i = branch["index"]
    f_bus = branch["f_bus"]
    t_bus = branch["t_bus"]
    f_idx = (i, f_bus, t_bus)
    t_idx = (i, t_bus, f_bus)

    p_fr = getvariable(pm.model, :p)[f_idx]
    t_fr = getvariable(pm.model, :t)[f_bus]
    t_to = getvariable(pm.model, :t)[t_bus]

    b = branch["b"]

    @constraint(pm.model, p_fr == -b*(t_fr - t_to))
end

function constraint_reactive_ohms_yt(pm::DCPPowerModel, branch)
    # Do nothing, this model does not have reactive variables
end

function constraint_phase_angle_diffrence(pm::DCPPowerModel, branch)
    i = branch["index"]
    f_bus = branch["f_bus"]
    t_bus = branch["t_bus"]

    t_fr = getvariable(pm.model, :t)[f_bus]
    t_to = getvariable(pm.model, :t)[t_bus]

    @constraint(pm.model, t_fr - t_to <= branch["angmax"])
    @constraint(pm.model, t_fr - t_to >= branch["angmin"])
end

function constraint_thermal_limit(pm::DCPPowerModel, branch) 
    i = branch["index"]
    f_bus = branch["f_bus"]
    t_bus = branch["t_bus"]
    f_idx = (i, f_bus, t_bus)
    t_idx = (i, t_bus, f_bus)

    p_fr = getvariable(pm.model, :p)[f_idx]

    if getlowerbound(p_fr) < -branch["rate_a"]
        setlowerbound(p_fr, -branch["rate_a"])
    end

    if getupperbound(p_fr) > branch["rate_a"]
        setupperbound(p_fr, branch["rate_a"])
    end
end




function add_bus_voltage_setpoint{T <: AbstractDCPForm}(sol, pm::GenericPowerModel{T})
    add_setpoint(sol, pm, "bus", "bus_i", "vm", :v; default_value = 1)
    add_setpoint(sol, pm, "bus", "bus_i", "va", :t; scale = (x) -> x*180/pi)
end

