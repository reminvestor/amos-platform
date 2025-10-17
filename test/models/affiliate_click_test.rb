require "test_helper"

class AffiliateClickTest < ActiveSupport::TestCase
  # Validation tests
  test "should require referral_code" do
    click = AffiliateClick.new(
      affiliate: affiliates(:active_affiliate),
      ip_address: '192.168.1.1',
      landed_at: Time.current
    )
    click.referral_code = nil

    assert_not click.valid?
    assert_includes click.errors[:referral_code], "can't be blank"
  end

  # Association tests
  test "should belong to affiliate" do
    click = affiliate_clicks(:recent_click)
    assert_respond_to click, :affiliate
    assert_instance_of Affiliate, click.affiliate
  end

  # Scope tests
  test "recent scope should order by landed_at desc" do
    clicks = AffiliateClick.recent.limit(2).to_a

    if clicks.size >= 2
      assert clicks[0].landed_at >= clicks[1].landed_at
    end
  end

  test "for_date_range scope should filter by date range" do
    start_date = 5.days.ago
    end_date = Time.current

    clicks = AffiliateClick.for_date_range(start_date, end_date)

    clicks.each do |click|
      assert click.landed_at >= start_date
      assert click.landed_at <= end_date
    end
  end

  test "for_date_range scope returns all when dates are nil" do
    all_count = AffiliateClick.count
    filtered = AffiliateClick.for_date_range(nil, nil).count

    assert_equal all_count, filtered
  end

  # Data storage tests
  test "should store ip_address" do
    click = affiliate_clicks(:recent_click)
    assert_equal '192.168.1.100', click.ip_address
  end

  test "should store user_agent" do
    click = affiliate_clicks(:recent_click)
    assert_not_nil click.user_agent
    assert click.user_agent.include?('Mozilla')
  end

  test "should store referrer" do
    click = affiliate_clicks(:recent_click)
    assert_equal 'https://google.com', click.referrer
  end

  test "should store session_id" do
    click = affiliate_clicks(:recent_click)
    assert_not_nil click.session_id
  end

  test "should store metadata as json" do
    click = affiliate_clicks(:recent_click)

    assert_instance_of Hash, click.metadata
    assert_equal 'twitter', click.metadata['utm_source']
    assert_equal 'social', click.metadata['utm_medium']
    assert_equal 'spring_promo', click.metadata['utm_campaign']
  end

  test "should allow empty metadata" do
    click = AffiliateClick.create!(
      affiliate: affiliates(:active_affiliate),
      referral_code: 'TEST123',
      ip_address: '192.168.1.1',
      landed_at: Time.current
    )

    assert_equal({}, click.metadata)
  end

  test "should track landed_at timestamp" do
    click = affiliate_clicks(:recent_click)
    assert_instance_of ActiveSupport::TimeWithZone, click.landed_at
  end

  # Creation tests
  test "should create click with all attributes" do
    click = AffiliateClick.create!(
      affiliate: affiliates(:active_affiliate),
      referral_code: 'ACTIVE123',
      ip_address: '10.0.0.1',
      user_agent: 'Test Browser',
      referrer: 'https://example.com',
      landed_at: Time.current,
      session_id: 'session_xyz',
      metadata: {
        utm_source: 'email',
        utm_campaign: 'newsletter'
      }
    )

    assert click.persisted?
    assert_equal 'ACTIVE123', click.referral_code
    assert_equal '10.0.0.1', click.ip_address
    assert_equal 'email', click.metadata['utm_source']
  end

  test "referrer can be null" do
    click = AffiliateClick.create!(
      affiliate: affiliates(:active_affiliate),
      referral_code: 'TEST123',
      ip_address: '192.168.1.1',
      landed_at: Time.current,
      referrer: nil
    )

    assert click.persisted?
    assert_nil click.referrer
  end
end
