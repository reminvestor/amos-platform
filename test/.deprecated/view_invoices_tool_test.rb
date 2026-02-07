require 'test_helper'

class ViewInvoicesToolTest < ActiveSupport::TestCase
  setup do
    @entity = entities(:one)
    @user = users(:one)
    @tool = Tools::ViewInvoicesTool.new(
      entity: @entity,
      user: @user
    )

    @entity.update!(stripe_customer_id: "cus_test123")
  end

  test "retrieves invoices successfully" do
    invoices = mock_stripe_invoice_list

    Stripe::Invoice.stubs(:list).with(
      customer: "cus_test123",
      limit: 10
    ).returns(invoices)

    result = @tool.execute({})

    assert result[:success]
    assert_equal 2, result[:invoices].length
    assert_equal "in_12345", result[:invoices][0][:id]
    assert_equal "INV-001", result[:invoices][0][:number]
    assert_equal "$50.0", result[:invoices][0][:amount]
    assert_equal "paid", result[:invoices][0][:status]
    assert result[:invoices][0][:paid]
    assert result[:invoices][0][:pdf_url].present?
    assert result[:invoices][0][:hosted_url].present?
  end

  test "uses custom limit parameter" do
    invoices = mock_stripe_invoice_list

    Stripe::Invoice.stubs(:list).with(
      customer: "cus_test123",
      limit: 5
    ).returns(invoices)

    result = @tool.execute({ limit: 5 })

    assert result[:success]
    assert_equal 2, result[:total_count]
  end

  test "clamps limit between 1 and 50" do
    invoices = mock_stripe_invoice_list

    # Test upper bound
    Stripe::Invoice.stubs(:list).with(
      customer: "cus_test123",
      limit: 50
    ).returns(invoices)

    result = @tool.execute({ limit: 100 })
    assert result[:success]

    # Test lower bound
    Stripe::Invoice.stubs(:list).with(
      customer: "cus_test123",
      limit: 1
    ).returns(invoices)

    result = @tool.execute({ limit: -5 })
    assert result[:success]
  end

  test "returns error when no stripe customer exists" do
    @entity.update!(stripe_customer_id: nil)

    result = @tool.execute({})

    assert_not result[:success]
    assert_includes result[:error], "No billing information available"
  end

  test "handles stripe errors gracefully" do
    Stripe::Invoice.stubs(:list).raises(
      Stripe::InvalidRequestError.new("Customer not found", "customer")
    )

    result = @tool.execute({})

    assert_not result[:success]
    assert_includes result[:error], "Failed to retrieve invoices"
  end

  test "formats invoice data correctly" do
    invoices = mock_stripe_invoice_list

    Stripe::Invoice.stubs(:list).returns(invoices)

    result = @tool.execute({})

    assert result[:success]

    invoice = result[:invoices][0]
    assert_match(/\w+ \d+, \d{4}/, invoice[:period_start])
    assert_match(/\w+ \d+, \d{4}/, invoice[:period_end])
    assert_match(/\w+ \d+, \d{4}/, invoice[:created])
  end

  test "handles empty invoice list" do
    Stripe::Invoice.stubs(:list).returns(
      OpenStruct.new(data: [])
    )

    result = @tool.execute({})

    assert result[:success]
    assert_equal 0, result[:invoices].length
    assert_equal 0, result[:total_count]
  end

  private

  def mock_stripe_invoice_list
    OpenStruct.new(
      data: [
        OpenStruct.new(
          id: "in_12345",
          number: "INV-001",
          amount_paid: 5000,
          status: "paid",
          paid: true,
          period_start: 1.month.ago.to_i,
          period_end: Time.now.to_i,
          created: 1.month.ago.to_i,
          currency: "usd",
          invoice_pdf: "https://stripe.com/invoice.pdf",
          hosted_invoice_url: "https://stripe.com/invoice"
        ),
        OpenStruct.new(
          id: "in_67890",
          number: "INV-002",
          amount_paid: 10000,
          status: "paid",
          paid: true,
          period_start: 2.months.ago.to_i,
          period_end: 1.month.ago.to_i,
          created: 2.months.ago.to_i,
          currency: "usd",
          invoice_pdf: "https://stripe.com/invoice2.pdf",
          hosted_invoice_url: "https://stripe.com/invoice2"
        )
      ]
    )
  end
end
