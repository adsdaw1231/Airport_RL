using DataStructures, Distributions, StableRNGs, CSV, Dates

# Structs 
# Create Event structs
abstract type Event end

mutable struct FlightDisembarks <: Event
    id::Int64
    flight_id::Int64
    no_passengers::Union{Nothing,Int64}
end
FlightDisembarks( id, flight_id )=FlightDisembarks( id, flight_id, nothing )

mutable struct Arrival <: Event
    id::Int64
    flight_id::Int64
    disembark_time::Float64
    passenger_id::Union{Nothing,Int64}
end

mutable struct Departure <: Event
    id::Int64
    passenger_id::Int64
    counter_id::Union{Nothing,Int64}
end

mutable struct RotateAttendants <: Event
    id::Int64
    odd_attendants::Bool
end

# Create Passenger struct
mutable struct Passenger
    id::Int64
    flight_id::Int64
    disembark_time::Float64
    enter_primary_time::Union{Float64, Nothing}
    enter_secondary_time::Union{Float64, Nothing}
    start_service_time::Union{Float64, Nothing}
    end_service_time::Union{Float64, Nothing}
    secondary_id::Union{Nothing,Int64}
    counter_id::Union{Nothing,Int64}
    attendant_rotated::Bool
end

# Create State struct
mutable struct State
    time::Float64
    event_list::PriorityQueue{Event,Float64}
    primary_queue::Queue{Passenger}
    secondary_queues::Vector{Queue{Passenger}}
    in_service::Vector{Union{Passenger,Nothing}}
    n_entities::Int64
    n_events::Int64
    n_flights::Int64
    n_open_counters::Int64
end

# Create Parameters struct
struct Parameters
    seed::Int64
    min_counters::Int64 
    max_counters::Int64 
    secondary_queue_length::Int64
    mean_interflight::Float64 
    min_no_passengers::Int64
    max_no_passengers::Int64 
    min_passenger_transit_time::Float64 
    max_passenger_transit_time::Float64 
    min_service_time::Float64 
    expected_service_time::Float64 
    final_time::Float64 
    attendant_rotation_interval::Float64 
    attendant_rotation_time::Float64 
    secondary_rush_time::Float64 
    helpful_attendants::Bool
end

# Give the initial value of State
function State( P::Parameters )
    time=0.0
    event_list=PriorityQueue{Event,Float64}()
    primary_queue=Queue{Passenger}()

    # Give secondary_queues max empty queues
    secondary_queues=Vector{Queue{Passenger}}(undef, P.max_counters)
    for i in 1:P.max_counters
        secondary_queues[i]=Queue{Passenger}()
    end

    # Give in_service max nothing 
    in_service=Vector{Nothing}(undef, P.max_counters)

    n_entities=0
    n_events=0
    n_flights=0
    n_open_counters=0

    return State(time, event_list, primary_queue, secondary_queues, in_service, n_entities, n_events, n_flights, n_open_counters)
end

# Create RandomNGs struct
struct RandomNGs
    rng::StableRNGs.LehmerRNG
    interflight_time::Function
    no_passengers::Function
    transit_times::Function
    service_time::Function
end

# Define the seed and the function about time
function RandomNGs( P::Parameters )
    rng = StableRNG( P.seed )
    interflight_time() = rand( rng, Exponential( P.mean_interflight ) )
    no_passengers() = rand( rng, DiscreteUniform( P.min_no_passengers, P.max_no_passengers ) )
    transit_times() = rand( rng, Uniform( P.min_passenger_transit_time, P.max_passenger_transit_time))
    alpha = P.expected_service_time / ( P.expected_service_time - 2 )
    service_time() = rand( rng, Pareto( alpha, P.min_service_time ) ) 
    return RandomNGs( rng, interflight_time, no_passengers, transit_times, service_time)
end

# Give the initial value and add first FlightDisembarks event and RotateAttendants event
function initialise( P::Parameters )
    R = RandomNGs(P)
    system = State(P)

    # Add a flight arrival at time 0.0
    t0 = 0.0
    system.n_events += 1
    system.n_flights += 1
    enqueue!( system.event_list, FlightDisembarks(system.n_events,system.n_flights),t0)

    # Add the first attendant rotation
    system.n_events += 1
    enqueue!( system.event_list, RotateAttendants(system.n_events,true), P.attendant_rotation_interval)
    return (system, R)
