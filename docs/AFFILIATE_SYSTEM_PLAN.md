# AFFILIATE MARKETING SYSTEM - IMPLEMENTATION PLAN

## 🎯 System Overview

A complete affiliate program where users can refer new customers, track referrals, earn commissions, and get paid. Admins can manage affiliates, set commission structures, and process payouts.

---

## 📊 PHASE 1: Database & Models (Foundation)

### New Database Tables

#### 1. `affiliates` - Core affiliate records
```ruby
create_table :affiliates do |t|
  t.references :user, null: false, foreign_key: true
  t.string :affiliate_code, null: false, index: { unique: true }
  t.integer :status, default: 0, null: false  # enum: pending, active, suspended, terminated
  t.decimal :commission_rate, precision: 5, scale: 4, default: 0.20  # 20%
  t.string :payment_email
  t.text :application_notes
  t.datetime :approved_at
  t.references :approved_by, foreign_key: { to_table: :admin_users }
  t.string :tier, default: 'bronze'  # bronze/silver/gold
  t.timestamps
end
```

#### 2. `referrals` - Track who was referred by whom
```ruby
create_table :referrals do |t|
  t.references :affiliate, null: false, foreign_key: true
  t.references :referred_user, foreign_key: { to_table: :users }
  t.references :referred_entity, foreign_key: { to_table: :entities }
  t.string :referral_code_used
  t.integer :status, default: 0  # enum: pending, converted, cancelled
  t.datetime :converted_at
  t.jsonb :cookie_data, default: {}
  t.timestamps

  t.index [:affiliate_id, :referred_entity_id]
end
```

#### 3. `affiliate_clicks` - Track link clicks
```ruby
create_table :affiliate_clicks do |t|
  t.references :affiliate, null: false, foreign_key: true
  t.string :referral_code
  t.string :ip_address
  t.text :user_agent
  t.string :referrer
  t.datetime :landed_at
  t.string :session_id
  t.jsonb :metadata, default: {}  # UTM params, etc.
  t.timestamps

  t.index :landed_at
  t.index [:affiliate_id, :landed_at]
end
```

#### 4. `commissions` - Earned commissions
```ruby
create_table :commissions do |t|
  t.references :affiliate, null: false, foreign_key: true
  t.references :referral, null: false, foreign_key: true
  t.references :entity, null: false, foreign_key: true
  t.string :commission_type  # signup_bonus, first_payment, recurring, lifetime
  t.decimal :amount, precision: 10, scale: 2, null: false
  t.string :currency, default: 'USD'
  t.integer :status, default: 0  # enum: pending, approved, paid, cancelled
  t.references :subscription_event, foreign_key: true
  t.datetime :earned_at
  t.datetime :approved_at
  t.references :approved_by, foreign_key: { to_table: :admin_users }
  t.timestamps

  t.index [:affiliate_id, :status]
  t.index [:status, :approved_at]
end
```

#### 5. `payouts` - Payment batches to affiliates
```ruby
create_table :payouts do |t|
  t.references :affiliate, null: false, foreign_key: true
  t.decimal :amount, precision: 10, scale: 2, null: false
  t.string :currency, default: 'USD'
  t.string :payment_method  # paypal, stripe, manual
  t.string :payment_reference
  t.integer :status, default: 0  # enum: pending, processing, completed, failed
  t.date :payout_date
  t.text :notes
  t.integer :commission_ids, array: true, default: []
  t.references :processed_by, foreign_key: { to_table: :admin_users }
  t.timestamps

  t.index [:affiliate_id, :status]
  t.index :payout_date
end
```

#### 6. `affiliate_tiers` - Different commission levels
```ruby
create_table :affiliate_tiers do |t|
  t.string :name, null: false
  t.decimal :commission_rate, precision: 5, scale: 4, null: false
  t.integer :min_referrals, default: 0
  t.jsonb :benefits, default: {}
  t.boolean :is_active, default: true
  t.timestamps

  t.index :name, unique: true
end
```

### Model Relationships

