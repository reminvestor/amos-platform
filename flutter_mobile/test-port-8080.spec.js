const { test } = require('@playwright/test');

test('Test minimal app on port 8080', async ({ page }) => {
  await page.goto('http://localhost:8080');
  await page.waitForLoadState('networkidle');
  await page.waitForTimeout(5000);

  // Take screenshot
  await page.screenshot({ path: 'screenshots/05-minimal-app-8080.png', fullPage: true });

  // Get visible text
  const allText = await page.evaluate(() => document.body.innerText);

  console.log('\n📝 VISIBLE TEXT:');
  console.log('='.repeat(70));
  console.log(allText || '(empty)');
  console.log('='.repeat(70));

  // Check for our test elements
  const helloWorld = await page.getByText('Hello World!').count();
  const emailField = await page.getByLabel(/Test Email/i).count();
  const passwordField = await page.getByLabel(/Test Password/i).count();
  const button = await page.getByRole('button', { name: /Test Button/i }).count();

  console.log(`\n🎯 Element Counts:`);
  console.log(`  - "Hello World!" text: ${helloWorld}`);
  console.log(`  - Email field: ${emailField}`);
  console.log(`  - Password field: ${passwordField}`);
  console.log(`  - Test button: ${button}`);

  // Check inputs by role
  const textboxes = await page.locator('input[type="text"], input:not([type])').count();
  const passwordInputs = await page.locator('input[type="password"]').count();
  const allInputs = await page.locator('input').count();

  console.log(`\n📋 Input Elements:`);
  console.log(`  - Text inputs: ${textboxes}`);
  console.log(`  - Password inputs: ${passwordInputs}`);
  console.log(`  - Total inputs: ${allInputs}`);

  console.log('\n' + '='.repeat(70));
  if (helloWorld > 0 && allInputs >= 2) {
    console.log('✅ SUCCESS! Minimal app is rendering correctly!');
  } else {
    console.log('❌ STILL BLANK - Even debug mode with Flutter web-server fails');
  }
  console.log('='.repeat(70));
});
