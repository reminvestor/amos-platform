# app/jobs/ocr_comparison_job.rb
class OcrComparisonJob < ApplicationJob
  queue_as :low_priority

  def perform(entity_id, file_path, options = {})
    entity = Entity.find(entity_id)
    service = Ocr::DualModeService.new(entity)

    Rails.logger.info "Running OCR shadow mode comparison for #{File.basename(file_path)}"

    # Run comparison
    comparison_result = service.compare_providers(file_path, options)

    # Store comparison results for analysis
    store_comparison_results(entity, file_path, comparison_result)

    # Log metrics
    log_comparison_metrics(comparison_result)

    comparison_result
  rescue StandardError => e
    Rails.logger.error "OCR comparison failed: #{e.message}"
    # Don't retry - this is just for testing/analysis
  end

  private

  def store_comparison_results(entity, file_path, comparison)
    # Store in a comparison tracking table (would need migration)
    # For now, just log to a file or Rails cache
    cache_key = "ocr_comparison:#{entity.id}:#{Digest::MD5.hexdigest(file_path)}"

    Rails.cache.write(
      cache_key,
      {
        file_path: file_path,
        entity_id: entity.id,
        comparison: comparison,
        timestamp: Time.current
      },
      expires_in: 7.days
    )

    # Also log key metrics
    Rails.logger.info "OCR Comparison Results:"
    Rails.logger.info "  File: #{File.basename(file_path)}"
    Rails.logger.info "  Textract time: #{comparison[:timings][:textract]}s"
    Rails.logger.info "  Docling time: #{comparison[:timings][:docling]}s"
    Rails.logger.info "  Text similarity: #{comparison[:similarity]}"
    Rails.logger.info "  Recommendation: #{comparison[:recommendation]}"
  end

  def log_comparison_metrics(comparison)
    # Log to observability system
    return unless defined?(ObservabilityEvent)

    ObservabilityEvent.create!(
      event_type: 'ocr_comparison',
      metadata: {
        textract_time_seconds: comparison[:timings][:textract],
        docling_time_seconds: comparison[:timings][:docling],
        similarity_score: comparison[:similarity],
        textract_success: !comparison[:results][:textract]&.dig(:error),
        docling_success: !comparison[:results][:docling]&.dig(:error),
        recommendation: comparison[:recommendation]
      }
    )
  rescue => e
    Rails.logger.warn "Failed to log OCR comparison metrics: #{e.message}"
  end
end