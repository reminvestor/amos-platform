# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    class DocumentsControllerTest < ActionDispatch::IntegrationTest
      fixtures :rag_stores, :rag_documents

      setup do
        @user = users(:one)
        @entity = entities(:one)
        @user.update!(entity: @entity, api_key: SecureRandom.hex(32))

        # Create a RAG store for the entity
        @rag_store = RagStore.create!(
          name: "Test Knowledge Base",
          app_name: "amos",
          store_type: "entity",
          entity: @entity,
          user: @user,
          status: "active"
        )

        # Create a test document
        @document = RagDocument.create!(
          rag_store: @rag_store,
          original_filename: "test_document.pdf",
          content_type: "application/pdf",
          file_size_bytes: 102400,
          file_hash: SecureRandom.hex(32),
          processing_status: "completed",
          is_latest_version: true,
          version: 1
        )
      end

      teardown do
        RagDocument.where(rag_store: @rag_store).destroy_all
        @rag_store&.destroy
      end

      # ====================================================================
      # Helper Methods
      # ====================================================================

      def auth_headers
        { "Authorization" => "Bearer #{@user.api_key}" }
      end

      # ====================================================================
      # INDEX Tests
      # ====================================================================

      test "should get documents list with valid token" do
        get api_v1_documents_path, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        assert response_body.key?("data")
        assert response_body.key?("meta")
      end

      test "documents list returns expected fields" do
        get api_v1_documents_path, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        documents = response_body["data"]

        assert documents.any?

        document = documents.find { |d| d["id"] == @document.id }
        assert document.present?
        assert document.key?("id")
        assert document.key?("filename")
        assert document.key?("title")
        assert document.key?("content_type")
        assert document.key?("file_size")
        assert document.key?("processing_status")
        assert document.key?("icon")
        assert document.key?("created_at")
      end

      test "documents list supports search filter" do
        get api_v1_documents_path, params: { search: "test" }, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        # Just verify search works without error
        assert response_body.key?("data")
      end

      test "documents list supports content type filter" do
        get api_v1_documents_path, params: { content_type: "pdf" }, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        documents = response_body["data"]
        documents.each do |doc|
          assert doc["content_type"].include?("pdf")
        end
      end

      test "documents list supports status filter" do
        get api_v1_documents_path, params: { status: "completed" }, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        documents = response_body["data"]
        documents.each do |doc|
          assert_equal "completed", doc["processing_status"]
        end
      end

      test "documents list returns pagination metadata" do
        get api_v1_documents_path, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        meta = response_body["meta"]

        assert meta.key?("current_page")
        assert meta.key?("total_pages")
        assert meta.key?("total_count")
      end

      test "documents list requires authentication" do
        get api_v1_documents_path, as: :json

        assert_response :unauthorized
      end

      # ====================================================================
      # SHOW Tests
      # ====================================================================

      test "should get document details with valid token" do
        get api_v1_document_path(@document), headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        assert_equal @document.id, response_body["id"]
        assert_equal @document.original_filename, response_body["filename"]
      end

      test "document show returns detailed fields" do
        get api_v1_document_path(@document), headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        # Detailed view should include extra fields
        assert response_body.key?("tags")
        assert response_body.key?("subjects")
        assert response_body.key?("processing_stage")
      end

      test "should return 404 for non-existent document" do
        get api_v1_document_path(id: 999999), headers: auth_headers, as: :json

        assert_response :not_found
      end

      test "document show requires authentication" do
        get api_v1_document_path(@document), as: :json

        assert_response :unauthorized
      end

      # ====================================================================
      # COLLECTIONS Tests
      # ====================================================================

      test "should get document collections" do
        get collections_api_v1_documents_path, headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        assert response_body.key?("data")

        collections = response_body["data"]
        assert collections.any?

        collection = collections.first
        assert collection.key?("id")
        assert collection.key?("name")
        assert collection.key?("status")
        assert collection.key?("document_count")
      end

      test "collections requires authentication" do
        get collections_api_v1_documents_path, as: :json

        assert_response :unauthorized
      end

      # ====================================================================
      # STATUS Tests
      # ====================================================================

      test "should get document status" do
        get status_api_v1_document_path(@document), headers: auth_headers, as: :json

        assert_response :success

        response_body = JSON.parse(response.body)
        assert_equal @document.id, response_body["id"]
        assert response_body.key?("processing_status")
        assert response_body.key?("processing_progress")
        assert response_body.key?("chunks_count")
      end

      test "status requires authentication" do
        get status_api_v1_document_path(@document), as: :json

        assert_response :unauthorized
      end

      # ====================================================================
      # CREATE Tests (file upload)
      # ====================================================================

      test "create document without file returns error" do
        post api_v1_documents_path,
          params: {},
          headers: auth_headers,
          as: :json

        assert_response :unprocessable_entity

        response_body = JSON.parse(response.body)
        assert response_body["error"].present?
      end

      test "create document requires authentication" do
        post api_v1_documents_path, as: :json

        assert_response :unauthorized
      end

      # ====================================================================
      # DESTROY Tests
      # ====================================================================

      test "should destroy document" do
        doc_to_delete = RagDocument.create!(
          rag_store: @rag_store,
          original_filename: "delete_me.pdf",
          content_type: "application/pdf",
          file_size_bytes: 1024,
          file_hash: SecureRandom.hex(32),
          processing_status: "completed",
          is_latest_version: true,
          version: 1
        )

        assert_difference "RagDocument.count", -1 do
          delete api_v1_document_path(doc_to_delete), headers: auth_headers, as: :json
        end

        assert_response :success

        response_body = JSON.parse(response.body)
        assert response_body["success"]
      end

      test "destroy document requires authentication" do
        delete api_v1_document_path(@document), as: :json

        assert_response :unauthorized
      end

      test "should not destroy document from different entity" do
        # Use a fixture document from a different entity's rag store
        # The document from entity_two_internal fixture belongs to a different entity
        other_store_doc = rag_documents(:document_duplicate)

        # Try to delete document from different entity
        delete api_v1_document_path(other_store_doc), headers: auth_headers, as: :json

        # Should not be found because it belongs to a different entity
        assert_response :not_found
      end
    end
  end
end
