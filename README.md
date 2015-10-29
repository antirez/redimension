Redimension
===

Redimension is a Redis multi-dimensional indexing and querying
library implemented in order to index items in N-dimensions, and
then asking for elements where each dimension is within the specified
ranges.

This library was written for multiple reasons:

1. In order to show the technique described in the [Redis indexing
documentation](http://redis.io/topics/indexes) in actual working
code.

2. Because it's useful for actual workloads.

3. Since I wanted to experiment with an actual API and implementation
of this problem to understand if it's a good idea to add new commands
to Redis implementing exactly this use case, but inside the server.

The technique used in order to implement this library, is to use
an ordered set of keys in order to represent a multi dimensional
index by interleaving the bits values of each dimension in a single
large number. This way it is possible the request squares (in 2D),
cubes (in 3D) and in general N-dimensional ranges with the same
side length in an efficient way as lexicographical ranges. In Redis,
this is implemented using the sorted set data type, together with
the [ZRANGEBYLEX command](http://redis.io/commands/zrangebylex).

Usage
===

Currently the library can index only unsigned integers of the
specified precision. There are no precision limits, you can index
integers composed of as much bits as you like: you specify the
number of bits for each dimension in the constructor when creating
a `Redimension` object.

An example usage in 2D is the following. Imagine you want to index
persons by salary and age:

    redis = Redic.new
    myindex = Redimension.new(redis,"people-by-salary", 2, 64)

We created a `Redimension` object specifying a Redis client that
must implement [Redic's API][redic-api]. We specified we want 2D
indexing, and 64 bits of precision for each dimension. The first
argument is the prefix under which the indices will be stored.

Redimention uses two indices: one is a sorted set mapping the item
IDs to scores, and the other is a hash that maps item IDs to sorted
set entries. Given the example above, two keys will be created:
`"people-by-salary:idx"` and `"people-by-salary:map"`.


[redic-api]: https://github.com/amakawa/redic#usage

Now we can add elements to our index.

    myindex.index([45,120000],"Josh")
    myindex.index([50,110000],"Pamela")
    myindex.index([30,125000],"Angela")

The `index` method takes an array of integers representing the value
of each dimension for the item, and an item name that will be
returned when asking for ranges during the query stage. Calling
`index` multiple times with the same item ID doesn't create multiple
entries. Insted, it updates the existent index.

Querying is simple. In the following query we ask for all the people
with age between 40 and 50, and salary between 100000 and 115000.

    results = myindex.query([[40, 50], [100000, 115000]])
    Output: [50, 110000, "Pamela"]

Ranges are **always** inclusive. Not a big problem since currently
we can only index integers so just increment/decrement to exclude
a given value.

If you want to play with the library, the above example is shipped
with the source code, the file is called `example.rb`.

Unindexing
===

In order to remove an indexed item, call `unindex` and pass the
item ID as a parameter:

    myindex.unindex("Josh")

Tests
===

Make sure you have `cutest` installed, and execute `make` for running
the tests. You should set the environment variable `REDIS_TEST_URL`
for the tests to work. Also note that the Redis instance referenced
by that URL will be flushed.

License
===

The code is released under the BSD 2 clause license.
