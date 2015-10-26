# TODO
#
# Abtract to N dimensions
#
# Filter points outside the specified dimensions.
#
# Document that you can pass a Redis object which just implements
# zadd to collect the operations to add, without executing it, so that
# for instance it is possible to pipeline adds or alike.

require 'rubygems'
require 'redis'

class Redimension 
    def initialize(redis,key)
        @redis = redis
        @key = key
        @prec = 64
        @idmap = false
        @binary = false # Default is hex encoding
    end

    # Encode two variables into the interleaved representation.
    def encode(x,y)
        xbin = x.to_s(2).rjust(@prec,'0')
        ybin = y.to_s(2).rjust(@prec,'0')
        comb = xbin.split("").zip(ybin.split("")).flatten.compact.join("")
        comb.to_i.to_s(16).rjust(@prec/4,'0')
    end

    # Add a variable with associated data 'id'
    def index(x,y,id)
        ele = "#{encode(x,y)}:#{x}:#{y}:#{id}"
        @redis.zadd(@key,0,ele)
    end

    def unindex(x,y)
    end

    def unindex_id(id)
    end

    # exp is the exponent of two that gives the size of the squares
    # we use in the range query. Two times the exponent is the number
    # of bits we unset and set to get the start and end points of the range.
    def query_raw(x0,y0,x1,y1,exp)
        items = []
        x_start = x0/(2**exp)
        x_end = x1/(2**exp)
        y_start = y0/(2**exp)
        y_end = y1/(2**exp)
        (x_start..x_end).each{|x|
            (y_start..y_end).each{|y|
                x_range_start = x*(2**exp)
                x_range_end = x_range_start | ((2**exp)-1)
                y_range_start = y*(2**exp)
                y_range_end = y_range_start | ((2**exp)-1)
                puts "#{x},#{y} x from #{x_range_start} to #{x_range_end}, y from #{y_range_start} to #{y_range_end}"

                # Turn it into interleaved form for ZRANGEBYLEX query.
                s = encode(x_range_start,y_range_start)
                # Now that we have the start of the range, calculate the end
                # by replacing the specified number of bits from 0 to 1.
                e = encode(x_range_end,y_range_end)
                res = @redis.zrangebylex(@key,"[#{s}","[#{e}")
                res.each{|item|
                    fields = item.split(":")
                    ele_x = fields[1].to_i
                    ele_y = fields[2].to_i
                    items << [ele_x,ele_y,fields[3]] \
                        if (ele_x >= x0 && ele_x <= x1 &&
                            ele_y >= y0 && ele_y <= y1)
                }
            }
        }
        items
    end

    # Like query_raw, but before performing the query makes sure to order
    # parameters so that x0 < x1 and y0 < y1. Also calculates the exponent
    # for the query_raw masking.
    def query(x0,y0,x1,y1)
        x0,x1 = x1,x0 if x0 > x1
        y0,y1 = y1,y0 if y0 > y1
        deltax = x1-x0
        delta = y1-y0
        delta = deltax if deltax < delta
        exp = 1
        while delta > 2
            delta /= 2
            exp += 1
        end
        query_raw(x0,y0,x1,y1,exp)
    end

    # Similar to #query but takes just the center of the query area and a
    # radius, and automatically filters away all the elements outside the
    # specified circular area.
    def query_radius(x,y,exp,radius)
    end
end

redis = Redis.new()
redis.del("myindex")
rn = Redimension.new(redis,"myindex")

rn.index(10,10,1)
rn.index(20,20,2)
rn.index(60,200,3)
rn.index(100,100,4)
rn.index(100,300,5)

puts rn.query(50,100,100,300).inspect

redis.del("fuzzy")
rn = Redimension.new(redis,"fuzzy")
id = 0
10000.times {
    rn.index(rand(1000),rand(1000),id)
    id += 1
}

puts rn.query(50,50,100,100).inspect
