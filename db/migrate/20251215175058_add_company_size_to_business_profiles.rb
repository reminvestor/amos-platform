class AddCompanySizeToBusinessProfiles < ActiveRecord::Migration[8.0]
  def change
    add_column :business_profiles, :company_size, :string
  end
end
