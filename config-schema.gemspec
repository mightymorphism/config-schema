$:.push File.expand_path("../lib", __FILE__)
require File.expand_path('../lib/config_schema/version', __FILE__)

Gem::Specification.new do |gem|
  gem.name          = 'config-schema'
  gem.authors       = [ "Mighty Morphism" ]
  gem.homepage      = 'https://github.com/mightymorphism/config_schema'
  gem.summary       = %q{ Config schema validation using JSON schema gem }
  gem.description   = %q{ Config schema validation using JSON schema gem }
  gem.version       = ConfigSchema::VERSION
  gem.license       = "MIT"

  gem.files = Dir['Rakefile', 'lib/**/*', 'README*', 'LICENSE*']
  gem.require_paths = %w[ lib ]

  gem.add_dependency 'hashie'
  gem.add_dependency 'json-schema', '~> 4.1', '>= 4.1.1'
end
