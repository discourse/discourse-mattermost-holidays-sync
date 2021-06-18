# frozen_string_literal: true
require 'rails_helper'

describe "Mattermost holiday sync" do
  def run_job
    ::Jobs::UpdateMattermostUsernames.new.execute(nil)
  end

  it "does nothing when disabled" do
    run_job
  end

  context "with credentials" do
    before do
      SiteSetting.discourse_mattermost_api_key = "abc"
      SiteSetting.discourse_mattermost_server = "https://chat.example.com"
      DiscourseCalendar.users_on_holiday = []
    end

    let(:discourse_user) { Fabricate(:user) }

    let(:users_body_data) {
      [
        {
          id: "userid",
          username: "david",
          email: discourse_user.email,
          props: { customStatus: "" }
        }
      ]
    }

    let!(:users_stub) {
      stub_request(:get, "https://chat.example.com/api/v4/users").
        with(headers: {
        'Authorization' => 'Bearer abc',
        'Host' => 'chat.example.com'
      }).
        to_return { { status: 200, body: users_body_data.to_json, headers: {} } }
    }

    it "does nothing when no changes are required" do
      run_job
      expect(users_stub).to have_been_requested
    end

    it "updates username and status when required" do
      DiscourseCalendar.users_on_holiday = [discourse_user.username]
      username_change = stub_request(:put, "https://chat.example.com/api/v4/users/userid/patch").
        with(body: { username: "david-v" }.to_json)

      status_change = stub_request(:put, "https://chat.example.com/api/v4/users/userid/status/custom").
        with(body: {
          emoji: SiteSetting.discourse_mattermost_holiday_status_emoji,
          text: SiteSetting.discourse_mattermost_holiday_status_text
          }.to_json
        )

      run_job
      expect(users_stub).to have_been_requested
      expect(username_change).to have_been_requested
      expect(status_change).to have_been_requested
    end

    it "does not attempt changes when already correct" do
      DiscourseCalendar.users_on_holiday = [discourse_user.username]
      users_body_data[0][:username] = "david-v"
      users_body_data[0][:props][:customStatus] = {
        emoji: SiteSetting.discourse_mattermost_holiday_status_emoji,
        text: SiteSetting.discourse_mattermost_holiday_status_text
      }.to_json

      run_job
      expect(users_stub).to have_been_requested
    end

    it "resets user when no longer on vacation" do
      DiscourseCalendar.users_on_holiday = []
      users_body_data[0][:username] = "david-v"
      users_body_data[0][:props][:customStatus] = {
        emoji: SiteSetting.discourse_mattermost_holiday_status_emoji,
        text: SiteSetting.discourse_mattermost_holiday_status_text
      }.to_json

      username_change = stub_request(:put, "https://chat.example.com/api/v4/users/userid/patch").
        with(body: { username: "david" }.to_json)

      status_change = stub_request(:delete, "https://chat.example.com/api/v4/users/userid/status/custom")

      run_job
      expect(users_stub).to have_been_requested
      expect(username_change).to have_been_requested
      expect(status_change).to have_been_requested
    end
  end
end
