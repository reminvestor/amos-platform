// Lazy-loaded QRCode module
// Only include this script on pages that generate QR codes
import QRCode from 'qrcode'
window.QRCode = QRCode

console.log('📱 QRCode library loaded')
