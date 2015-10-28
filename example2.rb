require 'rubygems'
require 'redis'
require "./redimension.rb"

redis = Redis.new
redis.del("people-by-salary")
redis.del("people-by-salary-map")
myindex = Redimension.new(redis,"people-by-salary",2,64)
myindex.hashkey = "people-by-salary-map"
myindex.update([45,120000],"Josh")
myindex.update([50,110000],"Pamela")
myindex.update([41,100000],"George")
myindex.update([30,125000],"Angela")

results = myindex.query([[40,50],[100000,115000]])
results.each{|r|
    puts r.inspect
}

myindex.unindex_by_id("Pamela")
puts "After unindexing:"
results = myindex.query([[40,50],[100000,115000]])
results.each{|r|
    puts r.inspect
}

myindex.update([42,100000],"George")
puts "After updating:"
results = myindex.query([[40,50],[100000,115000]])
results.each{|r|
    puts r.inspect
}
