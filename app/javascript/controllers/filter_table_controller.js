import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="filter-table"
// Usage:
//   <div data-controller="filter-table">
//     <input type="text" data-filter-table-target="searchInput" data-action="input->filter-table#filter">
//     <select data-filter-table-target="statusFilter" data-action="change->filter-table#filter">
//     <table>
//       <tbody data-filter-table-target="tableBody">
//         <tr data-filter-table-target="row" data-status="active" data-keywords="john doe admin">
//           <td>John Doe</td>
//           <td>Active</td>
//         </tr>
//       </tbody>
//     </table>
//     <button data-action="filter-table#clearFilters">Clear Filters</button>
//   </div>
export default class extends Controller {
  static targets = ["row", "searchInput", "statusFilter", "dateFromFilter", "dateToFilter", "noResults", "resultCount"]

  connect() {
    this.updateResultCount()
  }

  filter() {
    const searchTerm = this.hasSearchInputTarget
      ? this.searchInputTarget.value.toLowerCase()
      : ""

    const statusFilter = this.hasStatusFilterTarget
      ? this.statusFilterTarget.value
      : ""

    const dateFrom = this.hasDateFromFilterTarget
      ? this.dateFromFilterTarget.value
      : ""

    const dateTo = this.hasDateToFilterTarget
      ? this.dateToFilterTarget.value
      : ""

    let visibleCount = 0

    this.rowTargets.forEach(row => {
      const matchesSearch = this.matchesSearchTerm(row, searchTerm)
      const matchesStatus = this.matchesStatus(row, statusFilter)
      const matchesDateRange = this.matchesDateRange(row, dateFrom, dateTo)

      const isVisible = matchesSearch && matchesStatus && matchesDateRange

      if (isVisible) {
        row.style.display = ""
        visibleCount++
      } else {
        row.style.display = "none"
      }
    })

    this.updateResultCount(visibleCount)
    this.toggleNoResults(visibleCount === 0)
  }

  matchesSearchTerm(row, searchTerm) {
    if (!searchTerm) return true

    // Check data-keywords attribute first
    const keywords = row.dataset.keywords
    if (keywords) {
      return keywords.toLowerCase().includes(searchTerm)
    }

    // Otherwise search in text content
    const text = row.textContent.toLowerCase()
    return text.includes(searchTerm)
  }

  matchesStatus(row, statusFilter) {
    if (!statusFilter) return true

    const rowStatus = row.dataset.status
    return rowStatus === statusFilter
  }

  matchesDateRange(row, dateFrom, dateTo) {
    if (!dateFrom && !dateTo) return true

    const rowDate = row.dataset.date
    if (!rowDate) return true

    const date = new Date(rowDate)

    if (dateFrom) {
      const fromDate = new Date(dateFrom)
      if (date < fromDate) return false
    }

    if (dateTo) {
      const toDate = new Date(dateTo)
      toDate.setHours(23, 59, 59, 999) // Include the entire day
      if (date > toDate) return false
    }

    return true
  }

  clearFilters(event) {
    event.preventDefault()

    // Clear all filter inputs
    if (this.hasSearchInputTarget) {
      this.searchInputTarget.value = ""
    }

    if (this.hasStatusFilterTarget) {
      this.statusFilterTarget.value = ""
    }

    if (this.hasDateFromFilterTarget) {
      this.dateFromFilterTarget.value = ""
    }

    if (this.hasDateToFilterTarget) {
      this.dateToFilterTarget.value = ""
    }

    // Show all rows
    this.rowTargets.forEach(row => {
      row.style.display = ""
    })

    this.updateResultCount(this.rowTargets.length)
    this.toggleNoResults(false)
  }

  updateResultCount(count = null) {
    if (!this.hasResultCountTarget) return

    const visibleCount = count !== null ? count : this.visibleRowCount

    this.resultCountTarget.textContent = visibleCount
  }

  toggleNoResults(show) {
    if (!this.hasNoResultsTarget) return

    if (show) {
      this.noResultsTarget.style.display = ""
    } else {
      this.noResultsTarget.style.display = "none"
    }
  }

  get visibleRowCount() {
    return this.rowTargets.filter(row => row.style.display !== "none").length
  }
}
