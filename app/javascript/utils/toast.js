/**
 * Toast Notification Utility
 *
 * A reusable toast notification system using Bootstrap 5 toasts.
 * Replaces plain JavaScript alert() calls with styled notifications.
 *
 * Usage:
 *   import { showToast, showSuccess, showError, showWarning, showInfo } from '../utils/toast'
 *
 *   showToast('Hello world!')                    // Default info toast
 *   showSuccess('Saved successfully!')           // Green success toast
 *   showError('Something went wrong')            // Red error toast
 *   showWarning('Please check your input')       // Yellow warning toast
 *   showInfo('Processing...')                    // Blue info toast
 *
 *   // Custom options
 *   showToast('Custom toast', {
 *     type: 'success',
 *     title: 'Custom Title',
 *     duration: 5000,
 *     dismissible: true
 *   })
 */

// Toast type configurations
const TOAST_TYPES = {
  success: {
    icon: 'check-circle',
    bgClass: 'bg-success',
    textClass: 'text-white',
    title: 'Success'
  },
  error: {
    icon: 'alert-circle',
    bgClass: 'bg-danger',
    textClass: 'text-white',
    title: 'Error'
  },
  warning: {
    icon: 'alert-triangle',
    bgClass: 'bg-warning',
    textClass: 'text-dark',
    title: 'Warning'
  },
  info: {
    icon: 'info',
    bgClass: 'bg-primary',
    textClass: 'text-white',
    title: 'Info'
  }
}

// Default options
const DEFAULT_OPTIONS = {
  type: 'info',
  title: null,
  duration: 4000,
  dismissible: true,
  position: 'bottom-end' // bottom-end, top-end, bottom-start, top-start, top-center, bottom-center
}

/**
 * Get or create the toast container element
 */
function getToastContainer(position = 'bottom-end') {
  const positionClasses = {
    'bottom-end': 'bottom-0 end-0',
    'top-end': 'top-0 end-0',
    'bottom-start': 'bottom-0 start-0',
    'top-start': 'top-0 start-0',
    'top-center': 'top-0 start-50 translate-middle-x',
    'bottom-center': 'bottom-0 start-50 translate-middle-x'
  }

  let container = document.getElementById(`toast-container-${position}`)

  if (!container) {
    container = document.createElement('div')
    container.id = `toast-container-${position}`
    container.className = `toast-container position-fixed ${positionClasses[position] || positionClasses['bottom-end']} p-3`
    container.style.zIndex = '1100'
    document.body.appendChild(container)
  }

  return container
}

/**
 * Create a toast element
 */
function createToastElement(message, options) {
  const config = TOAST_TYPES[options.type] || TOAST_TYPES.info
  const title = options.title || config.title

  const toastEl = document.createElement('div')
  toastEl.className = 'toast'
  toastEl.setAttribute('role', 'alert')
  toastEl.setAttribute('aria-live', 'assertive')
  toastEl.setAttribute('aria-atomic', 'true')

  // Build the toast HTML
  toastEl.innerHTML = `
    <div class="toast-header ${config.bgClass} ${config.textClass}">
      <i data-lucide="${config.icon}" class="me-2" style="width: 16px; height: 16px;"></i>
      <strong class="me-auto">${title}</strong>
      ${options.dismissible ? `<button type="button" class="btn-close ${config.textClass === 'text-white' ? 'btn-close-white' : ''}" data-bs-dismiss="toast" aria-label="Close"></button>` : ''}
    </div>
    <div class="toast-body">
      ${message}
    </div>
  `

  return toastEl
}

/**
 * Show a toast notification
 * @param {string} message - The message to display
 * @param {Object} options - Configuration options
 * @returns {Object} - The Bootstrap Toast instance
 */
export function showToast(message, options = {}) {
  const mergedOptions = { ...DEFAULT_OPTIONS, ...options }
  const container = getToastContainer(mergedOptions.position)
  const toastEl = createToastElement(message, mergedOptions)

  container.appendChild(toastEl)

  // Initialize Lucide icons if available
  if (typeof lucide !== 'undefined') {
    lucide.createIcons({ nodes: [toastEl] })
  }

  // Create Bootstrap Toast instance
  const Toast = window.bootstrap?.Toast
  if (!Toast) {
    console.warn('Bootstrap Toast not available — message:', message)
    return null
  }

  const toast = new Toast(toastEl, {
    autohide: mergedOptions.duration > 0,
    delay: mergedOptions.duration
  })

  // Clean up after toast is hidden
  toastEl.addEventListener('hidden.bs.toast', () => {
    toastEl.remove()
  })

  toast.show()
  return toast
}

/**
 * Show a success toast
 * @param {string} message - The message to display
 * @param {Object} options - Additional options
 */
export function showSuccess(message, options = {}) {
  return showToast(message, { ...options, type: 'success' })
}

/**
 * Show an error toast
 * @param {string} message - The message to display
 * @param {Object} options - Additional options
 */
export function showError(message, options = {}) {
  return showToast(message, { ...options, type: 'error' })
}

/**
 * Show a warning toast
 * @param {string} message - The message to display
 * @param {Object} options - Additional options
 */
export function showWarning(message, options = {}) {
  return showToast(message, { ...options, type: 'warning' })
}

/**
 * Show an info toast
 * @param {string} message - The message to display
 * @param {Object} options - Additional options
 */
export function showInfo(message, options = {}) {
  return showToast(message, { ...options, type: 'info' })
}

