const { test, expect } = require('@playwright/test');

test.describe('Flutter Login Page', () => {
  test('should display login form with email and password fields', async ({ page }) => {
    // Navigate to the app
    await page.goto('http://localhost:8000');

    // Wait for Flutter app to load - give it extra time
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(3000);

    // Take initial screenshot
    await page.screenshot({ path: 'screenshots/01-initial-load.png', fullPage: true });
    console.log('📸 Screenshot saved: 01-initial-load.png');

    // Get the page HTML after JavaScript execution
    const html = await page.content();
    console.log('\n📄 Page HTML length:', html.length, 'characters');

    // Log all visible text on the page
    const bodyText = await page.locator('body').innerText();
    console.log('\n📝 Visible text on page:');
    console.log(bodyText);

    // Check for AMOS title/logo
    const amosText = await page.getByText('AMOS').count();
    console.log(`\n🔍 Found "AMOS" text: ${amosText} times`);

    // Try to find email field by different selectors
    console.log('\n🔍 Searching for email field...');
    const emailByLabel = await page.getByLabel(/email/i).count();
    const emailByPlaceholder = await page.getByPlaceholder(/email/i).count();
    const emailInputs = await page.locator('input[type="email"]').count();
    const allInputs = await page.locator('input').count();

    console.log(`  - By label "email": ${emailByLabel}`);
    console.log(`  - By placeholder "email": ${emailByPlaceholder}`);
    console.log(`  - By type="email": ${emailInputs}`);
    console.log(`  - Total input elements: ${allInputs}`);

    // Try to find password field
    console.log('\n🔍 Searching for password field...');
    const passwordByLabel = await page.getByLabel(/password/i).count();
    const passwordInputs = await page.locator('input[type="password"]').count();

    console.log(`  - By label "password": ${passwordByLabel}`);
    console.log(`  - By type="password": ${passwordInputs}`);

    // List all input elements and their attributes
    console.log('\n📋 All input elements on page:');
    const inputs = await page.locator('input').all();
    for (let i = 0; i < inputs.length; i++) {
      const input = inputs[i];
      const type = await input.getAttribute('type');
      const placeholder = await input.getAttribute('placeholder');
      const id = await input.getAttribute('id');
      const ariaLabel = await input.getAttribute('aria-label');
      console.log(`  Input ${i + 1}: type="${type}", placeholder="${placeholder}", id="${id}", aria-label="${ariaLabel}"`);
    }

    // List all buttons
    console.log('\n🔘 All buttons on page:');
    const buttons = await page.locator('button').all();
    for (let i = 0; i < buttons.length; i++) {
      const button = buttons[i];
      const text = await button.innerText().catch(() => '');
      const type = await button.getAttribute('type');
      console.log(`  Button ${i + 1}: text="${text}", type="${type}"`);
    }

    // Take final screenshot
    await page.screenshot({ path: 'screenshots/02-after-analysis.png', fullPage: true });
    console.log('\n📸 Screenshot saved: 02-after-analysis.png');

    // Save the full HTML for inspection
    const fs = require('fs');
    const path = require('path');
    const screenshotsDir = path.join(__dirname, 'screenshots');
    if (!fs.existsSync(screenshotsDir)) {
      fs.mkdirSync(screenshotsDir, { recursive: true });
    }
    fs.writeFileSync(path.join(screenshotsDir, 'page-html.txt'), html);
    console.log('💾 Full HTML saved: screenshots/page-html.txt');

    // Report findings
    console.log('\n' + '='.repeat(60));
    console.log('SUMMARY:');
    console.log('='.repeat(60));
    if (allInputs === 0) {
      console.log('❌ NO INPUT FIELDS FOUND - This is the problem!');
    } else if (emailInputs === 0 || passwordInputs === 0) {
      console.log('⚠️  Input fields exist but email/password fields not found');
    } else {
      console.log('✅ Email and password fields found!');
    }
    console.log('='.repeat(60));
  });
});
