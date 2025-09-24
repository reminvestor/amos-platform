# Legacy compatibility - redirect to new AmosAI module
require_relative 'amos_ai'

# Aliases for backward compatibility during deployment
# Zeitwerk expects ScoutAi (not ScoutAI) based on the filename scout_ai.rb
ScoutAi = AmosAI
ScoutAI = AmosAI