# frozen_string_literal: true

class AddWorkTrackingToBounties < ActiveRecord::Migration[7.1]
  def change
    # Work evidence - what the contributor actually did
    add_column :bounties, :pr_url, :string
    add_column :bounties, :pr_number, :integer
    add_column :bounties, :commit_sha, :string
    add_column :bounties, :branch_name, :string
    add_column :bounties, :repo_url, :string

    # External work (for non-code bounties)
    add_column :bounties, :work_url, :string           # Link to blog post, design, etc.
    add_column :bounties, :work_artifacts, :jsonb, default: []  # Array of {url, type, description}

    # Link to existing PR submission if applicable
    add_reference :bounties, :pull_request_submission, foreign_key: true, null: true

    # Indexes
    add_index :bounties, :pr_number
    add_index :bounties, :commit_sha
  end
end