/**
 * Show a confirmation dialog using a custom modal
 * Returns a Promise that resolves to true if confirmed, false if cancelled
 * @param {string} message - The confirmation message
 * @param {Object} options - Configuration options
 * @returns {Promise<boolean>}
 */
export function showConfirm(message, options = {}) {
  return new Promise((resolve) => {
    const defaults = {
      title: 'Confirm',
      confirmText: 'Confirm',
      cancelText: 'Cancel',
      confirmClass: 'btn-primary',
      dangerous: false
    }
    const opts = { ...defaults, ...options }

    // Use dangerous styling if specified
    if (opts.dangerous) {
      opts.confirmClass = 'btn-danger'
    }

    // Create modal element
    const modalId = `confirm-modal-${Date.now()}`
    const modalEl = document.createElement('div')
    modalEl.className = 'modal fade'
    modalEl.id = modalId
    modalEl.setAttribute('tabindex', '-1')
    modalEl.setAttribute('aria-labelledby', `${modalId}-label`)
    modalEl.setAttribute('aria-hidden', 'true')

    modalEl.innerHTML = `
      <div class="modal-dialog modal-dialog-centered">
        <div class="modal-content">
          <div class="modal-header">
            <h5 class="modal-title" id="${modalId}-label">${opts.title}</h5>
            <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>
          </div>
          <div class="modal-body">
            ${message}
          </div>
          <div class="modal-footer">
            <button type="button" class="btn btn-secondary" data-bs-dismiss="modal">${opts.cancelText}</button>
            <button type="button" class="btn ${opts.confirmClass}" data-action="confirm">${opts.confirmText}</button>
          </div>
        </div>
      </div>
    `

    document.body.appendChild(modalEl)

    const Modal = window.bootstrap?.Modal
    if (!Modal) {
      console.warn('Bootstrap Modal not available — confirm message:', message)
      modalEl.remove()
      resolve(false)
      return
    }

    const modal = new Modal(modalEl)

    // Handle confirm button click
    const confirmBtn = modalEl.querySelector('[data-action="confirm"]')
    confirmBtn.addEventListener('click', () => {
      modal.hide()
      resolve(true)
    })

    // Handle modal close (cancel)
    modalEl.addEventListener('hidden.bs.modal', () => {
      modalEl.remove()
      // Only resolve false if not already resolved by confirm
      resolve(false)
    }, { once: true })

    modal.show()
  })
}

/**
 * Show a prompt dialog using a custom modal
 * Returns a Promise that resolves to the entered string, or null if cancelled
 * @param {string} message - The prompt message
 * @param {Object} options - Configuration options
 * @returns {Promise<string|null>}
 */
export function showPrompt(message, options = {}) {
  return new Promise((resolve) => {
    const defaults = {
      title: 'Input Required',
      confirmText: 'OK',
      cancelText: 'Cancel',
      defaultValue: '',
      placeholder: '',
      inputType: 'text'
    }
    const opts = { ...defaults, ...options }

    const modalId = `prompt-modal-${Date.now()}`
    const modalEl = document.createElement('div')
    modalEl.className = 'modal fade'
    modalEl.id = modalId
    modalEl.setAttribute('tabindex', '-1')
    modalEl.setAttribute('aria-labelledby', `${modalId}-label`)
    modalEl.setAttribute('aria-hidden', 'true')

    modalEl.innerHTML = `
      <div class="modal-dialog modal-dialog-centered">
        <div class="modal-content">
          <div class="modal-header">
            <h5 class="modal-title" id="${modalId}-label">${opts.title}</h5>
            <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>
          </div>
          <div class="modal-body">
            <p class="mb-3">${message}</p>
            <input type="${opts.inputType}" class="form-control" id="${modalId}-input"
                   value="${opts.defaultValue}" placeholder="${opts.placeholder}" autofocus />
          </div>
          <div class="modal-footer">
            <button type="button" class="btn btn-secondary" data-bs-dismiss="modal">${opts.cancelText}</button>
            <button type="button" class="btn btn-primary" data-action="confirm">${opts.confirmText}</button>
          </div>
        </div>
      </div>
    `

    document.body.appendChild(modalEl)

    const Modal = window.bootstrap?.Modal
    if (!Modal) {
      console.warn('Bootstrap Modal not available — prompt message:', message)
      modalEl.remove()
      resolve(null)
      return
    }

    const modal = new Modal(modalEl)
    const input = modalEl.querySelector(`#${modalId}-input`)
    let resolved = false

    // Handle confirm
    const confirmBtn = modalEl.querySelector('[data-action="confirm"]')
    confirmBtn.addEventListener('click', () => {
      resolved = true
      modal.hide()
      resolve(input.value)
    })

    // Handle Enter key in input
    input.addEventListener('keydown', (e) => {
      if (e.key === 'Enter') {
        e.preventDefault()
        resolved = true
        modal.hide()
        resolve(input.value)
      }
    })

    // Handle modal close (cancel)
    modalEl.addEventListener('hidden.bs.modal', () => {
      modalEl.remove()
      if (!resolved) resolve(null)
    }, { once: true })

    // Focus input after modal is shown
    modalEl.addEventListener('shown.bs.modal', () => {
      input.focus()
      input.select()
    }, { once: true })

    modal.show()
  })
}

// Make functions globally available for inline scripts and non-module contexts
if (typeof window !== 'undefined') {
  window.showToast = showToast
  window.showSuccess = showSuccess
  window.showError = showError
  window.showWarning = showWarning
  window.showInfo = showInfo
  window.showConfirm = showConfirm
  window.showPrompt = showPrompt
}