```ruby
# app/models/affiliate.rb
class Affiliate < ApplicationRecord
  belongs_to :user
  belongs_to :approved_by, class_name: 'AdminUser', optional: true
  has_many :referrals, dependent: :restrict_with_error
  has_many :affiliate_clicks, dependent: :destroy
  has_many :commissions, dependent: :restrict_with_error
  has_many :payouts, dependent: :restrict_with_error

  enum status: { pending: 0, active: 1, suspended: 2, terminated: 3 }
  enum tier: { bronze: 0, silver: 1, gold: 2 }

  validates :affiliate_code, presence: true, uniqueness: true
  validates :commission_rate, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }

  before_validation :generate_affiliate_code, on: :create

  private

  def generate_affiliate_code
    self.affiliate_code ||= SecureRandom.alphanumeric(8).upcase
  end
end

# app/models/referral.rb
class Referral < ApplicationRecord
  belongs_to :affiliate
  belongs_to :referred_user, class_name: 'User', optional: true
  belongs_to :referred_entity, class_name: 'Entity', optional: true
  has_many :commissions, dependent: :restrict_with_error

  enum status: { pending: 0, converted: 1, cancelled: 2 }

  validates :referral_code_used, presence: true
end

# app/models/commission.rb
class Commission < ApplicationRecord
  belongs_to :affiliate
  belongs_to :referral
  belongs_to :entity
  belongs_to :subscription_event, optional: true
  belongs_to :approved_by, class_name: 'AdminUser', optional: true

  enum status: { pending: 0, approved: 1, paid: 2, cancelled: 3 }

  validates :amount, numericality: { greater_than: 0 }
  validates :commission_type, presence: true
end

# app/models/payout.rb
class Payout < ApplicationRecord
  belongs_to :affiliate
  belongs_to :processed_by, class_name: 'AdminUser', optional: true

  enum status: { pending: 0, processing: 1, completed: 2, failed: 3 }

  validates :amount, numericality: { greater_than: 0 }
  validates :payment_method, presence: true
end
```

---

## 🎨 PHASE 2: Affiliate User Experience (Public-Facing)

### A. Affiliate Registration & Onboarding

**Route:** `GET /affiliate/apply`

**Controller:** `app/controllers/affiliate/applications_controller.rb`

```ruby
class Affiliate::ApplicationsController < ApplicationController
  before_action :authenticate_user!

  def new
    @affiliate_application = Affiliate.new
  end

  def create
    @affiliate_application = current_user.build_affiliate(affiliate_params)

    if @affiliate_application.save
      # Notify admins
      AdminMailer.new_affiliate_application(@affiliate_application).deliver_later
      redirect_to affiliate_dashboard_path, notice: "Application submitted! We'll review it within 2 business days."
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def affiliate_params
    params.require(:affiliate).permit(:application_notes, :payment_email)
  end
end
```

**View:** `app/views/affiliate/applications/new.html.erb`
- Explanation of program benefits
- Commission structure details
- Application form with fields:
  - Why do you want to join?
  - How will you promote AMOS?
  - Website/social media links (optional)
  - Payment email (PayPal)

### B. Affiliate Dashboard

**Route:** `GET /affiliate/dashboard`

**Controller:** `app/controllers/affiliate/dashboard_controller.rb`

```ruby
class Affiliate::DashboardController < ApplicationController
  before_action :authenticate_user!
  before_action :ensure_affiliate

  def show
    @affiliate = current_user.affiliate
    @stats = AffiliateStatsService.new(@affiliate).calculate
    @recent_activity = @affiliate.recent_activity(limit: 10)
  end

  private

  def ensure_affiliate
    redirect_to affiliate_apply_path unless current_user.affiliate&.active?
  end
end
```

**Dashboard Components:**

1. **Overview Cards:**
   - Total clicks (this month)
   - Total conversions (all time)
   - Pending commissions ($)
   - Paid out total ($)
   - Current tier badge

2. **Referral Link Section:**
   - Display: `https://amos.com/signup?ref=JOHN2024`
   - Copy button (Stimulus controller)
   - QR code generator
   - Social share buttons

3. **Performance Charts:**
   - Clicks over last 30 days (Chart.js line chart)
   - Conversion funnel (clicks → signups → paying)

4. **Recent Activity Table:**
   - Columns: Date | Event | User | Status | Commission
   - Events: Click, Signup, Conversion, Payout

### C. Affiliate Resources

**Route:** `GET /affiliate/resources`

**Features:**
- Logo downloads (SVG, PNG in multiple sizes)
- Banner images (300x250, 728x90, 1200x628)
- Pre-written social posts
- Email template suggestions
- Landing page copy examples
- Brand guidelines PDF

### D. Payout History

**Route:** `GET /affiliate/payouts`

**Controller:** `app/controllers/affiliate/payouts_controller.rb`

```ruby
class Affiliate::PayoutsController < ApplicationController
  before_action :authenticate_user!
  before_action :ensure_affiliate

  def index
    @payouts = current_user.affiliate.payouts.order(created_at: :desc).page(params[:page])
  end
end
```

**View:** Table showing:
- Date | Amount | Method | Status | Transaction ID
- Filter by status, date range
- Export to CSV button

---

## 🔧 PHASE 3: Tracking & Attribution System

### A. Cookie-Based Tracking

**Implementation:** `app/controllers/concerns/affiliate_tracking.rb`

