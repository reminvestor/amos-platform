// Manual debug script that will run regardless of Stimulus state
console.log("🔧 Manual debug script loaded");

document.addEventListener('DOMContentLoaded', () => {
  console.log("🔧 Manual debug DOM content loaded");
  
  // Wait a bit for everything to initialize
  setTimeout(() => {
    // Find the search form and inputs
    const searchForm = document.getElementById('contact-search-form');
    const searchInput = document.getElementById('contact-search-input');
    const statusSelect = document.getElementById('contact-status-select');
    
    if (searchForm) {
      console.log("🔧 Found search form:", searchForm);
      
      // Add direct event listener to the form
      searchForm.addEventListener('submit', (e) => {
        console.log("🔧 Form submit event detected!", e);
      });
    } else {
      console.warn("⚠️ Search form not found with ID 'contact-search-form'");
      // Try to find it by other means
      const possibleForms = document.querySelectorAll('form');
      console.log(`Found ${possibleForms.length} forms on the page:`, possibleForms);
    }
    
    if (searchInput) {
      console.log("🔧 Found search input:", searchInput);
      
      // Add direct event listener to the input
      searchInput.addEventListener('input', (e) => {
        console.log("🔧 Direct input event on search field:", e.target.value);
        
        // After a short delay, submit the form
        clearTimeout(window.manualSearchTimeout);
        window.manualSearchTimeout = setTimeout(() => {
          console.log("🔧 Manual timeout triggered, submitting form");
          if (searchForm) {
            try {
              searchForm.requestSubmit();
            } catch (error) {
              console.error("Error with requestSubmit:", error);
              // Fallback to regular submit
              searchForm.submit();
            }
          }
        }, 300);
      });
      
      // Test trigger the input
      setTimeout(() => {
        console.log("🔧 Triggering test input event");
        searchInput.dispatchEvent(new Event('input', { bubbles: true }));
      }, 1000);
    } else {
      console.warn("⚠️ Search input not found with ID 'contact-search-input'");
      
      // Try to find the input by other means
      const possibleInputs = document.querySelectorAll('input[type="text"]');
      console.log(`Found ${possibleInputs.length} text inputs on the page:`, possibleInputs);
    }
    
    if (statusSelect) {
      console.log("🔧 Found status select:", statusSelect);
      
      // Add direct event listener to the select
      statusSelect.addEventListener('change', (e) => {
        console.log("🔧 Direct change event on status select:", e.target.value);
        
        // Submit the form immediately on select change
        if (searchForm) {
          try {
            searchForm.requestSubmit();
          } catch (error) {
            console.error("Error with requestSubmit:", error);
            // Fallback to regular submit
            searchForm.submit();
          }
        }
      });
    } else {
      console.warn("⚠️ Status select not found with ID 'contact-status-select'");
    }
  }, 500);
}); 