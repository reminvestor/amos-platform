module Tools
  class TextStatsTool < BaseTool
    def self.metadata
      {
        name: "text_stats",
        description: "Analyzes text and returns statistics like word count, character count, and reading time.",
        category: "utility",
        input_schema: {
          type: "object",
          properties: {
            text: { type: "string", description: "The text to analyze" }
          },
          required: ["text"]
        }
      }
    end

    def execute(args)
      log_execution(args)
      
      text = get_arg(args, :text)
      return error_response("Missing 'text' parameter") if text.blank?

      word_count = text.split.size
      char_count = text.length
      # Simple sentence splitting
      sentence_count = text.split(/[.!?]+/).size
      # Avg reading speed ~200 wpm
      reading_time_seconds = (word_count / 200.0 * 60).round

      success_response(
        stats: {
          words: word_count,
          characters: char_count,
          sentences: sentence_count,
          estimated_reading_time_seconds: reading_time_seconds
        }
      )
    end
  end
end

