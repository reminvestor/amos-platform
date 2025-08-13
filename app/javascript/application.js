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

// Import landing page module (using the index.js)

