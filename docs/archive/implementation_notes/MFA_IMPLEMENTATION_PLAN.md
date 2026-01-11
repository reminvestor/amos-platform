# MFA Implementation Plan

Plan for adding Multi-Factor Authentication (MFA) to the login process with TOTP and email verification.

## Overview

Add optional MFA to Devise authentication with:
- **TOTP** (Time-based One-Time Password) - Google Authenticator, Authy, Microsoft Authenticator
- **Email** - Verification codes sent to registered email (backup/alternative method)
- **Backup Codes** - One-time use codes for account recovery
- **SMS** - ⏳ *Deferred for later* (Twilio integration)

---

## 📋 Implementation Tasks

### Phase 1: Foundation ✅ (Start Here)
- [ ] **Task 1**: Add gems to Gemfile (`rotp`, `rqrcode`)
- [ ] **Task 2**: Create migration `add_mfa_to_users.rb`
- [ ] **Task 3**: Create concern `TwoFactorAuthenticatable` for User model
- [ ] **Task 4**: Update User model with MFA methods

### Phase 2: Setup Flow
- [ ] **Task 5**: Create `Users::TwoFactorController` (enable, confirm, disable)
- [ ] **Task 6**: Create MFA setup views (QR code, manual entry, verification)
- [ ] **Task 7**: Add routes for MFA setup

### Phase 3: Login Integration
- [ ] **Task 8**: Modify `Users::SessionsController` to check MFA
- [ ] **Task 9**: Create OTP verification view and action
- [ ] **Task 10**: Add "resend via email" functionality

### Phase 4: Email OTP
- [ ] **Task 11**: Create `OtpMailer` for email codes
- [ ] **Task 12**: Create email OTP template
- [ ] **Task 13**: Add email OTP storage (Redis cache)

### Phase 5: Backup Codes
- [ ] **Task 14**: Generate and display backup codes
- [ ] **Task 15**: Backup code verification in login flow

### Phase 6: Settings UI
- [ ] **Task 16**: Add MFA section to user settings
- [ ] **Task 17**: Regenerate backup codes option

### Phase 7: Mobile API
- [ ] **Task 18**: Update API auth to handle MFA challenge/response

---

---

## Phase 1: Foundation (TOTP Setup)

### Step 1.1: Install Dependencies

```ruby
# Gemfile
gem 'devise'                    # Already installed
gem 'devise-two-factor'         # MFA support for Devise
gem 'rqrcode'                   # Generate QR codes for TOTP
gem 'rotp'                      # TOTP implementation
```

```bash
bundle install
```

### Step 1.2: Database Migrations

Create migration for MFA fields:

```ruby
# db/migrate/XXX_add_mfa_to_users.rb
class AddMfaToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :otp_secret_key, :string
    add_column :users, :mfa_enabled, :boolean, default: false
    add_column :users, :mfa_method, :string, default: 'totp'  # 'totp', 'sms', 'email'
    add_column :users, :otp_backup_codes, :text  # JSON array of backup codes
    add_column :users, :phone_number, :string    # For SMS method
    add_column :users, :mfa_verified_at, :datetime

    add_index :users, :mfa_enabled
  end
end
```

### Step 1.3: Update User Model

```ruby
# app/models/user.rb
class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable, :two_factor_authenticatable

  # MFA Associations
  has_many :mfa_devices, dependent: :destroy

  # MFA Methods
  enum mfa_method: { totp: 'totp', sms: 'sms', email: 'email' }

  # Validations
  validates :otp_secret_key, presence: true, if: :mfa_enabled?
  validates :phone_number, presence: true, if: -> { mfa_enabled? && sms? }

  # Generate backup codes (8 codes, 8 characters each)
  def generate_backup_codes!
    codes = 8.times.map { SecureRandom.hex(4) }
    update!(otp_backup_codes: codes.to_json)
    codes
  end

  # Verify backup code and mark as used
  def use_backup_code!(code)
    return false unless mfa_enabled?

    codes = JSON.parse(otp_backup_codes || '[]')
    if codes.include?(code)
      codes.delete(code)
      update!(otp_backup_codes: codes.to_json)
      true
    else
      false
    end
  end

  # Setup new TOTP
  def setup_totp!
    self.otp_secret_key = ROTP::Base32.random
    self.mfa_method = 'totp'
    self.mfa_enabled = false  # Mark as unverified until confirmed
    save!
  end

  # Generate QR code for TOTP setup
  def totp_qr_code
    totp = ROTP::TOTP.new(otp_secret_key, issuer: "AMOS")
    RQRCode::QRCode.new(totp.provisioning_uri(email))
  end

  # Verify TOTP code
  def verify_totp!(code)
    return false unless otp_secret_key

    totp = ROTP::TOTP.new(otp_secret_key)
    totp.verify(code, drift_behind: 1, drift_ahead: 1)
  end
end
```

