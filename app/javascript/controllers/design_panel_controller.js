import { Controller } from "@hotwired/stimulus"

/**
 * Design Panel Controller
 * Manages the integrated sidebar for Design Mode
 */
export default class extends Controller {
  static targets = ["frontendComponents", "backendComponents", "canvasOptions"]
  static values = {
    currentView: { type: String, default: "frontend" },
    currentCanvas: { type: String, default: "template_library" }
  }

  connect() {
    console.log("🎨 Design Panel connected")
    
    // Restore saved state
    this.restoreState()
    
    // Initialize Lucide icons
    this.initLucideIcons()
    
    // Set up drop zone on initial load
    setTimeout(() => this.setupCanvasDropZone(), 500)
    
    // Load default canvas if none loaded
    this.maybeLoadDefaultCanvas()
  }

  initLucideIcons() {
    if (typeof lucide !== 'undefined') {
      setTimeout(() => lucide.createIcons(), 100)
    }
  }

  restoreState() {
    // Restore view mode
    const savedView = localStorage.getItem('designPanel_currentView') || 'frontend'
    this.currentViewValue = savedView
    this.updateViewToggle(savedView)
    this.updateComponentPalette(savedView)
    
    // Restore active canvas
    const savedCanvas = localStorage.getItem('designPanel_currentCanvas') || 'template_library'
    this.currentCanvasValue = savedCanvas
    this.updateActiveCanvas(savedCanvas)
  }

  maybeLoadDefaultCanvas() {
    const sessionKey = 'designPanelCanvasLoaded'
    if (sessionStorage.getItem(sessionKey)) return
    
    sessionStorage.setItem(sessionKey, 'true')
    
    // Load saved canvas or default
    const canvasToLoad = this.currentCanvasValue || 'template_library'
    setTimeout(() => {
      this.loadCanvasViaAjax(canvasToLoad)
    }, 300)
  }

  // ============ View Toggle (Frontend/Backend) ============
  
  switchView(event) {
    event?.preventDefault()
    event?.stopPropagation()
    
    const btn = event.currentTarget
    const view = btn.dataset.view
    
    if (view === this.currentViewValue) return
    
    this.currentViewValue = view
    localStorage.setItem('designPanel_currentView', view)
    
    this.updateViewToggle(view)
    this.updateComponentPalette(view)
    
    // Load appropriate canvas based on view
    const canvasMap = {
      'frontend': 'template_library',
      'backend': 'workflow_designer'
    }
    
    // Only switch canvas if switching views
    const newCanvas = canvasMap[view]
    if (newCanvas && newCanvas !== this.currentCanvasValue) {
      this.loadCanvas({ currentTarget: { dataset: { canvas: newCanvas } } })
    }
    
    console.log("🎨 Switched to view:", view)
  }

  updateViewToggle(view) {
    this.element.querySelectorAll('.view-toggle-btn').forEach(btn => {
      btn.classList.toggle('active', btn.dataset.view === view)
    })
  }

  updateComponentPalette(view) {
    if (this.hasFrontendComponentsTarget && this.hasBackendComponentsTarget) {
      this.frontendComponentsTarget.style.display = view === 'frontend' ? 'grid' : 'none'
      this.backendComponentsTarget.style.display = view === 'backend' ? 'grid' : 'none'
    }
  }

  // ============ Canvas Loading ============
  
  loadCanvas(event) {
    event?.preventDefault?.()
    event?.stopPropagation?.()
    
    const canvasType = event.currentTarget?.dataset?.canvas
    if (!canvasType) return
    
    this.currentCanvasValue = canvasType
    localStorage.setItem('designPanel_currentCanvas', canvasType)
    
    this.updateActiveCanvas(canvasType)
    this.loadCanvasViaAjax(canvasType)
  }

  updateActiveCanvas(canvasType) {
    this.element.querySelectorAll('.canvas-option').forEach(btn => {
      btn.classList.toggle('active', btn.dataset.canvas === canvasType)
    })
  }

