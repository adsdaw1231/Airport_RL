using CSV, DataFrames, Plots

function read_summary(file)
    lines = readlines(file)
    # 过滤掉以 '#' 开头的行和纯空行
    data_lines = filter(l -> !startswith(l, "#") && !isempty(strip(l)), lines)
    # 第一行是列名
    header = split(data_lines[1], ',')
    # 剩余行是数据
    rows = [split(line, ',') for line in data_lines[2:end]]
    # 创建 DataFrame，去除列名可能的空格
    df = DataFrame(rows, Symbol.(strip.(header)))
    # 将所有列转换为 Float64
    for col in names(df)
        df[!, col] = parse.(Float64, df[!, col])
    end
    return df
end

# 读取两个 CSV 文件（CSV.read 默认会忽略以 '#' 开头的注释行）
df1 = read_summary("data/summary.csv")
df2 = CSV.read("data_rl/summary.csv", DataFrame)

# 要对比的指标
metrics = ["avg_wait_time", "avg_queue_length", "max_queue_length",
           "avg_utilization", "counter_change_freq", "avg_open_counters",
           "overtime_rate", "max_wait_time"]

# 设置子图布局（每个指标一个子图）
p = plot(layout=(length(metrics), 1), size=(800, 1600), legend=:topright)

for (i, metric) in enumerate(metrics)
    # 绘制旧数据（实线圆形标记）
    plot!(p[i], df1.seed, df1[!, Symbol(metric)],
          label="Naive", marker=:circle, lw=1, color=:blue)
          
    # 绘制新数据（虚线方形标记）
    plot!(p[i], df2.seed, df2[!, Symbol(metric)],
          label="RL", marker=:square, lw=1, linestyle=:dash, color=:red)
    title!(p[i], metric)
    xlabel!(p[i], "Seed")
    ylabel!(p[i], "")
end

# 保存图片
savefig("comparison.png")
display(p)