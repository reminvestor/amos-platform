require "test_helper"

class AffiliateStatsServiceTest < ActiveSupport::TestCase
  def setup
    @affiliate = affiliates(:active_affiliate)
    @service = AffiliateStatsService.new(@affiliate)
  end

  # Basic stats calculation
  test "calculate returns hash with all expected keys" do
    stats = @service.calculate

    assert stats.key?(:clicks_this_month)
    assert stats.key?(:clicks_all_time)
    assert stats.key?(:total_conversions)
    assert stats.key?(:pending_referrals)
    assert stats.key?(:conversion_rate)
    assert stats.key?(:pending_commissions)
    assert stats.key?(:approved_commissions)
    assert stats.key?(:paid_commissions)
    assert stats.key?(:total_earned)
    assert stats.key?(:total_paid)
    assert stats.key?(:average_commission)
    assert stats.key?(:current_tier)
    assert stats.key?(:balance)
  end

  test "calculate returns zero values for affiliate with no activity" do
    new_affiliate = Affiliate.create!(
      user: users(:one),
      commission_rate: 0.20
    )
    service = AffiliateStatsService.new(new_affiliate)

    stats = service.calculate

    assert_equal 0, stats[:clicks_this_month]
    assert_equal 0, stats[:clicks_all_time]
    assert_equal 0, stats[:total_conversions]
    assert_equal 0, stats[:pending_referrals]
    assert_equal 0.0, stats[:conversion_rate]
    assert_equal 0.0, stats[:pending_commissions]
    assert_equal 0.0, stats[:total_earned]
  end

  test "clicks_all_time counts all affiliate clicks" do
    # Create additional clicks
    2.times do
      AffiliateClick.create!(
        affiliate: @affiliate,
        referral_code: @affiliate.affiliate_code,
        ip_address: '192.168.1.1',
        landed_at: Time.current
      )
    end

    stats = @service.calculate
    expected_count = @affiliate.affiliate_clicks.count

    assert_equal expected_count, stats[:clicks_all_time]
  end

  test "clicks_this_month counts only current month clicks" do
    # Create clicks from this month
    AffiliateClick.create!(
      affiliate: @affiliate,
      referral_code: @affiliate.affiliate_code,
      ip_address: '192.168.1.1',
      landed_at: Time.current
    )

    # Create clicks from last month (should not be counted)
    AffiliateClick.create!(
      affiliate: @affiliate,
      referral_code: @affiliate.affiliate_code,
      ip_address: '192.168.1.2',
      landed_at: 2.months.ago
    )

    stats = @service.calculate
    expected_count = @affiliate.affiliate_clicks
                               .where('landed_at >= ?', Time.current.beginning_of_month)
                               .count

    assert_equal expected_count, stats[:clicks_this_month]
  end

  test "total_conversions counts converted referrals" do
    stats = @service.calculate
    expected = @affiliate.referrals.where(status: :converted).count

    assert_equal expected, stats[:total_conversions]
  end

  test "pending_referrals counts pending referrals" do
    stats = @service.calculate
    expected = @affiliate.referrals.where(status: :pending).count

    assert_equal expected, stats[:pending_referrals]
  end

  test "conversion_rate calculates percentage correctly" do
    # Ensure we have clicks and conversions
    3.times do |i|
      AffiliateClick.create!(
        affiliate: @affiliate,
        referral_code: @affiliate.affiliate_code,
        ip_address: "192.168.1.#{i}",
        landed_at: Time.current
      )
    end

    stats = @service.calculate
    total_clicks = @affiliate.affiliate_clicks.count
    conversions = @affiliate.referrals.where(status: :converted).count

    if total_clicks > 0
      expected_rate = (conversions.to_f / total_clicks * 100).round(2)
      assert_equal expected_rate, stats[:conversion_rate]
    else
      assert_equal 0.0, stats[:conversion_rate]
    end
  end

  test "conversion_rate returns 0 when no clicks" do
    new_affiliate = Affiliate.create!(
      user: users(:one),
      commission_rate: 0.20
    )
    service = AffiliateStatsService.new(new_affiliate)

    stats = service.calculate
    assert_equal 0.0, stats[:conversion_rate]
  end

  test "pending_commissions sums pending commission amounts" do
    stats = @service.calculate
    expected = @affiliate.commissions.where(status: :pending).sum(:amount).to_f

    assert_equal expected, stats[:pending_commissions]
  end

  test "approved_commissions sums approved commission amounts" do
    stats = @service.calculate
    expected = @affiliate.commissions.where(status: :approved).sum(:amount).to_f

    assert_equal expected, stats[:approved_commissions]
  end

  test "paid_commissions sums paid commission amounts" do
    stats = @service.calculate
    expected = @affiliate.commissions.where(status: :paid).sum(:amount).to_f

    assert_equal expected, stats[:paid_commissions]
  end

  test "total_earned sums all commission amounts" do
    stats = @service.calculate
    expected = @affiliate.commissions.sum(:amount).to_f

    assert_equal expected, stats[:total_earned]
  end

  test "total_paid sums completed payout amounts" do
    stats = @service.calculate
    expected = @affiliate.payouts.where(status: :completed).sum(:amount).to_f

    assert_equal expected, stats[:total_paid]
  end

  test "average_commission calculates average amount" do
    # Create commissions with known amounts
    Commission.create!(
      affiliate: @affiliate,
      referral: referrals(:converted_referral),
      entity: entities(:one),
      commission_type: 'first_payment',
      amount: 100,
      earned_at: Time.current
    )

    Commission.create!(
      affiliate: @affiliate,
      referral: referrals(:converted_referral),
      entity: entities(:one),
      commission_type: 'recurring',
      amount: 50,
      earned_at: Time.current
    )

    @affiliate.reload
    stats = @service.calculate

    total = @affiliate.commissions.sum(:amount).to_f
    count = @affiliate.commissions.count
    expected_avg = (total / count).round(2)

    assert_equal expected_avg, stats[:average_commission]
  end

  test "average_commission returns 0 when no commissions" do
    new_affiliate = Affiliate.create!(
      user: users(:one),
      commission_rate: 0.20
    )
    service = AffiliateStatsService.new(new_affiliate)

    stats = service.calculate
    assert_equal 0.0, stats[:average_commission]
  end

  test "balance equals approved_commissions" do
    stats = @service.calculate

    assert_equal stats[:approved_commissions], stats[:balance]
  end

  # Detailed stats tests
  test "detailed_stats includes all calculate stats" do
    stats = @service.detailed_stats
    basic_stats = @service.calculate

    basic_stats.each do |key, value|
      assert stats.key?(key), "detailed_stats should include #{key}"
    end
  end

  test "detailed_stats includes additional time-based metrics" do
    stats = @service.detailed_stats

    assert stats.key?(:clicks_last_7_days)
    assert stats.key?(:clicks_last_30_days)
    assert stats.key?(:conversions_this_month)
    assert stats.key?(:commissions_this_month)
  end

  test "detailed_stats includes advanced metrics" do
    stats = @service.detailed_stats

    assert stats.key?(:average_time_to_conversion)
    assert stats.key?(:best_performing_month)
    assert stats.key?(:referral_retention_rate)
  end

  test "detailed_stats includes recent activity" do
    stats = @service.detailed_stats

    assert stats.key?(:recent_referrals)
    assert stats.key?(:recent_commissions)
    assert stats.key?(:recent_payouts)
  end

  # Chart data tests
  test "chart_data returns hash with labels and clicks" do
    chart = @service.chart_data(7)

    assert chart.key?(:labels)
    assert chart.key?(:clicks)
    assert_equal 8, chart[:labels].length # 7 days + today
    assert_equal 8, chart[:clicks].length
  end

  test "chart_data formats labels as MM/DD" do
    chart = @service.chart_data(7)

    chart[:labels].each do |label|
      assert_match /\d{2}\/\d{2}/, label
    end
  end

  test "chart_data counts clicks for each day" do
    # Create clicks on specific days
    2.days.ago.to_date.tap do |date|
      AffiliateClick.create!(
        affiliate: @affiliate,
        referral_code: @affiliate.affiliate_code,
        ip_address: '192.168.1.1',
        landed_at: date.to_time
      )
    end

    chart = @service.chart_data(7)

    # All values should be >= 0
    chart[:clicks].each do |count|
      assert count >= 0
    end
  end

  test "chart_data uses custom period" do
    chart = @service.chart_data(14)

    assert_equal 15, chart[:labels].length # 14 days + today
    assert_equal 15, chart[:clicks].length
  end
end
