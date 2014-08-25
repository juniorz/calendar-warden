describe ThoughtWorks::Warden do

  it 'should configure a google api client' do
    expect(app.settings.api_client).to be_kind_of(Google::APIClient)
    expect(app.settings.calendar_api).to be_kind_of(Google::APIClient::API)
  end
end
