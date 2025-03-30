import { Controller } from "@hotwired/stimulus"

// Auto-submits forms when inputs change, with debounce
export default class extends Controller {
  static values = {
    debug: { type: Boolean, default: true }
  }
  
  connect() {
    console.log("⭐ Turbo form controller connected!", this.element);
    this.timeout = null;
    
    // Log all form fields for debugging
    const formInputs = this.element.querySelectorAll('input, select');
    console.log(`Found ${formInputs.length} form inputs:`, formInputs);
    
    // Add event listeners directly to ensure they're working
    formInputs.forEach(input => {
      console.log(`Adding direct listener to ${input.name} (${input.id})`);
      input.addEventListener('input', (e) => {
        console.log(`🔴 Direct input event on ${e.target.name}:`, e.target.value);
        this.submit(e);
      });
      
      input.addEventListener('change', (e) => {
        console.log(`🔵 Direct change event on ${e.target.name}:`, e.target.value);
        this.submit(e);
      });
    });
    
    // Global event listener to detect all form events
    document.addEventListener('input', (e) => {
      console.log(`📌 Document caught input event on:`, e.target);
    });
  }
  
  submit(event) {
    if (!event || !event.target) {
      console.error("❌ Invalid event or target");
      return;
    }
    
    console.log(`✅ Input detected in turbo-form! ${event.target.name} = ${event.target.value}`);
    
    // Debounce to prevent too many requests while typing
    clearTimeout(this.timeout);
    this.timeout = setTimeout(() => {
      console.log(`🔄 Submitting search form directly...`);
      
      try {
        // Just submit the form naturally
        this.element.requestSubmit();
        console.log("Form submitted successfully");
      } catch (error) {
        console.error("Error submitting form:", error);
        
        // Fallback approach - try to manually trigger a submit
        console.log("Trying fallback form submission...");
        const submitEvent = new Event('submit', { bubbles: true, cancelable: true });
        this.element.dispatchEvent(submitEvent);
      }
    }, 300);
  }
} 