```ruby
module AffiliateTracking
  extend ActiveSupport::Concern

  included do
    before_action :track_affiliate_referral, if: :affiliate_ref_param?
  end

  private

  def affiliate_ref_param?
    params[:ref].present?
  end

  def track_affiliate_referral
    affiliate = Affiliate.find_by(affiliate_code: params[:ref], status: :active)
    return unless affiliate

    # Set cookie for 60 days
    cookies.signed[:affiliate_ref] = {
      value: params[:ref],
      expires: 60.days.from_now,
      httponly: true,
      secure: Rails.env.production?
    }

    # Log the click
    AffiliateClick.create!(
      affiliate: affiliate,
      referral_code: params[:ref],
      ip_address: request.remote_ip,
      user_agent: request.user_agent,
      referrer: request.referrer,
      session_id: session.id.to_s,
      landed_at: Time.current,
      metadata: {
        utm_source: params[:utm_source],
        utm_medium: params[:utm_medium],
        utm_campaign: params[:utm_campaign]
      }
    )
  end

  def affiliate_referral_code
    cookies.signed[:affiliate_ref]
  end
end
```

**Apply to Controllers:**
- `app/controllers/users/registrations_controller.rb`
- `app/controllers/marketing_controller.rb`
- `app/controllers/home_controller.rb`

### B. Conversion Tracking on Signup

**Modify:** `app/controllers/users/registrations_controller.rb`

```ruby
class Users::RegistrationsController < Devise::RegistrationsController
  include AffiliateTracking

  def create
    super do |user|
      if user.persisted? && affiliate_referral_code.present?
        AffiliateReferralService.create_referral(
          referral_code: affiliate_referral_code,
          user: user,
          entity: user.entity,
          cookie_data: {
            ip: request.remote_ip,
            user_agent: request.user_agent
          }
        )

        # Clear the cookie
        cookies.delete(:affiliate_ref)
      end
    end
  end
end
```

**Service:** `app/services/affiliate_referral_service.rb`

```ruby
class AffiliateReferralService
  def self.create_referral(referral_code:, user:, entity:, cookie_data:)
    affiliate = Affiliate.find_by(affiliate_code: referral_code, status: :active)
    return unless affiliate

    Referral.create!(
      affiliate: affiliate,
      referred_user: user,
      referred_entity: entity,
      referral_code_used: referral_code,
      status: :pending,
      cookie_data: cookie_data
    )

    # Notify affiliate of new signup
    AffiliateMailer.new_referral_signup(affiliate, user).deliver_later
  end
end
```

### C. Commission Creation on Payment

**Modify:** `app/controllers/webhooks_controller.rb`

Add to Stripe webhook handler:

```ruby
class WebhooksController < ApplicationController
  # ... existing code ...

  def handle_stripe_webhook
    case event.type
    when 'checkout.session.completed'
      handle_checkout_completed(event.data.object)
    when 'invoice.payment_succeeded'
      handle_invoice_payment(event.data.object)
    end
  end

  private

  def handle_checkout_completed(session)
    entity = Entity.find_by(stripe_customer_id: session.customer)
    return unless entity

    # Create affiliate commission for first payment
    AffiliateCommissionService.create_for_first_payment(entity, session.amount_total / 100.0)
  end

  def handle_invoice_payment(invoice)
    entity = Entity.find_by(stripe_customer_id: invoice.customer)
    return unless entity

    # Create recurring commission if within 12 months
    AffiliateCommissionService.create_for_recurring_payment(entity, invoice.amount_paid / 100.0)
  end
end
```

**Service:** `app/services/affiliate_commission_service.rb`

```ruby
class AffiliateCommissionService
  def self.create_for_first_payment(entity, amount)
    referral = Referral.find_by(referred_entity: entity, status: :pending)
    return unless referral

    commission_amount = amount * referral.affiliate.commission_rate

    Commission.create!(
      affiliate: referral.affiliate,
      referral: referral,
      entity: entity,
      commission_type: 'first_payment',
      amount: commission_amount,
      currency: 'USD',
      status: :pending,
      earned_at: Time.current
    )

    # Mark referral as converted
    referral.update!(status: :converted, converted_at: Time.current)

    # Notify affiliate
    AffiliateMailer.commission_earned(referral.affiliate, commission_amount).deliver_later
  end

  def self.create_for_recurring_payment(entity, amount)
    referral = Referral.find_by(referred_entity: entity, status: :converted)
    return unless referral

    # Only pay recurring commissions for first 12 months
    return if referral.converted_at < 12.months.ago

    commission_amount = amount * referral.affiliate.commission_rate

    Commission.create!(
      affiliate: referral.affiliate,
      referral: referral,
      entity: entity,
      commission_type: 'recurring',
      amount: commission_amount,
      currency: 'USD',
      status: :pending,
      earned_at: Time.current
    )
  end
end
```

---

## 🛠️ PHASE 4: Admin Panel (Admin-Only Routes)

### A. Affiliate Management Dashboard

**Route:** `GET /admin/affiliates`

**Controller:** `app/controllers/admin/affiliates_controller.rb`

