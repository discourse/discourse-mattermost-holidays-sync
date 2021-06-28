# frozen_string_literal: true

module Jobs
  class UpdateMattermostUsernames < ::Jobs::Scheduled
    every 10.minutes

    def execute(args)
      api_key = SiteSetting.discourse_mattermost_api_key
      server = SiteSetting.discourse_mattermost_server
      users_on_holiday = ::DiscourseCalendar.users_on_holiday

      return if api_key.blank? || server.blank?

      headers = {
        "Authorization": "Bearer #{api_key}"
      }

      # Fetch all mattermost users
      mattermost_users = []
      params = { per_page: 200, page: 0 }
      loop do
        response = Excon.get("#{server}/api/v4/users?#{params.to_query}", headers: headers)
        this_page_users = JSON.parse(response.body, symbolize_names: true)
        mattermost_users += this_page_users
        break if this_page_users.length < params[:per_page]
        params[:page] += 1
      end

      # Loop over mattermost users
      mattermost_users.each do |user|
        discourse_user = User.find_by_email(user[:email])

        next unless discourse_user
        discourse_username = discourse_user.username

        on_holiday = users_on_holiday.include?(discourse_username)

        if SiteSetting.discourse_mattermost_suffix_usernames
          mattermost_username = user[:username]
          username_on_holiday = !!mattermost_username.chomp!("-v")

          update_username = false
          if on_holiday && !username_on_holiday
            update_username = "#{mattermost_username}-v"
          elsif !on_holiday && username_on_holiday
            update_username = mattermost_username
          end

          if update_username
            # puts "Update #{mattermost_username} to #{update_username}"
            Excon.put("#{server}/api/v4/users/#{user[:id]}/patch",
              headers: headers,
              body: { username: update_username }.to_json
            )
          end
        end

        if SiteSetting.discourse_mattermost_set_status
          status_json = user.dig(:props, :customStatus)
          status_data = status_json.present? ? JSON.parse(status_json, symbolize_names: true) : nil
          status_emoji = status_data&.[](:emoji)
          status_on_holiday = status_data&.[](:emoji) == SiteSetting.discourse_mattermost_holiday_status_emoji
          purge_unknown_status = SiteSetting.discourse_mattermost_holiday_status_exclusive

          if on_holiday && !status_on_holiday
            Excon.put("#{server}/api/v4/users/#{user[:id]}/status/custom",
              headers: headers,
              body: {
                emoji: SiteSetting.discourse_mattermost_holiday_status_emoji,
                text: SiteSetting.discourse_mattermost_holiday_status_text
              }.to_json
            )
          elsif !on_holiday && (status_on_holiday || (purge_unknown_status && status_emoji))
            Excon.delete("#{server}/api/v4/users/#{user[:id]}/status/custom", headers: headers)
          end
        end
      end
    end

  end
end
