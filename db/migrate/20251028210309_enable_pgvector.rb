class EnablePgvector < ActiveRecord::Migration[8.0]
  def change
    # Enable pgvector extension
    enable_extension 'vector'
    
    # Log success
    puts "✅ pgvector extension enabled!"
    puts "You can now use vector columns in your database"
    puts "Example: add_column :documents, :embedding, :vector, limit: 1536"
  end
end