```ruby
class Admin::AffiliatesController < Admin::BaseController
  def index
    @affiliates = Affiliate.includes(:user)
                          .filter_by_status(params[:status])
                          .filter_by_tier(params[:tier])
                          .search(params[:query])
                          .order(created_at: :desc)
                          .page(params[:page])
  end

  def show
    @affiliate = Affiliate.includes(:referrals, :commissions, :payouts).find(params[:id])
    @stats = AffiliateStatsService.new(@affiliate).detailed_stats
  end

  def approve
    @affiliate = Affiliate.find(params[:id])
    @affiliate.update!(status: :active, approved_at: Time.current, approved_by: current_admin_user)

    AffiliateMailer.application_approved(@affiliate).deliver_later
    redirect_to admin_affiliate_path(@affiliate), notice: "Affiliate approved!"
  end

  def suspend
    @affiliate = Affiliate.find(params[:id])
    @affiliate.update!(status: :suspended)

    redirect_to admin_affiliate_path(@affiliate), notice: "Affiliate suspended."
  end

  def update_commission_rate
    @affiliate = Affiliate.find(params[:id])
    @affiliate.update!(commission_rate: params[:affiliate][:commission_rate])

    redirect_to admin_affiliate_path(@affiliate), notice: "Commission rate updated."
  end
end
```

**View Features:**
- Table with columns: Name | Email | Code | Status | Tier | Clicks | Conversions | Total Earned | Actions
- Filters: Status dropdown, Tier dropdown, Date range
- Search box (by name, email, code)
- Bulk actions (approve selected, suspend selected)
- Export to CSV button

### B. Commission Management

**Route:** `GET /admin/commissions`

**Controller:** `app/controllers/admin/commissions_controller.rb`

```ruby
class Admin::CommissionsController < Admin::BaseController
  def index
    @commissions = Commission.includes(:affiliate, :referral, :entity)
                            .filter_by_status(params[:status])
                            .filter_by_date_range(params[:date_from], params[:date_to])
                            .order(earned_at: :desc)
                            .page(params[:page])

    @total_pending = Commission.pending.sum(:amount)
    @total_approved = Commission.approved.sum(:amount)
  end

  def approve
    @commission = Commission.find(params[:id])
    @commission.update!(
      status: :approved,
      approved_at: Time.current,
      approved_by: current_admin_user
    )

    redirect_to admin_commissions_path, notice: "Commission approved."
  end

  def bulk_approve
    commission_ids = params[:commission_ids]
    Commission.where(id: commission_ids, status: :pending).update_all(
      status: :approved,
      approved_at: Time.current,
      approved_by_id: current_admin_user.id
    )

    redirect_to admin_commissions_path, notice: "#{commission_ids.count} commissions approved."
  end

  def cancel
    @commission = Commission.find(params[:id])
    @commission.update!(status: :cancelled)

    redirect_to admin_commissions_path, notice: "Commission cancelled."
  end
end
```

**View Features:**
- Table: Affiliate | Referral | Customer | Type | Amount | Status | Date | Actions
- Filters: Status, Date range, Affiliate
- Bulk approve checkbox selection
- Export to CSV

### C. Payout Processing

**Route:** `GET /admin/payouts`

**Controller:** `app/controllers/admin/payouts_controller.rb`

```ruby
class Admin::PayoutsController < Admin::BaseController
  def index
    @payouts = Payout.includes(:affiliate).order(created_at: :desc).page(params[:page])
    @pending_commissions_total = Commission.approved.sum(:amount)
    @ready_for_payout_count = Affiliate.with_approved_commissions.count
  end

  def new
    @affiliates_ready = Affiliate.with_approved_commissions_above_threshold(50)
  end

  def create
    result = PayoutBatchService.create_batch(
      affiliate_ids: params[:affiliate_ids],
      payment_method: params[:payment_method],
      admin_user: current_admin_user
    )

    if result.success?
      redirect_to admin_payouts_path, notice: "#{result.payouts.count} payouts created."
    else
      redirect_to new_admin_payout_path, alert: result.error
    end
  end

  def mark_completed
    @payout = Payout.find(params[:id])
    @payout.update!(
      status: :completed,
      payment_reference: params[:payment_reference],
      processed_by: current_admin_user
    )

    # Mark commissions as paid
    Commission.where(id: @payout.commission_ids).update_all(status: :paid)

    # Notify affiliate
    AffiliateMailer.payout_completed(@payout).deliver_later

    redirect_to admin_payouts_path, notice: "Payout marked as completed."
  end
end
```

**Service:** `app/services/payout_batch_service.rb`

