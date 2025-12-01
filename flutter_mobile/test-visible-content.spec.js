const { test } = require('@playwright/test');

test('Check what is actually visible on screen', async ({ page }) => {
  await page.goto('http://localhost:8000');
  await page.waitForLoadState('networkidle');
  await page.waitForTimeout(5000);

  // Take screenshot
  await page.screenshot({ path: 'screenshots/04-visible-check.png', fullPage: true });

  // Get ALL text content from the page
  const allText = await page.evaluate(() => {
    return document.body.innerText;
  });

  console.log('\n📝 ALL VISIBLE TEXT ON PAGE:');
  console.log('='.repeat(70));
  console.log(allText || '(empty - no visible text)');
  console.log('='.repeat(70));

  // Check for Flutter semantics (accessibility tree)
  const semanticsText = await page.locator('flt-semantics').allInnerTexts();
  console.log(`\n♿ Flutter Semantics Text (${semanticsText.length} nodes):`);
  semanticsText.forEach((text, i) => {
    if (text.trim()) {
      console.log(`  ${i + 1}. "${text}"`);
    }
  });

  // Check canvas size and position
  const canvasInfo = await page.evaluate(() => {
    const canvas = document.querySelector('canvas');
    if (canvas) {
      const rect = canvas.getBoundingClientRect();
      return {
        width: rect.width,
        height: rect.height,
        top: rect.top,
        left: rect.left,
        visible: rect.width > 0 && rect.height > 0
      };
    }
    return null;
  });

  console.log(`\n🎨 Canvas Info:`, canvasInfo);

  // Check if there are any flutter widgets with specific roles
  const buttons = await page.locator('[role="button"]').count();
  const textboxes = await page.locator('[role="textbox"]').count();
  const links = await page.locator('[role="link"]').count();

  console.log(`\n🎯 Flutter Widgets by ARIA Role:`);
  console.log(`  - Buttons: ${buttons}`);
  console.log(`  - Textboxes: ${textboxes}`);
  console.log(`  - Links: ${links}`);

  // List all elements with aria-label
  const ariaLabels = await page.locator('[aria-label]').evaluateAll(elements =>
    elements.map(el => ({
      tag: el.tagName,
      label: el.getAttribute('aria-label'),
      role: el.getAttribute('role')
    }))
  );

  if (ariaLabels.length > 0) {
    console.log(`\n🏷️  Elements with aria-label (${ariaLabels.length}):`);
    ariaLabels.forEach((item, i) => {
      console.log(`  ${i + 1}. <${item.tag}> role="${item.role}" aria-label="${item.label}"`);
    });
  }

  // Check current URL/route
  const url = page.url();
  console.log(`\n🌐 Current URL: ${url}`);

  console.log(`\n${'='.repeat(70)}`);
  console.log('CONCLUSION:');
  if (!allText || allText.trim().length === 0) {
    console.log('❌ The page is rendering but COMPLETELY BLANK');
    console.log('   This suggests Flutter is stuck in a loading state or error state');
  } else {
    console.log(`✅ Content is visible on the page`);
  }
  console.log('='.repeat(70));
});