### Step 1.4: Create MfaDevice Model

```ruby
# app/models/mfa_device.rb
class MfaDevice < ApplicationRecord
  belongs_to :user

  validates :name, presence: true
  validates :device_type, presence: true, inclusion: { in: %w[authenticator sms email] }

  enum device_type: { authenticator: 'authenticator', sms: 'sms', email: 'email' }

  def primary?
    primary == true
  end

  def make_primary!
    user.mfa_devices.update_all(primary: false)
    update!(primary: true)
  end
end
```

```ruby
# db/migrate/XXX_create_mfa_devices.rb
class CreateMfaDevices < ActiveRecord::Migration[8.0]
  def change
    create_table :mfa_devices do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.string :device_type, null: false  # authenticator, sms, email
      t.string :phone_number
      t.boolean :primary, default: false
      t.datetime :verified_at

      t.timestamps
    end
  end
end
```

---

## Phase 2: Setup & Management UI

### Step 2.1: Create MFA Setup Pages

**Routes**:
```ruby
# config/routes.rb
namespace :mfa do
  resources :setup, only: [:index, :new, :create]
  resources :verify, only: [:show, :update]
  resources :backup_codes, only: [:show, :create]
  resources :devices, only: [:index, :destroy, :update]
end
```

### Step 2.2: MFA Setup Controller

```ruby
# app/controllers/mfa/setup_controller.rb
module Mfa
  class SetupController < ApplicationController
    before_action :authenticate_user!

    def index
      @enabled_devices = current_user.mfa_devices.where(verified_at: ..Time.current)
      @pending_devices = current_user.mfa_devices.where(verified_at: nil)
    end

    def new
      @method = params[:method] # 'totp', 'sms', 'email'
      @device = current_user.mfa_devices.build(device_type: @method)

      case @method
      when 'totp'
        current_user.setup_totp!
        @qr_code = current_user.totp_qr_code
      when 'sms'
        # Store phone number, send verification code
      when 'email'
        # Send verification code to email
      end
    end

    def create
      @method = params[:device][:device_type]
      @device = current_user.mfa_devices.build(device_params)

      if @device.save
        redirect_to mfa_verify_path(@device, code: send_verification_code(@device))
      else
        render :new
      end
    end
  end
end
```

### Step 2.3: MFA Verification Controller

```ruby
# app/controllers/mfa/verify_controller.rb
module Mfa
  class VerifyController < ApplicationController
    before_action :authenticate_user!

    def show
      @device = current_user.mfa_devices.find(params[:id])
    end

    def update
      @device = current_user.mfa_devices.find(params[:id])
      code = params[:verification_code]

      if verify_code(@device, code)
        @device.update!(verified_at: Time.current)
        @backup_codes = current_user.generate_backup_codes! if first_mfa?
        current_user.update!(mfa_enabled: true) if @device.make_primary!
        redirect_to mfa_backup_codes_path(@device)
      else
        redirect_to mfa_verify_path(@device), alert: 'Invalid code'
      end
    end
  end
end
```

---

## Phase 3: Login Flow Integration

### Step 3.1: Update SessionsController

