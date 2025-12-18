// Entry point for the build script in your package.json
import "@hotwired/turbo-rails"
import "./controllers"
// ============================================================================
// OPTIMIZED BOOTSTRAP JS IMPORTS - Only load interactive components you use
// ============================================================================
// Old (importing everything): import * as bootstrap from "bootstrap"
// This imports ALL Bootstrap JS (77KB minified), but you only need ~15KB worth

// Import only the components you actually use:
import { Modal } from 'bootstrap';
import { Dropdown } from 'bootstrap';
import { Toast } from 'bootstrap';
import { Tooltip } from 'bootstrap';
import { Popover } from 'bootstrap';
import { Collapse } from 'bootstrap';
import { Tab } from 'bootstrap';

// Expose to window for server-rendered canvases
window.bootstrap = {
  Modal,
  Dropdown,
  Toast,
  Tooltip,
  Popover,
  Collapse,
  Tab
}
import "./channels"

// In development, load manual debugging tools
if (process.env.NODE_ENV !== 'production') {
  console.log("Loading debug tools");
  import('./manual_debug');
}

// Add a global event handler for all form submissions for debug purposes
document.addEventListener('turbo:submit-start', (event) => {
  console.log("🌐 Turbo form submission starting:", event);
});

document.addEventListener('turbo:submit-end', (event) => {
  console.log("🌐 Turbo form submission completed:", event);
});

document.addEventListener('turbo:frame-load', (event) => {
  console.log("🌐 Turbo frame loaded:", event.target);
});

import "trix"
import "@rails/actiontext"

// ============================================================================
// CODE SPLITTING: Chart.js and QRCode are now lazy-loaded only on pages that need them
// ============================================================================
// This saves ~100KB from the main bundle
// To use these on a page, add to your view:
//   <%= javascript_include_tag "chart_loader", type: "module", defer: true %>
//   <%= javascript_include_tag "qrcode_loader", type: "module", defer: true %>
//
// OLD (always loaded):
// import Chart from 'chart.js/auto'
// window.Chart = Chart
// import QRCode from 'qrcode'
// window.QRCode = QRCode

// Import TTS Audio Manager and make it available for dynamic imports
import TTSAudioManager from './tts_audio_manager'
window.TTSAudioManager = TTSAudioManager

// Import Theme Manager for light/dark mode switching
import ThemeManager from './theme_manager'

// Import Toast utility for styled notifications (replaces alert())
import './utils/toast'

// Import Emoji & GIF Picker for Hub messages
import './emoji_gif_picker'

// Import Hub Screenshot Paste for inline image sharing
import './hub_screenshot_paste'

// Import landing page module (using the index.js)

// Simple reveal-on-scroll for elements with class .reveal
function initRevealOnScroll() {
  const elements = document.querySelectorAll('.reveal');
  if (elements.length === 0) return;

  if (!('IntersectionObserver' in window)) {
    elements.forEach(el => el.classList.add('visible'));
    return;
  }

  const observer = new IntersectionObserver((entries, obs) => {
    entries.forEach(entry => {
      if (entry.isIntersecting) {
        entry.target.classList.add('visible');
        obs.unobserve(entry.target);
      }
    });
  }, { threshold: 0.1, root: null, rootMargin: '0px 0px -10% 0px' });

  elements.forEach(el => observer.observe(el));
}

document.addEventListener('DOMContentLoaded', initRevealOnScroll);
document.addEventListener('turbo:load', initRevealOnScroll);
