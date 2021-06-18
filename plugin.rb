# frozen_string_literal: true
# name: discourse-mattermost-holidays-sync
# about: Updated mattermost usernames with `-v` for users on holiday
# version: 0.1
# author: David Taylor
# url: https://github.com/discourse/discourse-mattermost-holidays-sync

after_initialize do
  require File.expand_path("../jobs/scheduled/update_mattermost_usernames", __FILE__)
end
