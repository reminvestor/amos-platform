// Entry point for the build script in your package.json
import "@hotwired/turbo-rails"
import "./controllers"
import * as bootstrap from "bootstrap"
// Expose Bootstrap for inline scripts loaded via server-rendered canvases
window.bootstrap = bootstrap
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

// Import Chart.js for affiliate charts
import Chart from 'chart.js/auto'
window.Chart = Chart

// Import QRCode for QR code generation
import QRCode from 'qrcode'
window.QRCode = QRCode

// Import TTS Audio Manager and make it available for dynamic imports
import TTSAudioManager from './tts_audio_manager'
window.TTSAudioManager = TTSAudioManager

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
