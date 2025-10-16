import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="affiliate-chart"
// Usage:
//   <canvas data-controller="affiliate-chart"
//           data-affiliate-chart-type-value="line"
//           data-affiliate-chart-labels-value='["Jan", "Feb", "Mar"]'
//           data-affiliate-chart-data-value='[10, 20, 30]'
//           data-affiliate-chart-label-value="Clicks"></canvas>
//
// Note: Requires Chart.js library
export default class extends Controller {
  static values = {
    type: { type: String, default: "line" },
    labels: Array,
    data: Array,
    datasets: Array,
    label: { type: String, default: "Data" },
    options: { type: Object, default: {} }
  }

  connect() {
    // Check if Chart.js is loaded
    if (typeof Chart === 'undefined') {
      console.error("Chart.js library not loaded")
      return
    }

    this.renderChart()
  }

  disconnect() {
    if (this.chart) {
      this.chart.destroy()
    }
  }

  renderChart() {
    const ctx = this.element.getContext('2d')

    // Prepare datasets
    const datasets = this.hasDatasetsValue
      ? this.datasetsValue
      : [this.createDefaultDataset()]

    const config = {
      type: this.typeValue,
      data: {
        labels: this.labelsValue,
        datasets: datasets
      },
      options: this.getChartOptions()
    }

    this.chart = new Chart(ctx, config)
  }

  createDefaultDataset() {
    const colors = this.getColorScheme()

    return {
      label: this.labelValue,
      data: this.dataValue,
      backgroundColor: colors.background,
      borderColor: colors.border,
      borderWidth: 2,
      tension: 0.4,
      fill: this.typeValue === 'line'
    }
  }

  getChartOptions() {
    // Merge default options with custom options
    const defaultOptions = {
      responsive: true,
      maintainAspectRatio: true,
      plugins: {
        legend: {
          display: this.typeValue !== 'line',
          position: 'bottom'
        },
        tooltip: {
          mode: 'index',
          intersect: false
        }
      },
      scales: this.getScaleOptions()
    }

    return this.deepMerge(defaultOptions, this.optionsValue)
  }

  getScaleOptions() {
    if (this.typeValue === 'pie' || this.typeValue === 'doughnut') {
      return {}
    }

    return {
      y: {
        beginAtZero: true,
        ticks: {
          precision: 0
        }
      },
      x: {
        grid: {
          display: false
        }
      }
    }
  }

  getColorScheme() {
    const type = this.typeValue

    switch (type) {
      case 'line':
        return {
          border: '#0d6efd',
          background: 'rgba(13, 110, 253, 0.1)'
        }
      case 'bar':
        return {
          border: '#198754',
          background: 'rgba(25, 135, 84, 0.8)'
        }
      case 'pie':
      case 'doughnut':
        return {
          background: [
            'rgba(13, 110, 253, 0.8)',
            'rgba(25, 135, 84, 0.8)',
            'rgba(255, 193, 7, 0.8)',
            'rgba(220, 53, 69, 0.8)',
            'rgba(13, 202, 240, 0.8)'
          ],
          border: [
            '#0d6efd',
            '#198754',
            '#ffc107',
            '#dc3545',
            '#0dcaf0'
          ]
        }
      default:
        return {
          border: '#6c757d',
          background: 'rgba(108, 117, 125, 0.1)'
        }
    }
  }

  updateChart(newData, newLabels = null) {
    if (!this.chart) return

    if (newLabels) {
      this.chart.data.labels = newLabels
    }

    if (this.chart.data.datasets.length > 0) {
      this.chart.data.datasets[0].data = newData
    }

    this.chart.update()
  }

  deepMerge(target, source) {
    const output = Object.assign({}, target)
    if (this.isObject(target) && this.isObject(source)) {
      Object.keys(source).forEach(key => {
        if (this.isObject(source[key])) {
          if (!(key in target))
            Object.assign(output, { [key]: source[key] })
          else
            output[key] = this.deepMerge(target[key], source[key])
        } else {
          Object.assign(output, { [key]: source[key] })
        }
      })
    }
    return output
  }

  isObject(item) {
    return item && typeof item === 'object' && !Array.isArray(item)
  }
}
