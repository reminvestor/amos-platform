const { test, expect } = require('@playwright/test');

test.describe('Flutter Login Page - Console Errors', () => {
  test('should check for console errors and rendering issues', async ({ page }) => {
    const consoleMessages = [];
    const errors = [];

    // Capture all console messages
    page.on('console', msg => {
      const type = msg.type();
      const text = msg.text();
      consoleMessages.push({ type, text });
      console.log(`[${type.toUpperCase()}] ${text}`);
    });

    // Capture page errors
    page.on('pageerror', error => {
      errors.push(error.message);
      console.log(`[PAGE ERROR] ${error.message}`);
    });

    // Navigate to the app
    console.log('\n🌐 Navigating to http://localhost:8000...');
    await page.goto('http://localhost:8000');

    // Wait for network to be idle
    await page.waitForLoadState('networkidle');
    console.log('✅ Network idle');

    // Wait a bit more for Flutter to initialize
    await page.waitForTimeout(5000);
    console.log('⏱️  Waited 5 seconds for Flutter initialization');

    // Take screenshot
    await page.screenshot({ path: 'screenshots/03-with-console-logs.png', fullPage: true });
    console.log('📸 Screenshot saved');

    // Check if main.dart.js loaded
    const scripts = await page.locator('script').all();
    console.log(`\n📜 Found ${scripts.length} script tags`);
    for (let i = 0; i < scripts.length; i++) {
      const src = await scripts[i].getAttribute('src');
      if (src) {
        console.log(`  - ${src}`);
      }
    }

    // Check for Flutter-specific elements
    const flutterView = await page.locator('flutter-view').count();
    const glassPane = await page.locator('flt-glass-pane').count();
    const semanticsHost = await page.locator('flt-semantics-host').count();

    console.log(`\n🎨 Flutter Elements:`);
    console.log(`  - flutter-view: ${flutterView}`);
    console.log(`  - flt-glass-pane: ${glassPane}`);
    console.log(`  - flt-semantics-host: ${semanticsHost}`);

    // Check if there's any canvas (Flutter uses canvas for rendering)
    const canvases = await page.locator('canvas').count();
    console.log(`  - canvas elements: ${canvases}`);

    // Check body content
    const bodyHtml = await page.locator('body').innerHTML();
    console.log(`\n📄 Body HTML length: ${bodyHtml.length} characters`);

    // Report errors
    console.log(`\n❌ JavaScript Errors: ${errors.length}`);
    errors.forEach((error, i) => {
      console.log(`  ${i + 1}. ${error}`);
    });

    console.log(`\n📋 Console Messages: ${consoleMessages.length} total`);
    const errorMsgs = consoleMessages.filter(m => m.type === 'error');
    const warningMsgs = consoleMessages.filter(m => m.type === 'warning');
    console.log(`  - Errors: ${errorMsgs.length}`);
    console.log(`  - Warnings: ${warningMsgs.length}`);

    if (errorMsgs.length > 0) {
      console.log('\n🚨 Error messages:');
      errorMsgs.forEach((msg, i) => {
        console.log(`  ${i + 1}. ${msg.text}`);
      });
    }

    if (warningMsgs.length > 0) {
      console.log('\n⚠️  Warning messages:');
      warningMsgs.forEach((msg, i) => {
        console.log(`  ${i + 1}. ${msg.text}`);
      });
    }

    // Final check for UI elements
    const inputs = await page.locator('input').count();
    const buttons = await page.locator('button').count();

    console.log('\n' + '='.repeat(70));
    console.log('DIAGNOSIS:');
    console.log('='.repeat(70));
    if (flutterView === 0) {
      console.log('❌ CRITICAL: Flutter view element not found - Flutter failed to initialize');
    } else if (canvases === 0) {
      console.log('❌ CRITICAL: No canvas elements - Flutter not rendering');
    } else if (inputs === 0) {
      console.log('⚠️  Flutter loaded but no input fields rendered');
      console.log('   Possible causes:');
      console.log('   - Routing issue (not showing login screen)');
      console.log('   - Authentication state redirecting away');
      console.log('   - Widget build error');
    } else {
      console.log('✅ Input fields found!');
    }

    if (errors.length > 0 || errorMsgs.length > 0) {
      console.log('\n🔥 Check errors above for root cause');
    }
    console.log('='.repeat(70));
  });
});