```ruby
class PayoutBatchService
  Result = Struct.new(:success?, :payouts, :error)

  def self.create_batch(affiliate_ids:, payment_method:, admin_user:)
    payouts = []

    Affiliate.where(id: affiliate_ids).find_each do |affiliate|
      commissions = affiliate.commissions.approved
      total_amount = commissions.sum(:amount)

      next if total_amount < 50 # Minimum threshold

      payout = Payout.create!(
        affiliate: affiliate,
        amount: total_amount,
        currency: 'USD',
        payment_method: payment_method,
        status: :pending,
        payout_date: Date.today,
        commission_ids: commissions.pluck(:id),
        processed_by: admin_user
      )

      payouts << payout
    end

    Result.new(true, payouts, nil)
  rescue => e
    Result.new(false, [], e.message)
  end
end
```

**View Features:**
- Overview panel:
  - Total pending commissions: $X,XXX
  - Total approved (ready to pay): $X,XXX
  - Number of affiliates awaiting payment

- Batch payout form:
  - Checkbox list of affiliates with amounts
  - Minimum threshold filter ($50+)
  - Payment method dropdown (PayPal/Stripe/Manual)
  - Preview total amount
  - Confirm button

- Payout history table:
  - Date | Affiliate | Amount | Method | Status | Reference | Actions
  - Mark as completed button
  - Add payment reference field
  - Download report (CSV)

### D. Affiliate Settings

**Route:** `GET /admin/settings/affiliate`

**Controller:** `app/controllers/admin/settings/affiliate_controller.rb`

```ruby
class Admin::Settings::AffiliateController < Admin::BaseController
  def show
    @settings = AffiliateSettings.instance
    @tiers = AffiliateTier.all
  end

  def update
    @settings = AffiliateSettings.instance

    if @settings.update(settings_params)
      redirect_to admin_settings_affiliate_path, notice: "Settings updated."
    else
      render :show
    end
  end

  private

  def settings_params
    params.require(:affiliate_settings).permit(
      :default_commission_rate,
      :cookie_duration_days,
      :minimum_payout_threshold,
      :auto_approve_applications,
      :require_review_for_high_commissions,
      :high_commission_threshold
    )
  end
end
```

**Settings to Configure:**
- Global commission rate (default for new affiliates)
- Cookie tracking duration (days)
- Minimum payout threshold ($)
- Auto-approve applications (boolean)
- Require admin review for commissions over $X
- Commission structure toggles:
  - [x] First payment commission
  - [x] Recurring payment commission (12 months)
  - [ ] Signup bonus ($X flat fee)
  - [ ] Lifetime commission

**Tier Management:**
- Edit existing tiers (Bronze/Silver/Gold)
- Set min referrals threshold for each tier
- Set commission rate per tier
- Add/remove tiers

### E. Analytics Dashboard

**Route:** `GET /admin/analytics/affiliates`

**Controller:** `app/controllers/admin/analytics/affiliates_controller.rb`

```ruby
class Admin::Analytics::AffiliatesController < Admin::BaseController
  def index
    date_range = params[:date_range] || '30days'
    @analytics = AffiliateAnalyticsService.new(date_range).generate_report
  end
end
```

**Metrics to Display:**
- Total affiliates (active vs pending)
- Total clicks (this period vs last period)
- Total conversions (count + revenue)
- Average conversion rate (%)
- Total commissions earned ($)
- Total payouts processed ($)
- Top 10 performing affiliates (by revenue)
- Conversion funnel chart (clicks → signups → paying)
- Monthly trend charts:
  - Affiliate signups over time
  - Commission earnings over time
  - Payout processing over time
- Average time to conversion (days)
- Customer lifetime value by referral source

**Export Options:**
- Export full report as CSV
- Custom date range selector
- Filter by affiliate, tier, status

---

## 🔐 PHASE 5: Security & Compliance

### Security Measures

1. **Fraud Detection**
```ruby
# app/services/affiliate_fraud_detector.rb
class AffiliateFraudDetector
  def self.check_suspicious_activity(affiliate)
    flags = []

    # Check for multiple signups from same IP
    recent_referrals = affiliate.referrals.where('created_at > ?', 7.days.ago)
    ip_addresses = recent_referrals.pluck(:cookie_data).map { |d| d['ip'] }

    if ip_addresses.group_by(&:itself).any? { |ip, occurrences| occurrences.count > 3 }
      flags << 'Multiple signups from same IP'
    end

    # Check for abnormally high conversion rate
    clicks = affiliate.affiliate_clicks.where('landed_at > ?', 30.days.ago).count
    conversions = affiliate.referrals.converted.where('created_at > ?', 30.days.ago).count
    conversion_rate = conversions.to_f / clicks if clicks > 0

    if conversion_rate && conversion_rate > 0.5
      flags << 'Unusually high conversion rate'
    end

    # Check for rapid-fire clicks
    recent_clicks = affiliate.affiliate_clicks.where('landed_at > ?', 1.hour.ago)
    if recent_clicks.count > 100
      flags << 'Abnormally high click volume'
    end

    flags
  end
end
```

