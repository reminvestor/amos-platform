module AiAgents::Pipeline
  class WorkspaceManager
    attr_reader :pipeline_execution, :agent_id

    BASE_PATH = ENV.fetch('PIPELINE_WORKSPACE_PATH', '/tmp/pipeline-workspaces')

    def initialize(pipeline_execution, agent_id)
      @pipeline_execution = pipeline_execution
      @agent_id = agent_id
    end

    # Create isolated workspace for agent
    def create_workspace!
      workspace_path = generate_workspace_path

      FileUtils.mkdir_p(workspace_path, mode: 0700)
      Rails.logger.info "🏗️  Created workspace: #{workspace_path}"

      workspace_path
    rescue => e
      Rails.logger.error "Failed to create workspace: #{e.message}"
      raise
    end

    # Clean up workspace after agent completes
    def cleanup_workspace!
      workspace_path = generate_workspace_path

      if File.directory?(workspace_path)
        FileUtils.rm_rf(workspace_path)
        Rails.logger.info "🧹 Cleaned up workspace: #{workspace_path}"
      end
    rescue => e
      Rails.logger.error "Failed to cleanup workspace: #{e.message}"
      # Don't raise - cleanup failures shouldn't break the pipeline
    end

    # Get workspace path
    def workspace_path
      generate_workspace_path
    end

    # Check if workspace exists
    def workspace_exists?
      File.directory?(workspace_path)
    end

    # Clone repository into workspace
    def clone_repository(git_connection, repository, branch = nil)
      workspace = workspace_path
      clone_path = File.join(workspace, 'repo')

      client = git_connection.client
      result = client.clone_repository(repository, clone_path, branch: branch)

      if result[:success]
        Rails.logger.info "✅ Cloned repository #{repository} to #{clone_path}"
        clone_path
      else
        raise "Failed to clone repository: #{result[:error]}"
      end
    end

    # Create a new branch in the cloned repository
    def create_branch(repo_path, branch_name)
      Dir.chdir(repo_path) do
        `git checkout -b #{branch_name}`
        raise "Failed to create branch" unless $?.success?
      end

      Rails.logger.info "🌿 Created branch: #{branch_name}"
      true
    end

    # Commit changes in workspace
    def commit_changes(repo_path, message)
      Dir.chdir(repo_path) do
        `git add .`
        `git commit -m #{Shellwords.escape(message)}`
        raise "Failed to commit changes" unless $?.success?
      end

      Rails.logger.info "💾 Committed changes: #{message}"
      true
    end

    # Push branch to remote
    def push_branch(repo_path, branch_name)
      Dir.chdir(repo_path) do
        `git push origin #{branch_name}`
        raise "Failed to push branch" unless $?.success?
      end

      Rails.logger.info "🚀 Pushed branch: #{branch_name}"
      true
    end

    # Write content to file in workspace
    def write_file(filename, content)
      file_path = File.join(workspace_path, filename)
      FileUtils.mkdir_p(File.dirname(file_path))
      File.write(file_path, content)

      Rails.logger.info "📝 Wrote file: #{filename}"
      file_path
    end

    # Read file from workspace
    def read_file(filename)
      file_path = File.join(workspace_path, filename)
      return nil unless File.exist?(file_path)

      File.read(file_path)
    end

    # List files in workspace
    def list_files(pattern = '*')
      Dir.glob(File.join(workspace_path, pattern))
    end

    # Get workspace size
    def workspace_size
      return 0 unless workspace_exists?

      total_size = 0
      Find.find(workspace_path) do |file|
        total_size += File.size(file) if File.file?(file)
      end
      total_size
    end

    # Human-readable workspace size
    def workspace_size_human
      size = workspace_size
      if size < 1.kilobyte
        "#{size} B"
      elsif size < 1.megabyte
        "#{(size / 1.kilobyte).round(1)} KB"
      else
        "#{(size / 1.megabyte).round(1)} MB"
      end
    end

    # Class method: Cleanup all old workspaces
    def self.cleanup_old_workspaces!(older_than: 24.hours)
      return unless File.directory?(BASE_PATH)

      cutoff_time = older_than.ago
      cleanup_count = 0

      Dir.glob(File.join(BASE_PATH, '*')).each do |workspace_dir|
        next unless File.directory?(workspace_dir)

        # Check if workspace is old enough
        if File.mtime(workspace_dir) < cutoff_time
          FileUtils.rm_rf(workspace_dir)
          cleanup_count += 1
          Rails.logger.info "🧹 Cleaned up old workspace: #{workspace_dir}"
        end
      end

      Rails.logger.info "✅ Cleaned up #{cleanup_count} old workspaces"
      cleanup_count
    rescue => e
      Rails.logger.error "Failed to cleanup old workspaces: #{e.message}"
      0
    end

    # Class method: Get total disk usage of all workspaces
    def self.total_disk_usage
      return 0 unless File.directory?(BASE_PATH)

      total = 0
      Dir.glob(File.join(BASE_PATH, '*')).each do |workspace_dir|
        Find.find(workspace_dir) do |file|
          total += File.size(file) if File.file?(file)
        end
      end
      total
    end

    private

    def generate_workspace_path
      File.join(BASE_PATH, "#{pipeline_execution.id}-#{agent_id}")
    end
  end
end
