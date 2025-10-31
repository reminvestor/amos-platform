// Theme Manager - Handles light/dark theme switching
class ThemeManager {
  constructor() {
    this.themeKey = 'amos_theme_preference';
    this.init();
  }

  init() {
    console.log('🎨 ThemeManager: Initializing...');
    // Load theme on page load
    const savedTheme = this.getSavedTheme();
    const theme = savedTheme || this.getSystemPreference();
    console.log('🎨 ThemeManager: Applying theme:', theme);
    this.applyTheme(theme);

    // Listen for system preference changes
    if (window.matchMedia) {
      window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', (e) => {
        if (!this.getSavedTheme()) {
          this.applyTheme(e.matches ? 'dark' : 'light');
        }
      });
    }

    // Initialize toggle buttons
    this.initToggleButtons();
  }

  getSavedTheme() {
    return localStorage.getItem(this.themeKey);
  }

  getSystemPreference() {
    if (window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches) {
      return 'dark';
    }
    return 'light';
  }

  applyTheme(theme) {
    console.log('🎨 ThemeManager: Setting data-theme attribute to:', theme);
    document.documentElement.setAttribute('data-theme', theme);
    localStorage.setItem(this.themeKey, theme);
    this.updateToggleButtons(theme);
    console.log('🎨 ThemeManager: Theme applied. Current HTML attribute:', document.documentElement.getAttribute('data-theme'));
  }

  toggleTheme() {
    const currentTheme = document.documentElement.getAttribute('data-theme') || 'light';
    const newTheme = currentTheme === 'light' ? 'dark' : 'light';
    console.log('🎨 ThemeManager: Toggling from', currentTheme, 'to', newTheme);
    this.applyTheme(newTheme);
  }

  initToggleButtons() {
    // Find all theme toggle buttons
    const buttons = document.querySelectorAll('[data-theme-toggle]');
    console.log('🎨 ThemeManager: Found', buttons.length, 'toggle buttons');
    buttons.forEach(button => {
      button.addEventListener('click', (e) => {
        e.preventDefault();
        console.log('🎨 ThemeManager: Toggle button clicked!');
        this.toggleTheme();
      });
    });
  }

  updateToggleButtons(theme) {
    // Update all toggle button states
    document.querySelectorAll('[data-theme-toggle]').forEach(button => {
      const icon = button.querySelector('[data-theme-icon]');
      if (icon && typeof lucide !== 'undefined') {
        // Update icon based on current theme
        if (theme === 'dark') {
          icon.setAttribute('data-lucide', 'sun');
        } else {
          icon.setAttribute('data-lucide', 'moon');
        }
        lucide.createIcons();
      }
    });
  }
}

// Initialize theme manager when DOM is ready
if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', () => {
    window.themeManager = new ThemeManager();
  });
} else {
  window.themeManager = new ThemeManager();
}

// Reinitialize on Turbo navigation
document.addEventListener('turbo:load', () => {
  if (window.themeManager) {
    window.themeManager.initToggleButtons();
    const currentTheme = document.documentElement.getAttribute('data-theme') || 'light';
    window.themeManager.updateToggleButtons(currentTheme);
  } else {
    window.themeManager = new ThemeManager();
  }
});

export default ThemeManager;