end
    
# Update function and helpful function
# To move the Passenger to secondary_queues
function move_to_secondary!( S::State, P::Parameters, R::RandomNGs )
    # Keep someone can be moved
    if isempty(S.primary_queue)
        return nothing
    end

    # Firstly move the Passenger to the empty counter's secondary_queue 
    for i in 1:S.n_open_counters
        if !isempty(S.primary_queue)
            if isnothing( S.in_service[i] )
                new_Passenger = dequeue!( S.primary_queue )
                new_Passenger.secondary_id = i
                new_Passenger.enter_secondary_time = S.time
                enqueue!( S.secondary_queues[i], new_Passenger )
            end
        end
    end

    # After above, move Passenger to the secondary_queue whose length is the shortest
    shortest_length = 0
    # If the primary_queue is not empty, keep the secondary_queues be filled
    while shortest_length < P.secondary_queue_length
        if !isempty(S.primary_queue)

            # Search the index of the secondary_queue whose length is the shortest
            index=argmin(length.(S.secondary_queues[1:S.n_open_counters]))
            shortest_length = length(S.secondary_queues[index])# Get the shortest_length

            # Move Passenger to the secondary_queue whose length is the shortest
            if length(S.secondary_queues[index]) < P.secondary_queue_length 
                new_Passenger = dequeue!( S.primary_queue )
                new_Passenger.secondary_id = index
                new_Passenger.enter_secondary_time = S.time 
                enqueue!( S.secondary_queues[index], new_Passenger )
            end
        else
            # If the primary_queue is empty, break the loop
            return nothing
        end
    end

    return nothing
end

# Get longest time and index of Passenger in secondary
function get_longest_time_in_secondary( S::State, P::Parameters )
    time_in_secondary = zeros(Float64, P.max_counters)
   for i in 1:S.n_open_counters 
        if !isempty(S.secondary_queues[i])
            # The first Passenger in the secondary_queue waits for longest_time 
            new_Passenger = first(S.secondary_queues[i])
            time_in_secondary[i] = S.time - new_Passenger.enter_secondary_time
        end
    end 

    # Get longest time and index
    index=argmax(time_in_secondary)
    longest_time = time_in_secondary[index]

    return ( index, longest_time )
end

# About Af3
function helpful_attendants( S::State, P::Parameters, R::RandomNGs, i, index, longest_time)
    # If the empty counter with the empty secondary_queue, move the longest_time Passenger into the counter
    if isempty(S.secondary_queues[i])
        if !isempty(S.secondary_queues[index]) 
            new_Passenger = dequeue!(S.secondary_queues[index]) 
            new_Passenger.start_service_time = S.time
            new_Passenger.end_service_time = S.time + R.service_time()  
            new_Passenger.counter_id = i
            S.in_service[i] = new_Passenger
            S.n_events += 1
            Departure_event = Departure(S.n_events, new_Passenger.id, new_Passenger.counter_id )
            enqueue!( S.event_list, Departure_event, new_Passenger.end_service_time )
            return true
        end
    else # If the empty counter without the empty secondary_queue and the longest_time is more than the P.secondary_rush_time, move the longest_time Passenger into the counter   
        if !isempty(S.secondary_queues[index])  
            if longest_time > P.secondary_rush_time
                new_Passenger = dequeue!( S.secondary_queues[index] ) 
                new_Passenger.start_service_time = S.time
                new_Passenger.end_service_time = S.time + R.service_time()  
                new_Passenger.counter_id = i
                S.in_service[i] = new_Passenger
                S.n_events += 1
                Departure_event = Departure( S.n_events, new_Passenger.id, new_Passenger.counter_id )
                enqueue!( S.event_list, Departure_event, new_Passenger.end_service_time )
                return true
            end
        end
    end
end

