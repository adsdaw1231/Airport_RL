include("RL-Airport_1.jl")

#训练模型
P = Parameters(1, 2, 8, 2, 45.0, 15, 25, 5.0, 30.0, 2.0, 4.0, 1440, 30, 1.0, 20.0, true)
(agent, reward) = train_agent(P, 50000)

#CSV输出文件生成
dir = pwd()*"/data_RL/"
file_summary = dir*"/summary.csv"
fid_summary  = open(file_summary, "w")
write_metadata( fid_summary )
println(fid_summary, "seed,avg_wait_time,avg_queue_length,max_queue_length,avg_utilization,counter_change_freq,avg_open_counters,overtime_rate,max_wait_time")

#评估模型
for seed in 1:10
    P = Parameters(seed, 2, 8, 2, 45.0, 15, 25, 5.0, 30.0, 2.0, 4.0, 1440, 30, 1.0, 20.0, true)
    (avg_wait_time, avg_queue_length, max_queue_length,
            avg_utilization, counter_change_freq, avg_open_counters,
            overtime_rate, max_wait_time) = evaluate_and_record(P, agent)
    println(fid_summary, "$(P.seed), $avg_wait_time, $avg_queue_length, $max_queue_length,$avg_utilization, $counter_change_freq, $avg_open_counters,$overtime_rate, $max_wait_time")
end

close( fid_summary )

