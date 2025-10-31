// Theme Manager - Handles light/dark theme switching
class ThemeManager {
  constructor() {
    this.themeKey = 'amos_theme_preference';
    this.init();
  }

  init() {
    // Load theme on page load
    const savedTheme = this.getSavedTheme();
    const theme = savedTheme || this.getSystemPreference();
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
    document.documentElement.setAttribute('data-theme', theme);
    localStorage.setItem(this.themeKey, theme);
    this.updateToggleButtons(theme);
  }

  toggleTheme() {
    const currentTheme = document.documentElement.getAttribute('data-theme') || 'light';
    const newTheme = currentTheme === 'light' ? 'dark' : 'light';
    this.applyTheme(newTheme);
  }

  initToggleButtons() {
    // Find all theme toggle buttons
    document.querySelectorAll('[data-theme-toggle]').forEach(button => {
      button.addEventListener('click', (e) => {
        e.preventDefault();
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
