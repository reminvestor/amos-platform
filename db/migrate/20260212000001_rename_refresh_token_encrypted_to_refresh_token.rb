class RenameRefreshTokenEncryptedToRefreshToken < ActiveRecord::Migration[8.0]
  def change
    # The model uses `encrypts :refresh_token` which expects a `refresh_token` column,
    # but the original migration created `refresh_token_encrypted`.
    # Rails encrypts handles encryption transparently on the `refresh_token` column.
    rename_column :users, :refresh_token_encrypted, :refresh_token
  end
end
