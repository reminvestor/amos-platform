describe('Contact Management Workflow', () => {
  beforeAll(async () => {
    await device.launchApp();
  });

  beforeEach(async () => {
    await device.reloadReactNative();
  });

  it('should view contact list', async () => {
    // Navigate to contacts
    await element(by.id('contacts-tab')).multiTap();

    // Verify contacts are displayed
    await expect(element(by.id('contacts-list'))).toBeVisible();
    await expect(element(by.id('contact-card-0'))).toBeVisible();
  });

  it('should view contact detail', async () => {
    // Navigate to contacts
    await element(by.id('contacts-tab')).multiTap();

    // Tap on first contact
    await element(by.id('contact-card-0')).multiTap();

    // Verify contact details
    await expect(element(by.id('contact-name'))).toBeVisible();
    await expect(element(by.id('contact-email'))).toBeVisible();
    await expect(element(by.id('contact-phone'))).toBeVisible();
  });

  it('should copy contact email', async () => {
    // Navigate to contacts
    await element(by.id('contacts-tab')).multiTap();

    // Tap on first contact
    await element(by.id('contact-card-0')).multiTap();

    // Copy email
    await element(by.id('copy-email-btn')).multiTap();

    // Verify success message
    await expect(element(by.text('Email copied to clipboard'))).toBeVisible();
  });

  it('should favorite a contact', async () => {
    // Navigate to contacts
    await element(by.id('contacts-tab')).multiTap();

    // Tap favorite button on first contact
    await element(by.id('contact-favorite-btn-0')).multiTap();

    // Verify star icon changed
    await expect(element(by.id('contact-favorite-btn-0-filled'))).toBeVisible();
  });

  it('should change contact status', async () => {
    // Navigate to contacts
    await element(by.id('contacts-tab')).multiTap();

    // Tap on first contact
    await element(by.id('contact-card-0')).multiTap();

    // Change status to inactive
    await element(by.id('status-inactive-btn')).multiTap();

    // Verify status updated
    await expect(element(by.text('Contact status updated'))).toBeVisible();
  });

  it('should search contacts', async () => {
    // Navigate to contacts
    await element(by.id('contacts-tab')).multiTap();

    // Enter search text
    await element(by.id('contacts-search-input')).typeText('John');

    // Submit search
    await element(by.id('contacts-search-input')).multiTap();

    // Verify filtered results
    await expect(element(by.id('contacts-list'))).toBeVisible();
  });

  it('should filter contacts by status', async () => {
    // Navigate to contacts
    await element(by.id('contacts-tab')).multiTap();

    // Open filter modal
    await element(by.id('contacts-filter-btn')).multiTap();

    // Select status filter
    await element(by.id('status-filter-active')).multiTap();

    // Apply filter
    await element(by.id('apply-filter-btn')).multiTap();

    // Verify contacts are filtered
    await expect(element(by.id('contacts-list'))).toBeVisible();
  });

  it('should view contact groups', async () => {
    // Navigate to contacts
    await element(by.id('contacts-tab')).multiTap();

    // Switch to groups view
    await element(by.id('view-mode-groups-btn')).multiTap();

    // Verify groups are displayed
    await expect(element(by.id('contact-groups-list'))).toBeVisible();
    await expect(element(by.id('contact-group-0'))).toBeVisible();
  });

  it('should select multiple contacts', async () => {
    // Navigate to contacts
    await element(by.id('contacts-tab')).multiTap();

    // Long press to enter selection mode
    await element(by.id('contact-card-0')).multiTap();
    await element(by.id('contact-checkbox-0')).multiTap();

    // Select another contact
    await element(by.id('contact-checkbox-1')).multiTap();

    // Verify selection toolbar appears
    await expect(element(by.id('selection-toolbar'))).toBeVisible();
  });

  it('should delete contact with confirmation', async () => {
    // Navigate to contacts
    await element(by.id('contacts-tab')).multiTap();

    // Tap on first contact
    await element(by.id('contact-card-0')).multiTap();

    // Tap delete button
    await element(by.id('delete-contact-btn')).multiTap();

    // Confirm deletion
    await element(by.text('Delete')).multiTap();

    // Verify success message
    await expect(element(by.text('Contact deleted'))).toBeVisible();

    // Verify navigation back
    await expect(element(by.id('contacts-list'))).toBeVisible();
  });

  it('should refresh contact list', async () => {
    // Navigate to contacts
    await element(by.id('contacts-tab')).multiTap();

    // Pull to refresh
    await waitFor(element(by.id('contacts-list')))
      .toBeVisible()
      .whileElement(by.id('contacts-list'))
      .scroll(200, 'up');

    // Verify list is refreshed
    await expect(element(by.id('contacts-list'))).toBeVisible();
  });
});
