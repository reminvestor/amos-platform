class AddOnboardingTrackingToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :onboarding_step, :string
    add_column :users, :onboarding_started_at, :datetime
    add_column :users, :onboarding_completed_at, :datetime
  end
end
