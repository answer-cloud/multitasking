# frozen_string_literal: true

module Public
  # The skill that teaches Claude Code to assign a task, for the connection
  # page's install command to curl. Public for the same reason as the hook:
  # curl has no session, and the file holds no secrets.
  class SkillsController < BaseController
    def show
      send_file Rails.root.join("script/assign-skill.md"), type: "text/markdown; charset=utf-8", disposition: "inline"
    end
  end
end
