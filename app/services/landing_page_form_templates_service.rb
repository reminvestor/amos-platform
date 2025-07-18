# == Landing Page Form Templates Service
#
# This service provides predefined form templates that can be embedded in landing pages
# to collect contact information. Claude can use these templates when generating HTML content.
#
# == Available Templates:
# - contact_form: Basic contact form with name, email, message
# - newsletter_signup: Simple email capture for newsletters  
# - lead_magnet: Email + name for downloading content
# - demo_request: Full contact form for requesting demos
# - event_registration: Registration form for events/webinars
# - free_trial: Signup form for trial accounts
# - quote_request: Form for requesting price quotes
# - consultation_booking: Form for booking consultations
#
# == Usage:
# form_html = LandingPageFormTemplatesService.get_template('newsletter_signup')
# templates = LandingPageFormTemplatesService.available_templates
#
class LandingPageFormTemplatesService
  
  # Get all available form templates
  # @return [Hash] Hash of template names and descriptions
  def self.available_templates
    {
      'contact_form' => 'Basic contact form with name, email, and message',
      'newsletter_signup' => 'Simple email capture for newsletter signups',
      'lead_magnet' => 'Email and name capture for content downloads',
      'demo_request' => 'Full contact form for requesting product demos',
      'event_registration' => 'Registration form for events and webinars', 
      'free_trial' => 'Signup form for free trial accounts',
      'quote_request' => 'Form for requesting price quotes',
      'consultation_booking' => 'Form for booking consultations'
    }
  end
  
  # Get a specific form template HTML
  # @param template_name [String] The name of the template
  # @return [String] HTML form code
  def self.get_template(template_name)
    case template_name.to_s
    when 'contact_form'
      contact_form_template
    when 'newsletter_signup'
      newsletter_signup_template
    when 'lead_magnet'
      lead_magnet_template
    when 'demo_request'
      demo_request_template
    when 'event_registration'
      event_registration_template
    when 'free_trial'
      free_trial_template
    when 'quote_request'
      quote_request_template
    when 'consultation_booking'
      consultation_booking_template
    else
      raise ArgumentError, "Unknown template: #{template_name}"
    end
  end
  
  # Check if a template exists
  # @param template_name [String] The name of the template
  # @return [Boolean] true if template exists
  def self.template_exists?(template_name)
    available_templates.key?(template_name.to_s)
  end
  
  private
  
  # Basic contact form template
  def self.contact_form_template
    <<~HTML
      <form class="landing-page-form" action="/api/v1/contacts" method="POST" data-form-type="contact">
        <div class="mb-3">
          <label for="first_name" class="form-label">First Name *</label>
          <input type="text" class="form-control" id="first_name" name="first_name" required>
        </div>
        <div class="mb-3">
          <label for="last_name" class="form-label">Last Name *</label>
          <input type="text" class="form-control" id="last_name" name="last_name" required>
        </div>
        <div class="mb-3">
          <label for="email" class="form-label">Email Address *</label>
          <input type="email" class="form-control" id="email" name="email" required>
        </div>
        <div class="mb-3">
          <label for="phone" class="form-label">Phone Number</label>
          <input type="tel" class="form-control" id="phone" name="phone">
        </div>
        <div class="mb-3">
          <label for="message" class="form-label">Message *</label>
          <textarea class="form-control" id="message" name="message" rows="4" required></textarea>
        </div>
        <button type="submit" class="btn btn-primary btn-lg w-100">Send Message</button>
      </form>
    HTML
  end
  
  # Newsletter signup template
  def self.newsletter_signup_template
    <<~HTML
      <form class="landing-page-form" action="/api/v1/contacts" method="POST" data-form-type="newsletter">
        <div class="row">
          <div class="col-md-8 mb-3">
            <label for="email" class="form-label visually-hidden">Email Address</label>
            <input type="email" class="form-control form-control-lg" id="email" name="email" 
                   placeholder="Enter your email address" required>
            <input type="hidden" name="newsletter_signup" value="true">
          </div>
          <div class="col-md-4 mb-3">
            <button type="submit" class="btn btn-primary btn-lg w-100">Subscribe</button>
          </div>
        </div>
        <small class="text-muted">We respect your privacy. Unsubscribe at any time.</small>
      </form>
    HTML
  end
  
  # Lead magnet template (for content downloads)
  def self.lead_magnet_template
    <<~HTML
      <form class="landing-page-form" action="/api/v1/contacts" method="POST" data-form-type="lead_magnet">
        <div class="mb-3">
          <label for="first_name" class="form-label">First Name *</label>
          <input type="text" class="form-control" id="first_name" name="first_name" required>
        </div>
        <div class="mb-3">
          <label for="email" class="form-label">Email Address *</label>
          <input type="email" class="form-control" id="email" name="email" required>
        </div>
        <div class="mb-3">
          <label for="company" class="form-label">Company</label>
          <input type="text" class="form-control" id="company" name="company">
        </div>
        <input type="hidden" name="lead_source" value="content_download">
        <button type="submit" class="btn btn-success btn-lg w-100">Download Now</button>
        <small class="text-muted d-block mt-2">We'll email you the download link instantly.</small>
      </form>
    HTML
  end
  
  # Demo request template
  def self.demo_request_template
    <<~HTML
      <form class="landing-page-form" action="/api/v1/contacts" method="POST" data-form-type="demo_request">
        <div class="row">
          <div class="col-md-6 mb-3">
            <label for="first_name" class="form-label">First Name *</label>
            <input type="text" class="form-control" id="first_name" name="first_name" required>
          </div>
          <div class="col-md-6 mb-3">
            <label for="last_name" class="form-label">Last Name *</label>
            <input type="text" class="form-control" id="last_name" name="last_name" required>
          </div>
        </div>
        <div class="mb-3">
          <label for="email" class="form-label">Business Email *</label>
          <input type="email" class="form-control" id="email" name="email" required>
        </div>
        <div class="row">
          <div class="col-md-6 mb-3">
            <label for="company" class="form-label">Company *</label>
            <input type="text" class="form-control" id="company" name="company" required>
          </div>
          <div class="col-md-6 mb-3">
            <label for="company_size" class="form-label">Company Size</label>
            <select class="form-select" id="company_size" name="company_size">
              <option value="">Select size</option>
              <option value="1-10">1-10 employees</option>
              <option value="11-50">11-50 employees</option>
              <option value="51-200">51-200 employees</option>
              <option value="201-1000">201-1000 employees</option>
              <option value="1000+">1000+ employees</option>
            </select>
          </div>
        </div>
        <div class="mb-3">
          <label for="phone" class="form-label">Phone Number</label>
          <input type="tel" class="form-control" id="phone" name="phone">
        </div>
        <input type="hidden" name="demo_request" value="true">
        <button type="submit" class="btn btn-primary btn-lg w-100">Request Demo</button>
      </form>
    HTML
  end
  
  # Event registration template
  def self.event_registration_template
    <<~HTML
      <form class="landing-page-form" action="/api/v1/contacts" method="POST" data-form-type="event_registration">
        <div class="row">
          <div class="col-md-6 mb-3">
            <label for="first_name" class="form-label">First Name *</label>
            <input type="text" class="form-control" id="first_name" name="first_name" required>
          </div>
          <div class="col-md-6 mb-3">
            <label for="last_name" class="form-label">Last Name *</label>
            <input type="text" class="form-control" id="last_name" name="last_name" required>
          </div>
        </div>
        <div class="mb-3">
          <label for="email" class="form-label">Email Address *</label>
          <input type="email" class="form-control" id="email" name="email" required>
        </div>
        <div class="mb-3">
          <label for="company" class="form-label">Company/Organization</label>
          <input type="text" class="form-control" id="company" name="company">
        </div>
        <div class="mb-3">
          <label for="job_title" class="form-label">Job Title</label>
          <input type="text" class="form-control" id="job_title" name="job_title">
        </div>
        <input type="hidden" name="event_registration" value="true">
        <button type="submit" class="btn btn-success btn-lg w-100">Register Now</button>
        <small class="text-muted d-block mt-2">You'll receive confirmation and event details via email.</small>
      </form>
    HTML
  end
  
  # Free trial signup template
  def self.free_trial_template
    <<~HTML
      <form class="landing-page-form" action="/api/v1/contacts" method="POST" data-form-type="free_trial">
        <div class="mb-3">
          <label for="first_name" class="form-label">First Name *</label>
          <input type="text" class="form-control" id="first_name" name="first_name" required>
        </div>
        <div class="mb-3">
          <label for="email" class="form-label">Email Address *</label>
          <input type="email" class="form-control" id="email" name="email" required>
        </div>
        <div class="mb-3">
          <label for="company" class="form-label">Company Name</label>
          <input type="text" class="form-control" id="company" name="company">
        </div>
        <div class="mb-3">
          <label for="password" class="form-label">Create Password *</label>
          <input type="password" class="form-control" id="password" name="password" 
                 minlength="8" required>
          <small class="text-muted">Minimum 8 characters</small>
        </div>
        <input type="hidden" name="free_trial_signup" value="true">
        <button type="submit" class="btn btn-success btn-lg w-100">Start Free Trial</button>
        <small class="text-muted d-block mt-2">No credit card required. 30-day free trial.</small>
      </form>
    HTML
  end
  
  # Quote request template
  def self.quote_request_template
    <<~HTML
      <form class="landing-page-form" action="/api/v1/contacts" method="POST" data-form-type="quote_request">
        <div class="row">
          <div class="col-md-6 mb-3">
            <label for="first_name" class="form-label">First Name *</label>
            <input type="text" class="form-control" id="first_name" name="first_name" required>
          </div>
          <div class="col-md-6 mb-3">
            <label for="last_name" class="form-label">Last Name *</label>
            <input type="text" class="form-control" id="last_name" name="last_name" required>
          </div>
        </div>
        <div class="mb-3">
          <label for="email" class="form-label">Email Address *</label>
          <input type="email" class="form-control" id="email" name="email" required>
        </div>
        <div class="mb-3">
          <label for="phone" class="form-label">Phone Number *</label>
          <input type="tel" class="form-control" id="phone" name="phone" required>
        </div>
        <div class="mb-3">
          <label for="company" class="form-label">Company *</label>
          <input type="text" class="form-control" id="company" name="company" required>
        </div>
        <div class="mb-3">
          <label for="project_details" class="form-label">Project Details *</label>
          <textarea class="form-control" id="project_details" name="project_details" 
                    rows="4" placeholder="Please describe your project or service needs..." required></textarea>
        </div>
        <div class="mb-3">
          <label for="budget_range" class="form-label">Budget Range</label>
          <select class="form-select" id="budget_range" name="budget_range">
            <option value="">Select budget range</option>
            <option value="under_5k">Under $5,000</option>
            <option value="5k_15k">$5,000 - $15,000</option>
            <option value="15k_50k">$15,000 - $50,000</option>
            <option value="50k_100k">$50,000 - $100,000</option>
            <option value="over_100k">Over $100,000</option>
          </select>
        </div>
        <input type="hidden" name="quote_request" value="true">
        <button type="submit" class="btn btn-warning btn-lg w-100">Get Quote</button>
      </form>
    HTML
  end
  
  # Consultation booking template
  def self.consultation_booking_template
    <<~HTML
      <form class="landing-page-form" action="/api/v1/contacts" method="POST" data-form-type="consultation_booking">
        <div class="row">
          <div class="col-md-6 mb-3">
            <label for="first_name" class="form-label">First Name *</label>
            <input type="text" class="form-control" id="first_name" name="first_name" required>
          </div>
          <div class="col-md-6 mb-3">
            <label for="last_name" class="form-label">Last Name *</label>
            <input type="text" class="form-control" id="last_name" name="last_name" required>
          </div>
        </div>
        <div class="mb-3">
          <label for="email" class="form-label">Email Address *</label>
          <input type="email" class="form-control" id="email" name="email" required>
        </div>
        <div class="mb-3">
          <label for="phone" class="form-label">Phone Number *</label>
          <input type="tel" class="form-control" id="phone" name="phone" required>
        </div>
        <div class="mb-3">
          <label for="company" class="form-label">Company/Organization</label>
          <input type="text" class="form-control" id="company" name="company">
        </div>
        <div class="mb-3">
          <label for="consultation_type" class="form-label">Type of Consultation *</label>
          <select class="form-select" id="consultation_type" name="consultation_type" required>
            <option value="">Select consultation type</option>
            <option value="strategy">Strategy Consultation</option>
            <option value="technical">Technical Consultation</option>
            <option value="marketing">Marketing Consultation</option>
            <option value="general">General Business Consultation</option>
            <option value="other">Other</option>
          </select>
        </div>
        <div class="mb-3">
          <label for="preferred_time" class="form-label">Preferred Time</label>
          <select class="form-select" id="preferred_time" name="preferred_time">
            <option value="">Select preferred time</option>
            <option value="morning">Morning (9 AM - 12 PM)</option>
            <option value="afternoon">Afternoon (12 PM - 5 PM)</option>
            <option value="evening">Evening (5 PM - 8 PM)</option>
          </select>
        </div>
        <div class="mb-3">
          <label for="consultation_goals" class="form-label">What would you like to discuss?</label>
          <textarea class="form-control" id="consultation_goals" name="consultation_goals" 
                    rows="3" placeholder="Brief description of your goals or challenges..."></textarea>
        </div>
        <input type="hidden" name="consultation_booking" value="true">
        <button type="submit" class="btn btn-info btn-lg w-100">Book Consultation</button>
        <small class="text-muted d-block mt-2">We'll contact you within 24 hours to schedule.</small>
      </form>
    HTML
  end
end 