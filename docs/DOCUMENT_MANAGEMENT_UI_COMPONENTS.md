# Document Management UI Components

## Overview

This document outlines the UI components and user flows for the enhanced Document Management System, building on top of the existing document store at `/documents`.

## UI Mockups & Components

### 1. Enhanced Document List View

**Current**: Basic table with documents  
**Enhanced**: Rich document browser with filters and organization

```html
<!-- /app/views/documents/index.html.erb (enhanced) -->
<div class="container-fluid py-4">
  <!-- Header with Quick Actions -->
  <div class="admin-page-header">
    <div class="header-left">
      <h1>Document Library</h1>
      <p>Manage your knowledge base and documents</p>
    </div>
    <div class="header-actions">
      <button class="admin-btn admin-btn-outline" data-bs-toggle="modal" data-bs-target="#quickUploadModal">
        <i data-lucide="zap"></i> Quick Upload
      </button>
      <a href="/documents/new" class="admin-btn admin-btn-primary">
        <i data-lucide="upload"></i> Upload Documents
      </a>
    </div>
  </div>

  <div class="row">
    <!-- Left Sidebar: Subjects & Filters -->
    <div class="col-lg-3">
      <!-- Subject Navigator -->
      <div class="admin-card mb-3">
        <div class="admin-card-header">
          <h5>Collections</h5>
          <button class="admin-btn admin-btn-sm admin-btn-ghost" data-bs-toggle="modal" data-bs-target="#createSubjectModal">
            <i data-lucide="plus"></i>
          </button>
        </div>
        <div class="subject-tree">
          <div class="subject-item active">
            <i data-lucide="folder"></i>
            <span>All Documents</span>
            <span class="badge">127</span>
          </div>
          <div class="subject-item">
            <i data-lucide="briefcase"></i>
            <span>Legal Cases</span>
            <span class="badge">45</span>
          </div>
          <div class="subject-item ms-3">
            <i data-lucide="file-text"></i>
            <span>Active Cases</span>
            <span class="badge">12</span>
          </div>
          <div class="subject-item ms-3">
            <i data-lucide="archive"></i>
            <span>Archived Cases</span>
            <span class="badge">33</span>
          </div>
          <div class="subject-item">
            <i data-lucide="trending-up"></i>
            <span>Sales Reports</span>
            <span class="badge">28</span>
          </div>
        </div>
      </div>

      <!-- Smart Filters -->
      <div class="admin-card">
        <div class="admin-card-header">
          <h5>Filters</h5>
          <button class="admin-btn admin-btn-sm admin-btn-ghost" id="clearFilters">
            Clear
          </button>
        </div>
        <div class="filter-section">
          <label class="admin-label">Document Type</label>
          <div class="filter-options">
            <label class="admin-checkbox">
              <input type="checkbox" value="pdf"> PDF
            </label>
            <label class="admin-checkbox">
              <input type="checkbox" value="doc"> Word
            </label>
            <label class="admin-checkbox">
              <input type="checkbox" value="spreadsheet"> Spreadsheet
            </label>
          </div>
        </div>
        
        <div class="filter-section">
          <label class="admin-label">Date Range</label>
          <select class="admin-select">
            <option>All Time</option>
            <option>Last 7 Days</option>
            <option>Last 30 Days</option>
            <option>Last 3 Months</option>
            <option>Custom Range...</option>
          </select>
        </div>

        <div class="filter-section">
          <label class="admin-label">Tags</label>
          <div class="tag-cloud">
            <span class="filter-tag">contract <span class="count">23</span></span>
            <span class="filter-tag">invoice <span class="count">15</span></span>
            <span class="filter-tag">report <span class="count">42</span></span>
            <span class="filter-tag">confidential <span class="count">8</span></span>
          </div>
        </div>
      </div>
    </div>

    <!-- Main Content: Document Grid/List -->
    <div class="col-lg-9">
      <!-- Search Bar with AI Toggle -->
      <div class="document-search-bar mb-4">
        <div class="search-input-group">
          <i data-lucide="search"></i>
          <input type="text" 
                 class="admin-input" 
                 placeholder="Search documents by name, content, or ask a question..."
                 id="documentSearch">
          <div class="search-mode-toggle">
            <label class="admin-switch">
              <input type="checkbox" id="aiSearchToggle">
              <span>AI Search</span>
            </label>
          </div>
        </div>
        <div class="search-suggestions" id="searchSuggestions" style="display: none;">
          <div class="suggestion-item">
            <i data-lucide="clock"></i>
            <span>Recent: "Q4 Sales Report 2024"</span>
          </div>
          <div class="suggestion-item">
            <i data-lucide="trending-up"></i>
            <span>Popular: "Employee Handbook"</span>
          </div>
        </div>
      </div>

      <!-- View Toggle & Sort -->
      <div class="document-controls mb-3">
        <div class="view-toggle">
          <button class="admin-btn admin-btn-sm active" data-view="grid">
            <i data-lucide="grid"></i>
          </button>
          <button class="admin-btn admin-btn-sm" data-view="list">
            <i data-lucide="list"></i>
          </button>
        </div>
        <select class="admin-select admin-select-sm">
          <option>Sort: Recently Added</option>
          <option>Sort: Name (A-Z)</option>
          <option>Sort: Most Viewed</option>
          <option>Sort: Relevance</option>
        </select>
      </div>

      <!-- Document Grid View -->
      <div class="document-grid" id="documentGrid">
        <!-- Document Card -->
        <div class="document-card">
          <div class="document-preview">
            <i data-lucide="file-text" class="preview-icon"></i>
            <div class="document-badges">
              <span class="badge badge-primary">Contract</span>
              <span class="badge badge-warning">Review</span>
            </div>
          </div>
          <div class="document-info">
            <h6>Service Agreement - Acme Corp</h6>
            <p class="document-meta">
              <span><i data-lucide="calendar"></i> Nov 1, 2024</span>
              <span><i data-lucide="eye"></i> 45 views</span>
            </p>
            <div class="document-actions">
              <button class="admin-btn admin-btn-sm admin-btn-ghost" title="Preview">
                <i data-lucide="eye"></i>
              </button>
              <button class="admin-btn admin-btn-sm admin-btn-ghost" title="Download">
                <i data-lucide="download"></i>
              </button>
              <button class="admin-btn admin-btn-sm admin-btn-ghost" title="More">
                <i data-lucide="more-vertical"></i>
              </button>
            </div>
          </div>
        </div>
        <!-- More document cards... -->
      </div>
    </div>
  </div>
</div>
```

