describe('Campaign Management Workflow', () => {
  beforeAll(async () => {
    await device.launchApp();
  });

  beforeEach(async () => {
    await device.reloadReactNative();
  });

  it('should create a new campaign', async () => {
    // Navigate to campaigns
    await element(by.id('campaigns-tab')).multiTap();

    // Tap create campaign button
    await element(by.id('create-campaign-btn')).multiTap();

    // Fill in campaign details
    await element(by.id('campaign-name-input')).typeText('Test Campaign');
    await element(by.id('campaign-subject-input')).typeText('Test Subject Line');
    await element(by.id('campaign-from-name-input')).typeText('Test Sender');
    await element(by.id('campaign-from-email-input')).typeText('test@example.com');
    await element(by.id('campaign-body-input')).typeText('Test email body');

    // Save campaign
    await element(by.id('save-campaign-btn')).multiTap();

    // Verify success message
    await expect(element(by.text('Campaign created successfully'))).toBeVisible();

    // Verify navigation back
    await expect(element(by.id('campaigns-tab'))).toBeVisible();
  });

  it('should edit an existing campaign', async () => {
    // Navigate to campaigns
    await element(by.id('campaigns-tab')).multiTap();

    // Select first campaign
    await element(by.id('campaign-card-0')).multiTap();

    // Navigate to edit
    await element(by.id('edit-campaign-btn')).multiTap();

    // Update campaign name
    await element(by.id('campaign-name-input')).clearText();
    await element(by.id('campaign-name-input')).typeText('Updated Campaign');

    // Save changes
    await element(by.id('save-campaign-btn')).multiTap();

    // Verify success message
    await expect(element(by.text('Campaign updated successfully'))).toBeVisible();
  });

  it('should pause and resume a campaign', async () => {
    // Navigate to campaigns
    await element(by.id('campaigns-tab')).multiTap();

    // Find in-progress campaign and pause it
    await element(by.id('campaign-pause-btn-0')).multiTap();

    // Confirm pause action
    await element(by.text('Pause')).multiTap();

    // Verify success message
    await expect(element(by.text('Campaign paused'))).toBeVisible();

    // Resume the campaign
    await element(by.id('campaign-resume-btn-0')).multiTap();

    // Confirm resume action
    await element(by.text('Resume')).multiTap();

    // Verify success message
    await expect(element(by.text('Campaign resumed'))).toBeVisible();
  });

  it('should filter campaigns by status', async () => {
    // Navigate to campaigns
    await element(by.id('campaigns-tab')).multiTap();

    // Open filter modal
    await element(by.id('campaigns-filter-btn')).multiTap();

    // Select status filter
    await element(by.id('status-filter-completed')).multiTap();

    // Apply filter
    await element(by.id('apply-filter-btn')).multiTap();

    // Verify campaigns are filtered
    await expect(element(by.id('campaigns-list'))).toBeVisible();
  });

  it('should search campaigns', async () => {
    // Navigate to campaigns
    await element(by.id('campaigns-tab')).multiTap();

    // Enter search text
    await element(by.id('campaigns-search-input')).typeText('Spring');

    // Submit search
    await element(by.id('campaigns-search-input')).multiTap();

    // Verify filtered results
    await expect(element(by.id('campaigns-list'))).toBeVisible();
  });

  it('should view campaign analytics', async () => {
    // Navigate to campaigns
    await element(by.id('campaigns-tab')).multiTap();

    // Select a campaign
    await element(by.id('campaign-card-0')).multiTap();

    // Verify analytics are displayed
    await expect(element(by.id('analytics-section'))).toBeVisible();
    await expect(element(by.id('open-rate-card'))).toBeVisible();
    await expect(element(by.id('click-rate-card'))).toBeVisible();
  });

  it('should favorite a campaign', async () => {
    // Navigate to campaigns
    await element(by.id('campaigns-tab')).multiTap();

    // Tap favorite button on first campaign
    await element(by.id('favorite-btn-0')).multiTap();

    // Verify star icon changed
    await expect(element(by.id('favorite-btn-0-filled'))).toBeVisible();
  });

  it('should schedule a campaign', async () => {
    // Navigate to campaigns
    await element(by.id('campaigns-tab')).multiTap();

    // Tap create campaign
    await element(by.id('create-campaign-btn')).multiTap();

    // Fill basic details
    await element(by.id('campaign-name-input')).typeText('Scheduled Campaign');
    await element(by.id('campaign-subject-input')).typeText('Subject');
    await element(by.id('campaign-from-name-input')).typeText('Sender');
    await element(by.id('campaign-from-email-input')).typeText('sender@example.com');
    await element(by.id('campaign-body-input')).typeText('Body');

    // Enable scheduling
    await element(by.id('schedule-toggle')).multiTap();

    // Select date
    await element(by.id('schedule-date-btn')).multiTap();
    await element(by.id('date-picker-confirm')).multiTap();

    // Select time
    await element(by.id('schedule-time-btn')).multiTap();
    await element(by.id('time-picker-confirm')).multiTap();

    // Save campaign
    await element(by.id('save-campaign-btn')).multiTap();

    // Verify success
    await expect(element(by.text('Campaign created successfully'))).toBeVisible();
  });

  it('should handle campaign validation errors', async () => {
    // Navigate to campaigns
    await element(by.id('campaigns-tab')).multiTap();

    // Tap create campaign
    await element(by.id('create-campaign-btn')).multiTap();

    // Try to save without filling required fields
    await element(by.id('save-campaign-btn')).multiTap();

    // Verify validation error
    await expect(element(by.text('Campaign name is required'))).toBeVisible();
  });
});
