class PipelineArtifact < ApplicationRecord
  # Relationships
  belongs_to :pipeline_execution
  belongs_to :agent_execution, optional: true

  # Validations
  validates :artifact_type, presence: true
  validates :file_name, presence: true

  # Enums for artifact types
  ARTIFACT_TYPES = %w[
    plan
    test_spec
    acceptance_tests
    architecture_diagram
    review_report
    code
    test_report
    coverage_report
    screenshot
    video
    performance_metrics
    security_scan
    build_log
    clarifications
  ].freeze

  validates :artifact_type, inclusion: { in: ARTIFACT_TYPES }

  # Scopes
  scope :by_type, ->(type) { where(artifact_type: type) }
  scope :with_content, -> { where.not(content: nil) }
  scope :with_storage_path, -> { where.not(storage_path: nil) }
  scope :recent, -> { order(created_at: :desc) }

  # Callbacks
  after_initialize :set_defaults, if: :new_record?

  # Check if stored inline vs S3
  def inline_content?
    content.present?
  end

  def s3_stored?
    storage_path.present?
  end

  # Get content (from inline or S3)
  def get_content
    return content if inline_content?
    return fetch_from_s3 if s3_stored?
    nil
  end

  # Store content (inline if small, S3 if large)
  def store_content(data)
    if data.bytesize < 10.megabytes
      self.content = data
      self.file_size = data.bytesize
    else
      upload_to_s3(data)
      self.file_size = data.bytesize
    end
    save!
  end

  # Human-readable artifact type
  def type_label
    artifact_type.titleize
  end

  # File size in human-readable format
  def file_size_human
    return 'N/A' unless file_size

    if file_size < 1.kilobyte
      "#{file_size} B"
    elsif file_size < 1.megabyte
      "#{(file_size / 1.kilobyte).round(1)} KB"
    else
      "#{(file_size / 1.megabyte).round(1)} MB"
    end
  end

  private

  def set_defaults
    self.file_size ||= 0
    self.metadata ||= {}
  end

  def fetch_from_s3
    return nil unless ENV['AWS_S3_BUCKET'].present?
    return nil unless storage_path.present?

    require 'aws-sdk-s3'

    s3_client = Aws::S3::Client.new(
      region: ENV['AWS_REGION'] || 'us-east-1',
      access_key_id: ENV['AWS_ACCESS_KEY_ID'],
      secret_access_key: ENV['AWS_SECRET_ACCESS_KEY']
    )

    response = s3_client.get_object(
      bucket: ENV['AWS_S3_BUCKET'],
      key: storage_path
    )

    response.body.read
  rescue Aws::S3::Errors::ServiceError => e
    Rails.logger.error "Failed to fetch from S3: #{e.message}"
    nil
  end

  def upload_to_s3(data)
    unless ENV['AWS_S3_BUCKET'].present?
      Rails.logger.warn "AWS_S3_BUCKET not configured - storing inline instead"
      self.content = data
      return
    end

    require 'aws-sdk-s3'

    bucket = ENV['AWS_S3_BUCKET']
    key = "pipeline-artifacts/#{pipeline_execution_id}/#{SecureRandom.hex(8)}/#{file_name}"

    s3_client = Aws::S3::Client.new(
      region: ENV['AWS_REGION'] || 'us-east-1',
      access_key_id: ENV['AWS_ACCESS_KEY_ID'],
      secret_access_key: ENV['AWS_SECRET_ACCESS_KEY']
    )

    s3_client.put_object(
      bucket: bucket,
      key: key,
      body: data,
      content_type: content_type_for_file(file_name)
    )

    self.storage_path = key
    Rails.logger.info "Uploaded artifact to S3: s3://#{bucket}/#{key}"
  rescue Aws::S3::Errors::ServiceError => e
    Rails.logger.error "Failed to upload to S3: #{e.message}"
    # Fallback to inline storage
    self.content = data
  end

  def content_type_for_file(filename)
    case File.extname(filename).downcase
    when '.json' then 'application/json'
    when '.txt', '.md' then 'text/plain'
    when '.html' then 'text/html'
    when '.xml' then 'application/xml'
    when '.yaml', '.yml' then 'application/x-yaml'
    when '.png' then 'image/png'
    when '.jpg', '.jpeg' then 'image/jpeg'
    when '.pdf' then 'application/pdf'
    else 'application/octet-stream'
    end
  end
end
