Gem::Specification.new do |s|
  s.name              = "redimension"
  s.version           = "0.0.1"
  s.summary           = "Redis multi-dimensional indexing and querying library"
  s.description       = "Redis multi-dimensional indexing and querying library"
  s.authors           = ["Salvatore Sanfilippo"]
  s.email             = ["antirez@gmail.com"]
  s.homepage          = "https://github.com/antirez/redimension"
  s.license           = "BSD"

  s.files = `git ls-files`.split("\n")

  s.add_dependency "redic"
  s.add_development_dependency "cutest"
end
