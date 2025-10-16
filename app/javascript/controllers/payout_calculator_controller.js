import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="payout-calculator"
// Usage:
//   <div data-controller="payout-calculator">
//     <input type="checkbox" data-payout-calculator-target="checkbox"
//            data-action="change->payout-calculator#calculate"
//            data-amount="150.50">
//     <span data-payout-calculator-target="total">$0.00</span>
//     <span data-payout-calculator-target="count">0</span>
//   </div>
export default class extends Controller {
  static targets = ["checkbox", "total", "count", "selectedItems"]

  connect() {
    this.calculate()
  }

  calculate() {
    let totalAmount = 0
    let selectedCount = 0

    this.checkboxTargets.forEach(checkbox => {
      if (checkbox.checked && !checkbox.disabled) {
        selectedCount++

        // Get amount from data attribute or closest row
        const amount = this.getAmountForCheckbox(checkbox)
        if (amount) {
          totalAmount += amount
        }
      }
    })

    this.updateDisplay(totalAmount, selectedCount)
  }

  getAmountForCheckbox(checkbox) {
    // Try to get amount from data attribute
    if (checkbox.dataset.amount) {
      return parseFloat(checkbox.dataset.amount)
    }

    // Try to find amount in the same row
    const row = checkbox.closest('tr')
    if (row) {
      const amountCell = row.querySelector('[data-amount]')
      if (amountCell) {
        return parseFloat(amountCell.dataset.amount)
      }

      // Try to parse from .payout-amount or .amount cell
      const amountElement = row.querySelector('.payout-amount, .amount')
      if (amountElement) {
        const text = amountElement.textContent.trim()
        const numberMatch = text.match(/[\d,]+\.?\d*/);
        if (numberMatch) {
          return parseFloat(numberMatch[0].replace(/,/g, ''))
        }
      }
    }

    return 0
  }

  updateDisplay(totalAmount, selectedCount) {
    // Update total display
    this.totalTargets.forEach(target => {
      target.textContent = this.formatCurrency(totalAmount)
    })

    // Update count display
    this.countTargets.forEach(target => {
      target.textContent = selectedCount
    })

    // Update selected items list if exists
    if (this.hasSelectedItemsTarget) {
      this.updateSelectedItemsList()
    }

    // Dispatch custom event
    this.dispatch("calculated", {
      detail: {
        total: totalAmount,
        count: selectedCount
      }
    })
  }

  updateSelectedItemsList() {
    const selectedItems = []

    this.checkboxTargets.forEach(checkbox => {
      if (checkbox.checked && !checkbox.disabled) {
        const row = checkbox.closest('tr')
        if (row) {
          const name = row.querySelector('[data-name]')?.textContent.trim() ||
                      row.cells[1]?.textContent.trim() ||
                      'Unknown'
          const amount = this.getAmountForCheckbox(checkbox)

          selectedItems.push({ name, amount })
        }
      }
    })

    // Update the selected items display
    if (selectedItems.length > 0) {
      const html = selectedItems.map(item =>
        `<div>${item.name}: ${this.formatCurrency(item.amount)}</div>`
      ).join('')
      this.selectedItemsTarget.innerHTML = html
    } else {
      this.selectedItemsTarget.innerHTML = '<em class="text-muted">No items selected</em>'
    }
  }

  formatCurrency(amount) {
    return '$' + amount.toLocaleString('en-US', {
      minimumFractionDigits: 2,
      maximumFractionDigits: 2
    })
  }

  selectAll(event) {
    event.preventDefault()

    this.checkboxTargets.forEach(checkbox => {
      if (!checkbox.disabled) {
        checkbox.checked = true
      }
    })

    this.calculate()
  }

  deselectAll(event) {
    event.preventDefault()

    this.checkboxTargets.forEach(checkbox => {
      checkbox.checked = false
    })

    this.calculate()
  }

  toggleAboveThreshold(event) {
    event.preventDefault()

    const threshold = parseFloat(event.currentTarget.dataset.threshold || 0)

    this.checkboxTargets.forEach(checkbox => {
      const amount = this.getAmountForCheckbox(checkbox)
      checkbox.checked = amount >= threshold
    })

    this.calculate()
  }
}
