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
        comb.to_i.to_s(16).rjust(@prec*@dim/4,'0')
    end

    # Add a variable with associated data 'id'
    def index(vars,id)
        check_dim(vars)
        ele = encode(vars)
        vars.each{|v| ele << ":#{v}"}
        ele << ":#{id}"
        @redis.zadd(@key,0,ele)
    end

    # ZREM according to current position in the space and ID.
    def unindex(vars,id)
        # TODO
    end

    # Unidex by just ID in case @idmap is set to true in order to take
    # an associated Redis hash with ID -> current indexed representation,
    # so that the user can unindex easily.
    def unindex_id(id)
        # TODO
    end

    # exp is the exponent of two that gives the size of the squares
    # we use in the range query. N times the exponent is the number
    # of bits we unset and set to get the start and end points of the range.
    def query_raw(vrange,exp)
        vstart = []
        vend = []
        # We start scaling our indexes in order to iterate all areas, so
        # that to move between N-dimensional areas we can just increment
        # vars.
        vrange.each{|r|
            vstart << r[0]/(2**exp)
            vend << r[1]/(2**exp)
        }

        # Visit all the sub-areas to cover our N-dim search region.
        ranges = []
        vcurrent = vstart.dup
        while true
            # For each sub-region, encode all the start-end ranges
            # for each dimension.
            vrange_start = []
            vrange_end = []
            (0...@dim).each{|i|
                vrange_start << vcurrent[i]*(2**exp)
                vrange_end << (vrange_start[i] | ((2**exp)-1))
            }

            puts "Logical square #{vcurrent.inspect} from #{vrange_start.inspect} to #{vrange_end.inspect}" if @debug

            # Now we need to combine the ranges for each dimension
            # into a single lexicographcial query, so we turn
            # the ranges it into interleaved form.
            s = encode(vrange_start)
            # Now that we have the start of the range, calculate the end
            # by replacing the specified number of bits from 0 to 1.
            e = encode(vrange_end)
            ranges << ["[#{s}:","[#{e}:\xff"]
            puts "Lex query: #{ranges[-1]}" if @debug

            # Increment to loop in N dimensions in order to visit
            # all the sub-areas representing the N dimensional area to
            # query.
            break if vcurrent == vend
            (0...@dim).each{|i|
                if vcurrent[i] != vend[i]
                    vcurrent[i] += 1
                    break
                else
                    vcurrent[i] = vstart[i]
                end
            }
        end

        # Perform the ZRANGEBYLEX queries to collect the results from the
        # defined ranges. Use pipelining to speedup.
        allres = @redis.pipelined {
            ranges.each{|range|
                @redis.zrangebylex(@key,range[0],range[1])
            }
        }

        # Filter items according to the requested limits. This is needed
        # since our sub-areas used to cover the whole search area are not
        # perfectly aligned with boundaries, so we also retrieve elements
        # outside the searched ranges.
        items = []
        allres.each{|res|
            res.each{|item|
                fields = item.split(":")
                skip = false
                (0...@dim).each{|i|
                    if fields[i+1].to_i < vrange[i][0] ||
                       fields[i+1].to_i > vrange[i][1]
                    then
                        skip = true
                        break
                    end
                }
                items << fields[1..-2].map{|f| f.to_i} + [fields[-1]] if !skip
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
        # TODO
    end
end

