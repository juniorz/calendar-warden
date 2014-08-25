require 'rubygems'

require 'bundler/setup'

require 'google/api_client'
require 'google/api_client/client_secrets'
require 'google/api_client/auth/file_storage'
require 'sinatra'
require 'logger'

enable :sessions

CLIENT_SECRETS_FILE = "./secrets/local.secrets-webapp.json"
CREDENTIAL_STORE_FILE = "./tmp/#{$0}-oauth2.json"

# https://developers.google.com/accounts/docs/OAuth2
# https://developers.google.com/accounts/docs/OAuth2WebServer
# https://developers.google.com/api-client-library/ruby/guide/aaa_oauth
# https://github.com/intridea/omniauth-oauth2/issues/40#issuecomment-22193296

ROOM_CALENDAR = {
     chico_mendes: "thoughtworks.com_37313433313636302d333830@resource.calendar.google.com",
     sim_mas_nao: "thoughtworks.com_37313732313338312d373537@resource.calendar.google.com",
     lelia_gonzales: "thoughtworks.com_3330333432383935363531@resource.calendar.google.com",
     brasil: "thoughtworks.com_31323137373134312d353732@resource.calendar.google.com",
     tw_offices: "thoughtworks.com_3135383336323935373238@resource.calendar.google.com",
     pagu: "thoughtworks.com_2d36353639323535352d353233@resource.calendar.google.com",
     street_art: "thoughtworks.com_3139313432393239373034@resource.calendar.google.com",
     paulo_freire: "thoughtworks.com_2d3430363632373832353536@resource.calendar.google.com",
     bolicho: "thoughtworks.com_2d3238333338333333363138@resource.calendar.google.com",
     ctg: "thoughtworks.com_2d343134393436322d3835@resource.calendar.google.com",
     galpao: "thoughtworks.com_2d3136333930333638363531@resource.calendar.google.com",
     castle: "thoughtworks.com_2d35393233393931322d353235@resource.calendar.google.com",
     riacho_ipiranga: "thoughtworks.com_2d39333739393938362d3132@resource.calendar.google.com",
     sao_paulo: "thoughtworks.com_2d39393634303632352d353330@resource.calendar.google.com",
     cancha: "thoughtworks.com_38393738373834343135@resource.calendar.google.com",
     vila_do_chaves: "thoughtworks.com_2d3532393931353437323839@resource.calendar.google.com",
     troll: "thoughtworks.com_393734383030332d343636@resource.calendar.google.com",
     pastoreio: "thoughtworks.com_3134383630323038393334@resource.calendar.google.com",
     darcy_penteado: "thoughtworks.com_3232393631343539343634@resource.calendar.google.com",
     beer: "thoughtworks.com_32393134353732302d383330@resource.calendar.google.com",
     maria_lacerda: "thoughtworks.com_393436363035362d393434@resource.calendar.google.com",
}

def logger; settings.logger end

def api_client; settings.api_client; end

def calendar_api; settings.calendar; end

def user_credentials
  # Build a per-request oauth credential based on token stored in session
  # which allows us to use a shared API client.
  @authorization ||= (
    auth = api_client.authorization.dup
    auth.redirect_uri = to('/oauth2callback')
    auth.update_token!(session)
    auth
  )
end

configure do
  log_file = File.open('logs/calendar.log', 'a+')
  log_file.sync = true
  logger = Logger.new(log_file)
  logger.level = Logger::DEBUG

  client = Google::APIClient.new(
    :application_name => 'TW Calendars',
    :application_version => '1.0.0'
  )

  file_storage = Google::APIClient::FileStorage.new(CREDENTIAL_STORE_FILE)
  if file_storage.authorization.nil?
    # https://developers.google.com/api-client-library/ruby/guide/aaa_oauth

    client_secrets = Google::APIClient::ClientSecrets.load(CLIENT_SECRETS_FILE)
    client.authorization = client_secrets.to_authorization

    ##client.authorization.scope = 'https://www.googleapis.com/auth/calendar'
    client.authorization.scope = 'https://www.googleapis.com/auth/calendar.readonly'
  else
    client.authorization = file_storage.authorization
  end

  # Since we're saving the API definition to the settings, we're only retrieving
  # it once (on server start) and saving it between requests.
  # If this is still an issue, you could serialize the object and load it on
  # subsequent runs.
  calendar = client.discovered_api('calendar', 'v3')

  set :logger, logger
  set :api_client, client
  set :calendar, calendar
end

before do
  # Ensure user has authorized the app
  unless user_credentials.access_token || request.path_info =~ /\A\/oauth2/
    redirect to('/oauth2authorize')
  end
end

after do
  # Serialize the access/refresh token to the session and credential store.
  session[:access_token] = user_credentials.access_token
  session[:refresh_token] = user_credentials.refresh_token
  session[:expires_in] = user_credentials.expires_in
  session[:issued_at] = user_credentials.issued_at

  # This file is only written at the first authorization
  file_storage = Google::APIClient::FileStorage.new(CREDENTIAL_STORE_FILE)
  file_storage.write_credentials(user_credentials)
end

get '/oauth2authorize' do
  # Request authorization
  #
  # Forces offline access.
  # With offline access the access token expires every 1 hour
  # Without, it expires in 11 hours, but then you have to login again
  auth_uri = user_credentials.authorization_uri(
    :access_type => 'offline',
    :approval_prompt => 'force',
    :login_hint => '@thoughtworks.com'
  )

  redirect auth_uri.to_s, 303
end

get '/oauth2callback' do
  # Exchange token
  user_credentials.code = params[:code] if params[:code]
  user_credentials.fetch_access_token!
  redirect to('/')
end

get '/' do
  "You have allowed the app to read TW's calendar for you."
end

get '/rooms' do
  [200, {'Content-Type' => 'application/json'}, ROOM_CALENDAR.keys.sort.to_json]
end

get '/room/all' do
  events = ROOM_CALENDAR.collect {|key, value| suspicious_events_for(value).last }.flatten

  [200, {'Content-Type' => 'application/json'}, events.to_json]
end

get '/room/:room_name' do
  room_name = params[:room_name].downcase.to_sym
  calendar_id = ROOM_CALENDAR[room_name]

  return 404 if calendar_id.nil?

  code, events = *suspicious_events_for(calendar_id)

  [code, {'Content-Type' => 'application/json'}, events.to_json]
end

private
def suspicious_events_for(calendar_id)
  parameters = {
    'calendarId' => calendar_id,
    'showDeleted' => false,
    'timeMin' => '2014-08-01T00:00:00-03:00',
    'timeMax' => '2014-09-01T00:00:00-03:00',
    'timeZone' => 'America/Sao_Paulo',
    'orderBy' => 'startTime',
    'singleEvents' => 'true'
  }

  # Fetch list of events on the user's default calandar
  result = api_client.execute(:api_method => calendar_api.events.list,
                              :parameters => parameters,
                              :authorization => user_credentials)

  return [result.status, result.data] unless result.status == 200

  events = result.data.to_hash["items"].select {|event|
    accepted = event["attendees"].nil? || event["attendees"].any?{|e| e["self"] && e["responseStatus"] != "declined" }

    accepted && Time.parse(event["updated"]) < Time.new("2014-01-01T00:00:00Z")
  }

  events.uniq!{ |e| e["iCalUID"] }

  return [200, events]
end