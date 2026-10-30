# frozen_string_literal: true

module Public
  # The hook script, for the connection page's install command to curl. Public
  # because curl has no session, and the script holds no secrets: it reads the
  # token from the user's own config file.
  class HooksController < BaseController
    def show
      send_file Rails.root.join("script/agent-hook"), type: "text/plain; charset=utf-8", disposition: "inline"
    end
  end
end
