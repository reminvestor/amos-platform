module Tools
  class ViewInvoicesTool < BaseTool
    def self.metadata
      {
        name: 'view_invoices',
        description: 'View billing history and invoices',
        input_schema: {
          type: 'object',
          properties: {
            limit: {
              type: 'integer',
              description: 'Number of invoices to retrieve (default: 10, max: 50)',
              default: 10
            }
          },
          required: []
        }
      }
    end

    def self.read_only?
      true
    end

    def execute(args)
      log_execution(args)

      unless entity.stripe_customer_id.present?
        return error_response("No billing information available")
      end

      limit = get_arg(args, :limit, 10)
      limit = [[limit, 1].max, 50].min # Clamp between 1 and 50

      begin
        invoices = Stripe::Invoice.list(
          customer: entity.stripe_customer_id,
          limit: limit
        )

        invoice_list = invoices.data.map do |invoice|
          {
            id: invoice.id,
            number: invoice.number,
            amount: "$#{(invoice.amount_paid / 100.0).round(2)}",
            status: invoice.status,
            paid: invoice.paid,
            period_start: Time.at(invoice.period_start).strftime('%B %d, %Y'),
            period_end: Time.at(invoice.period_end).strftime('%B %d, %Y'),
            created: Time.at(invoice.created).strftime('%B %d, %Y'),
            pdf_url: invoice.invoice_pdf,
            hosted_url: invoice.hosted_invoice_url
          }
        end

        success_response(
          invoices: invoice_list,
          total_count: invoices.data.length,
          message: "Retrieved #{invoice_list.length} invoice(s)"
        )
      rescue Stripe::StripeError => e
        error_response("Failed to retrieve invoices: #{e.message}")
      end
    end
  end
end
