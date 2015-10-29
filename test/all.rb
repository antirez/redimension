require_relative "../lib/redimension"

setup do
  redis = Redic.new(ENV.fetch("REDIS_TEST_URL"))
  keys = %w(people-by-salary people-by-salary-map redim-fuzzy)
  redis.call("DEL", *keys)
  redis
end

test do |redis|
  myindex = Redimension.new(redis, "people-by-salary", 2)

  myindex.index([45, 120000], "Josh")
  myindex.index([50, 110000], "Pamela")
  myindex.index([30, 125000], "Angela")

  results = myindex.query([[40, 50], [100000, 115000]])

  expected = [[50, 110000, "Pamela"]]

  assert_equal expected, results
end

test do |redis|
  myindex = Redimension.new(redis, "people-by-salary", 2, 64)

  myindex.update([45, 120000], "Josh")
  myindex.update([50, 110000], "Pamela")
  myindex.update([41, 100000], "George")
  myindex.update([30, 125000], "Angela")

  results = myindex.query([[40, 50], [100000, 115000]])

  expected = [
    [41, 100000, "George"],
    [50, 110000, "Pamela"],
  ]

  assert_equal expected, results

  myindex.unindex_by_id("Pamela")

  results = myindex.query([[40, 50], [100000, 115000]])

  expected = [[41, 100000, "George"]]

  assert_equal expected, results

  myindex.update([42, 100000], "George")

  results = myindex.query([[40,50],[100000,115000]])

  expected = [[42, 100000, "George"]]

  assert_equal expected, results
end

test "fuzzy" do |redis|
  fuzzy = -> (dim, items, queries) {
    redis.call("DEL", "redim-fuzzy")

    rn = Redimension.new(redis, "redim-fuzzy", dim, 64)
    id = 0
    dataset = []

    1000.times do
      vars = []
      dim.times { vars << rand(1000) }
      dataset << vars + [id.to_s]

      rn.index(vars, id)

      id += 1
    end

    1000.times do
      random = []
      dim.times do
        s = rand(1000)
        e = rand(1000)

        # Sort the range for the test itself, the library can take
        # arguments in the wrong order without issues.
        s, e = e, s if s > e
        random << [s,e]
      end

      start_t = Time.now
      res1 = rn.query(random)
      end_t = Time.now

      res2 = dataset.select { |i|
        included = true

        (0...dim).each { |j|
          included = false if i[j] < random[j][0] ||
                    i[j] > random[j][1]
        }

        included
      }

      assert_equal res1.sort, res2.sort
    end
  }

  fuzzy.call(4,  100, 1000)
  fuzzy.call(3,  100, 1000)
  fuzzy.call(2, 1000, 1000)
end
