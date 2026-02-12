require "test_helper"

class Admin::PayoutsControllerTest < ActionDispatch::IntegrationTest
  def setup
    @admin = AdminUser.find_or_create_by!(email: "admin_payout_test_#{SecureRandom.hex(4)}@test.com") do |u|
      u.password = 'Password123!'
    end
    @affiliate = affiliates(:active_affiliate)

    # Create approved commissions for payout
    @commission1 = Commission.create!(
      affiliate: @affiliate,
      referral: referrals(:converted_referral),
      entity: entities(:one),
      commission_type: 'first_payment',
      amount: 60.00,
      status: :approved,
      earned_at: Time.current
    )

    @commission2 = Commission.create!(
      affiliate: @affiliate,
      referral: referrals(:converted_referral),
      entity: entities(:one),
      commission_type: 'recurring',
      amount: 40.00,
      status: :approved,
      earned_at: Time.current
    )
  end

  test "should get index" do
    skip "Admin authentication needs to be configured"
    get admin_payouts_path
    assert_response :success
  end

  test "should get new payout batch form" do
    skip "Admin authentication needs to be configured"
    get new_admin_payout_path
    assert_response :success
  end

  test "should create payout batch" do
    skip "Admin authentication needs to be configured"

    assert_difference 'Payout.count', 1 do
      post admin_payouts_path, params: {
        affiliate_ids: [@affiliate.id],
        payment_method: 'paypal'
      }
    end

    assert_redirected_to admin_payouts_path
  end

  test "should mark payout as completed" do
    skip "Admin authentication needs to be configured"
    payout = payouts(:pending_payout)

    assert payout.pending?

    post mark_completed_admin_payout_path(payout), params: {
      payment_reference: 'PAYPAL-12345'
    }

    payout.reload
    assert payout.completed?
    assert_equal 'PAYPAL-12345', payout.payment_reference
    assert_equal @admin, payout.processed_by
    assert_redirected_to admin_payouts_path
  end

  test "marking payout completed should mark commissions as paid" do
    skip "Admin authentication needs to be configured"
    payout = Payout.create!(
      affiliate: @affiliate,
      amount: 100.00,
      payment_method: 'paypal',
      commission_ids: [@commission1.id, @commission2.id],
      status: :pending
    )

    post mark_completed_admin_payout_path(payout), params: {
      payment_reference: 'TEST-123'
    }

    @commission1.reload
    @commission2.reload

    assert @commission1.paid?
    assert @commission2.paid?
  end

  test "should show pending commissions total" do
    skip "Admin authentication needs to be configured"
    get admin_payouts_path

    assert assigns(:pending_commissions_total), "Should assign @pending_commissions_total"
  end

  test "should show affiliates ready for payout" do
    skip "Admin authentication needs to be configured"
    get new_admin_payout_path

    assert assigns(:affiliates_ready), "Should assign @affiliates_ready"
  end

  test "should filter payouts by status" do
    skip "Admin authentication needs to be configured"
    get admin_payouts_path(status: 'completed')
    assert_response :success
  end
end
