# frozen_string_literal: true

class AddQuickbooksListOperations < ActiveRecord::Migration[8.0]
  def up
    quickbooks = Integration.find_by(slug: 'quickbooks')
    return puts "⏭️  QuickBooks integration not found, skipping" unless quickbooks

    # List Invoices
    IntegrationOperation.find_or_create_by!(
      integration: quickbooks,
      operation_id: 'quickbooks.list_invoices'
    ) do |op|
      op.name = 'List Invoices'
      op.description = 'Retrieve a list of invoices with optional filtering'
      op.http_method = 'GET'
      op.path_template = '/company/{companyId}/query'
      op.pagination_strategy = 'offset'
      op.is_idempotent = true
      op.requires_confirmation = false
      op.is_enabled = true
      op.max_limit = 1000
      op.request_schema = {
        type: 'object',
        properties: {
          query: {
            type: 'string',
            description: "SQL-like query. Examples: 'SELECT * FROM Invoice', 'SELECT * FROM Invoice WHERE Balance > \\'0\\''",
            default: 'SELECT * FROM Invoice MAXRESULTS 50'
          }
        }
      }
    end

    # Get Invoice
    IntegrationOperation.find_or_create_by!(
      integration: quickbooks,
      operation_id: 'quickbooks.get_invoice'
    ) do |op|
      op.name = 'Get Invoice'
      op.description = 'Retrieve a specific invoice by ID'
      op.http_method = 'GET'
      op.path_template = '/company/{companyId}/invoice/{invoiceId}'
      op.is_idempotent = true
      op.is_enabled = true
      op.requires_confirmation = false
    end

    # Update Invoice
    IntegrationOperation.find_or_create_by!(
      integration: quickbooks,
      operation_id: 'quickbooks.update_invoice'
    ) do |op|
      op.name = 'Update Invoice'
      op.description = 'Update an existing invoice'
      op.http_method = 'POST'
      op.path_template = '/company/{companyId}/invoice'
      op.is_idempotent = false
      op.is_enabled = true
      op.requires_confirmation = true
    end

    # List Items
    IntegrationOperation.find_or_create_by!(
      integration: quickbooks,
      operation_id: 'quickbooks.list_items'
    ) do |op|
      op.name = 'List Items'
      op.description = 'Retrieve a list of items (products/services)'
      op.http_method = 'GET'
      op.path_template = '/company/{companyId}/query'
      op.is_idempotent = true
      op.is_enabled = true
      op.request_schema = {
        type: 'object',
        properties: {
          query: { type: 'string', default: 'SELECT * FROM Item MAXRESULTS 100' }
        }
      }
    end

    # List Accounts
    IntegrationOperation.find_or_create_by!(
      integration: quickbooks,
      operation_id: 'quickbooks.list_accounts'
    ) do |op|
      op.name = 'List Accounts'
      op.description = 'Retrieve a list of chart of accounts'
      op.http_method = 'GET'
      op.path_template = '/company/{companyId}/query'
      op.is_idempotent = true
      op.is_enabled = true
      op.request_schema = {
        type: 'object',
        properties: {
          query: { type: 'string', default: 'SELECT * FROM Account MAXRESULTS 100' }
        }
      }
    end

    # List Payments
    IntegrationOperation.find_or_create_by!(
      integration: quickbooks,
      operation_id: 'quickbooks.list_payments'
    ) do |op|
      op.name = 'List Payments'
      op.description = 'Retrieve a list of payments'
      op.http_method = 'GET'
      op.path_template = '/company/{companyId}/query'
      op.is_idempotent = true
      op.is_enabled = true
      op.request_schema = {
        type: 'object',
        properties: {
          query: { type: 'string', default: 'SELECT * FROM Payment MAXRESULTS 100' }
        }
      }
    end

    # Get Cash Flow Report
    IntegrationOperation.find_or_create_by!(
      integration: quickbooks,
      operation_id: 'quickbooks.get_cash_flow'
    ) do |op|
      op.name = 'Get Cash Flow Report'
      op.description = 'Retrieve cash flow statement for cash management analysis'
      op.http_method = 'GET'
      op.path_template = '/company/{companyId}/reports/CashFlow'
      op.is_idempotent = true
      op.is_enabled = true
    end

    puts "✅ Added QuickBooks list operations"
  end

  def down
    quickbooks = Integration.find_by(slug: 'quickbooks')
    return unless quickbooks

    IntegrationOperation.where(
      integration: quickbooks,
      operation_id: %w[
        quickbooks.list_invoices
        quickbooks.get_invoice
        quickbooks.update_invoice
        quickbooks.list_items
        quickbooks.list_accounts
        quickbooks.list_payments
        quickbooks.get_cash_flow
      ]
    ).destroy_all
  end
end