  async loadCanvasViaAjax(canvasType) {
    console.log("🌐 Design Panel loading canvas:", canvasType)
    
    try {
      const response = await fetch('/scout/load_canvas', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'X-CSRF-Token': this.getCSRFToken()
        },
        body: JSON.stringify({ canvas_type: canvasType })
      })
      
      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`)
      }
      
      const result = await response.json()
      
      if (result.success && result.canvas?.content) {
        const templateContent = document.querySelector('.template-content')
        if (templateContent) {
          templateContent.innerHTML = result.canvas.content
          this.initLucideIcons()
          
          // Set up drop zone for components in the loaded canvas
          this.setupCanvasDropZone()
          
          console.log("✅ Canvas loaded:", canvasType)
        }
      } else {
        console.error("Canvas load failed - no content in response")
      }
    } catch (error) {
      console.error("❌ Canvas load failed:", error)
    }
  }

  // ============ Component Drag & Drop ============
  
  handleDragStart(event) {
    const element = event.currentTarget
    const componentType = element.dataset.componentType
    
    event.dataTransfer.setData('application/json', JSON.stringify({
      type: 'component',
      componentType: componentType,
      view: this.currentViewValue
    }))
    event.dataTransfer.effectAllowed = 'copy'
    
    console.log('🎨 Dragging component:', componentType)
    
    // Add visual feedback - store reference before setTimeout
    element.classList.add('dragging')
    setTimeout(() => {
      if (element) element.classList.remove('dragging')
    }, 100)
  }
  
  handleDragEnd(event) {
    event.currentTarget.classList.remove('dragging')
  }
  
  setupCanvasDropZone() {
    console.log('🎯 Setting up canvas drop zone...')
    
    // NEW: Direct DOM landing page editor (preferred - no iframe!)
    const landingPageContent = document.querySelector('#landingPageContent')
    
    // Legacy: Iframe-based editor (deprecated)
    const iframe = document.querySelector('#editorFrame')
    
    // Generic canvas areas
    const templateContent = document.querySelector('.template-content')
    const templateArea = document.querySelector('.template-area')
    
    console.log('🎯 Found elements:', { 
      landingPageContent: !!landingPageContent,
      iframe: !!iframe, 
      templateContent: !!templateContent,
      templateArea: !!templateArea
    })
    
    // Priority 1: Direct DOM landing page editor (new approach!)
    if (landingPageContent) {
      console.log('🎯 Setting up DIRECT DOM landing page drop handlers')
      this.setupDirectEditorDropHandlers(landingPageContent)
      return // No need to set up other handlers
    }
    
    // Priority 2: Iframe (legacy - keep for backwards compatibility)
    if (iframe) {
      console.log('🎯 Using legacy iframe overlay (consider migrating)')
      this.setupIframeDropOverlay(iframe)
      return
    }
    
    // Priority 3: Generic template content
    if (templateContent) {
      console.log('🎯 Setting up template-content drop handlers')
      this.setupDropHandlers(templateContent)
      return
    }
    
    // Priority 4: Template area as fallback
    if (templateArea) {
      console.log('🎯 Setting up template-area drop handlers (fallback)')
      this.setupDropHandlers(templateArea)
    }
  }
  
  /**
   * Set up drop handlers for the new direct DOM landing page editor
   * This is the preferred approach - no iframe complications!
   */
  setupDirectEditorDropHandlers(contentElement) {
    if (contentElement._dropHandlersSet) {
      console.log('🎯 Direct editor drop handlers already set')
      return
    }
    contentElement._dropHandlersSet = true
    
    let highlightedElement = null
    
    const clearHighlights = () => {
      if (highlightedElement) {
        highlightedElement.classList.remove('drop-target')
        highlightedElement = null
      }
      contentElement.classList.remove('drag-over')
    }
    
    contentElement.addEventListener('dragover', (e) => {
      e.preventDefault()
      e.dataTransfer.dropEffect = 'copy'
      
      // Show we're in a drop zone
      contentElement.classList.add('drag-over')
      
      // Find the nearest section/container we're hovering over
      const target = e.target
      const dropTarget = target.closest('section, footer, header, [class*="section"], [class*="hero"], .container')
      
      if (dropTarget && dropTarget !== highlightedElement) {
        clearHighlights()
        highlightedElement = dropTarget
        dropTarget.classList.add('drop-target')
      }
    })
    
    contentElement.addEventListener('dragleave', (e) => {
      if (!contentElement.contains(e.relatedTarget)) {
        clearHighlights()
      }
    })
    
    contentElement.addEventListener('drop', (e) => {
      e.preventDefault()
      e.stopPropagation()
      
      const dropTarget = highlightedElement || e.target
      clearHighlights()
      
      try {
        const jsonData = e.dataTransfer.getData('application/json')
        if (!jsonData) {
          console.warn('🎯 No JSON data in drop')
          return
        }
        
        const data = JSON.parse(jsonData)
        console.log('🎯 DROP on landing page editor:', data)
        
        if (data.type === 'component') {
          // Use the landing page editor's own insert function if available
          if (window.landingPageEditor?.insertComponent) {
            window.landingPageEditor.insertComponent(data.componentType, dropTarget)
          } else {
            // Fallback to our own insert logic
            this.insertDirectComponent(data.componentType, dropTarget, contentElement)
          }
        }
      } catch (err) {
        console.error('🎯 Drop error:', err)
      }
    })
    
    console.log('✅ Direct editor drop handlers configured')
  }
  
  /**
   * Insert component directly into the landing page content
   */
  insertDirectComponent(componentType, targetElement, contentElement) {
    console.log('🎨 Direct insert:', componentType, 'near', targetElement?.tagName)
    
    const componentHtml = this.getComponentHtml(componentType)
    const isSectionComponent = componentType.startsWith('section_') || componentType === 'footer'
    
    // Create the element
    const wrapper = document.createElement('div')
    wrapper.innerHTML = componentHtml.trim()
    const newElement = wrapper.firstElementChild || wrapper
    
    // Add highlight class
    newElement.classList.add('just-inserted')
    
    if (isSectionComponent) {
      // Insert after the target section, or at end
      const section = targetElement?.closest?.('section, footer, header, [class*="section"]')
      if (section) {
        section.insertAdjacentElement('afterend', newElement)
      } else {
        contentElement.appendChild(newElement)
      }
    } else {
      // For elements, insert inside the nearest container
      const container = targetElement?.closest?.('.container, section, div[class*="content"]')
      if (container) {
        container.appendChild(newElement)
      } else {
        contentElement.appendChild(newElement)
      }
    }
    
    // Scroll to new element
    newElement.scrollIntoView({ behavior: 'smooth', block: 'center' })
    
    // Mark editor as having changes
    if (window.landingPageEditor?.markChanged) {
      window.landingPageEditor.markChanged()
    }
    
    // Show notification
    this.showNotification(`${componentType.replace(/_/g, ' ')} added!`, 'success')
    
    // Remove highlight after animation
    setTimeout(() => {
      newElement.classList.remove('just-inserted')
    }, 1500)
    
    console.log('✅ Component inserted directly:', componentType)
  }
  
  setupIframeDropOverlay(iframe) {
    console.log('🎯 Setting up iframe drop overlay')
    
    // Get or create an overlay that sits on top of the iframe
    let overlay = document.querySelector('.iframe-drop-overlay')
    if (!overlay) {
      overlay = document.createElement('div')
      overlay.className = 'iframe-drop-overlay'
      overlay.style.cssText = `
        position: absolute;
        top: 0;
        left: 0;
        right: 0;
        bottom: 0;
        z-index: 100;
        pointer-events: none;
        background: transparent;
      `
      
      // Insert overlay as sibling to iframe
      iframe.parentElement.style.position = 'relative'
      iframe.parentElement.appendChild(overlay)
    }
    
    // Enable pointer events only during drag
    document.addEventListener('dragstart', () => {
      overlay.style.pointerEvents = 'auto'
      console.log('🎯 Overlay enabled for drag')
    })
    
    document.addEventListener('dragend', () => {
      overlay.style.pointerEvents = 'none'
      overlay.style.background = 'transparent'
      console.log('🎯 Overlay disabled after drag')
    })
    
    // Track mouse position to determine where in iframe to insert
    let lastY = 0
    
    overlay.addEventListener('dragover', (e) => {
      e.preventDefault()
      e.dataTransfer.dropEffect = 'copy'
      lastY = e.clientY
      
      // Visual feedback
      overlay.style.background = 'rgba(236, 72, 153, 0.1)'
      
      // Find which section we're over in the iframe
      const iframeDoc = iframe.contentDocument || iframe.contentWindow?.document
      if (iframeDoc) {
        this.highlightIframeSectionAtY(iframeDoc, e.clientY - iframe.getBoundingClientRect().top)
      }
    })
    
    overlay.addEventListener('dragleave', (e) => {
      if (!overlay.contains(e.relatedTarget)) {
        overlay.style.background = 'transparent'
        // Clear highlights
        const iframeDoc = iframe.contentDocument || iframe.contentWindow?.document
        if (iframeDoc) {
          iframeDoc.querySelectorAll('[data-drop-highlight]').forEach(el => {
            el.style.outline = ''
            el.removeAttribute('data-drop-highlight')
          })
        }
      }
    })
    
    overlay.addEventListener('drop', (e) => {
      e.preventDefault()
      e.stopPropagation()
      
      overlay.style.background = 'transparent'
      overlay.style.pointerEvents = 'none'
      
      console.log('🎯 Drop on iframe overlay at Y:', lastY)
      
      try {
        const jsonData = e.dataTransfer.getData('application/json')
        if (!jsonData) {
          console.warn('🎯 No JSON data in drop')
          return
        }
        
        const data = JSON.parse(jsonData)
        if (data.type === 'component') {
          // Find the section at this Y position
          const iframeDoc = iframe.contentDocument || iframe.contentWindow?.document
          const iframeY = e.clientY - iframe.getBoundingClientRect().top + (iframeDoc.documentElement.scrollTop || 0)
          
          this.insertComponentInIframe(data.componentType, iframeDoc, iframeY)
        }
      } catch (err) {
        console.error('🎯 Drop error:', err)
      }
    })
  }
  
  highlightIframeSectionAtY(doc, y) {
    // Clear previous highlights
    doc.querySelectorAll('[data-drop-highlight]').forEach(el => {
      el.style.outline = ''
      el.removeAttribute('data-drop-highlight')
    })
    
    // Find sections
    const sections = doc.querySelectorAll('section, footer, header, [class*="section"], [class*="hero"]')
    
    for (const section of sections) {
      const rect = section.getBoundingClientRect()
      if (y >= rect.top && y <= rect.bottom) {
        section.style.outline = '3px dashed #ec4899'
        section.setAttribute('data-drop-highlight', 'true')
        break
      }
    }
  }
  
  insertComponentInIframe(componentType, doc, yPosition) {
    console.log('🎯 Inserting in iframe at Y:', yPosition)
    
    const componentHtml = this.getComponentHtml(componentType)
    const isSectionComponent = componentType.startsWith('section_') || componentType === 'footer'
    
    // Find all sections
    const sections = Array.from(doc.querySelectorAll('section, footer, header, [class*="section"], [class*="hero"]'))
    
    // Find which section we're after based on Y position
    let insertAfter = null
    for (const section of sections) {
      const rect = section.getBoundingClientRect()
      const scrollTop = doc.documentElement.scrollTop || doc.body.scrollTop || 0
      const sectionY = rect.top + scrollTop
      
      if (yPosition > sectionY) {
        insertAfter = section
      }
    }
    
    console.log('🎯 Insert after section:', insertAfter?.tagName, insertAfter?.className?.substring?.(0, 30))
    
    // Create the element
    const wrapper = doc.createElement('div')
    wrapper.innerHTML = componentHtml
    
    // Get the actual element to insert
    let elementToInsert = wrapper.firstElementChild || wrapper
    elementToInsert.setAttribute('data-inserted', 'true')
    
    if (insertAfter) {
      insertAfter.insertAdjacentElement('afterend', elementToInsert)
    } else {
      // Insert at beginning if no section found
      const body = doc.body
      if (body.firstElementChild) {
        body.firstElementChild.insertAdjacentElement('beforebegin', elementToInsert)
      } else {
        body.appendChild(elementToInsert)
      }
    }
    
    // Clear any highlights
    doc.querySelectorAll('[data-drop-highlight]').forEach(el => {
      el.style.outline = ''
      el.removeAttribute('data-drop-highlight')
    })
    
    // Scroll to new element
    elementToInsert.scrollIntoView({ behavior: 'smooth', block: 'center' })
    
    // Highlight briefly
    elementToInsert.style.boxShadow = '0 0 0 4px rgba(236, 72, 153, 0.5)'
    setTimeout(() => {
      elementToInsert.style.boxShadow = ''
      elementToInsert.removeAttribute('data-inserted')
    }, 1500)
    
    // Enable save button
    if (window.scoutInlineEditor) {
      window.scoutInlineEditor.changes = window.scoutInlineEditor.changes || {}
      window.scoutInlineEditor.changes.components = window.scoutInlineEditor.changes.components || []
      window.scoutInlineEditor.changes.components.push({ type: componentType, inserted: true })
      
      if (typeof updateSaveButton === 'function') {
        updateSaveButton(true)
      }
    }
    
    console.log('✅ Component inserted in iframe:', componentType)
    this.showNotification(`${componentType.replace(/_/g, ' ')} added!`, 'success')
  }
  
  setupDropHandlers(container, iframe = null) {
    // Prevent duplicate handlers
    if (container._dropHandlersSet) {
      console.log('🎯 Drop handlers already set on', container.className || container.tagName)
      return
    }
    container._dropHandlersSet = true
    
    console.log('🎯 Attaching drop handlers to:', container.className || container.tagName)
    
    // Store reference to currently highlighted element
    let currentHighlight = null
    
    const clearHighlight = () => {
      if (currentHighlight) {
        currentHighlight.style.outline = ''
        currentHighlight.style.outlineOffset = ''
        currentHighlight = null
      }
    }
    
    container.addEventListener('dragover', (e) => {
      e.preventDefault()
      e.dataTransfer.dropEffect = 'copy'
      
      // Find the best drop target - the element we're hovering over
      const target = e.target
      
      // Find nearest droppable element
      const dropTarget = target.closest?.('section, footer, header, div[class*="section"], div[class*="hero"], .container, .row, article, main') || target
      
      // Update highlight
      if (dropTarget !== currentHighlight) {
        clearHighlight()
        currentHighlight = dropTarget
        if (currentHighlight && currentHighlight !== container) {
          currentHighlight.style.outline = '3px dashed #ec4899'
          currentHighlight.style.outlineOffset = '-3px'
        }
      }
      
      // Also highlight container if hovering on empty space
      if (target === container || !dropTarget || dropTarget === container) {
        container.style.outline = '3px dashed rgba(236, 72, 153, 0.5)'
        container.style.outlineOffset = '-3px'
      } else {
        container.style.outline = ''
      }
    })
    
    container.addEventListener('dragleave', (e) => {
      // Only clear if leaving container entirely
      if (!container.contains(e.relatedTarget)) {
        clearHighlight()
        container.style.outline = ''
        container.style.outlineOffset = ''
      }
    })
    
    container.addEventListener('drop', (e) => {
      e.preventDefault()
      e.stopPropagation()
      
      const dropTarget = e.target
      console.log('🎯 DROP on element:', dropTarget.tagName, dropTarget.className?.substring?.(0, 50))
      
      // Clear visual feedback
      clearHighlight()
      container.style.outline = ''
      container.style.outlineOffset = ''
      
      try {
        const jsonData = e.dataTransfer.getData('application/json')
        if (!jsonData) {
          console.warn('🎯 No JSON data in drop')
          return
        }
        
        const data = JSON.parse(jsonData)
        if (data.type === 'component') {
          console.log('🎯 Inserting component:', data.componentType)
          this.insertComponent(data.componentType, dropTarget, iframe, container)
        }
      } catch (err) {
        console.error('🎯 Drop error:', err)
      }
    })
  }
  
  insertComponent(componentType, targetElement, iframe = null, container = null) {
    console.log('🎨 Inserting component:', componentType, 'at', targetElement?.tagName)
    
    // Get the document context (iframe or main document)
    const doc = iframe ? (iframe.contentDocument || iframe.contentWindow?.document) : document
    const body = container || doc.body
    
    // Create component HTML based on type
    const componentHtml = this.getComponentHtml(componentType)
    
    // Determine if this is a section-level component or an inline component
    const isSectionComponent = componentType.startsWith('section_') || componentType === 'footer'
    
    // Find the right insertion point based on component type
    let insertionPoint = null
    let insertMethod = 'afterend'
    
    if (isSectionComponent) {
      // For sections: find the nearest section and insert after it
      insertionPoint = targetElement.closest?.('section, footer, header, [class*="section"], [class*="hero"]')
      
      if (!insertionPoint) {
        // No section found - insert at end of body/container
        insertionPoint = body
        insertMethod = 'beforeend'
      }
      
      console.log('🎨 Section insert after:', insertionPoint?.tagName, insertionPoint?.className?.substring?.(0, 30))
    } else {
      // For inline components (buttons, text, etc.): insert inside the nearest container
      insertionPoint = targetElement.closest?.('.container, .row, section, div[class*="content"], article')
      
      if (insertionPoint) {
        // Insert at the end of this container
        insertMethod = 'beforeend'
      } else {
        // Fallback: insert after the target element
        insertionPoint = targetElement
        insertMethod = 'afterend'
      }
      
      console.log('🎨 Element insert into:', insertionPoint?.tagName, insertionPoint?.className?.substring?.(0, 30))
    }
    
    // Create the component element
    const wrapper = doc.createElement('div')
    wrapper.innerHTML = componentHtml
    
    // For sections, unwrap and use the section directly
    if (isSectionComponent && wrapper.firstElementChild?.tagName === 'SECTION' || wrapper.firstElementChild?.tagName === 'FOOTER') {
      const sectionEl = wrapper.firstElementChild
      sectionEl.classList.add('inserted-component')
      sectionEl.setAttribute('data-inserted', 'true')
      
      if (insertMethod === 'beforeend') {
        insertionPoint.appendChild(sectionEl)
      } else if (insertMethod === 'afterend' && insertionPoint.insertAdjacentElement) {
        insertionPoint.insertAdjacentElement('afterend', sectionEl)
      } else {
        body.appendChild(sectionEl)
      }
    } else {
      // For other components, wrap in a div
      wrapper.className = 'inserted-component'
      wrapper.style.marginTop = '1rem'
      wrapper.style.marginBottom = '1rem'
      wrapper.setAttribute('data-inserted', 'true')
      
      if (insertMethod === 'beforeend') {
        insertionPoint.appendChild(wrapper)
      } else if (insertMethod === 'afterend' && insertionPoint?.insertAdjacentElement) {
        insertionPoint.insertAdjacentElement('afterend', wrapper)
      } else {
        body.appendChild(wrapper)
      }
    }
    
    // Enable save button if in landing page editor
    if (iframe && window.scoutInlineEditor) {
      window.scoutInlineEditor.changes = window.scoutInlineEditor.changes || {}
      window.scoutInlineEditor.changes.components = window.scoutInlineEditor.changes.components || []
      window.scoutInlineEditor.changes.components.push({ type: componentType, inserted: true })
      
      // Try to call updateSaveButton
      if (typeof updateSaveButton === 'function') {
        updateSaveButton(true)
      }
    }
    
    // Scroll to the new component
    const newElement = doc.querySelector('[data-inserted="true"]:last-of-type')
    if (newElement) {
      newElement.scrollIntoView({ behavior: 'smooth', block: 'center' })
      // Briefly highlight
      newElement.style.boxShadow = '0 0 0 4px rgba(236, 72, 153, 0.5)'
      setTimeout(() => {
        newElement.style.boxShadow = ''
        newElement.removeAttribute('data-inserted')
      }, 1500)
    }
    
    console.log('✅ Component inserted:', componentType)
    
    // Show notification
    this.showNotification(`${componentType.replace(/_/g, ' ')} added!`, 'success')
  }
  
  getComponentHtml(componentType) {
    const components = {
      // Frontend components - clean sample content, no "click to edit" hints
      'text_block': `<p style="font-size: 1rem; color: inherit;">Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.</p>`,
      'heading': `<h2 style="font-size: 2rem; font-weight: bold; color: inherit;">Section Heading</h2>`,
      'image': `<div style="background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); padding: 4rem 2rem; border-radius: 0.5rem; text-align: center; color: white; font-size: 3rem;">🖼️</div>`,
      'button': `<button style="background: linear-gradient(135deg, #ec4899, #f472b6); color: white; border: none; padding: 0.75rem 1.5rem; border-radius: 0.5rem; font-weight: 600; cursor: pointer;">Get Started</button>`,
      'form': `<form style="background: rgba(255,255,255,0.05); padding: 1.5rem; border-radius: 0.5rem; border: 1px solid rgba(255,255,255,0.1);"><div style="margin-bottom: 1rem;"><label style="display: block; margin-bottom: 0.25rem; color: inherit;">Email</label><input type="email" placeholder="your@email.com" style="width: 100%; padding: 0.5rem; border-radius: 0.25rem; border: 1px solid rgba(255,255,255,0.2); background: rgba(255,255,255,0.1); color: inherit;"></div><button type="submit" style="background: #ec4899; color: white; border: none; padding: 0.5rem 1rem; border-radius: 0.25rem; cursor: pointer;">Subscribe</button></form>`,
      'card': `<div style="background: rgba(255,255,255,0.05); padding: 1.5rem; border-radius: 0.75rem; border: 1px solid rgba(255,255,255,0.1); max-width: 350px;"><h3 style="margin-bottom: 0.5rem; color: inherit;">Card Title</h3><p style="color: rgba(255,255,255,0.7); line-height: 1.5;">A brief description of the card content goes here.</p></div>`,
      'table': `<table style="width: 100%; border-collapse: collapse;"><thead><tr><th style="border: 1px solid rgba(255,255,255,0.2); padding: 0.5rem; text-align: left; color: inherit;">Name</th><th style="border: 1px solid rgba(255,255,255,0.2); padding: 0.5rem; text-align: left; color: inherit;">Value</th></tr></thead><tbody><tr><td style="border: 1px solid rgba(255,255,255,0.2); padding: 0.5rem; color: inherit;">Item 1</td><td style="border: 1px solid rgba(255,255,255,0.2); padding: 0.5rem; color: inherit;">$99</td></tr><tr><td style="border: 1px solid rgba(255,255,255,0.2); padding: 0.5rem; color: inherit;">Item 2</td><td style="border: 1px solid rgba(255,255,255,0.2); padding: 0.5rem; color: inherit;">$149</td></tr></tbody></table>`,
      'chart': `<div style="background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%); padding: 3rem 2rem; border-radius: 0.75rem; text-align: center; font-size: 3rem;">📊</div>`,
      
      // Section components
      'section_hero': `<section style="padding: 4rem 2rem; text-align: center; background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);">
        <h1 style="font-size: 3rem; font-weight: bold; margin-bottom: 1rem; color: #fff;">Hero Section Title</h1>
        <p style="font-size: 1.25rem; color: rgba(255,255,255,0.8); margin-bottom: 2rem; max-width: 600px; margin-left: auto; margin-right: auto;">Add your compelling subtitle or value proposition here</p>
        <button style="background: linear-gradient(135deg, #ec4899, #f472b6); color: white; padding: 1rem 2rem; border: none; border-radius: 8px; font-size: 1.1rem; cursor: pointer;">Get Started</button>
      </section>`,
      
      'section_features': `<section style="padding: 3rem 2rem; background: #1a1a2e;">
        <h2 style="text-align: center; color: #fff; margin-bottom: 2rem;">Features</h2>
        <div style="display: grid; grid-template-columns: repeat(3, 1fr); gap: 2rem; max-width: 1200px; margin: 0 auto;">
          <div style="background: rgba(255,255,255,0.05); padding: 2rem; border-radius: 12px; text-align: center;">
            <div style="font-size: 2rem; margin-bottom: 1rem;">⚡</div>
            <h3 style="color: #ec4899; margin-bottom: 0.5rem;">Feature 1</h3>
            <p style="color: rgba(255,255,255,0.7);">Description of your first feature</p>
          </div>
          <div style="background: rgba(255,255,255,0.05); padding: 2rem; border-radius: 12px; text-align: center;">
            <div style="font-size: 2rem; margin-bottom: 1rem;">🚀</div>
            <h3 style="color: #ec4899; margin-bottom: 0.5rem;">Feature 2</h3>
            <p style="color: rgba(255,255,255,0.7);">Description of your second feature</p>
          </div>
          <div style="background: rgba(255,255,255,0.05); padding: 2rem; border-radius: 12px; text-align: center;">
            <div style="font-size: 2rem; margin-bottom: 1rem;">💎</div>
            <h3 style="color: #ec4899; margin-bottom: 0.5rem;">Feature 3</h3>
            <p style="color: rgba(255,255,255,0.7);">Description of your third feature</p>
          </div>
        </div>
      </section>`,
      
      'section_cards': `<section style="padding: 3rem 2rem; background: #f8f9fa;">
        <h2 style="text-align: center; color: #1a1a2e; margin-bottom: 2rem;">Our Services</h2>
        <div style="display: grid; grid-template-columns: repeat(3, 1fr); gap: 1.5rem; max-width: 1100px; margin: 0 auto;">
          <div style="background: white; padding: 2rem; border-radius: 12px; box-shadow: 0 4px 12px rgba(0,0,0,0.08);">
            <div style="font-size: 2rem; margin-bottom: 1rem;">🎯</div>
            <h3 style="color: #1a1a2e; margin-bottom: 0.5rem;">Service One</h3>
            <p style="color: #666; line-height: 1.6;">A brief description of what this service includes and how it helps customers.</p>
          </div>
          <div style="background: white; padding: 2rem; border-radius: 12px; box-shadow: 0 4px 12px rgba(0,0,0,0.08);">
            <div style="font-size: 2rem; margin-bottom: 1rem;">💡</div>
            <h3 style="color: #1a1a2e; margin-bottom: 0.5rem;">Service Two</h3>
            <p style="color: #666; line-height: 1.6;">A brief description of what this service includes and how it helps customers.</p>
          </div>
          <div style="background: white; padding: 2rem; border-radius: 12px; box-shadow: 0 4px 12px rgba(0,0,0,0.08);">
            <div style="font-size: 2rem; margin-bottom: 1rem;">🚀</div>
            <h3 style="color: #1a1a2e; margin-bottom: 0.5rem;">Service Three</h3>
            <p style="color: #666; line-height: 1.6;">A brief description of what this service includes and how it helps customers.</p>
          </div>
        </div>
      </section>`,
      
      'section_testimonials': `<section style="padding: 3rem 2rem; background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);">
        <h2 style="text-align: center; color: #fff; margin-bottom: 2rem;">What People Say</h2>
        <div style="display: grid; grid-template-columns: repeat(2, 1fr); gap: 2rem; max-width: 900px; margin: 0 auto;">
          <div style="background: rgba(255,255,255,0.1); padding: 2rem; border-radius: 12px;">
            <p style="color: white; font-style: italic; margin-bottom: 1rem;">"This is an amazing product that changed how we work!"</p>
            <div style="display: flex; align-items: center; gap: 0.75rem;">
              <div style="width: 40px; height: 40px; background: #ec4899; border-radius: 50%; display: flex; align-items: center; justify-content: center; color: white; font-weight: bold;">JD</div>
              <div><strong style="color: white;">Jane Doe</strong><br><span style="color: rgba(255,255,255,0.7); font-size: 0.875rem;">CEO, Company</span></div>
            </div>
          </div>
          <div style="background: rgba(255,255,255,0.1); padding: 2rem; border-radius: 12px;">
            <p style="color: white; font-style: italic; margin-bottom: 1rem;">"Highly recommend to anyone looking for a solution."</p>
            <div style="display: flex; align-items: center; gap: 0.75rem;">
              <div style="width: 40px; height: 40px; background: #3b82f6; border-radius: 50%; display: flex; align-items: center; justify-content: center; color: white; font-weight: bold;">JS</div>
              <div><strong style="color: white;">John Smith</strong><br><span style="color: rgba(255,255,255,0.7); font-size: 0.875rem;">CTO, Startup</span></div>
            </div>
          </div>
        </div>
      </section>`,
      
      'section_cta': `<section style="padding: 4rem 2rem; text-align: center; background: #0f0f1a;">
        <h2 style="font-size: 2.5rem; color: white; margin-bottom: 1rem;">Ready to Get Started?</h2>
        <p style="color: rgba(255,255,255,0.7); margin-bottom: 2rem; max-width: 500px; margin-left: auto; margin-right: auto;">Join thousands of satisfied customers today</p>
        <div style="display: flex; gap: 1rem; justify-content: center; flex-wrap: wrap;">
          <button style="background: #ec4899; color: white; padding: 1rem 2rem; border: none; border-radius: 8px; cursor: pointer; font-weight: 600;">Start Free Trial</button>
          <button style="background: transparent; color: white; padding: 1rem 2rem; border: 2px solid white; border-radius: 8px; cursor: pointer;">Contact Sales</button>
        </div>
      </section>`,
      
      'section_pricing': `<section style="padding: 3rem 2rem; background: #1a1a2e;">
        <h2 style="text-align: center; color: #fff; margin-bottom: 0.5rem;">Pricing</h2>
        <p style="text-align: center; color: rgba(255,255,255,0.6); margin-bottom: 2rem;">Choose the plan that works for you</p>
        <div style="display: grid; grid-template-columns: repeat(3, 1fr); gap: 1.5rem; max-width: 1000px; margin: 0 auto;">
          <div style="background: rgba(255,255,255,0.05); padding: 2rem; border-radius: 12px; text-align: center;">
            <h3 style="color: #fff; margin-bottom: 0.5rem;">Starter</h3>
            <div style="font-size: 2.5rem; font-weight: bold; color: #ec4899; margin: 1rem 0;">$9<span style="font-size: 1rem; color: rgba(255,255,255,0.5);">/mo</span></div>
            <ul style="list-style: none; padding: 0; margin: 1.5rem 0; color: rgba(255,255,255,0.7); text-align: left;">
              <li style="margin-bottom: 0.5rem;">✓ Feature 1</li>
              <li style="margin-bottom: 0.5rem;">✓ Feature 2</li>
              <li style="margin-bottom: 0.5rem;">✓ Feature 3</li>
            </ul>
            <button style="width: 100%; background: transparent; border: 1px solid #ec4899; color: #ec4899; padding: 0.75rem; border-radius: 6px; cursor: pointer;">Get Started</button>
          </div>
          <div style="background: linear-gradient(135deg, #ec4899, #f472b6); padding: 2rem; border-radius: 12px; text-align: center; transform: scale(1.05);">
            <span style="background: white; color: #ec4899; padding: 0.25rem 0.75rem; border-radius: 20px; font-size: 0.75rem; font-weight: bold;">POPULAR</span>
            <h3 style="color: #fff; margin: 0.5rem 0;">Pro</h3>
            <div style="font-size: 2.5rem; font-weight: bold; color: white; margin: 1rem 0;">$29<span style="font-size: 1rem; opacity: 0.7;">/mo</span></div>
            <ul style="list-style: none; padding: 0; margin: 1.5rem 0; color: rgba(255,255,255,0.9); text-align: left;">
              <li style="margin-bottom: 0.5rem;">✓ Everything in Starter</li>
              <li style="margin-bottom: 0.5rem;">✓ Pro Feature 1</li>
              <li style="margin-bottom: 0.5rem;">✓ Pro Feature 2</li>
            </ul>
            <button style="width: 100%; background: white; color: #ec4899; padding: 0.75rem; border-radius: 6px; cursor: pointer; font-weight: bold;">Get Started</button>
          </div>
          <div style="background: rgba(255,255,255,0.05); padding: 2rem; border-radius: 12px; text-align: center;">
            <h3 style="color: #fff; margin-bottom: 0.5rem;">Enterprise</h3>
            <div style="font-size: 2.5rem; font-weight: bold; color: #ec4899; margin: 1rem 0;">$99<span style="font-size: 1rem; color: rgba(255,255,255,0.5);">/mo</span></div>
            <ul style="list-style: none; padding: 0; margin: 1.5rem 0; color: rgba(255,255,255,0.7); text-align: left;">
              <li style="margin-bottom: 0.5rem;">✓ Everything in Pro</li>
              <li style="margin-bottom: 0.5rem;">✓ Priority Support</li>
              <li style="margin-bottom: 0.5rem;">✓ Custom Features</li>
            </ul>
            <button style="width: 100%; background: transparent; border: 1px solid #ec4899; color: #ec4899; padding: 0.75rem; border-radius: 6px; cursor: pointer;">Contact Us</button>
          </div>
        </div>
      </section>`,
      
      // Footer component
      'footer': `<footer style="padding: 3rem 2rem; background: #0f0f1a; border-top: 1px solid rgba(255,255,255,0.1);">
        <div style="max-width: 1200px; margin: 0 auto; display: grid; grid-template-columns: 2fr 1fr 1fr 1fr; gap: 2rem;">
          <div>
            <h3 style="color: white; margin-bottom: 1rem; font-size: 1.5rem;">Your Company</h3>
            <p style="color: rgba(255,255,255,0.6); margin-bottom: 1rem;">Making amazing things happen since 2024.</p>
            <div style="display: flex; gap: 1rem;">
              <a href="#" style="color: rgba(255,255,255,0.6); text-decoration: none;">Twitter</a>
              <a href="#" style="color: rgba(255,255,255,0.6); text-decoration: none;">LinkedIn</a>
              <a href="#" style="color: rgba(255,255,255,0.6); text-decoration: none;">GitHub</a>
            </div>
          </div>
          <div>
            <h4 style="color: white; margin-bottom: 1rem;">Product</h4>
            <ul style="list-style: none; padding: 0; margin: 0;">
              <li style="margin-bottom: 0.5rem;"><a href="#" style="color: rgba(255,255,255,0.6); text-decoration: none;">Features</a></li>
              <li style="margin-bottom: 0.5rem;"><a href="#" style="color: rgba(255,255,255,0.6); text-decoration: none;">Pricing</a></li>
              <li style="margin-bottom: 0.5rem;"><a href="#" style="color: rgba(255,255,255,0.6); text-decoration: none;">Integrations</a></li>
            </ul>
          </div>
          <div>
            <h4 style="color: white; margin-bottom: 1rem;">Company</h4>
            <ul style="list-style: none; padding: 0; margin: 0;">
              <li style="margin-bottom: 0.5rem;"><a href="#" style="color: rgba(255,255,255,0.6); text-decoration: none;">About</a></li>
              <li style="margin-bottom: 0.5rem;"><a href="#" style="color: rgba(255,255,255,0.6); text-decoration: none;">Blog</a></li>
              <li style="margin-bottom: 0.5rem;"><a href="#" style="color: rgba(255,255,255,0.6); text-decoration: none;">Careers</a></li>
            </ul>
          </div>
          <div>
            <h4 style="color: white; margin-bottom: 1rem;">Legal</h4>
            <ul style="list-style: none; padding: 0; margin: 0;">
              <li style="margin-bottom: 0.5rem;"><a href="#" style="color: rgba(255,255,255,0.6); text-decoration: none;">Privacy</a></li>
              <li style="margin-bottom: 0.5rem;"><a href="#" style="color: rgba(255,255,255,0.6); text-decoration: none;">Terms</a></li>
              <li style="margin-bottom: 0.5rem;"><a href="#" style="color: rgba(255,255,255,0.6); text-decoration: none;">Contact</a></li>
            </ul>
          </div>
        </div>
        <div style="max-width: 1200px; margin: 2rem auto 0; padding-top: 2rem; border-top: 1px solid rgba(255,255,255,0.1); text-align: center; color: rgba(255,255,255,0.5);">
          © 2024 Your Company. All rights reserved.
        </div>
      </footer>`,
      
      // Backend/workflow components
      'webhook': `<div style="background: rgba(34, 197, 94, 0.1); border: 1px solid rgba(34, 197, 94, 0.3); padding: 1rem; border-radius: 0.5rem;"><strong style="color: #22c55e;">⚡ Webhook Trigger</strong><p style="font-size: 0.875rem; opacity: 0.7; margin-top: 0.25rem;">Configure via chat</p></div>`,
      'schedule': `<div style="background: rgba(34, 197, 94, 0.1); border: 1px solid rgba(34, 197, 94, 0.3); padding: 1rem; border-radius: 0.5rem;"><strong style="color: #22c55e;">⏰ Schedule Trigger</strong><p style="font-size: 0.875rem; opacity: 0.7; margin-top: 0.25rem;">Configure via chat</p></div>`,
      'api_call': `<div style="background: rgba(59, 130, 246, 0.1); border: 1px solid rgba(59, 130, 246, 0.3); padding: 1rem; border-radius: 0.5rem;"><strong style="color: #3b82f6;">🌐 API Call</strong><p style="font-size: 0.875rem; opacity: 0.7; margin-top: 0.25rem;">Configure endpoint via chat</p></div>`,
      'email': `<div style="background: rgba(59, 130, 246, 0.1); border: 1px solid rgba(59, 130, 246, 0.3); padding: 1rem; border-radius: 0.5rem;"><strong style="color: #3b82f6;">📧 Send Email</strong><p style="font-size: 0.875rem; opacity: 0.7; margin-top: 0.25rem;">Configure via chat</p></div>`,
      'transform': `<div style="background: rgba(139, 92, 246, 0.1); border: 1px solid rgba(139, 92, 246, 0.3); padding: 1rem; border-radius: 0.5rem;"><strong style="color: #8b5cf6;">🔄 Transform</strong><p style="font-size: 0.875rem; opacity: 0.7; margin-top: 0.25rem;">Transform data via chat</p></div>`,
      'filter': `<div style="background: rgba(139, 92, 246, 0.1); border: 1px solid rgba(139, 92, 246, 0.3); padding: 1rem; border-radius: 0.5rem;"><strong style="color: #8b5cf6;">🔍 Filter</strong><p style="font-size: 0.875rem; opacity: 0.7; margin-top: 0.25rem;">Configure filter via chat</p></div>`
    }
    
    return components[componentType] || `<div style="padding: 1rem; border: 1px dashed #666; border-radius: 0.5rem;">Unknown component: ${componentType}</div>`
  }
  
  showNotification(message, type = 'info') {
    if (window.scoutShowNotification) {
      window.scoutShowNotification(message, type)
    } else {
      console.log(`[${type}] ${message}`)
    }
  }

  // ============ Work Categories ============
  
  toggleCategory(event) {
    event?.preventDefault()
    event?.stopPropagation()
    
    const header = event.currentTarget
    const category = header.closest('.work-category')
    const items = category.querySelector('.work-category-items')
    
    if (!items) return
    
    const isExpanded = items.style.display !== 'none'
    
    if (isExpanded) {
      items.style.display = 'none'
      header.classList.remove('expanded')
    } else {
      items.style.display = 'block'
      header.classList.add('expanded')
    }
  }
  
  openWorkItem(event) {
    event?.preventDefault()
    event?.stopPropagation()
    
    const item = event.currentTarget
    const itemId = item.dataset.itemId
    const itemType = item.dataset.itemType
    
    console.log("🎨 Opening work item:", itemType, itemId)
    
    // Map item type to canvas with correct data parameter
    const canvasConfig = {
      'landing_pages': { canvas: 'landing_page_editor', param: 'landing_page_id' },
      'modules': { canvas: 'module_designer', param: 'module_id' },
      'workflows': { canvas: 'workflow_designer', param: 'workflow_id' },
      'emails': { canvas: 'email_editor', param: 'email_sequence_id' }
    }
    
    const config = canvasConfig[itemType]
    if (config) {
      // Load the editor canvas directly with the item ID
      this.loadCanvasWithData(config.canvas, { [config.param]: itemId })
    }
  }
  
  async loadCanvasWithData(canvasType, canvasData = {}) {
    console.log("🌐 Design Panel loading canvas with data:", canvasType, canvasData)
    
    try {
      const response = await fetch('/scout/load_canvas', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'X-CSRF-Token': this.getCSRFToken()
        },
        body: JSON.stringify({ 
          canvas_type: canvasType,
          canvas_data: canvasData
        })
      })
      
      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`)
      }
      
      const result = await response.json()
      
      if (result.success && result.canvas?.content) {
        const templateContent = document.querySelector('.template-content')
        if (templateContent) {
          templateContent.innerHTML = result.canvas.content
          this.initLucideIcons()
          
          // Set up drop zone for components in the loaded canvas
          this.setupCanvasDropZone()
          
          console.log("✅ Canvas with data loaded:", canvasType)
        }
      } else {
        console.error("Canvas load failed - no content in response", result)
      }
    } catch (error) {
      console.error("❌ Canvas load failed:", error)
    }
  }

  newProject(event) {
    event?.preventDefault()
    
    // Focus the chat input
    const chatInput = document.querySelector('.chat-input')
    if (chatInput) {
      chatInput.focus()
      chatInput.placeholder = "Describe what you want to build..."
    }
    
    console.log("🎨 Starting new project")
  }

  openApp(event) {
    event?.preventDefault()
    const appId = event.currentTarget.dataset.appId
    console.log("🎨 Opening app:", appId)
    // TODO: Load app editor
  }

  // ============ Navigation ============
  
  switchSpace(event) {
    event?.preventDefault()
    event?.stopPropagation()
    
    const space = event.currentTarget.dataset.space
    if (!space || space === 'design') return // Already in design
    
    console.log("🚀 Switching to space:", space)
    
    fetch('/scout/switch_space', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': this.getCSRFToken()
      },
      body: JSON.stringify({ space: space })
    })
    .then(response => {
      if (response.ok) {
        window.location.reload()
      }
    })
  }

  // ============ Theme Toggle ============
  
  toggleTheme() {
    const html = document.documentElement
    const currentTheme = html.getAttribute('data-theme') || 'dark'
    const newTheme = currentTheme === 'dark' ? 'light' : 'dark'
    
    html.setAttribute('data-theme', newTheme)
    localStorage.setItem('theme', newTheme)
    
    console.log("🎨 Theme switched to:", newTheme)
  }

  // ============ Utilities ============
  
  getCSRFToken() {
    return document.querySelector('meta[name="csrf-token"]')?.getAttribute('content') || ''
  }
}
