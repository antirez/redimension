require 'rubygems'
require 'redis'

class Redimension 
    attr_accessor :debug
    attr_reader :redis, :key, :dim, :prec

    def initialize(redis,key,dim,prec)
        @debug = false
        @redis = redis
        @dim = dim
        @key = key
        @prec = 64
        @idmap = false
        @binary = false # Default is hex encoding
    end

    def check_dim(vars)
        if vars.length != @dim
            raise "Please always use #{@dim} vars with this index."
        end
    end

    # Encode two variables into the interleaved representation.
    def encode(vars)
        comb = false
        vars.each{|v|
            vbin = v.to_s(2).rjust(@prec,'0')
            comb = comb ? comb.zip(vbin.split("")) : vbin.split("")
        }
        comb = comb.flatten.compact.join("")
        comb.to_i.to_s(16).rjust(@prec/4,'0')
    end

    # Add a variable with associated data 'id'
    def index(vars,id)
        check_dim(vars)
        ele = encode(vars)
        vars.each{|v| ele << ":#{v}"}
        ele << ":#{id}"
        @redis.zadd(@key,0,ele)
    end

    def unindex(vars)
    end

    def unindex_id(id)
    end

    # exp is the exponent of two that gives the size of the squares
    # we use in the range query. Two times the exponent is the number
    # of bits we unset and set to get the start and end points of the range.
    def query_raw(vrange,exp)
        vstart = []
        vend = []
        vrange.each{|r|
            vstart << r[0]/(2**exp)
            vend << r[1]/(2**exp)
        }

        ranges = []
        notdone = true
        while notdone
            # Turn each sub-area into a lex query.
            vrange_start = []
            vrange_end = []
            (0...@dim).each{|i|
                vrange_start << vstart[i]*(2**exp)
                vrange_end << (vrange_start[i] | ((2**exp)-1))
            }
            # Turn it into interleaved form for ZRANGEBYLEX query.
            s = encode(vrange_start)
            # Now that we have the start of the range, calculate the end
            # by replacing the specified number of bits from 0 to 1.
            e = encode(vrange_end)
            ranges << ["[#{s}:","[#{e}:\xff"]

            # Increment to loop in N dimensions in order to visit
            # all the sub-areas representing the N dimensional area to
            # query.
            (0...@dim).each{|i|
                if vstart[i] != vend[i]
                    vstart[i] += 1
                    break
                elsif i == dim-1
                    notdone = false; # Visited everything!
                else
                    vstart[i] = 0
                end
            }
        end

        # Perform ZRANGEBYLEX queries to collect the results from the
        # defined ranges.
        allres = @redis.pipelined {
            ranges.each{|range|
                @redis.zrangebylex(@key,range[0],range[1])
            }
        }

        # Filter items according to the requested limits.
        items = []
        allres.each{|res|
            res.each{|item|
                fields = item.split(":")
                (0...@dim).each{|i|
                    next if fields[i+1].to_i < vrange[i][0] ||
                            fields[i+1].to_i > vrange[i][1]
                    items << fields[1..-2].map{|f| f.to_i} + [fields[-1]]
                }
            }
        }
        items
    end

    # Like query_raw, but before performing the query makes sure to order
    # parameters so that x0 < x1 and y0 < y1 and so forth.
    # Also calculates the exponent for the query_raw masking.
    def query(vrange)
        vrange = vrange.map{|vr|
            vr[0] < vr[1] ? vr : [vr[1],vr[0]]
        }
        delta = vrange.map{|vr| vr[1]-vr[0]}.min
        exp = 1
        while delta > 2
            delta /= 2
            exp += 1
        end
        query_raw(vrange,exp)
    end

    # Similar to #query but takes just the center of the query area and a
    # radius, and automatically filters away all the elements outside the
    # specified circular area.
    def query_radius(x,y,exp,radius)
    end
end

