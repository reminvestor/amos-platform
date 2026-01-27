require "test_helper"

class ScoutFileUploadIntegrationTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @entity = entities(:demo_company)
    @user = users(:admin_user)
    @user.update!(entity: @entity, onboarded: true)
    @entity.update!(subscription_status: 'active')

    sign_in @user
  end

  test "file upload endpoint creates ImageAsset correctly" do
    # Create a test file
    test_file = Tempfile.new(['test', '.pdf'])
    test_file.write("Test PDF content")
    test_file.rewind

    uploaded_file = Rack::Test::UploadedFile.new(
      test_file.path,
      'application/pdf',
      original_filename: 'test_document.pdf'
    )

    # Upload file via Scout endpoint
    post "/scout/upload_files", params: {
      files: { 0 => uploaded_file }
    }

    assert_response :success
    response_json = JSON.parse(@response.body)

    # Verify response structure
    assert response_json['success']
    assert_equal 1, response_json['urls'].length

    # Verify file data
    file_data = response_json['urls'].first
    assert_equal 'test_document.pdf', file_data['filename']
    assert_equal 'application/pdf', file_data['content_type']
    assert file_data['asset_id'].present?

    # Verify ImageAsset was created
    image_asset = ImageAsset.find(file_data['asset_id'])
    assert_equal @entity, image_asset.entity
    assert_equal @user, image_asset.user
    assert_equal 'test_document.pdf', image_asset.title
    assert image_asset.file.attached?

  ensure
    test_file.close
    test_file.unlink
  end

  test "multiple files can be uploaded at once" do
    test_files = []
    uploaded_files = {}

    # Create 3 test files
    3.times do |i|
      tempfile = Tempfile.new(["test_#{i}", '.pdf'])
      tempfile.write("Test content #{i}")
      tempfile.rewind
      test_files << tempfile

      uploaded_files[i.to_s] = Rack::Test::UploadedFile.new(
        tempfile.path,
        'application/pdf',
        original_filename: "test_document_#{i}.pdf"
      )
    end

    # Upload all files
    post "/scout/upload_files", params: {
      files: uploaded_files
    }

    assert_response :success
    response_json = JSON.parse(@response.body)

    # Verify all files were uploaded
    assert response_json['success']
    assert_equal 3, response_json['urls'].length

    # Verify each file has correct data
    response_json['urls'].each_with_index do |file_data, index|
      assert_equal "test_document_#{index}.pdf", file_data['filename']
      assert file_data['asset_id'].present?

      # Verify ImageAsset was created
      image_asset = ImageAsset.find(file_data['asset_id'])
      assert_equal @entity, image_asset.entity
    end

  ensure
    test_files.each { |f| f.close; f.unlink }
  end

  test "file upload with different content types" do
    test_cases = [
      { filename: 'test.pdf', content_type: 'application/pdf' },
      { filename: 'test.txt', content_type: 'text/plain' },
      { filename: 'test.docx', content_type: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document' },
      { filename: 'test.csv', content_type: 'text/csv' },
      { filename: 'test.jpg', content_type: 'image/jpeg' },
      { filename: 'test.png', content_type: 'image/png' }
    ]

    test_cases.each do |test_case|
      tempfile = Tempfile.new([File.basename(test_case[:filename], '.*'), File.extname(test_case[:filename])])
      tempfile.write("Test content for #{test_case[:filename]}")
      tempfile.rewind

      uploaded_file = Rack::Test::UploadedFile.new(
        tempfile.path,
        test_case[:content_type],
        original_filename: test_case[:filename]
      )

      # Upload file
      post "/scout/upload_files", params: {
        files: { 0 => uploaded_file }
      }

      assert_response :success
      response_json = JSON.parse(@response.body)

      # Verify response
      assert response_json['success']
      file_data = response_json['urls'].first
      assert_equal test_case[:filename], file_data['filename']
      assert_equal test_case[:content_type], file_data['content_type']

      # Verify ImageAsset
      image_asset = ImageAsset.find(file_data['asset_id'])
      assert_equal test_case[:filename], image_asset.title

      tempfile.close
      tempfile.unlink
    end
  end

  test "file upload fails gracefully without authentication" do
    sign_out @user

    tempfile = Tempfile.new(['test', '.pdf'])
    tempfile.write("Test content")
    tempfile.rewind

    uploaded_file = Rack::Test::UploadedFile.new(
      tempfile.path,
      'application/pdf',
      original_filename: 'test.pdf'
    )

    # Try to upload without authentication
    post "/scout/upload_files", params: {
      files: { 0 => uploaded_file }
    }

    # Should redirect to sign in
    assert_response :redirect

  ensure
    tempfile.close
    tempfile.unlink
  end

  test "file upload preserves file extension and MIME type" do
    test_file = Tempfile.new(['document', '.pdf'])
    test_file.write("PDF content here")
    test_file.rewind

    uploaded_file = Rack::Test::UploadedFile.new(
      test_file.path,
      'application/pdf',
      original_filename: 'my_document.pdf'
    )

    post "/scout/upload_files", params: {
      files: { 0 => uploaded_file }
    }

    assert_response :success
    response_json = JSON.parse(@response.body)

    file_data = response_json['urls'].first
    image_asset = ImageAsset.find(file_data['asset_id'])

    # Verify file information
    assert_equal 'my_document.pdf', image_asset.title
    assert image_asset.file.blob.content_type.start_with?('application/pdf')
    assert image_asset.file.blob.byte_size > 0

  ensure
    test_file.close
    test_file.unlink
  end

  test "read_document_tool can access uploaded files" do
    # Upload a file first
    test_file = Tempfile.new(['test', '.txt'])
    test_file.write("This is test document content that we will read back.")
    test_file.rewind

    uploaded_file = Rack::Test::UploadedFile.new(
      test_file.path,
      'text/plain',
      original_filename: 'test_read.txt'
    )

    post "/scout/upload_files", params: {
      files: { 0 => uploaded_file }
    }

    assert_response :success
    response_json = JSON.parse(@response.body)
    asset_id = response_json['urls'].first['asset_id']

    # Now try to read it using the read_document_tool
    tool = Tools::ReadDocumentTool.new(
      context: {},
      user: @user,
      entity: @entity
    )

    result = tool.execute({
      asset_id: asset_id,
      max_length: 50000
    })

    # Verify the document was read successfully
    assert result[:success]
    assert result[:content].include?("test document content")
    assert_equal "test_read.txt", result[:filename]

  ensure
    test_file.close
    test_file.unlink
  end
end
