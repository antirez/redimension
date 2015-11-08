require 'rubygems'
require 'redis'
require "./redimension.rb"

def fuzzy_test(dim,items,queries)
    redis = Redis.new()
    redis.del("redim-fuzzy")
    rn = Redimension.new(redis,"redim-fuzzy",dim,64)
    id = 0
    dataset = []
    items.times {
        vars = []
        dim.times {vars << rand(1000)}
        dataset << vars+[id.to_s]
        rn.index(vars,id)
        puts "Adding #{dataset[-1].inspect}"
        id += 1
    }

    queries.times {
        random = []
        dim.times {
            s = rand(1000)
            e = rand(1000)
            # Sort the range for the test itself, the library can take
            # arguments in the wrong order without issues.
            s,e=e,s if s > e
            random << [s,e]
        }
        print "TESTING #{random.inspect}:"
        STDOUT.flush

        start_t = Time.now
        res1 = rn.query(random)
        end_t = Time.now
        print "#{res1.length} result in #{(end_t-start_t).to_f} seconds\n"
        res2 = dataset.select{|i|
            included = true
            (0...dim).each{|j|
                included = false if i[j] < random[j][0] ||
                                    i[j] > random[j][1]
            }
            included
        }
        if res1.sort != res2.sort
            puts "ERROR #{res1.length} VS #{res2.length}:"
            puts res1.sort.inspect
            puts res2.sort.inspect
            exit
        end
    }
    puts "#{dim}D test passed"
    redis.del("redim-fuzzy")
end

fuzzy_test(4,100,1000)
fuzzy_test(3,100,1000)
fuzzy_test(2,1000,1000)