```ruby
# app/controllers/devise/sessions_controller.rb
def create
  # Standard Devise authentication
  self.resource = warden.authenticate!(auth_options)

  # Check if user has MFA enabled
  if resource.mfa_enabled?
    # Create temporary session
    session[:mfa_pending] = true
    session[:mfa_user_id] = resource.id
    sign_out(resource)  # Sign out until MFA verified

    redirect_to mfa_challenge_path
  else
    # Standard sign in
    sign_in(resource)
    redirect_to root_path
  end
end
```

### Step 3.2: MFA Challenge Controller

```ruby
# app/controllers/mfa/challenge_controller.rb
module Mfa
  class ChallengeController < ApplicationController
    def show
      return redirect_to root_path unless session[:mfa_pending]

      @user = User.find(session[:mfa_user_id])
      @backup_code_mode = params[:backup] == 'true'
    end

    def verify
      return redirect_to root_path unless session[:mfa_pending]

      @user = User.find(session[:mfa_user_id])
      code = params[:code]

      if @user.backup_code_mode? && @user.use_backup_code!(code)
        sign_in(@user)
        session.delete(:mfa_pending)
        redirect_to root_path
      elsif @user.verify_totp!(code)
        sign_in(@user)
        session.delete(:mfa_pending)
        redirect_to root_path
      else
        redirect_to mfa_challenge_path, alert: 'Invalid code'
      end
    end
  end
end
```

---

## Phase 4: SMS Integration (Optional)

### Step 4.1: Add Twilio Gem

```ruby
# Gemfile
gem 'twilio-ruby'
```

### Step 4.2: SMS Service

```ruby
# app/services/mfa_sms_service.rb
class MfaSmsService
  def initialize(phone_number)
    @phone_number = phone_number
    @client = Twilio::REST::Client.new(ENV['TWILIO_ACCOUNT_SID'], ENV['TWILIO_AUTH_TOKEN'])
  end

  def send_verification_code(code)
    @client.messages.create(
      from: ENV['TWILIO_PHONE_NUMBER'],
      to: @phone_number,
      body: "Your AMOS verification code is: #{code}"
    )
  end
end
```

---

## Phase 5: Security Considerations

### Step 5.1: Rate Limiting

```ruby
# app/controllers/mfa/challenge_controller.rb
class ChallengeController < ApplicationController
  before_action :rate_limit_mfa_attempts

  private

  def rate_limit_mfa_attempts
    key = "mfa_attempts:#{request.remote_ip}:#{session[:mfa_user_id]}"
    attempts = Redis.current.incr(key)
    Redis.current.expire(key, 15.minutes) if attempts == 1

    if attempts > 5
      sign_out if user_signed_in?
      session.clear
      redirect_to root_path, alert: 'Too many attempts. Please try again later.'
    end
  end
end
```

### Step 5.2: Session Timeout

```ruby
# config/initializers/devise.rb
config.timeout_in = 30.minutes  # Normal session
config.mfa_timeout_in = 5.minutes  # MFA verification session
```

### Step 5.3: Audit Logging

```ruby
# app/models/mfa_audit_log.rb
class MfaAuditLog < ApplicationRecord
  belongs_to :user

  enum action: { enabled: 'enabled', disabled: 'disabled', verified: 'verified', failed_attempt: 'failed_attempt' }

  scope :failed, -> { where(action: :failed_attempt) }
  scope :recent, -> { order(created_at: :desc) }
end
```

---

## Phase 6: User Experience

### Step 6.1: Settings Page

Add MFA management to user settings:
- List active MFA devices
- Enable/disable MFA
- Reset MFA
- Generate new backup codes
- View MFA audit log

### Step 6.2: Recovery Options

- Send recovery email if account locked
- Admin account recovery
- Support ticket system

---

## Implementation Timeline

| Phase | Task | Time | Difficulty |
|-------|------|------|-----------|
| 1 | Dependencies + Database | 2 hours | Low |
| 2 | Setup UI + Controllers | 4 hours | Medium |
| 3 | Login Integration | 3 hours | Medium |
| 4 | SMS Integration | 2 hours | Low |
| 5 | Security & Audit | 2 hours | Medium |
| 6 | UX & Settings | 3 hours | Low |
| **Total** | **Complete MFA System** | **~16 hours** | **Medium** |