### 2. Document Detail View with Analytics

```html
<!-- /app/views/documents/show.html.erb -->
<div class="container-fluid py-4">
  <div class="row">
    <!-- Document Preview/Viewer -->
    <div class="col-lg-8">
      <div class="admin-card">
        <div class="document-viewer-header">
          <h4>Service Agreement - Acme Corp.pdf</h4>
          <div class="viewer-controls">
            <button class="admin-btn admin-btn-sm admin-btn-ghost">
              <i data-lucide="zoom-in"></i>
            </button>
            <button class="admin-btn admin-btn-sm admin-btn-ghost">
              <i data-lucide="download"></i>
            </button>
            <button class="admin-btn admin-btn-sm admin-btn-ghost">
              <i data-lucide="share-2"></i>
            </button>
          </div>
        </div>
        <div class="document-viewer">
          <!-- PDF.js or document preview here -->
        </div>
      </div>
    </div>

    <!-- Sidebar: Metadata & Analytics -->
    <div class="col-lg-4">
      <!-- Document Info -->
      <div class="admin-card mb-3">
        <h5>Document Information</h5>
        <dl class="info-list">
          <dt>Uploaded</dt>
          <dd>Nov 1, 2024 by John Smith</dd>
          <dt>Size</dt>
          <dd>2.4 MB</dd>
          <dt>Pages</dt>
          <dd>12</dd>
          <dt>Language</dt>
          <dd>English</dd>
        </dl>
      </div>

      <!-- Collections & Tags -->
      <div class="admin-card mb-3">
        <h5>Organization</h5>
        <div class="mb-3">
          <label class="admin-label">Collections</label>
          <div class="selected-subjects">
            <span class="subject-tag">
              <i data-lucide="folder"></i> Legal Cases
              <button class="remove">&times;</button>
            </span>
            <button class="admin-btn admin-btn-sm admin-btn-ghost">
              <i data-lucide="plus"></i> Add
            </button>
          </div>
        </div>
        <div>
          <label class="admin-label">Tags</label>
          <div class="tag-input-container">
            <input type="text" class="admin-input" placeholder="Add tags...">
            <div class="selected-tags">
              <span class="tag">contract</span>
              <span class="tag">client</span>
              <span class="tag">2024</span>
            </div>
          </div>
        </div>
      </div>

      <!-- Analytics -->
      <div class="admin-card mb-3">
        <h5>Usage Analytics</h5>
        <div class="analytics-stats">
          <div class="stat-item">
            <span class="stat-value">127</span>
            <span class="stat-label">Total Views</span>
          </div>
          <div class="stat-item">
            <span class="stat-value">23</span>
            <span class="stat-label">AI Queries</span>
          </div>
          <div class="stat-item">
            <span class="stat-value">4.2</span>
            <span class="stat-label">Avg Relevance</span>
          </div>
        </div>
        <div class="usage-chart">
          <!-- Mini chart showing usage over time -->
        </div>
      </div>

      <!-- Related Documents -->
      <div class="admin-card">
        <h5>Related Documents</h5>
        <div class="related-docs-list">
          <a href="#" class="related-doc-item">
            <i data-lucide="file-text"></i>
            <div>
              <h6>Amendment to Service Agreement</h6>
              <span class="text-muted">85% similar</span>
            </div>
          </a>
          <a href="#" class="related-doc-item">
            <i data-lucide="file-text"></i>
            <div>
              <h6>Acme Corp - Previous Contract</h6>
              <span class="text-muted">72% similar</span>
            </div>
          </a>
        </div>
      </div>
    </div>
  </div>
</div>
```

