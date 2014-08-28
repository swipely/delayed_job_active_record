source 'https://rubygems.org'

gem 'rake'

gemspec

gem 'pry'

group :test do
  platforms :jruby do
    gem 'activerecord-jdbcsqlite3-adapter'
    gem 'jdbc-sqlite3'
  end

  platforms :ruby, :mswin, :mingw do
    gem 'sqlite3'
  end

  # For testing tagged logging.
  gem 'rails', '~> 4.0.2'

  gem 'coveralls', :require => false
  gem 'rspec', '>= 2.11'
  gem 'simplecov', :require => false
end
