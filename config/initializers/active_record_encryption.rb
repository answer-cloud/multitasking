# frozen_string_literal: true

# Keys for Active Record encryption (`encrypts`), which keeps third-party
# tokens — a Slack user token can read that person's messages — unreadable in
# the database and in backups.
#
# Credentials win when they carry `active_record_encryption`. Without them the
# keys are derived from secret_key_base, so every environment works with no
# extra secret to hold. Rotating secret_key_base then makes stored tokens
# unreadable; people reconnect, and nothing else is lost.
Rails.application.configure do
  next if credentials.active_record_encryption.present?

  derive = ->(purpose) { key_generator.generate_key("active_record_encryption.#{purpose}", 32).unpack1("H*") }

  config.active_record.encryption.primary_key = derive.call(:primary_key)
  config.active_record.encryption.deterministic_key = derive.call(:deterministic_key)
  config.active_record.encryption.key_derivation_salt = derive.call(:key_derivation_salt)
end
