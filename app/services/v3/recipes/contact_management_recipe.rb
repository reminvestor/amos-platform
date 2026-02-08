# frozen_string_literal: true

module V3
  module Recipes
    # ContactManagementRecipe - Create, update, import, group, and tag contacts
    #
    # Handles all contact-related operations including:
    # - Single contact creation
    # - Bulk contact creation/import
    # - Contact group creation + adding contacts
    # - Contact updates
    #
    class ContactManagementRecipe < Base
      CONTACT_PATTERNS = [
        /\bcreate\s+(a\s+)?contact/,
        /\badd\s+(a\s+)?(new\s+)?contact/,
        /\bimport\s+contacts?/,
        /\bnew\s+contact/,
        /\bcreate\s+(a\s+)?contact\s*group/,
        /\badd\s+(contacts?\s+to|to\s+).*group/,
        /\bcreate\s+group/,
        /\bnew\s+group/,
      ].freeze

      def self.matches?(goal, spec = {})
        CONTACT_PATTERNS.any? { |p| goal.match?(p) }
      end

      def self.priority
        10
      end

      def execute(spec:)
        goal_lower = (context[:original_goal] || "").downcase

        if goal_lower.match?(/group/)
          create_contact_group(spec)
        elsif goal_lower.match?(/import|bulk/) || spec_val(spec, :contacts).is_a?(Array)
          bulk_create_contacts(spec)
        else
          create_single_contact(spec)
        end
      end

      private

      def create_single_contact(spec)
        # Pass through to existing PlatformCreateTool
        data = extract_contact_data(spec)
        platform_create(type: "contact", data: data)
      end

      def bulk_create_contacts(spec)
        contacts = spec_val(spec, :contacts, [])
        return error_response("No contacts provided. Include a 'contacts' array.") if contacts.empty?

        results = []
        contacts.each_with_index do |contact_data, idx|
          stream_progress("Creating contact #{idx + 1}/#{contacts.length}...", percentage: ((idx + 1.0) / contacts.length * 100).round)
          result = platform_create(type: "contact", data: contact_data)
          results << result
        end

        succeeded = results.count { |r| r.is_a?(Hash) && r[:success] != false }
        failed = results.length - succeeded

        success_response(
          created_count: succeeded,
          failed_count: failed,
          total: contacts.length,
          results: results,
          message: "Created #{succeeded} contact(s)#{failed > 0 ? " (#{failed} failed)" : ""}."
        )
      end

      def create_contact_group(spec)
        group_name = spec_val(spec, :group_name) || spec_val(spec, :name)
        contact_ids = spec_val(spec, :contact_ids, [])

        return error_response("Missing: group_name or name") if group_name.blank?

        # Create the group
        group_result = platform_create(type: "contact_group", data: { name: group_name })
        return group_result unless group_result.is_a?(Hash) && group_result[:success] != false

        # Add contacts to group if provided
        if contact_ids.any?
          group_id = group_result[:id] || group_result[:contact_group_id]
          if group_id
            group = ContactGroup.find_by(id: group_id, entity: entity)
            if group
              added = 0
              contact_ids.each do |cid|
                contact = entity.contacts.find_by(id: cid)
                next unless contact
                group.contacts << contact unless group.contacts.include?(contact)
                added += 1
              end
              group_result[:contacts_added] = added
              group_result[:message] = "Group '#{group_name}' created with #{added} contact(s)."
            end
          end
        end

        group_result
      end

      def extract_contact_data(spec)
        # Normalize spec keys to contact fields
        data = {}
        data["first_name"] = spec_val(spec, :first_name)
        data["last_name"] = spec_val(spec, :last_name)
        data["email"] = spec_val(spec, :email)
        data["phone"] = spec_val(spec, :phone)
        data["company"] = spec_val(spec, :company)
        data["lifecycle_stage"] = spec_val(spec, :lifecycle_stage, "lead")
        data["status"] = spec_val(spec, :status, "active")
        data["tags"] = spec_val(spec, :tags) if spec_val(spec, :tags)
        data["custom_fields"] = spec_val(spec, :custom_fields) if spec_val(spec, :custom_fields)

        # Also pass through any fields from a flat data hash
        if spec_val(spec, :data).is_a?(Hash)
          data.merge!(spec_val(spec, :data).stringify_keys)
        end

        data.compact
      end
    end
  end
end
