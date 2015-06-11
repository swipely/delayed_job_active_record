source "https://rubygems.org"

gem "rake"
gem "pry"

group :test do
  platforms :jruby do
    gem "activerecord-jdbcmysql-adapter"
    gem "jdbc-mysql"

    gem "activerecord-jdbcpostgresql-adapter"
    gem "jdbc-postgres"

    gem "activerecord-jdbcsqlite3-adapter"
    gem "jdbc-sqlite3"
  end

  platforms :ruby, :mswin, :mingw do
    gem "mysql", "~> 2.9"
    gem "pg"
    gem "sqlite3"
  end

  # For testing tagged logging.
  gem "rails", "~> 4.2"

  gem "coveralls", require: false
  gem "rspec", ">= 3"
  gem "rubocop", ">= 0.23"
  gem "simplecov", require: false
end

gemspec
