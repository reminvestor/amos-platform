import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="qr-code"
// Usage:
//   <div data-controller="qr-code" data-qr-code-text-value="URL to encode">
//     <canvas data-qr-code-target="canvas"></canvas>
//     <button data-action="qr-code#generate">Generate QR Code</button>
//     <button data-action="qr-code#download">Download QR Code</button>
//   </div>
//
// Note: This controller uses the qrcode library. Include it via CDN:
// <script src="https://cdn.jsdelivr.net/npm/qrcode@1.5.3/build/qrcode.min.js"></script>
export default class extends Controller {
  static values = {
    text: String,
    size: { type: Number, default: 256 },
    color: { type: String, default: "#000000" },
    background: { type: String, default: "#ffffff" }
  }

  static targets = ["canvas", "container", "image"]

  connect() {
    // Auto-generate if text is provided
    if (this.hasTextValue && this.textValue) {
      this.generate()
    }
  }

  textValueChanged() {
    if (this.textValue) {
      this.generate()
    }
  }

  generate(event) {
    if (event) {
      event.preventDefault()
    }

    const text = this.textValue

    if (!text) {
      console.error("No text provided for QR code generation")
      return
    }

    // Check if QRCode library is available
    if (typeof QRCode === 'undefined') {
      console.error("QRCode library not loaded. Please include qrcode.min.js")
      this.showError("QR Code library not loaded")
      return
    }

    // Use canvas target if available, otherwise create one
    const canvas = this.hasCanvasTarget ? this.canvasTarget : this.createCanvas()

    const options = {
      width: this.sizeValue,
      height: this.sizeValue,
      color: {
        dark: this.colorValue,
        light: this.backgroundValue
      }
    }

    QRCode.toCanvas(canvas, text, options, (error) => {
      if (error) {
        console.error("QR Code generation error:", error)
        this.showError("Failed to generate QR code")
      } else {
        this.showSuccess()

        // If using image target, convert canvas to image
        if (this.hasImageTarget) {
          this.imageTarget.src = canvas.toDataURL()
        }
      }
    })
  }

  download(event) {
    event.preventDefault()

    if (!this.hasCanvasTarget) {
      console.error("No canvas found to download")
      return
    }

    const canvas = this.canvasTarget
    const link = document.createElement('a')
    const filename = this.data.get("filename") || 'qr-code.png'

    link.download = filename
    link.href = canvas.toDataURL('image/png')
    link.click()
  }

  createCanvas() {
    const canvas = document.createElement('canvas')

    if (this.hasContainerTarget) {
      this.containerTarget.appendChild(canvas)
    } else {
      this.element.appendChild(canvas)
    }

    return canvas
  }

  showSuccess() {
    // Dispatch custom event for success
    this.dispatch("generated", { detail: { text: this.textValue } })
  }

  showError(message) {
    // Dispatch custom event for error
    this.dispatch("error", { detail: { message: message } })

    // Show error in container if available
    if (this.hasContainerTarget) {
      this.containerTarget.innerHTML = `
        <div class="alert alert-danger" role="alert">
          <i class="bi bi-exclamation-triangle me-2"></i>${message}
        </div>
      `
    }
  }

  toggle(event) {
    event.preventDefault()

    if (this.hasContainerTarget) {
      this.containerTarget.classList.toggle('d-none')

      // Generate if showing for first time
      if (!this.containerTarget.classList.contains('d-none') && !this.hasCanvasTarget) {
        this.generate()
      }
    }
  }
}