# To move the Passenger to counter
function move_to_server!( S::State, P::Parameters, R::RandomNGs )

    # Get longest time and index of Passenger in secondary
    ( index, longest_time )=get_longest_time_in_secondary(S,P)

    for i in 1:P.max_counters
        
        if isnothing(S.in_service[i])
            # Additional feature 3
            if i <= S.n_open_counters        
                if P.helpful_attendants == true
                    A = false
                    A = helpful_attendants( S, P, R, i, index, longest_time)
                    if A == true
                        return nothing #If the counter get Passenger by the Af3, end the progress of move_to_service 
                    end
                end
            end

            # Without Af3 or the situation can't satisfy the condition of Af3
            if !isempty(S.secondary_queues[i])       
                new_Passenger = dequeue!(S.secondary_queues[i]) 
                new_Passenger.start_service_time = S.time
                new_Passenger.end_service_time = S.time + R.service_time() 
                new_Passenger.counter_id = i
                S.in_service[i] = new_Passenger
                S.n_events += 1
                Departure_event = Departure(S.n_events, new_Passenger.id, new_Passenger.counter_id )
                enqueue!( S.event_list, Departure_event, new_Passenger.end_service_time )
                return nothing
            end

        end

    end
    return nothing
end

# About Af1 and Af3
function open_new_counter( S::State, P::Parameters, R::RandomNGs )
    move_to_server!( S, P, R )
    move_to_secondary!( S, P, R )
end

# About Af1
function change_counter!(S::State, P::Parameters)
    # Caculate the n_total(the total number of people in in_service, secondary_queues, and primary_queue)
    sum_secondary=sum( length.(S.secondary_queues) )
    n_total=count(!isnothing, S.in_service)+sum_secondary+length(S.primary_queue)

    # To judge whether the number of counter need to be changed
    if n_total > 10*S.n_open_counters
        if S.n_open_counters < P.max_counters
            S.n_open_counters += 1
        end
    elseif n_total < 10*(S.n_open_counters-2)
        if S.n_open_counters > P.min_counters
            S.n_open_counters -= 1
        end
    end
end

function update!( S::State, P::Parameters, R::RandomNGs, E::Arrival )
    S.n_entities += 1    # New entity will enter the system
    E.passenger_id = S.n_entities
    # Create a new Passenger
    new_Passenger = Passenger( S.n_entities, E.flight_id, E.disembark_time, S.time, nothing, nothing, nothing, nothing, nothing, false )
    
    # Add the customer to the appropriate queue
    enqueue!( S.primary_queue, new_Passenger )

    # To judge and change the number of counters
    change_counter!( S, P )
    
    # If the counter change, the new counter and secondary_queue should be filled
    if isnothing(S.in_service[S.n_open_counters]) && S.n_open_counters > P.min_counters
        open_new_counter( S, P, R )
    end

    # If the secondary_queues is available, the customer goes to secondary_queues
    move_to_secondary!( S, P, R )
    # If the service is available, the customer goes to service
    move_to_server!( S, P, R )

    return nothing
end

function update!( S::State, P::Parameters, R::RandomNGs, E::Departure )
    # Get the informations about the Departure Passenger 
    new_Passenger=S.in_service[E.counter_id]
    # Delete the Passenger from the system
    S.in_service[E.counter_id] = nothing

    # When someone leave, to judge the counter
    change_counter!(S, P)

    # About Af2 
    if new_Passenger.attendant_rotated == true
        new_Passenger.end_service_time = S.time
    end

    # When someone leave, first move Passenger into counter, than move Passenger to fill the secondary 
    move_to_server!( S, P, R )
    move_to_secondary!( S, P, R ) 

    return new_Passenger
end

function update!( S::State, P::Parameters, R::RandomNGs, E::FlightDisembarks )
    # Get the number of Passenger
    E.no_passengers = R.no_passengers()

    # Keep the shorter time Arrival event have the lower event_ID 
    arrival_time = Vector{Float64}(undef, E.no_passengers)
    for i in 1:E.no_passengers
        arrival_time[i] = S.time + R.transit_times() 
    end

    # Add new Arrival event with time from shorter to longer
    for i in 1:E.no_passengers
        S.n_events += 1
        index = argmin(arrival_time)

        enqueue!( S.event_list, Arrival( S.n_events, E.flight_id, S.time, nothing ), arrival_time[index] )
        arrival_time[index] = Inf
    end

    # Add new flight arrival
    S.n_events += 1
    S.n_flights += 1
    new_FlightDisembarks = FlightDisembarks( S.n_events, S.n_flights )
    enqueue!( S.event_list, new_FlightDisembarks, S.time + R.interflight_time() )
    return nothing
end

