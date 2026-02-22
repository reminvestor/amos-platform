# frozen_string_literal: true

module Benchmarks
  module V2
    module Scenarios
      class ContactImportAndCampaign
        def self.build
          Scenario.new(
            id: :contact_import_and_campaign,
            level: :L2,
            category: :data_analysis,
            name: "Import contacts and create targeted campaign",
            description: "Tests data handling + content creation: the AI must understand " \
                         "a data request, create contacts, organize them, and build a campaign.",
            tags: [:core],
            messages: [
              "I have 5 new leads I need to add: John Smith (john@acme.com, CEO), " \
              "Sarah Jones (sarah@techstart.io, CTO), Mike Chen (mike@growthco.com, VP Marketing), " \
              "Lisa Park (lisa@designlab.co, Founder), and Tom Wilson (tom@buildright.com, COO). " \
              "Put them all in a group called 'Q1 Enterprise Leads' and then create a personalized " \
              "outreach email campaign targeting them about our enterprise plan.",
            ],
            assertions: [
              { type: :record_exists, model: "Contact", conditions: {}, min_count: 5 },
              { type: :record_exists, model: "ContactGroup", conditions: {} },
              { type: :tool_called, tool_name: "platform_create", min_times: 2 },
              { type: :no_errors },
              { type: :conversation_completed },
            ],
            quality_rubric: <<~RUBRIC,
              Evaluate the contact import and campaign creation:
              1. TASK COMPLETION (0-15): Were all elements created?
                 - All 5 contacts created with correct names, emails, and titles
                 - Contact group 'Q1 Enterprise Leads' created
                 - Contacts assigned to the group
                 - Campaign created targeting the group
              2. DATA ACCURACY (0-15): Is the data correct?
                 - Names, emails, titles match the input exactly
                 - No contacts missing or duplicated
                 - Group membership is correct
              3. CAMPAIGN QUALITY (0-10): Is the outreach email effective?
                 - Subject line is compelling for enterprise prospects
                 - Body references their seniority/role appropriately
                 - Clear value proposition for enterprise plan
                 - Professional tone appropriate for C-suite
              4. EFFICIENCY (0-10): Was this handled well?
                 - All contacts created without one-by-one confirmation
                 - Logical flow: contacts -> group -> campaign
            RUBRIC
            timeout_seconds: 240
          )
        end
      end
    end
  end
end
