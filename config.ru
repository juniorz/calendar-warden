require './lib/tw-warden'

if ENV['RACK_ENV'] == 'production'
  require 'rack/session/dalli'

  client = Dalli::Client.new(ENV['MEMCACHIER_SERVERS'], {
    :username => ENV['MEMCACHIER_USERNAME'],
    :password => ENV['MEMCACHIER_PASSWORD']
  })
  use Rack::Session::Dalli, :cache => client
end

run ThoughtWorks::Warden