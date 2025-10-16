namespace :docling do
  desc "Check Docling installation status"
  task check: :environment do
    puts "\n🔍 Checking Docling Installation...\n\n"

    # Check Python
    print "Python 3: "
    if system("which python3 > /dev/null 2>&1")
      version = `python3 --version`.strip
      puts "✅ #{version}"
    else
      puts "❌ Not found"
      puts "\nInstall Python 3.9+: https://www.python.org/downloads/"
      exit 1
    end

    # Check pip
    print "pip3: "
    if system("which pip3 > /dev/null 2>&1")
      version = `pip3 --version`.strip.split(' ')[1]
      puts "✅ #{version}"
    else
      puts "❌ Not found"
      exit 1
    end

    # Check Docling availability
    result = DoclingBridgeService.check_installation

    puts "\nDocling Library:"
    if result[:installed]
      puts "  ✅ Installed: v#{result[:version]}"
      puts "  📍 Python path: #{result[:python_path]}"
    else
      puts "  ❌ Not installed"
      puts "  📝 Error: #{result[:error]}" if result[:error]
      puts "\n#{result[:hint]}" if result[:hint]
      puts "\nTo install:"
      puts "  cd #{Rails.root}"
      puts "  pip3 install -r requirements.txt"
      exit 1
    end

    # Check script file
    script_path = Rails.root.join("lib", "docling_processor.py")
    print "\nProcessor Script: "
    if File.exist?(script_path)
      puts "✅ #{script_path}"
    else
      puts "❌ Missing: #{script_path}"
      exit 1
    end

    # Test processing
    puts "\n🧪 Testing Document Processing..."
    begin
      bridge = DoclingBridgeService.new
      puts "  ✅ Bridge service initialized"

      # Check supported extensions
      puts "\n📄 Supported File Types:"
      DoclingBridgeService::SUPPORTED_EXTENSIONS.each do |ext|
        puts "  • #{ext}"
      end

      puts "\n✅ Docling is ready!"
      puts "\nDocumentProcessorService will automatically use Docling for enhanced parsing."

    rescue => e
      puts "  ❌ Error: #{e.message}"
      exit 1
    end
  end

  desc "Test Docling with a sample file"
  task :test, [:file_path] => :environment do |t, args|
    unless args[:file_path]
      puts "Usage: rails docling:test[path/to/file.pdf]"
      exit 1
    end

    file_path = args[:file_path]
    unless File.exist?(file_path)
      puts "❌ File not found: #{file_path}"
      exit 1
    end

    puts "\n📄 Testing Docling with: #{file_path}\n\n"

    begin
      bridge = DoclingBridgeService.new
      result = bridge.process_file(file_path)

      if result[:success]
        puts "✅ Processing successful!\n\n"

        puts "📊 Results:"
        puts "  • Chunks extracted: #{result[:chunks].length}"
        puts "  • Total pages: #{result[:metadata][:total_pages]}"
        puts "  • Tables found: #{result[:metadata][:tables_found]}"
        puts "  • Images found: #{result[:metadata][:images_found]}"

        if result[:chunks].any?
          puts "\n📝 Sample chunk:"
          first_chunk = result[:chunks].first
          puts "  Page: #{first_chunk[:metadata][:page]}"
          puts "  Type: #{first_chunk[:metadata][:type]}"
          puts "  Content (first 200 chars):"
          puts "  #{first_chunk[:content][0..200]}..."
        end

        puts "\n✅ Docling is working correctly!"
      else
        puts "❌ Processing failed: #{result[:error]}"
        exit 1
      end

    rescue => e
      puts "❌ Error: #{e.message}"
      puts e.backtrace.join("\n")
      exit 1
    end
  end

  desc "Process a file and show all chunks"
  task :process, [:file_path] => :environment do |t, args|
    unless args[:file_path]
      puts "Usage: rails docling:process[path/to/file.pdf]"
      exit 1
    end

    file_path = args[:file_path]
    unless File.exist?(file_path)
      puts "❌ File not found: #{file_path}"
      exit 1
    end

    puts "\n📄 Processing: #{file_path}\n\n"

    begin
      processor = DocumentProcessorService.new(use_docling: true)
      result = processor.process_documents([
        { type: 'file', content: file_path, filename: File.basename(file_path) }
      ])

      if result[:success]
        puts "✅ Processed #{result[:total_chunks]} chunks\n\n"

        result[:chunks].each_with_index do |chunk, index|
          puts "━━━ Chunk #{index + 1} ━━━"
          puts "Source: #{chunk[:metadata][:source]}"
          puts "Type: #{chunk[:metadata][:type]}"
          puts "Page: #{chunk[:metadata][:page]}" if chunk[:metadata][:page]
          puts "Processor: #{chunk[:metadata][:processor] || 'standard'}"
          puts "\nContent:"
          puts chunk[:content]
          puts "\n"
        end

        puts "✅ Complete!"
      else
        puts "❌ Processing failed: #{result[:error]}"
        exit 1
      end

    rescue => e
      puts "❌ Error: #{e.message}"
      puts e.backtrace.join("\n")
      exit 1
    end
  end

  desc "Compare Docling vs Standard processing"
  task :compare, [:file_path] => :environment do |t, args|
    unless args[:file_path]
      puts "Usage: rails docling:compare[path/to/file.pdf]"
      exit 1
    end

    file_path = args[:file_path]
    unless File.exist?(file_path)
      puts "❌ File not found: #{file_path}"
      exit 1
    end

    puts "\n📊 Comparing Docling vs Standard Processing\n"
    puts "File: #{file_path}\n\n"

    begin
      # Test with Docling
      puts "🔬 Testing Docling..."
      start_time = Time.now
      docling_processor = DocumentProcessorService.new(use_docling: true)
      docling_result = docling_processor.process_documents([
        { type: 'file', content: file_path, filename: File.basename(file_path) }
      ])
      docling_time = Time.now - start_time

      # Test without Docling
      puts "🔬 Testing Standard Processing..."
      start_time = Time.now
      standard_processor = DocumentProcessorService.new(use_docling: false)
      standard_result = standard_processor.process_documents([
        { type: 'file', content: file_path, filename: File.basename(file_path) }
      ])
      standard_time = Time.now - start_time

      # Compare results
      puts "\n📊 Comparison Results:\n\n"

      puts "┌─────────────────────────┬──────────────┬──────────────┐"
      puts "│ Metric                  │ Docling      │ Standard     │"
      puts "├─────────────────────────┼──────────────┼──────────────┤"
      puts "│ Processing Time         │ #{format('%10.2fs', docling_time)}   │ #{format('%10.2fs', standard_time)}   │"
      puts "│ Chunks Extracted        │ #{format('%12d', docling_result[:total_chunks])} │ #{format('%12d', standard_result[:total_chunks])} │"
      puts "│ Success                 │ #{docling_result[:success] ? '✅ Yes      ' : '❌ No       '} │ #{standard_result[:success] ? '✅ Yes      ' : '❌ No       '} │"
      puts "└─────────────────────────┴──────────────┴──────────────┘"

      if docling_result[:success] && standard_result[:success]
        puts "\n📈 Analysis:"
        puts "  • Speed difference: #{((docling_time / standard_time - 1) * 100).round(1)}% #{docling_time > standard_time ? 'slower' : 'faster'}"
        puts "  • Chunk difference: #{((docling_result[:total_chunks].to_f / standard_result[:total_chunks] - 1) * 100).round(1)}% #{docling_result[:total_chunks] > standard_result[:total_chunks] ? 'more' : 'fewer'} chunks"

        puts "\n💡 Recommendation:"
        if docling_result[:total_chunks] > standard_result[:total_chunks]
          puts "  Docling extracted more chunks, suggesting better structure detection."
        elsif docling_time < standard_time * 2
          puts "  Docling's enhanced parsing is worth the minor speed trade-off."
        else
          puts "  Consider standard processing for simple documents."
        end
      end

    rescue => e
      puts "❌ Error: #{e.message}"
      puts e.backtrace.join("\n")
      exit 1
    end
  end
end