### 3. Analytics Dashboard

```html
<!-- /app/views/documents/analytics.html.erb -->
<div class="container-fluid py-4">
  <div class="admin-page-header">
    <h1>Document Analytics</h1>
    <div class="date-range-picker">
      <button class="admin-btn admin-btn-outline">
        <i data-lucide="calendar"></i>
        Last 30 Days
      </button>
    </div>
  </div>

  <!-- Key Metrics -->
  <div class="row mb-4">
    <div class="col-md-3">
      <div class="metric-card">
        <div class="metric-icon">
          <i data-lucide="file-text"></i>
        </div>
        <div class="metric-content">
          <h3>1,247</h3>
          <p>Total Documents</p>
          <span class="trend positive">+12% from last month</span>
        </div>
      </div>
    </div>
    <div class="col-md-3">
      <div class="metric-card">
        <div class="metric-icon">
          <i data-lucide="search"></i>
        </div>
        <div class="metric-content">
          <h3>3,892</h3>
          <p>Searches</p>
          <span class="trend positive">+28% from last month</span>
        </div>
      </div>
    </div>
    <div class="col-md-3">
      <div class="metric-card">
        <div class="metric-icon">
          <i data-lucide="brain"></i>
        </div>
        <div class="metric-content">
          <h3>89%</h3>
          <p>AI Query Success</p>
          <span class="trend neutral">No change</span>
        </div>
      </div>
    </div>
    <div class="col-md-3">
      <div class="metric-card">
        <div class="metric-icon">
          <i data-lucide="users"></i>
        </div>
        <div class="metric-content">
          <h3>45</h3>
          <p>Active Users</p>
          <span class="trend positive">+5 new this month</span>
        </div>
      </div>
    </div>
  </div>

  <div class="row">
    <!-- Popular Documents -->
    <div class="col-lg-6">
      <div class="admin-card">
        <h5>Most Accessed Documents</h5>
        <div class="popular-docs-chart">
          <!-- Bar chart of top documents -->
        </div>
      </div>
    </div>

    <!-- Search Insights -->
    <div class="col-lg-6">
      <div class="admin-card">
        <h5>Top Search Terms</h5>
        <div class="search-terms-cloud">
          <!-- Word cloud or list of popular searches -->
        </div>
      </div>
    </div>
  </div>

  <div class="row mt-4">
    <!-- Knowledge Gaps -->
    <div class="col-lg-12">
      <div class="admin-card">
        <h5>Knowledge Gaps - Failed Searches</h5>
        <table class="admin-table">
          <thead>
            <tr>
              <th>Search Query</th>
              <th>Frequency</th>
              <th>Last Searched</th>
              <th>Suggested Action</th>
            </tr>
          </thead>
          <tbody>
            <tr>
              <td>"Employee onboarding checklist"</td>
              <td>23 times</td>
              <td>2 hours ago</td>
              <td>
                <button class="admin-btn admin-btn-sm admin-btn-primary">
                  Create Document
                </button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
  </div>
</div>
```

## Key UI Features

### 1. Smart Search Interface
- **Toggle between keyword and AI semantic search**
- **Search suggestions based on history and popular queries**
- **Faceted filtering (type, date, tags, collections)**
- **Search result previews with highlighted matches**

### 2. Document Organization
- **Drag-and-drop to collections**
- **Bulk operations (tag, move, delete)**
- **Visual subject hierarchy**
- **Smart folders with rules**

### 3. Quick Actions
- **Quick upload with auto-categorization**
- **Keyboard shortcuts for power users**
- **Right-click context menus**
- **Inline editing of metadata**

### 4. Collaboration Features
- **Document annotations**
- **Comments and discussions**
- **Share links with permissions**
- **Activity feed**

### 5. Mobile Responsive
- **Touch-friendly document browser**
- **Mobile document viewer**
- **Offline document access**
- **Mobile upload from camera**

## CSS Styling Guide