# Search the Departure event in the event_list and update the Departure time 
function search_and_update_departure( S::State, P::Parameters, target::Int64 )
    for (event, priority) in S.event_list
        if isa( event, Departure )
            if event.passenger_id == target 
                delete!( S.event_list, event )
                enqueue!( S.event_list, event, priority + P.attendant_rotation_time )
                break
            end
        end
    end
end

# When counter rotate, change the Departure_event and the Passenger that are affected
function service_pause!( S::State, P::Parameters, E::RotateAttendants )
    # The odd counters are affected
    if E.odd_attendants == true  
        for i in 1:2:P.max_counters
            if !isnothing(S.in_service[i])
                new_Passenger = S.in_service[i]
                new_Passenger.attendant_rotated = true
                S.in_service[i] = new_Passenger

                target = new_Passenger.id
                search_and_update_departure( S, P, target )
                
            end
        end 
    else # The even counters are affected
        for i in 2:2:P.max_counters
            if !isnothing(S.in_service[i])         
                new_Passenger = S.in_service[i]           
                new_Passenger.attendant_rotated = true
                S.in_service[i] = new_Passenger
                
                target = new_Passenger.id
                search_and_update_departure( S, P, target )

            end
        end 
    end

    return nothing
end

function update!( S::State, P::Parameters, R::RandomNGs, E::RotateAttendants )

    # When counter rotate, change the Departure_event and the Passenger that are affected
    service_pause!( S, P, E )

    # Add next RotateAttendants event 
    S.n_events += 1
    if E.odd_attendants == true  
        new_rotateAttendants=RotateAttendants( S.n_events, false )# Next time will be even
    else 
        new_rotateAttendants=RotateAttendants( S.n_events, true )# Next time will be odd
    end
    enqueue!( S.event_list, new_rotateAttendants, S.time + P.attendant_rotation_interval )

    return nothing
end

# Print function
# Write the fundamental informations
function write_metadata( output::IO ) 
    (path, prog) = splitdir( @__FILE__ )
    println( output, "# file created by code in $(prog)" )
    t = now()
    println( output, "# file created on $(Dates.format(t, "yyyy-mm-dd at HH:MM:SS"))" )
end

# Write the Parameters
function write_parameters( output::IO, P::Parameters )
    T = typeof(P)
    for name in fieldnames(T)
        println( output, "# parameter: $name = $(getfield(P,name))" )
    end
end
write_parameters( P::Parameters ) = write_parameters( stdout, P )

# Write the state headers
function write_state_header(fid_state)
    println(fid_state, "event_ID,time,event,upcoming_arrivals,primary_length,secondary_lengths,in_service,n_total,n_open_counters")
end

# Write the state informations
function write_state(fid::IO, S::State, E::Event)
    # Get the event name
    name_event=string(typeof(E))

    # Get n_total
    sum_secondary=sum( length.(S.secondary_queues) )
    n_total=count(!isnothing, S.in_service)+sum_secondary+length(S.primary_queue)

    # Get the number of Arrival event in the event_list
    upcoming_arrivals=count(x -> isa(x, Arrival), keys(S.event_list))

    # Change the ',' into ';'
    secondary_lengths = "[" * join(string.(length.(S.secondary_queues)), ";") * "]"
    in_service = "[" * join(string.(Int.(.!(isnothing.(S.in_service)))), ";") * "]"

    println(fid, "$(E.id),$(S.time),$(name_event),$(upcoming_arrivals),$(length(S.primary_queue)),$(secondary_lengths),$(in_service),$(n_total),$(S.n_open_counters)")
    return nothing
end

# Write entity headers
function write_entity_header(fid_entities)
    println(fid_entities, "passenger_id,flight_id,disembark_time,enter_primary,enter_secondary,start_service,end_service,secondary_id,counter_id,attendant_rotated")
end

# Write entities informations
function write_entities(fid::IO, S::State, P::Passenger)
    println(fid, "$(P.id),$(P.flight_id),$(P.disembark_time),$(P.enter_primary_time),$(P.enter_secondary_time),$(P.start_service_time),$(P.end_service_time),$(P.secondary_id),$(P.counter_id),$(P.attendant_rotated)")
end

# Run function
# Exercute the simulation system
# ... 前面代码保持不变 ...

