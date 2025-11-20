const purgecss = require('@fullhuman/postcss-purgecss').default;

module.exports = {
  plugins: [
    require('autoprefixer'),
    // PurgeCSS removes unused CSS classes
    // This is CRITICAL for Bootstrap - it ships with thousands of utility classes
    // but most apps only use 10-20% of them
    ...(process.env.NODE_ENV === 'production' ? [
      purgecss({
        content: [
          './app/views/**/*.html.erb',
          './app/helpers/**/*.rb',
          './app/javascript/**/*.js',
          './app/components/**/*.rb',
          './app/components/**/*.html.erb',
        ],
        // Don't purge these patterns - they're dynamically generated
        safelist: {
          standard: [
            /^alert-/,        // Alert variants (alert-success, alert-danger, etc.)
            /^btn-/,          // Button variants
            /^bg-/,           // Background colors
            /^text-/,         // Text colors/utilities
            /^border-/,       // Border utilities
            /^modal/,         // Modal classes (often added dynamically)
            /^dropdown/,      // Dropdown classes
            /^toast/,         // Toast notifications
            /^tooltip/,       // Tooltips
            /^popover/,       // Popovers
            /^collapse/,      // Collapse/accordion
            /^fade/,          // Transitions
            /^show/,          // Show state
            /^active/,        // Active state
            /^disabled/,      // Disabled state
            /^data-bs-/,      // Bootstrap data attributes
            /^lucide/,        // Lucide icon classes
            /^form-/,         // Form classes (form-control, form-label, form-select, etc.)
            'form-control',   // Specific form control class
            'form-select',    // Specific form select class
            'form-label',     // Specific form label class
            'form-text',      // Specific form text class
          ],
          deep: [],
          greedy: [
            /tooltip/,
            /popover/,
            /modal/,
            /dropdown/,
          ]
        },
        // Default extractor for HTML and JS
        defaultExtractor: content => content.match(/[\w-/:]+(?<!:)/g) || []
      })
    ] : [])
  ]
}