```scss
// Document-specific styles to add to admin_dark.scss

// Document Cards
.document-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
  gap: 1.5rem;
}

.document-card {
  background: $admin-bg-secondary;
  border: 1px solid $admin-border;
  border-radius: 0.75rem;
  overflow: hidden;
  transition: all 0.2s ease;
  
  &:hover {
    transform: translateY(-2px);
    box-shadow: 0 4px 12px rgba(0, 0, 0, 0.3);
    border-color: $admin-accent-end;
  }
  
  .document-preview {
    height: 160px;
    background: $admin-bg-tertiary;
    display: flex;
    align-items: center;
    justify-content: center;
    position: relative;
    
    .preview-icon {
      width: 4rem;
      height: 4rem;
      color: $admin-text-muted;
    }
    
    .document-badges {
      position: absolute;
      top: 0.5rem;
      right: 0.5rem;
      display: flex;
      gap: 0.25rem;
    }
  }
  
  .document-info {
    padding: 1rem;
    
    h6 {
      color: $admin-text-primary;
      margin-bottom: 0.5rem;
      font-weight: 600;
    }
    
    .document-meta {
      display: flex;
      gap: 1rem;
      font-size: 0.75rem;
      color: $admin-text-secondary;
      margin-bottom: 1rem;
      
      span {
        display: flex;
        align-items: center;
        gap: 0.25rem;
      }
    }
    
    .document-actions {
      display: flex;
      gap: 0.5rem;
    }
  }
}

// Subject Tree
.subject-tree {
  .subject-item {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    padding: 0.5rem 0.75rem;
    border-radius: 0.375rem;
    cursor: pointer;
    transition: all 0.15s ease;
    
    &:hover {
      background: rgba($admin-accent-end, 0.1);
      color: $admin-text-primary;
    }
    
    &.active {
      background: rgba($admin-accent-end, 0.2);
      color: $admin-accent-end;
    }
    
    .badge {
      margin-left: auto;
      background: $admin-element-bg;
      color: $admin-text-secondary;
      font-size: 0.7rem;
      padding: 0.125rem 0.5rem;
      border-radius: 9999px;
    }
  }
}

// Analytics Cards
.metric-card {
  background: $admin-bg-secondary;
  border: 1px solid $admin-border;
  border-radius: 0.75rem;
  padding: 1.5rem;
  display: flex;
  gap: 1rem;
  
  .metric-icon {
    width: 3rem;
    height: 3rem;
    border-radius: 0.75rem;
    background: linear-gradient(135deg, $admin-accent-start, $admin-accent-end);
    display: flex;
    align-items: center;
    justify-content: center;
    
    i {
      color: white;
      width: 1.5rem;
      height: 1.5rem;
    }
  }
  
  .metric-content {
    flex: 1;
    
    h3 {
      color: $admin-text-primary;
      font-size: 2rem;
      font-weight: 600;
      margin: 0;
    }
    
    p {
      color: $admin-text-secondary;
      margin: 0;
      font-size: 0.875rem;
    }
    
    .trend {
      font-size: 0.75rem;
      font-weight: 500;
      
      &.positive { color: #22C55E; }
      &.negative { color: #EF4444; }
      &.neutral { color: $admin-text-muted; }
    }
  }
}
```

## JavaScript Interactions

```javascript
// Document Management interactions
class DocumentManager {
  constructor() {
    this.initializeSearch();
    this.initializeFilters();
    this.initializeDragDrop();
    this.initializeQuickUpload();
  }
  
  initializeSearch() {
    const searchInput = document.getElementById('documentSearch');
    const aiToggle = document.getElementById('aiSearchToggle');
    
    searchInput.addEventListener('input', debounce((e) => {
      const query = e.target.value;
      const useAI = aiToggle.checked;
      
      if (useAI) {
        this.performSemanticSearch(query);
      } else {
        this.performKeywordSearch(query);
      }
    }, 300));
  }
  
  async performSemanticSearch(query) {
    // Call AI search endpoint
    const response = await fetch('/api/documents/semantic_search', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ query })
    });
    
    const results = await response.json();
    this.renderSearchResults(results);
  }
  
  initializeDragDrop() {
    // Enable drag and drop for document organization
    const documentCards = document.querySelectorAll('.document-card');
    const subjectItems = document.querySelectorAll('.subject-item');
    
    documentCards.forEach(card => {
      card.draggable = true;
      card.addEventListener('dragstart', this.handleDragStart);
    });
    
    subjectItems.forEach(subject => {
      subject.addEventListener('dragover', this.handleDragOver);
      subject.addEventListener('drop', this.handleDrop);
    });
  }
}

// Initialize on page load
document.addEventListener('turbo:load', () => {
  new DocumentManager();
});
```

## Implementation Priority

### Phase 1 (MVP Enhancement)
1. Subject/Collection organization
2. Enhanced search with filters
3. Document metadata and tagging
4. Basic analytics tracking

### Phase 2
1. AI-powered search
2. Document relationships
3. Analytics dashboard
4. Bulk operations

### Phase 3
1. Collaboration features
2. Smart folders
3. Data lake integration
4. Advanced analytics
