module Jobs
  class UpdateMattermostUsernames < Jobs::Scheduled
    every 10.minutes

    def execute(args)
      api_key = SiteSetting.discourse_mattermost_api_key
      server = SiteSetting.discourse_mattermost_server
      users_on_holiday = ::DiscourseCalendar.users_on_holiday

      return if api_key.blank? || server.blank?

      # Fetch all mattermost users
      response = Excon.get("#{server}/api/v4/users", headers: {
        "Authorization": "Bearer #{api_key}"
      })
      mattermost_users = JSON.parse(response.body, symbolize_names: true)

      # Loop over mattermost users
      mattermost_users.each do |user|
        mattermost_username = user[:username]
        marked_on_holiday = !!mattermost_username.chomp!("-v")

        discourse_user = User.find_by_email(user[:email])
        next unless discourse_user
        discourse_username = discourse_user.username

        on_holiday = users_on_holiday.include?(discourse_username)

        update_username = false
        if on_holiday && !marked_on_holiday
          update_username = "#{mattermost_username}-v"
        elsif !on_holiday && marked_on_holiday
          update_username = mattermost_username
        end

        if update_username
          # puts "Update #{mattermost_username} to #{update_username}"
          Excon.put("#{server}/api/v4/users/#{user[:id]}/patch", headers: {
            "Authorization": "Bearer #{api_key}"
          }, body: {
            username: update_username
          }.to_json)
        end

      end

    end

  end
end
