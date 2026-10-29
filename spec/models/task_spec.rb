# frozen_string_literal: true

require "rails_helper"

RSpec.describe Task do
  describe "validations" do
    it "needs a title" do
      expect(build(:task, title: "")).not_to be_valid
    end

    it "accepts only known sources" do
      expect(build(:task, source: "carrier-pigeon")).not_to be_valid
    end

    # A url is rendered as a link, so anything other than http(s) — a
    # javascript: url above all — must never be saved.
    it "accepts only http and https links" do
      expect(build(:task, url: "https://example.com")).to be_valid
      expect(build(:task, url: "javascript:alert(1)")).not_to be_valid
    end
  end

  describe "quiet" do
    it "is quiet once nobody has touched it for a while" do
      expect(build(:task, last_activity_at: 3.days.ago)).to be_quiet
      expect(build(:task, last_activity_at: 1.hour.ago)).not_to be_quiet
    end

    it "is never quiet once it is done" do
      expect(build(:task, :done, last_activity_at: 1.month.ago)).not_to be_quiet
    end
  end

  describe "finishing and reopening" do
    let(:task) { create(:task, :quiet) }

    it "records when it was finished" do
      task.complete!

      expect(task.completed_at).to be_within(1.second).of(Time.current)
    end

    it "comes back fresh when reopened" do
      task.complete!
      task.reopen!

      expect(task).not_to be_done
      expect(task).not_to be_quiet
    end
  end
end
