class OAuthConfiguration < ApplicationRecord
  belongs_to :entity
  belongs_to :integration
end
