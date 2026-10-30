# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: projects
#
#  id            :bigint           not null, primary key
#  aliases       :string           default([]), not null, is an Array
#  color         :string
#  directory     :string
#  name          :string           not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  created_by_id :bigint
#  team_id       :bigint           not null
#
# Indexes
#
#  index_projects_on_created_by_id          (created_by_id)
#  index_projects_on_team_id                (team_id)
#  index_projects_on_team_id_and_directory  (team_id,directory) UNIQUE WHERE (directory IS NOT NULL)
#  index_projects_on_team_id_and_name       (team_id,name)
#
# Foreign Keys
#
#  fk_rails_...  (created_by_id => users.id)
#  fk_rails_...  (team_id => teams.id)
#
RSpec.describe Project do
  let(:team) { create(:team) }

  describe "the folder" do
    it "forgets a trailing slash, so the same folder is always written the same way" do
      expect(create(:project, team: team, directory: " /code/app/ ").directory).to eq("/code/app")
    end

    it "keeps a blank folder as no folder" do
      expect(create(:project, team: team, directory: "").directory).to be_nil
    end

    # The hook sends absolute paths, so a path starting with ~ could never match.
    it "refuses a path that is not a full one" do
      expect(build(:project, team: team, directory: "~/code/app")).not_to be_valid
    end

    it "belongs to one project per team" do
      create(:project, team: team, directory: "/code/app")

      expect(build(:project, team: team, directory: "/code/app")).not_to be_valid
      expect(build(:project, directory: "/code/app")).to be_valid
    end
  end

  describe "the colour" do
    it "comes from the palette even when nobody picked one, as for a project an agent made" do
      project = create(:project, team: team)

      expect(project.read_attribute(:color)).to be_nil
      expect(Project::COLORS).to include(project.color)
    end

    it "keeps the one somebody picked" do
      expect(create(:project, team: team, color: "leaf").reload.color).to eq("leaf")
    end

    # The colour becomes part of a class name in the markup.
    it "refuses anything outside the palette" do
      expect(build(:project, team: team, color: "red\" onclick=\"x")).not_to be_valid
    end
  end

  describe "the other names" do
    it "reads a comma-separated list, dropping blanks and repeats" do
      project = build(:project, alias_list: " Slater ,, Slater Sweet, slater ")

      expect(project.aliases).to eq([ "Slater", "Slater Sweet" ])
      expect(project.alias_list).to eq("Slater, Slater Sweet")
    end

    it "refuses a name longer than a project name may be" do
      expect(build(:project, aliases: [ "x" * 121 ])).not_to be_valid
    end

    it "refuses more than twenty" do
      expect(build(:project, aliases: (1..21).map { |n| "Name #{n}" })).not_to be_valid
    end
  end

  describe "finding the project for a folder" do
    let!(:code) { create(:project, team: team, directory: "/code") }
    let!(:app) { create(:project, team: team, directory: "/code/app") }

    it "matches the folder itself" do
      expect(team.projects.for_directory("/code/app")).to eq(app)
    end

    it "matches the nearest folder above, so a subfolder lands in its repository's project" do
      expect(team.projects.for_directory("/code/app/lib/tasks")).to eq(app)
    end

    # "/code/app" is not above "/code/apple": the match is on whole folders.
    it "does not match a folder that only starts with the same letters" do
      expect(team.projects.for_directory("/code/apple")).to eq(code)
    end

    it "never matches another team's project" do
      other = create(:project, directory: "/elsewhere")

      expect(team.projects.for_directory("/elsewhere")).to be_nil
      expect(other.team.projects.for_directory("/elsewhere")).to eq(other)
    end
  end

  describe "claiming a folder for an agent's task" do
    it "makes a project named after the folder the first time" do
      project = team.projects.claim_directory("/Users/you/code/storefront")

      expect(project).to be_persisted
      expect(project.name).to eq("storefront")
      expect(project.team).to eq(team)
    end

    it "reuses the project the second time" do
      first = team.projects.claim_directory("/code/storefront")

      expect(team.projects.claim_directory("/code/storefront/")).to eq(first)
      expect(team.projects.count).to eq(1)
    end

    it "adopts a project somebody made by hand with the folder's name" do
      by_hand = create(:project, team: team, name: "Storefront")

      expect(team.projects.claim_directory("/code/storefront")).to eq(by_hand)
      expect(by_hand.reload.directory).to eq("/code/storefront")
    end

    it "claims nothing when there is no folder" do
      expect(team.projects.claim_directory(nil)).to be_nil
      expect(team.projects.claim_directory(" ")).to be_nil
    end

    it "claims nothing, rather than failing, when the folder is not a full path" do
      expect(team.projects.claim_directory("code/storefront")).to be_nil
      expect(team.projects.count).to eq(0)
    end
  end

  describe "deleting" do
    it "keeps its tasks, unfiled" do
      project = create(:project, team: team)
      task = create(:task, team: team, project: project)

      project.destroy!

      expect(task.reload.project).to be_nil
    end
  end
end
