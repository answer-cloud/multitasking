# frozen_string_literal: true

module ApplicationCable
  # Only signed-in people get a socket. The dashboard's live list streams are
  # signed per team, so this is the second lock, not the only one.
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    def connect
      self.current_user = env["warden"]&.user || reject_unauthorized_connection
    end
  end
end
