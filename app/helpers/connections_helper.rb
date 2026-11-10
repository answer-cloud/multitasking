# frozen_string_literal: true

module ConnectionsHelper
  # The save-this-tab bookmarklet. It opens TasksController#new in a new tab
  # with the page's title and address, and the person saves it from there.
  #
  # It sends nothing itself: the form on our side carries the CSRF token and
  # the sign-in, so the bookmarklet needs no inbox token and a page it runs on
  # learns nothing about us. `noopener` stops our page reaching back into theirs.
  def tab_bookmarklet
    "javascript:(()=>{window.open(#{new_task_url.to_json}+'?'+new URLSearchParams(" \
      "{title:document.title,url:location.href}),'_blank','noopener')})()"
  end

  # The Slack app, as a manifest an admin pastes into api.slack.com, with this
  # server's own addresses filled in. It asks only for user scopes: Done acts
  # as each person who connects, never as a bot in their channels.
  def slack_manifest
    {
      "display_information" => { "name" => app_name, "description" => "Pin a message with 📌 and it lands on your list." },
      "oauth_config" => {
        "redirect_urls" => [ callback_slack_connection_url ],
        "scopes" => { "user" => Slack::ConnectionsController::USER_SCOPES }
      },
      "settings" => {
        "event_subscriptions" => { "request_url" => slack_events_url, "user_events" => [ "reaction_added" ] },
        "org_deploy_enabled" => false,
        "socket_mode_enabled" => false,
        "token_rotation_enabled" => false
      }
    }.to_yaml.delete_prefix("---\n")
  end
end
