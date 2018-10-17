using Printf
using TwoPointFluxFVM
using PyPlot


mutable struct ILiqParameters <:FVMParameters
    @AddDefaultFVMParameters
    eps::Float64 
    z::Float64
    ic::Int32
    iphi::Int32
    ILiqParameters()=ILiqParameters(new())
end

function flux!(this::ILiqParameters,f,uk,ul)
    ic=this.ic
    iphi=this.iphi
    f[iphi]=this.eps*(uk[iphi]-ul[iphi])
    muk=-log(1-uk[ic])
    mul=-log(1-ul[ic])
    bp,bm=fbernoulli_pm(this.z*2*(uk[iphi]-ul[iphi])+(muk-mul))
    f[ic]=bm*uk[ic]-bp*ul[ic]
end 


function classflux!(this::ILiqParameters,f,uk,ul)
    ic=this.ic
    iphi=this.iphi
    f[iphi]=this.eps*(uk[iphi]-ul[iphi])
    arg=uk[iphi]-ul[iphi]
    bp,bm=fbernoulli_pm(uk[iphi]-ul[iphi])
    f[ic]=bm*uk[ic]-bp*ul[ic]
end 

function storage!(this::FVMParameters, f,u)
    ic=this.ic
    iphi=this.iphi
    f[iphi]=0
    f[ic]=u[ic]
end

function reaction!(this::FVMParameters, f,u)
    ic=this.ic
    iphi=this.iphi
    f[iphi]=this.z*(1-2*u[ic])
    f[ic]=0
end


function ILiqParameters(this)
    DefaultFVMParameters(this,2)
    this.eps=1.0e-4
    this.z=-1
    this.iphi=1
    this.ic=2
    this.flux=flux!
    this.storage=storage!
    this.reaction=reaction!
    return this
end



function plot_solution(sys,U0)
    U=bulk_unknowns(sys,U0)

    iphi=sys.parameters.iphi
    ic=sys.parameters.ic
    geom=sys.geometry
    PyPlot.clf()
    PyPlot.plot(geom.node_coordinates[1,:],U[iphi,:], label="Potential", color="g")
    PyPlot.plot(geom.node_coordinates[1,:],U[ic,:], label="c-", color="b")
    PyPlot.grid()
    PyPlot.legend(loc="upper right")
    PyPlot.pause(1.0e-10)
end


function run_iliq(;n=100,pyplot=false,dlcap=false)

    h=1.0/convert(Float64,n)
    geom=FVMGraph(collect(0:h:1))
    
    parameters=ILiqParameters()
    ic=parameters.ic
    iphi=parameters.iphi
    
    sys=TwoPointFluxFVMSystem(geom,parameters)
    sys.boundary_values[iphi,1]=5
    sys.boundary_values[iphi,2]=0.0
    
    
    sys.boundary_factors[iphi,1]=Dirichlet
    sys.boundary_factors[iphi,2]=Dirichlet

    sys.boundary_values[ic,2]=0.5
    sys.boundary_factors[ic,2]=Dirichlet
    
    inival=unknowns(sys)
    inival_bulk=bulk_unknowns(sys,inival)
    for inode=1:size(inival_bulk,2)
        inival_bulk[iphi,inode]=0
        inival_bulk[ic,inode]=0.5
    end
    parameters.eps=1.0e-3
    control=FVMNewtonControl()
    control.verbose=true
    print("time loop")
    if !dlcap
        control.damp_initial=0.5
        t=0.0
        tend=1.0
        tstep=1.0e-4
        while t<tend
            t=t+tstep
            U=solve(sys,inival,control=control,tstep=tstep)
            for i=1:length(inival)
                inival[i]=U[i]
            end
            @printf("time=%g\n",t)
            if pyplot
                plot_solution(sys,U)
            end
            tstep*=1.4
        end
    else
        print("calculating double layer capacitance")
        delta=1.0e-4
        for inode=1:size(inival_bulk,2)
            inival_bulk[iphi,inode]=0
            inival_bulk[ic,inode]=0.5
        end
        sys.boundary_values[iphi,1]=0
        
        dphi=1.0e-1
        phimax=5
        delta=1.0e-4
        vplus=zeros(0)
        cdlplus=zeros(0)
        vminus=zeros(0)
        cdlminus=zeros(0)
        for dir in [1,-1]
            sol=copy(inival)
            phi=0.0
            while phi<phimax
                sys.boundary_values[iphi,1]=dir*phi
                sol=solve(sys,sol)
                Q=integrate(sys,reaction!,sol)
                sys.boundary_values[iphi,1]=dir*phi+delta
                sol=solve(sys,sol)
                if pyplot
                    plot_solution(sys,sol)
                end
                Qdelta=integrate(sys,reaction!,sol)
                cdl=(Qdelta[iphi]-Q[iphi])/delta
                if dir==1
                    push!(vplus,dir*phi)
                    push!(cdlplus,cdl)
                else
                    push!(vminus,dir*phi)
                    push!(cdlminus,cdl)
                end
                phi+=dphi
            end
        end
        if pyplot
            PyPlot.clf()
            PyPlot.plot(vplus,cdlplus,color="g")
            PyPlot.plot(vminus,cdlminus,color="g")
            PyPlot.grid()
            PyPlot.legend(loc="upper right")
            PyPlot.pause(1.0e-10)
        end
    end
end



if !isinteractive()
    @time run_iliq(n=100,pyplot=true,dlcap=false)
    PyPlot.waitforbuttonpress()
end