2. **Rate Limiting**
```ruby
# app/controllers/concerns/affiliate_tracking.rb
def track_affiliate_referral
  # ... existing code ...

  # Rate limit: Max 100 clicks per IP per hour
  recent_clicks = AffiliateClick.where(
    ip_address: request.remote_ip,
    landed_at: 1.hour.ago..Time.current
  ).count

  return if recent_clicks > 100

  # ... create click record ...
end
```

3. **Admin Review for High-Value Commissions**
```ruby
# app/services/affiliate_commission_service.rb
def self.create_for_first_payment(entity, amount)
  # ... existing code ...

  commission_amount = amount * referral.affiliate.commission_rate

  # Auto-approve small commissions, require review for large ones
  status = commission_amount > 500 ? :pending : :approved

  Commission.create!(
    # ... other attributes ...
    status: status
  )

  if status == :pending
    AdminMailer.high_value_commission_review(commission).deliver_later
  end
end
```

4. **Two-Factor Authentication for Payouts**
```ruby
# Add to Admin::PayoutsController
before_action :verify_2fa, only: [:create, :mark_completed]

def verify_2fa
  unless session[:2fa_verified_at] && session[:2fa_verified_at] > 10.minutes.ago
    redirect_to admin_2fa_verification_path(return_to: request.fullpath)
  end
end
```

5. **Audit Logging**
```ruby
# app/models/concerns/auditable.rb
module Auditable
  extend ActiveSupport::Concern

  included do
    after_create :log_creation
    after_update :log_update
  end

  private

  def log_creation
    AdminActivity.create!(
      admin_user: Current.admin_user,
      action: 'create',
      resource_type: self.class.name,
      resource_id: self.id,
      details: self.attributes.to_json
    )
  end

  def log_update
    AdminActivity.create!(
      admin_user: Current.admin_user,
      action: 'update',
      resource_type: self.class.name,
      resource_id: self.id,
      details: {
        changes: self.saved_changes
      }.to_json
    )
  end
end

# Apply to models
class Commission < ApplicationRecord
  include Auditable
end

class Payout < ApplicationRecord
  include Auditable
end
```

---

## 📧 PHASE 6: Notifications & Communication

### Email Templates

**Mailer:** `app/mailers/affiliate_mailer.rb`

```ruby
class AffiliateMailer < ApplicationMailer
  def application_received(affiliate)
    @affiliate = affiliate
    mail(to: @affiliate.user.email, subject: 'Affiliate Application Received')
  end

  def application_approved(affiliate)
    @affiliate = affiliate
    @referral_link = "#{root_url}?ref=#{@affiliate.affiliate_code}"
    mail(to: @affiliate.user.email, subject: 'Welcome to the AMOS Affiliate Program!')
  end

  def new_referral_signup(affiliate, referred_user)
    @affiliate = affiliate
    @referred_user = referred_user
    mail(to: @affiliate.user.email, subject: 'New Referral Signup!')
  end

  def commission_earned(affiliate, amount)
    @affiliate = affiliate
    @amount = amount
    mail(to: @affiliate.user.email, subject: "You've earned $#{amount}!")
  end

  def payout_processed(payout)
    @payout = payout
    @affiliate = payout.affiliate
    mail(to: @affiliate.user.email, subject: "Payout of $#{@payout.amount} processed!")
  end

  def tier_upgraded(affiliate, new_tier)
    @affiliate = affiliate
    @new_tier = new_tier
    mail(to: @affiliate.user.email, subject: "Congratulations! You've reached #{new_tier} tier!")
  end
end
```

**Admin Mailer:** `app/mailers/admin_mailer.rb`

```ruby
class AdminMailer < ApplicationMailer
  def new_affiliate_application(affiliate)
    @affiliate = affiliate
    admin_emails = AdminUser.where(role: [:admin, :super_admin]).pluck(:email)
    mail(to: admin_emails, subject: 'New Affiliate Application')
  end

  def high_value_commission_review(commission)
    @commission = commission
    admin_emails = AdminUser.where(role: [:admin, :super_admin]).pluck(:email)
    mail(to: admin_emails, subject: "High-Value Commission Pending Review ($#{commission.amount})")
  end

  def suspicious_activity_detected(affiliate, flags)
    @affiliate = affiliate
    @flags = flags
    admin_emails = AdminUser.where(role: [:admin, :super_admin]).pluck(:email)
    mail(to: admin_emails, subject: 'Suspicious Affiliate Activity Detected')
  end
end
```

---

## 🎨 PHASE 7: UI/UX Implementation

### Technology Stack
- **Backend:** Rails 8 + Hotwire (Turbo + Stimulus)
- **Frontend:** Bootstrap 5 (already in project)
- **Charts:** Chart.js via CDN
- **Icons:** Bootstrap Icons (already in project)
- **Tables:** Stimulus-powered sortable tables

### Key Views Structure

