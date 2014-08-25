require 'rubygems'
require 'bundler'

Bundler.require(:default, ENV['RACK_ENV'] || :development)

require 'google/api_client'
require 'google/api_client/client_secrets'
require 'google/api_client/auth/file_storage'

module ThoughtWorks
  CLIENT_SECRETS_FILE = './secrets/client_secret.json'

  OAUTH_AUTHORIZE = '/oauth2/authorize'
  OAUTH_CALLBACK = '/oauth2/authorized'
  OAUTH_SUCCESS = '/oauth-success/'

  class Warden < Sinatra::Base
    configure :production, :development do
      enable :logging
    end

    configure do
      enable :sessions
      set :session_secret, ENV['SESSION_SECRET'] ||= 'super secret'

      client = Google::APIClient.new(
        :application_name => 'TW Warden',
        :application_version => '1.0.0'
      )

      client_secrets = begin
        secrets = ENV['GOOGLE_CLIENT_SECRETS'] ||= File.read(CLIENT_SECRETS_FILE)
        Google::APIClient::ClientSecrets.new(JSON.parse(secrets))
      end

      client.authorization = client_secrets.to_authorization
      client.authorization.scope = 'https://www.googleapis.com/auth/calendar'

      calendar = client.discovered_api('calendar', 'v3')

      set :api_client, client
      set :calendar_api, calendar
    end

    before do
      unless google_oauth_authorized? || oauth_flow?
        redirect to(OAUTH_AUTHORIZE)
      end
    end

    # must be an after because the client auto updates the access token
    # based on the refresh token
    after do
      store_user_credentials!(user_credentials)
    end

    get OAUTH_AUTHORIZE do
      auth_uri = user_credentials.authorization_uri(
        :access_type => 'offline',
        :approval_prompt => 'force',
        :login_hint => '@thoughtworks.com'
      )

      redirect auth_uri.to_s, 303
    end

    get OAUTH_CALLBACK do
      user_credentials.code = params[:code] if params[:code]
      user_credentials.fetch_access_token!

      redirect to(OAUTH_SUCCESS)
    end

    get OAUTH_SUCCESS do
      "Yeah!"
    end

    private
    def self.client_secrets
      secrets = ENV['GOOGLE_CLIENT_SECRETS'] ||= File.load(CLIENT_SECRETS_FILE)
      Google::APIClient::ClientSecrets.new(secrets)
    end

    def google_oauth_authorized?
      user_credentials.access_token
    end

    def oauth_flow?
      request.path_info =~ /\A\/oauth2\//
    end

    def store_user_credentials!(credentials)
      # Serialize the access/refresh token to the session and credential store.
      session[:access_token] = credentials.access_token
      session[:refresh_token] = credentials.refresh_token
      session[:expires_in] = credentials.expires_in
      session[:issued_at] = credentials.issued_at
    end

    def retrieve_user_credentials
      session
    end

    def api_client; settings.api_client; end

    def calendar_api; settings.calendar; end

    def user_credentials
      # Build a per-request oauth credential based on token stored in session
      # which allows us to use a shared API client.
      @authorization ||= (
        auth = api_client.authorization.dup
        auth.redirect_uri = to(OAUTH_CALLBACK)
        auth.update_token!(retrieve_user_credentials)
        auth
      )
    end
  end
end
