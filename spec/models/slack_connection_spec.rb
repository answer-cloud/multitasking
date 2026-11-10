# frozen_string_literal: true

require "rails_helper"

RSpec.describe SlackConnection do
  describe ".message_in" do
    it "reads the channel and timestamp from a message's link" do
      expect(described_class.message_in("https://acme.slack.com/archives/C0B6AG209MX/p1794264664849189"))
        .to eq(channel: "C0B6AG209MX", ts: "1794264664.849189", thread_ts: nil)
    end

    it "reads the thread from a reply's link" do
      link = "https://acme.slack.com/archives/C0B6AG209MX/p1794264664849189?thread_ts=1794004859.175909&cid=C0B6AG209MX"

      expect(described_class.message_in(" #{link} ")).to eq(channel: "C0B6AG209MX", ts: "1794264664.849189", thread_ts: "1794004859.175909")
    end

    it "reads an Enterprise Grid workspace's link" do
      expect(described_class.message_in("https://acme.enterprise.slack.com/archives/C1/p1794264664849189")).to include(channel: "C1")
    end

    it "ignores a thread timestamp that is not one" do
      expect(described_class.message_in("https://acme.slack.com/archives/C1/p1794264664849189?thread_ts=x")[:thread_ts]).to be_nil
    end

    it "ignores anything that is not a Slack message link" do
      [ "Send the contract", "https://slack.com.evil.example/archives/C1/p1794264664849189",
        "http://acme.slack.com/archives/C1/p1794264664849189", "https://acme.slack.com/archives/C1",
        "See https://acme.slack.com/archives/C1/p1794264664849189" ].each do |text|
        expect(described_class.message_in(text)).to be_nil, text
      end
    end
  end
end