```
app/views/
├── affiliate/
│   ├── applications/
│   │   ├── new.html.erb          # Application form
│   ├── dashboard/
│   │   └── show.html.erb          # Main affiliate dashboard
│   ├── resources/
│   │   └── index.html.erb         # Marketing materials
│   └── payouts/
│       └── index.html.erb         # Payout history
│
└── admin/
    └── affiliates/
        ├── index.html.erb          # Affiliate list
        ├── show.html.erb           # Affiliate detail
        ├── commissions/
        │   └── index.html.erb      # Commission management
        ├── payouts/
        │   ├── index.html.erb      # Payout list
        │   └── new.html.erb        # Batch payout creator
        └── settings/
            └── show.html.erb       # Configuration
```

### Stimulus Controllers Needed

```javascript
// app/javascript/controllers/copy_to_clipboard_controller.js
// Copies referral link to clipboard

// app/javascript/controllers/affiliate_chart_controller.js
// Renders Chart.js charts for analytics

// app/javascript/controllers/bulk_select_controller.js
// Handles bulk selection for commissions/payouts

// app/javascript/controllers/filter_table_controller.js
// Client-side table filtering

// app/javascript/controllers/qr_code_controller.js
// Generates QR codes for referral links
```

---

## ⚙️ RECOMMENDED CONFIGURATION

### Affiliate Program Settings

| Setting | Recommended Value | Rationale |
|---------|------------------|-----------|
| **Commission Structure** | 20% recurring for 12 months | Balances affiliate motivation with business sustainability |
| **Cookie Duration** | 60 days | Industry standard for SaaS |
| **Minimum Payout** | $50 | Reduces payment processing overhead |
| **Auto-Approve Applications** | No | Prevents fraud and low-quality affiliates |
| **Review Threshold** | Commissions >$500 | Manual review for high-value payouts |
| **Conversion Event** | First paid subscription | Clear, verifiable milestone |
| **Tiers** | Bronze (0-4 refs), Silver (5-19 refs), Gold (20+ refs) | Encourages growth |

### Commission Tiers

| Tier | Min Referrals | Commission Rate | Benefits |
|------|---------------|-----------------|----------|
| Bronze | 0 | 20% | Standard marketing materials |
| Silver | 5 | 25% | Priority support, early feature access |
| Gold | 20 | 30% | Dedicated account manager, co-marketing opportunities |

---

## 📋 IMPLEMENTATION CHECKLIST

### Week 1: Foundation & Tracking

- [ ] Create database migrations (6 tables)
- [ ] Generate models with associations and validations
- [ ] Add indexes for performance
- [ ] Create seed data for testing
- [ ] Implement `AffiliateTracking` concern
- [ ] Add affiliate tracking to signup flow
- [ ] Create `AffiliateReferralService`
- [ ] Hook into Stripe webhooks for commission creation
- [ ] Test end-to-end: click → signup → payment → commission

### Week 2: Affiliate Experience

- [ ] Build affiliate application form (`/affiliate/apply`)
- [ ] Create affiliate dashboard layout
- [ ] Implement stats calculation service
- [ ] Add referral link display with copy button
- [ ] Create Chart.js Stimulus controller
- [ ] Build performance charts (clicks, conversions)
- [ ] Create recent activity table
- [ ] Build resources page with downloadable assets
- [ ] Create payout history page
- [ ] Design and implement all affiliate email templates

### Week 3: Admin Panel

- [ ] Build admin affiliates index (`/admin/affiliates`)
- [ ] Add filters (status, tier, date) and search
- [ ] Create affiliate detail view with full stats
- [ ] Build commission management page (`/admin/commissions`)
- [ ] Add bulk approve functionality
- [ ] Create payout batch processing interface
- [ ] Build payout history with mark-as-completed
- [ ] Create settings/configuration page
- [ ] Implement tier management CRUD
- [ ] Design admin email templates

### Week 4: Analytics & Polish

- [ ] Build analytics dashboard (`/admin/analytics/affiliates`)
- [ ] Implement `AffiliateAnalyticsService`
- [ ] Create charts for trends and funnels
- [ ] Add CSV export functionality (all tables)
- [ ] Implement fraud detection service
- [ ] Add rate limiting to tracking
- [ ] Create audit logging system
- [ ] Add 2FA verification for payouts
- [ ] Write integration tests (RSpec/Minitest)
- [ ] Write system tests for critical flows
- [ ] Create admin documentation
- [ ] Create affiliate help/FAQ page

---

## 🚀 DEPLOYMENT STEPS

### Pre-Launch

1. **Database Migrations:**
```bash
rails db:migrate
rails db:seed # Load initial tiers
```

2. **Environment Variables:**
```bash
# .env
AFFILIATE_COOKIE_DURATION_DAYS=60
AFFILIATE_MIN_PAYOUT_THRESHOLD=50
AFFILIATE_AUTO_APPROVE=false
```