---

## File Structure

```
app/
  controllers/
    mfa/
      setup_controller.rb
      verify_controller.rb
      challenge_controller.rb
      backup_codes_controller.rb
      devices_controller.rb
    devise/
      sessions_controller.rb  (modified)

  models/
    user.rb                  (modified)
    mfa_device.rb
    mfa_audit_log.rb

  services/
    mfa_sms_service.rb
    mfa_email_service.rb

  views/
    mfa/
      setup/
        index.html.erb
        new.html.erb      # TOTP, SMS, Email options
      verify/
        show.html.erb     # Verification code entry
      challenge/
        show.html.erb     # Login-time MFA challenge
      devices/
        index.html.erb    # Manage devices
      backup_codes/
        show.html.erb     # Display backup codes

db/
  migrate/
    XXX_add_mfa_to_users.rb
    XXX_create_mfa_devices.rb
    XXX_create_mfa_audit_logs.rb

config/
  initializers/
    mfa_config.rb
```

---

## Testing Strategy

### Unit Tests
```ruby
# test/models/user_test.rb
test 'setup_totp generates secret key' do
  user.setup_totp!
  assert user.otp_secret_key.present?
end

test 'verify_totp accepts valid code' do
  totp = ROTP::TOTP.new(user.otp_secret_key)
  code = totp.now
  assert user.verify_totp!(code)
end

test 'use_backup_code consumes code' do
  codes = user.generate_backup_codes!
  assert user.use_backup_code!(codes.first)
  assert_not user.use_backup_code!(codes.first)  # Already used
end
```

### Integration Tests
```ruby
# test/integration/mfa_setup_flow_test.rb
test 'user can setup TOTP via QR code' do
  visit mfa_setup_path
  click_on 'Authenticator App'
  assert page.has_content?('Scan this QR code')
  fill_in 'verification_code', with: generate_totp_code
  click_on 'Verify'
  assert page.has_content?('Your backup codes')
end
```

### System Tests
```ruby
# test/system/mfa_login_test.rb
test 'login with TOTP verification' do
  user = create(:user, mfa_enabled: true)
  visit new_user_session_path
  fill_in 'Email', with: user.email
  fill_in 'Password', with: 'password'
  click_on 'Sign In'

  assert current_path == mfa_challenge_path
  fill_in 'Code', with: generate_totp_code
  click_on 'Verify'

  assert_equal root_path, current_path
  assert user_signed_in?
end
```

---

## Environment Variables

```env
# .env
# Twilio (optional)
TWILIO_ACCOUNT_SID=your_account_sid
TWILIO_AUTH_TOKEN=your_auth_token
TWILIO_PHONE_NUMBER=+1234567890

# MFA Configuration
MFA_ENABLED=true
MFA_SMS_PROVIDER=twilio  # or vonage, aws_sns
MFA_TOTP_ISSUER=AMOS
MFA_MAX_ATTEMPTS=5
MFA_ATTEMPT_TIMEOUT=15  # minutes
MFA_BACKUP_CODE_COUNT=8
```

---

## Rollout Strategy

### Phase 1: Optional (Current)
- Users can enable MFA voluntarily
- No enforcement
- Monitor adoption and issues

### Phase 2: Recommended (3 months)
- Dashboard nudge: "We recommend enabling MFA"
- Show banner for users without MFA
- Admin users required to enable

### Phase 3: Mandatory (6 months)
- New users required to set up MFA during signup
- Existing users get 30-day grace period
- Enforce after deadline

---

## Success Metrics

- [ ] 0% security incidents related to account compromise
- [ ] 50%+ adoption rate within 3 months
- [ ] <1 second MFA challenge response time
- [ ] <0.1% failed verification attempts
- [ ] 100% backup code reliability

---

## Related Documentation

- [Devise Security Best Practices](https://github.com/heartcombo/devise)
- [TOTP Implementation Guide](https://github.com/mdp/rotp)
- [Twilio SMS Integration](https://www.twilio.com/docs/sms)
