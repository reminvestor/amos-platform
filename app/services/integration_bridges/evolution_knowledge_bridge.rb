# frozen_string_literal: true

module IntegrationBridges
  # EvolutionKnowledgeBridge - Archives bug fixes to Global Knowledge Archive
  #
  # When the Platform Evolution Engine successfully fixes a bug and the PR is merged,
  # this bridge ensures the learning is preserved for future reference.
  #
  class EvolutionKnowledgeBridge
    attr_reader :pull_request

    def initialize(pull_request)
      @pull_request = pull_request
    end

    # Archive the learning from a merged PR
    def archive_learning!
      return unless should_archive?

      code_fix = pull_request.code_fix
      debug_session = code_fix&.debug_session
      ticket = debug_session&.support_ticket

      archive = GlobalKnowledgeArchive.create!(
        entity: ticket&.entity,
        title: build_title(ticket),
        knowledge_type: 'lesson_learned',
        source_type: 'evolution_learning',
        source_agent_slug: 'platform_evolution_engine',
        content: build_content(ticket, debug_session, code_fix),
        applicable_domains: extract_domains(code_fix),
        applicable_capabilities: extract_capabilities(code_fix),
        utility_score: 0.7,  # Start with moderate utility
        context: build_context(ticket, debug_session, code_fix)
      )

      Rails.logger.info "[EvolutionKnowledgeBridge] Archived learning: #{archive.title}"
      archive
    rescue => e
      Rails.logger.warn "[EvolutionKnowledgeBridge] Failed to archive: #{e.message}"
      nil
    end

    # Process all merged PRs that haven't been archived
    def self.process_unarchived_prs
      PullRequestSubmission.where(status: 'merged')
        .where("metadata->>'archived' IS NULL OR metadata->>'archived' = 'false'")
        .find_each do |pr|
          bridge = new(pr)
          if bridge.archive_learning!
            pr.update!(metadata: (pr.metadata || {}).merge(archived: true))
          end
        end
    end

    private

    def should_archive?
      return false unless pull_request.status == 'merged'
      return false if already_archived?
      return false unless pull_request.code_fix.present?
      
      true
    end

    def already_archived?
      pull_request.metadata&.dig('archived') == true
    end

    def build_title(ticket)
      if ticket&.title.present?
        "Fix: #{ticket.title.truncate(80)}"
      else
        "Platform Evolution Fix ##{pull_request.id}"
      end
    end

    def build_content(ticket, debug_session, code_fix)
      {
        error_type: ticket&.error_type,
        error_message: ticket&.description&.truncate(500),
        root_cause: debug_session&.root_cause,
        solution_approach: debug_session&.proposed_solution,
        files_changed: code_fix&.files_changed,
        fix_summary: code_fix&.description,
        test_results: code_fix&.test_results,
        key_insights: extract_insights(debug_session, code_fix)
      }
    end

    def extract_insights(debug_session, code_fix)
      insights = []
      
      if debug_session&.analysis_log.present?
        # Extract key learnings from analysis
        analysis = debug_session.analysis_log
        insights << analysis['key_insight'] if analysis['key_insight'].present?
        insights += analysis['learnings'] if analysis['learnings'].is_a?(Array)
      end
      
      if code_fix&.metadata.present?
        # Extract any documented patterns
        metadata = code_fix.metadata
        insights << metadata['pattern_identified'] if metadata['pattern_identified'].present?
      end
      
      insights.compact.uniq
    end

    def extract_domains(code_fix)
      return [] unless code_fix&.files_changed.present?
      
      domains = []
      files = code_fix.files_changed
      
      files.each do |file|
        case file
        when /services\/agents/
          domains << 'agent_execution'
        when /services\/tools/
          domains << 'tool_development'
        when /services\/living_platform/
          domains << 'autonomous_systems'
        when /services\/platform_evolution/
          domains << 'self_healing'
        when /models/
          domains << 'data_modeling'
        when /controllers/
          domains << 'api_development'
        end
      end
      
      domains.uniq
    end

    def extract_capabilities(code_fix)
      return [] unless code_fix&.files_changed.present?
      
      capabilities = []
      
      # Infer capabilities from files touched
      code_fix.files_changed.each do |file|
        if match = file.match(/services\/tools\/(\w+)_tool\.rb/)
          capabilities << match[1]
        end
        if match = file.match(/services\/(\w+)_service\.rb/)
          capabilities << match[1]
        end
      end
      
      capabilities.uniq.first(5)
    end

    def build_context(ticket, debug_session, code_fix)
      {
        ticket_id: ticket&.id,
        ticket_number: ticket&.ticket_number,
        debug_session_id: debug_session&.id,
        code_fix_id: code_fix&.id,
        pr_id: pull_request.id,
        pr_url: pull_request.pr_url,
        merged_at: pull_request.merged_at,
        fix_confidence: debug_session&.confidence_score
      }.compact
    end
  end
end


