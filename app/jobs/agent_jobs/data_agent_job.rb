# Specialized agent for data operations (import, export, analytics)
module AgentJobs
  class DataAgentJob < BaseAgentJob
    
    def execute_agent_task
      Rails.logger.info "[DataAgent] Processing: #{@task}"
      
      # Determine data task type
      task_type = analyze_data_task
      
      case task_type
      when :import_contacts
        import_contacts_from_file
      when :export_data
        export_data_to_file
      when :analytics
        generate_analytics_report
      when :clean_data
        clean_and_deduplicate_data
      when :segment_analysis
        analyze_customer_segments
      else
        handle_general_data_task
      end
    end
    
    private
    
    def analyze_data_task
      task_lower = @task.downcase
      
      case task_lower
      when /import.*contacts?|upload.*list|add.*from.*file/i
        :import_contacts
      when /export|download|extract|backup/i
        :export_data
      when /analytics|report|metrics|statistics/i
        :analytics
      when /clean|dedupe|duplicate|merge/i
        :clean_data
      when /segment|cohort|group.*analysis/i
        :segment_analysis
      else
        :general
      end
    end
    
    def import_contacts_from_file
      stream_content("I'll help you import contacts from a file.")
      
      # Check for attached files
      files = @context[:metadata][:attached_files] || []
      
      if files.empty?
        stream_content("Please attach a CSV or Excel file containing your contacts.")
        return {
          success: false,
          message: "No file attached. Please attach a contact list file."
        }
      end
      
      file_info = files.first
      update_status('running', 'Reading file...', progress: 20)
      
      # Read and parse file
      contacts_data = parse_contact_file(file_info)
      
      if contacts_data.nil? || contacts_data.empty?
        return {
          success: false,
          message: "Could not parse the file. Please ensure it's a valid CSV or Excel file."
        }
      end
      
      update_status('running', "Processing #{contacts_data.count} contacts...", progress: 40)
      
      # Map fields
      field_mapping = detect_or_request_field_mapping(contacts_data.first)
      
      # Import contacts
      results = import_contacts(contacts_data, field_mapping)
      
      # Generate report
      stream_content(
        "✅ Import completed!\n\n" +
        "• Total rows: #{contacts_data.count}\n" +
        "• Imported: #{results[:imported]}\n" +
        "• Updated: #{results[:updated]}\n" +
        "• Skipped: #{results[:skipped]}\n" +
        "• Errors: #{results[:errors]}\n\n" +
        "Your contact list has been updated."
      )
      
      {
        success: true,
        imported: results[:imported],
        updated: results[:updated],
        message: "Imported #{results[:imported]} new contacts"
      }
    end
    
    def parse_contact_file(file_info)
      # Read file using asset_id
      asset = Asset.find_by(id: file_info['asset_id'])
      return nil unless asset
      
      case file_info['content_type']
      when 'text/csv', 'application/csv'
        parse_csv_file(asset)
      when 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
        parse_excel_file(asset)
      else
        nil
      end
    end
    
    def parse_csv_file(asset)
      require 'csv'
      
      csv_content = asset.file.download
      CSV.parse(csv_content, headers: true).map(&:to_h)
    rescue => e
      Rails.logger.error "[DataAgent] CSV parse error: #{e.message}"
      nil
    end
    
    def parse_excel_file(asset)
      require 'roo'
      
      # Download to temp file
      temp_file = Tempfile.new(['import', '.xlsx'])
      temp_file.binmode
      temp_file.write(asset.file.download)
      temp_file.rewind
      
      xlsx = Roo::Spreadsheet.open(temp_file.path)
      sheet = xlsx.sheet(0)
      
      # Get headers from first row
      headers = sheet.row(1)
      
      # Parse remaining rows
      data = []
      (2..sheet.last_row).each do |i|
        row = sheet.row(i)
        data << Hash[headers.zip(row)]
      end
      
      data
    rescue => e
      Rails.logger.error "[DataAgent] Excel parse error: #{e.message}"
      nil
    ensure
      temp_file&.close
      temp_file&.unlink
    end
    
    def detect_or_request_field_mapping(sample_row)
      headers = sample_row.keys
      
      # Auto-detect common fields
      mapping = {}
      
      headers.each do |header|
        header_lower = header.downcase
        
        if header_lower.include?('email') || header_lower == 'e-mail'
          mapping[:email] = header
        elsif header_lower.include?('first') && header_lower.include?('name')
          mapping[:first_name] = header
        elsif header_lower.include?('last') && header_lower.include?('name')
          mapping[:last_name] = header
        elsif header_lower == 'name' && !mapping[:first_name]
          mapping[:full_name] = header
        elsif header_lower.include?('phone') || header_lower.include?('mobile')
          mapping[:phone] = header
        elsif header_lower.include?('company') || header_lower.include?('organization')
          mapping[:company] = header
        elsif header_lower.include?('tag') || header_lower.include?('group')
          mapping[:tags] = header
        end
      end
      
      # Verify mapping with user
      stream_content("I detected these field mappings:\n#{mapping.map { |k, v| "• #{k}: #{v}" }.join("\n")}")
      
      if mapping[:email].nil?
        email_field = request_user_input(
          "Which column contains email addresses?",
          options: headers
        )
        mapping[:email] = email_field
      end
      
      mapping
    end
    
    def import_contacts(contacts_data, field_mapping)
      entity = Entity.find(@context[:entity_id])
      
      imported = 0
      updated = 0
      skipped = 0
      errors = 0
      
      contacts_data.each_with_index do |row, index|
        begin
          # Extract fields
          email = row[field_mapping[:email]]&.strip&.downcase
          
          # Skip if no email
          if email.blank?
            skipped += 1
            next
          end
          
          # Check for existing contact
          contact = Contact.find_or_initialize_by(
            entity: entity,
            email: email
          )
          
          # Map fields
          if field_mapping[:full_name]
            names = row[field_mapping[:full_name]]&.split(' ')
            contact.first_name = names&.first
            contact.last_name = names&.drop(1)&.join(' ')
          else
            contact.first_name = row[field_mapping[:first_name]]&.strip if field_mapping[:first_name]
            contact.last_name = row[field_mapping[:last_name]]&.strip if field_mapping[:last_name]
          end
          
          contact.phone = row[field_mapping[:phone]]&.strip if field_mapping[:phone]
          contact.company = row[field_mapping[:company]]&.strip if field_mapping[:company]
          
          # Handle tags
          if field_mapping[:tags]
            tags = row[field_mapping[:tags]]&.split(',')&.map(&:strip) || []
            contact.tags = (contact.tags || []) | tags
          end
          
          # Add import metadata
          contact.metadata ||= {}
          contact.metadata['imported_at'] = Time.current
          contact.metadata['import_source'] = 'file_upload'
          
          if contact.new_record?
            contact.save!
            imported += 1
          elsif contact.changed?
            contact.save!
            updated += 1
          else
            skipped += 1
          end
          
          # Update progress
          if index % 10 == 0
            progress = 40 + (50 * index / contacts_data.count)
            update_status('running', "Processing contact #{index + 1}/#{contacts_data.count}...", progress: progress)
          end
          
        rescue => e
          Rails.logger.error "[DataAgent] Import error for row #{index}: #{e.message}"
          errors += 1
        end
      end
      
      {
        imported: imported,
        updated: updated,
        skipped: skipped,
        errors: errors
      }
    end
    
    def export_data_to_file
      stream_content("I'll help you export your data.")
      
      data_type = request_user_input(
        "What data would you like to export?",
        options: ["All contacts", "Filtered contacts", "Landing pages", "Email campaigns", "Analytics data"]
      )
      
      format = request_user_input(
        "What format would you like?",
        options: ["CSV", "Excel", "JSON"]
      )
      
      update_status('running', 'Preparing export...', progress: 30)
      
      # Generate export based on type
      data = case data_type
      when "All contacts"
        export_all_contacts
      when "Filtered contacts"
        export_filtered_contacts
      when "Landing pages"
        export_landing_pages
      when "Email campaigns"
        export_email_campaigns
      when "Analytics data"
        export_analytics_data
      end
      
      # Create file
      file_url = generate_export_file(data, format, data_type)
      
      stream_content(
        "✅ Export ready!\n\n" +
        "• Data type: #{data_type}\n" +
        "• Records: #{data.count}\n" +
        "• Format: #{format}\n\n" +
        "Download your export: #{file_url}"
      )
      
      {
        success: true,
        file_url: file_url,
        record_count: data.count,
        message: "Exported #{data.count} records"
      }
    end
    
    def generate_analytics_report
      stream_content("I'll generate an analytics report for you.")
      
      report_type = request_user_input(
        "What type of report would you like?",
        options: ["Overview dashboard", "Contact growth", "Campaign performance", "Landing page metrics", "Revenue analysis"]
      )
      
      time_period = request_user_input(
        "For what time period?",
        options: ["Last 7 days", "Last 30 days", "Last 3 months", "Year to date", "All time"]
      )
      
      update_status('running', 'Analyzing data...', progress: 50)
      
      # Generate report based on type
      report = case report_type
      when "Overview dashboard"
        generate_overview_report(time_period)
      when "Contact growth"
        generate_contact_growth_report(time_period)
      when "Campaign performance"
        generate_campaign_report(time_period)
      when "Landing page metrics"
        generate_landing_page_report(time_period)
      when "Revenue analysis"
        generate_revenue_report(time_period)
      end
      
      # Format and stream report
      stream_content(format_analytics_report(report_type, report))
      
      {
        success: true,
        report_type: report_type,
        metrics: report,
        message: "Analytics report generated"
      }
    end
    
    def clean_and_deduplicate_data
      stream_content("I'll help clean and deduplicate your data.")
      
      entity = Entity.find(@context[:entity_id])
      
      # Find duplicates
      update_status('running', 'Finding duplicates...', progress: 30)
      
      duplicates = Contact.where(entity: entity)
                         .group(:email)
                         .having('count(*) > 1')
                         .count
      
      if duplicates.empty?
        stream_content("✅ No duplicate contacts found! Your data is clean.")
        return { success: true, message: "No duplicates found" }
      end
      
      stream_content("Found #{duplicates.count} duplicate email addresses.")
      
      merge_strategy = request_user_input(
        "How should I handle duplicates?",
        options: ["Keep newest", "Keep oldest", "Merge data", "Review each"]
      )
      
      # Process duplicates
      merged = 0
      deleted = 0
      
      duplicates.each do |email, count|
        contacts = Contact.where(entity: entity, email: email).order(:created_at)
        
        case merge_strategy
        when "Keep newest"
          keeper = contacts.last
          contacts.where.not(id: keeper.id).destroy_all
          deleted += count - 1
        when "Keep oldest"
          keeper = contacts.first
          contacts.where.not(id: keeper.id).destroy_all
          deleted += count - 1
        when "Merge data"
          keeper = merge_duplicate_contacts(contacts)
          merged += 1
          deleted += count - 1
        end
      end
      
      stream_content(
        "✅ Data cleaning completed!\n\n" +
        "• Duplicates found: #{duplicates.count}\n" +
        "• Contacts merged: #{merged}\n" +
        "• Contacts removed: #{deleted}\n\n" +
        "Your contact list is now clean."
      )
      
      {
        success: true,
        duplicates_found: duplicates.count,
        merged: merged,
        deleted: deleted
      }
    end
    
    def export_all_contacts
      Contact.where(entity_id: @context[:entity_id])
            .includes(:tags)
            .map { |c| contact_to_export_hash(c) }
    end
    
    def export_filtered_contacts
      filter = request_user_input("Describe how you'd like to filter contacts:")
      
      # Parse filter (simplified version)
      contacts = Contact.where(entity_id: @context[:entity_id])
      
      if filter.downcase.include?('tag')
        tag = request_user_input("Which tag?")
        contacts = contacts.where("tags @> ?", [tag].to_json)
      elsif filter.downcase.include?('recent')
        contacts = contacts.where("created_at > ?", 30.days.ago)
      elsif filter.downcase.include?('customer')
        contacts = contacts.where("metadata->>'stripe_customer_id' IS NOT NULL")
      end
      
      contacts.map { |c| contact_to_export_hash(c) }
    end
    
    def contact_to_export_hash(contact)
      {
        email: contact.email,
        first_name: contact.first_name,
        last_name: contact.last_name,
        phone: contact.phone,
        company: contact.company,
        tags: contact.tags&.join(', '),
        created_at: contact.created_at,
        last_contacted: contact.metadata&.dig('last_contacted')
      }
    end
    
    def generate_export_file(data, format, data_type)
      case format
      when "CSV"
        generate_csv_export(data)
      when "Excel"
        generate_excel_export(data, data_type)
      when "JSON"
        generate_json_export(data)
      end
    end
    
    def generate_csv_export(data)
      require 'csv'
      
      return "#" if data.empty?
      
      # Create CSV content
      csv_string = CSV.generate do |csv|
        csv << data.first.keys # headers
        data.each { |row| csv << row.values }
      end
      
      # Save to temporary file and create download URL
      filename = "export_#{Time.current.strftime('%Y%m%d_%H%M%S')}.csv"
      save_export_file(csv_string, filename, 'text/csv')
    end
    
    def save_export_file(content, filename, content_type)
      # In production, this would upload to S3 or similar
      # For now, return a placeholder URL
      "/downloads/#{filename}"
    end
    
    def generate_overview_report(period)
      entity = Entity.find(@context[:entity_id])
      date_range = parse_time_period(period)
      
      {
        total_contacts: entity.contacts.count,
        new_contacts: entity.contacts.where(created_at: date_range).count,
        total_campaigns: entity.email_campaigns.count,
        campaigns_sent: entity.email_campaigns.where(sent_at: date_range).count,
        landing_pages: entity.landing_pages.published.count,
        page_views: entity.landing_pages.sum(:view_count),
        conversions: entity.landing_pages.sum(:conversion_count)
      }
    end
    
    def parse_time_period(period)
      case period
      when "Last 7 days" then 7.days.ago..Time.current
      when "Last 30 days" then 30.days.ago..Time.current
      when "Last 3 months" then 3.months.ago..Time.current
      when "Year to date" then Date.current.beginning_of_year..Time.current
      else 100.years.ago..Time.current
      end
    end
    
    def format_analytics_report(type, data)
      "📊 #{type} Report\n" +
      "━" * 40 + "\n\n" +
      data.map { |key, value|
        "• #{key.to_s.humanize}: #{format_metric(value)}"
      }.join("\n")
    end
    
    def format_metric(value)
      case value
      when Integer
        number_with_delimiter(value)
      when Float
        number_with_precision(value, precision: 2)
      when BigDecimal
        "$#{number_with_precision(value, precision: 2)}"
      else
        value.to_s
      end
    end
    
    def number_with_delimiter(number)
      number.to_s.gsub(/(\d)(?=(\d\d\d)+(?!\d))/, "\\1,")
    end
    
    def number_with_precision(number, precision: 2)
      "%.#{precision}f" % number
    end
    
    def merge_duplicate_contacts(contacts)
      # Keep the oldest as base
      keeper = contacts.first
      
      # Merge data from others
      contacts.drop(1).each do |contact|
        # Merge non-blank fields
        keeper.first_name ||= contact.first_name
        keeper.last_name ||= contact.last_name
        keeper.phone ||= contact.phone
        keeper.company ||= contact.company
        
        # Merge tags
        keeper.tags = (keeper.tags || []) | (contact.tags || [])
        
        # Merge metadata
        keeper.metadata = (keeper.metadata || {}).merge(contact.metadata || {})
        
        # Delete the duplicate
        contact.destroy
      end
      
      keeper.save!
      keeper
    end
    
    def handle_general_data_task
      stream_content(
        "I can help you with various data operations:\n\n" +
        "**Import & Export**\n" +
        "• Import contacts from CSV/Excel\n" +
        "• Export data in multiple formats\n" +
        "• Backup your data\n\n" +
        "**Data Quality**\n" +
        "• Find and merge duplicates\n" +
        "• Clean and standardize data\n" +
        "• Validate email addresses\n\n" +
        "**Analytics**\n" +
        "• Generate performance reports\n" +
        "• Analyze customer segments\n" +
        "• Track growth metrics\n\n" +
        "What would you like to do with your data?"
      )
      
      {
        success: true,
        message: "Please specify what data operation you need."
      }
    end
  end
end