function run!( S::State, P::Parameters, R::RandomNGs, fid_state::IO, fid_entitier::IO )

    S.n_open_counters = P.min_counters

    # 统计变量
    waiting_times = Float64[]
    prev_time = S.time
    counter_time_integral = 0.0
    queue_length_time_integral = 0.0
    total_service_time = 0.0
    max_queue_length = 0
    counter_change_count = 0

    while S.time < P.final_time

        (event, time) = dequeue_pair!(S.event_list)
        Δt = time - S.time
        if Δt > 0
            counter_time_integral += S.n_open_counters * Δt
            total_queue_len = length(S.primary_queue) + sum(length.(S.secondary_queues))
            queue_length_time_integral += total_queue_len * Δt
            max_queue_length = max(max_queue_length, total_queue_len)
        end
        S.time = time

        # 记录柜台变化次数（仅当柜台数改变时）
        old_count = S.n_open_counters
        new_Passenger = update!( S, P, R, event )
        if S.n_open_counters != old_count
            counter_change_count += 1
        end

        write_state( fid_state, S, event )

        if !isnothing(new_Passenger)
            write_entities( fid_entitier, S, new_Passenger)
            wait_time = new_Passenger.start_service_time - new_Passenger.enter_primary_time
            push!(waiting_times, wait_time)
            total_service_time += (new_Passenger.end_service_time - new_Passenger.start_service_time)
        end

    end

    # 最后一个事件到 final_time 之间的积分
    final_dt = P.final_time - S.time
    if final_dt > 0
        total_queue_len = length(S.primary_queue) + sum(length.(S.secondary_queues))
        queue_length_time_integral += total_queue_len * final_dt
        counter_time_integral += S.n_open_counters * final_dt
        max_queue_length = max(max_queue_length, total_queue_len)
    end

    total_time = P.final_time
    served_passengers = length(waiting_times)

    # 计算指标
    if served_passengers > 0
        avg_wait_time = mean(waiting_times)
        max_wait_time = maximum(waiting_times)
        overtime_rate = count(w -> w > 15.0, waiting_times) / served_passengers
    else
        avg_wait_time = 0.0
        max_wait_time = 0.0
        overtime_rate = 0.0
    end

    avg_queue_length = queue_length_time_integral / total_time
    avg_open_counters = counter_time_integral / total_time
    avg_utilization = total_service_time / counter_time_integral
    counter_change_freq = counter_change_count / total_time

    return (avg_wait_time, avg_queue_length, max_queue_length,
            avg_utilization, counter_change_freq, avg_open_counters,
            overtime_rate, max_wait_time)
end

function run_AirportOverseasPassport(P::Parameters)
    
    # File directory and name; * concatenates strings.
    dir = pwd()*"/data/"*"/seed"*string(P.seed) # Directory name
    mkpath(dir)                          # This creates the directory 
    file_entities = dir*"/entities.csv"  # The name of the data file (informative) 
    file_state = dir*"/state.csv"        # The name of the data file (informative) 
    file_summary = dir*"/summary.csv"    # 新增汇总文件

    fid_entities = open(file_entities, "w")
    fid_state    = open(file_state, "w")
    fid_summary  = open(file_summary, "w")

    write_metadata( fid_entities )
    write_metadata( fid_state )
    write_metadata( fid_summary )
    write_parameters( fid_entities, P )
    write_parameters( fid_state, P )
    write_parameters( fid_summary, P )

    # Headers
    write_entity_header( fid_entities )
    write_state_header( fid_state )
    println(fid_summary, "seed,avg_wait_time,avg_queue_length,max_queue_length,avg_utilization,counter_change_freq,avg_open_counters,overtime_rate,max_wait_time")

    # Run the actual simulation
    ( S, R ) = initialise( P ) 

    (avg_wait_time, avg_queue_length, max_queue_length,
            avg_utilization, counter_change_freq, avg_open_counters,
            overtime_rate, max_wait_time) =
        run!( S, P, R, fid_state, fid_entities )

    # 写入汇总
    println(fid_summary, "$(P.seed), $avg_wait_time, $avg_queue_length, $max_queue_length,$avg_utilization, $counter_change_freq, $avg_open_counters,$overtime_rate, $max_wait_time")

    # Remember to close the files
    close( fid_entities )
    close( fid_state )
    close( fid_summary )
    return (avg_wait_time, avg_queue_length, max_queue_length,
            avg_utilization, counter_change_freq, avg_open_counters,
            overtime_rate, max_wait_time)
end

