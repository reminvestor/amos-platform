require "application_system_test_case"

class AdminAffiliateManagementTest < ApplicationSystemTestCase
  setup do
    @admin = admin_users(:one)
    @user = users(:one)
    @affiliate = Affiliate.create!(
      user: @user,
      status: :pending,
      tier: :bronze,
      commission_rate: 0.20,
      payment_email: "affiliate@example.com",
      application_notes: "I want to promote your product"
    )
    sign_in_as_admin(@admin)
  end

  test "admin can view all affiliates" do
    visit admin_affiliates_path

    assert_text "Affiliate Management"
    assert_text @affiliate.affiliate_code
    assert_text @user.email
    assert_text "Pending"
  end

  test "admin can approve affiliate application" do
    visit admin_affiliate_path(@affiliate)

    click_button "Approve"

    assert_text "Affiliate approved successfully"
    @affiliate.reload
    assert_equal "active", @affiliate.status
  end

  test "admin can suspend affiliate" do
    @affiliate.update!(status: :active)
    
    visit admin_affiliate_path(@affiliate)

    click_button "Suspend"

    assert_text "Affiliate suspended"
    @affiliate.reload
    assert_equal "suspended", @affiliate.status
  end

  test "admin can update commission rate" do
    visit edit_admin_affiliate_path(@affiliate)

    fill_in "Commission rate", with: "0.30"
    click_button "Update Commission Rate"

    assert_text "Commission rate updated"
    @affiliate.reload
    assert_equal 0.30, @affiliate.commission_rate
  end

  test "admin can view affiliate commissions" do
    commission = Commission.create!(
      affiliate: @affiliate,
      referral: Referral.create!(
        affiliate: @affiliate,
        referral_code_used: @affiliate.affiliate_code,
        status: :converted
      ),
      entity: entities(:one),
      amount: 100.00,
      commission_type: "signup",
      status: :pending
    )

    visit admin_commissions_path

    assert_text "Commission Management"
    assert_text "$100.00"
    assert_text "Pending"
  end

  test "admin can approve commission" do
    commission = Commission.create!(
      affiliate: @affiliate,
      referral: Referral.create!(
        affiliate: @affiliate,
        referral_code_used: @affiliate.affiliate_code,
        status: :converted
      ),
      entity: entities(:one),
      amount: 100.00,
      commission_type: "signup",
      status: :pending
    )

    visit admin_commissions_path

    within "#commission_#{commission.id}" do
      click_button "Approve"
    end

    assert_text "Commission approved"
    commission.reload
    assert_equal "approved", commission.status
  end

  test "admin can bulk approve commissions" do
    3.times do |i|
      Commission.create!(
        affiliate: @affiliate,
        referral: Referral.create!(
          affiliate: @affiliate,
          referral_code_used: @affiliate.affiliate_code,
          status: :converted
        ),
        entity: entities(:one),
        amount: 100.00,
        commission_type: "signup",
        status: :pending
      )
    end

    visit admin_commissions_path

    check "select_all"
    click_button "Bulk Approve Selected"

    assert_text "3 commissions approved"
  end

  test "admin can create payout" do
    commission = Commission.create!(
      affiliate: @affiliate,
      referral: Referral.create!(
        affiliate: @affiliate,
        referral_code_used: @affiliate.affiliate_code,
        status: :converted
      ),
      entity: entities(:one),
      amount: 100.00,
      commission_type: "signup",
      status: :approved
    )

    visit new_admin_payout_path

    select @affiliate.user.email, from: "Affiliate"
    fill_in "Amount", with: "100.00"
    select "PayPal", from: "Payment method"
    
    click_button "Create Payout"

    assert_text "Payout created successfully"
    assert Payout.exists?(affiliate: @affiliate, amount: 100.00)
  end

  test "admin can mark payout as completed" do
    payout = Payout.create!(
      affiliate: @affiliate,
      amount: 500.00,
      status: :processing,
      payment_method: "PayPal"
    )

    visit admin_payout_path(payout)

    fill_in "Transaction ID", with: "PAYPAL123456"
    click_button "Mark as Completed"

    assert_text "Payout marked as completed"
    payout.reload
    assert_equal "completed", payout.status
    assert_equal "PAYPAL123456", payout.transaction_id
  end

  test "admin can view affiliate analytics" do
    visit admin_analytics_affiliates_path

    assert_text "Affiliate Analytics"
    assert_text "Total Affiliates"
    assert_text "Total Commissions"
    assert_text "Total Payouts"
  end

  test "admin can configure affiliate settings" do
    visit admin_settings_affiliate_path

    fill_in "Default commission rate", with: "0.25"
    fill_in "Cookie duration (days)", with: "60"
    fill_in "Minimum payout threshold", with: "100"

    click_button "Update Settings"

    assert_text "Affiliate settings updated"
  end

  private

  def sign_in_as_admin(admin)
    visit admin_login_path
    fill_in "Email", with: admin.email
    fill_in "Password", with: "password"
    click_button "Sign In"
  end
end
