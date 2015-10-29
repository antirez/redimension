require "redic"

class Redimension
  attr_reader :redis, :prefix, :dim, :prec

  def initialize(redis, prefix, dim, prec = 64)
    @redis = redis
    @prefix = prefix
    @dim = dim

    @idx = sprintf("%s:idx", prefix)
    @map = sprintf("%s:map", prefix)

    @prec = prec
  end

  def check_dim(vars)
    if vars.length != @dim
      raise "Please always use #{@dim} vars with this index."
    end
  end

  # Encode N variables into the bits-interleaved representation.
  def encode(vars)
    comb = false

    vars.each do |v|
      vbin = v.to_s(2).rjust(@prec, '0')
      comb = comb ? comb.zip(vbin.chars) : vbin.chars
    end

    comb.join.to_i.to_s(16).rjust(@prec * @dim / 4, '0')
  end

  # Encode an element coordinates and ID as the whole string to add
  # into the sorted set.
  def elestring(vars, id)
    check_dim(vars)
    ele = encode(vars)
    vars.each { |v| ele << ":#{v}" }
    ele << ":#{id}"
  end

  # Add a variable with associated data 'id'
  def index(vars, id)
    ele = elestring(vars,id)
    oldele = @redis.call("HGET", @map, id)

    @redis.queue("ZREM", @idx, oldele)
    @redis.queue("HDEL", @map, id)
    @redis.queue("ZADD", @idx, 0, ele)
    @redis.queue("HSET", @map, id, ele)
    @redis.commit
  end

  # Unindex by item ID
  def unindex(id)
    ele = @redis.call("HGET", @map, id)

    @redis.queue("ZREM", @idx, ele)
    @redis.queue("HDEL", @map, ele)
    @redis.commit
  end

  # `exp` is the exponent of two that gives the size of the squares
  # we use in the range query. N times the exponent is the number
  # of bits we unset and set to get the start and end points of the range.
  def query_raw(vrange, exp)
    vstart = []
    vend   = []

    # We start scaling our indexes in order to iterate all areas, so
    # that to move between N-dimensional areas we can just increment
    # vars.
    vrange.each do |r|
      vstart << r[0] / (2**exp)
      vend   << r[1] / (2**exp)
    end

    # Visit all the sub-areas to cover our N-dim search region.
    ranges = []
    vcurrent = vstart.dup
    notdone = true

    while notdone

      # For each sub-region, encode all the start-end ranges
      # for each dimension.
      vrange_start = []
      vrange_end = []

      @dim.times do |i|
        vrange_start << vcurrent[i] * (2**exp)
        vrange_end  << (vrange_start[i] | ((2**exp) - 1))
      end

      # Now we need to combine the ranges for each dimension
      # into a single lexicographcial query, so we turn
      # the ranges it into interleaved form.
      s = encode(vrange_start)

      # Now that we have the start of the range, calculate the end
      # by replacing the specified number of bits from 0 to 1.
      e = encode(vrange_end)
      ranges << ["[#{s}:","[#{e}:\xff"]

      # Increment to loop in N dimensions in order to visit
      # all the sub-areas representing the N dimensional area to
      # query.
      @dim.times do |i|
        if vcurrent[i] != vend[i]
          vcurrent[i] += 1
          break
        elsif i == dim-1
          notdone = false; # Visited everything!
        else
          vcurrent[i] = vstart[i]
        end
      end
    end

    # Perform the ZRANGEBYLEX queries to collect the results from the
    # defined ranges. Use pipelining to speedup.
    ranges.each do |range|
      @redis.queue("ZRANGEBYLEX", @idx, range[0], range[1])
    end

    allres = @redis.commit

    # Filter items according to the requested limits. This is needed
    # since our sub-areas used to cover the whole search area are not
    # perfectly aligned with boundaries, so we also retrieve elements
    # outside the searched ranges.
    items = []

    allres.each do |res|
      res.each do |item|
        skip = false

        _, *values, id = item.split(":")

        values.map!(&:to_i)

        @dim.times do |i|
          if values[i] < vrange[i][0] || values[i] > vrange[i][1]
            skip = true
            break
          end
        end

        if skip == false
          items << values + [id]
        end
      end
    end

    items
  end

  # Like query_raw, but before performing the query makes sure to order
  # parameters so that x0 < x1 and y0 < y1 and so forth.
  # Also calculates the exponent for the query_raw masking.
  def query(vrange)
    vrange = vrange.map do |vr|
      vr[0] < vr[1] ? vr : [vr[1], vr[0]]
    end

    deltas = vrange.map { |vr| (vr[1] - vr[0]) + 1 }
    delta = deltas.min
    exp = 1

    while delta > 2
      delta /= 2
      exp += 1
    end

    # If ranges for different dimensions are extremely different in span,
    # we may end with a too small exponent which will result in a very
    # big number of queries in order to be very selective. This is most
    # of the times not a good idea, so at the cost of querying larger
    # areas and filtering more, we scale 'exp' until we can serve this
    # request with less than 20 ZRANGEBYLEX commands.
    #
    # Note: the magic "20" depends on the number of items inside the
    # requested range, since it's a tradeoff with filtering items outside
    # the searched area. It is possible to improve the algorithm by using
    # ZLEXCOUNT to get the number of items.
    while true
      deltas = vrange.map do |vr|
        (vr[1] / (2**exp)) - (vr[0] / (2**exp)) + 1
      end

      ranges = deltas.reduce { |a, b| a * b }
      break if ranges < 20
      exp += 1
    end

    query_raw(vrange, exp)
  end

  # Similar to #query but takes just the center of the query area and a
  # radius, and automatically filters away all the elements outside the
  # specified circular area.
  def query_radius(x, y, exp, radius)
    # TODO
  end
end

