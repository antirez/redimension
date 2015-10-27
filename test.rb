require "./redimension.rb"

redis = Redis.new()

redis.del("fuzzy")
rn = Redimension.new(redis,"fuzzy",2,64)
id = 0
dataset = []
1000.times {
    x = rand(1000)
    y = rand(1000)
    dataset << [x,y,id.to_s]
    rn.index(x,y,id)
    id += 1
}

1000.times {
    x0 = rand(1000)
    y0 = rand(1000)
    x1 = rand(1000)
    y1 = rand(1000)
    x0,x1=x1,x0 if x0>x1
    y0,y1=y1,y0 if y0>y1
    puts "TESTING #{[x0,y0,x1,y1].inspect}"
    res1 = rn.query(x0,y0,x1,y1)
    res2 = dataset.select{|i|
        i[0] >= x0 && i[0] <= x1 &&
        i[1] >= y0 && i[1] <= y1
    }
    if res1.sort != res2.sort
        puts "ERROR:"
        puts res1.sort.inspect
        puts res2.sort.inspect
        exit
    end
}
