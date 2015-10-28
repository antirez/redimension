require 'rubygems'
require 'redis'
require "./redimension.rb"

redis = Redis.new
myindex = Redimension.new(redis,"people-by-salary",2,64)
myindex.index([45,120000],"Josh")
myindex.index([50,110000],"Pamela")
myindex.index([30,125000],"Angela")
results = myindex.query([[40,50],[100000,115000]])
results.each{|r|
    puts r.inspect
}
