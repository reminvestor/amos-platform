class AuthConfig < ApplicationRecord
  belongs_to :oauth_configuration

  # Validations
  validates :auth_key, presence: true
  validates :auth_placement, presence: true, inclusion: { in: %w[header query url] }

  # Scopes
  default_scope -> { order(position: :asc) }
  scope :headers, -> { where(auth_placement: 'header') }
  scope :query_params, -> { where(auth_placement: 'query') }
  scope :url_params, -> { where(auth_placement: 'url') }

  # Examples of auth_key and auth_value:
  # Header: auth_key="Authorization", auth_value="Bearer {token}"
  # Header: auth_key="X-API-Key", auth_value="{api_key}"
  # Query:  auth_key="apikey", auth_value="{token}"
  # URL:    auth_key="account_id", auth_value="{account_id}"
end