3. **Admin Setup:**
- Create initial admin users if needed
- Configure Stripe webhook for production
- Set up email delivery (already using Mailgun)

### Launch Checklist

- [ ] Deploy to staging environment
- [ ] Test full flow: apply → approve → click → signup → payment → commission → payout
- [ ] Verify email notifications work
- [ ] Test fraud detection thresholds
- [ ] Load test affiliate tracking endpoint
- [ ] Review security measures (rate limiting, 2FA)
- [ ] Deploy to production
- [ ] Create internal documentation for admins
- [ ] Announce affiliate program to existing users

---

## 📊 SUCCESS METRICS

Track these KPIs post-launch:

| Metric | Target (Month 1) | Target (Month 3) |
|--------|------------------|------------------|
| Affiliate Applications | 20 | 50 |
| Approved Affiliates | 15 | 40 |
| Total Clicks | 1,000 | 5,000 |
| Conversions | 10 | 50 |
| Conversion Rate | 1% | 1-2% |
| Total Commission Paid | $500 | $3,000 |
| Affiliate-Driven Revenue | $2,500 | $15,000 |

---

## 🔄 FUTURE ENHANCEMENTS (V2)

Consider adding later:

1. **Automated Payouts:** Stripe Connect or PayPal API integration
2. **Multi-Tier Referrals:** Referrer earns from sub-referrers (2-level)
3. **Performance Bonuses:** Extra $ for hitting milestones (10 conversions = $100 bonus)
4. **Custom Landing Pages:** Each affiliate gets custom landing page
5. **A/B Testing:** Track which marketing materials perform best
6. **Affiliate Leaderboard:** Public ranking to gamify performance
7. **API Access:** Allow affiliates to pull their stats programmatically
8. **White-Label Materials:** Co-branded marketing assets
9. **Recurring Webinars:** Training for affiliates on best practices
10. **Mobile App:** Affiliate dashboard on iOS/Android

---

## 🛠️ TECHNICAL NOTES

### Performance Considerations

1. **Database Indexes:**
```ruby
add_index :affiliate_clicks, [:affiliate_id, :landed_at]
add_index :commissions, [:affiliate_id, :status]
add_index :referrals, [:affiliate_id, :referred_entity_id]
```

2. **Caching:**
```ruby
# Cache affiliate stats for 1 hour
Rails.cache.fetch("affiliate_stats_#{affiliate.id}", expires_in: 1.hour) do
  AffiliateStatsService.new(affiliate).calculate
end
```

3. **Background Jobs:**
```ruby
# Process commission creation asynchronously
CreateAffiliateCommissionJob.perform_later(entity_id, amount, commission_type)
```

### Testing Strategy

1. **Unit Tests:**
- Test model validations and associations
- Test service object logic
- Test fraud detection algorithms

2. **Integration Tests:**
- Test cookie tracking flow
- Test referral creation on signup
- Test commission creation on payment

3. **System Tests:**
- Test affiliate application flow
- Test admin approval process
- Test payout batch creation

---

## 📞 SUPPORT & DOCUMENTATION

### For Affiliates

Create help pages at `/affiliate/help`:
- How to get started
- Best practices for promotion
- How commissions are calculated
- When payouts are processed
- FAQ

### For Admins

Create internal wiki with:
- How to review affiliate applications
- How to approve commissions
- How to process payouts
- How to handle fraud alerts
- Troubleshooting common issues

---

## ✅ FINAL CHECKLIST BEFORE LAUNCH

- [ ] All database migrations run successfully
- [ ] All models have proper validations
- [ ] Affiliate tracking works correctly
- [ ] Commission creation triggers on Stripe events
- [ ] All email templates rendered correctly
- [ ] Admin panel fully functional
- [ ] Fraud detection enabled
- [ ] Rate limiting configured
- [ ] Audit logging active
- [ ] 2FA enabled for payouts
- [ ] CSV exports working
- [ ] Charts rendering properly
- [ ] Mobile responsive design tested
- [ ] Cross-browser testing complete
- [ ] Security audit passed
- [ ] Load testing passed
- [ ] Documentation complete
- [ ] Training materials ready
- [ ] Legal terms of service updated
- [ ] Privacy policy updated
- [ ] Stripe webhooks configured in production

---

## 🎉 LAUNCH PLAN

### Day 1: Soft Launch
- Enable affiliate system for internal testing
- Invite 5-10 beta testers (existing customers)
- Monitor closely for issues

### Week 1: Limited Launch
- Send email to existing users announcing program
- Monitor application volume and quality
- Approve first batch of affiliates

### Week 2-4: Full Launch
- Add affiliate program to website footer
- Create blog post about the program
- Share on social media
- Monitor metrics and iterate

---

**Questions? Ready to start building?** Let me know which phase you'd like me to begin implementing! 🚀
