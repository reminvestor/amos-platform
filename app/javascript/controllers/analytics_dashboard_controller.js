import { Controller } from "@hotwired/stimulus"
import Chart from 'chart.js/auto'

export default class extends Controller {
  static targets = [
    "connectionStatus",
    "campaignsActive", "emailsSentToday", "opensLastHour", "clicksLastHour",
    "landingPageVisits", "landingPageConversions", "conversionRate",
    "totalContacts", "activeContacts",
    "engagementChart", "heatmapChart",
    "activityFeed", "topPerformers",
    "lastUpdate"
  ]

  connect() {
    console.log("Analytics dashboard connected")
    this.initCharts()
    this.startSSE()
    this.loadActivityFeed()
    this.loadTopPerformers()
    this.loadHeatmap()
  }

  disconnect() {
    this.stopSSE()
    if (this.engagementChart) this.engagementChart.destroy()
    if (this.heatmapChart) this.heatmapChart.destroy()
  }

  initCharts() {
    // Engagement Chart (Line chart for real-time data)
    const engagementCtx = this.engagementChartTarget.getContext('2d')
    this.engagementChart = new Chart(engagementCtx, {
      type: 'line',
      data: {
        labels: [],
        datasets: [
          {
            label: 'Opens',
            data: [],
            borderColor: 'rgb(75, 192, 192)',
            backgroundColor: 'rgba(75, 192, 192, 0.1)',
            tension: 0.4
          },
          {
            label: 'Clicks',
            data: [],
            borderColor: 'rgb(255, 159, 64)',
            backgroundColor: 'rgba(255, 159, 64, 0.1)',
            tension: 0.4
          }
        ]
      },
      options: {
        responsive: true,
        maintainAspectRatio: true,
        animation: { duration: 500 },
        scales: {
          y: { beginAtZero: true }
        },
        plugins: {
          legend: { position: 'top' },
          title: {
            display: true,
            text: 'Real-Time Engagement'
          }
        }
      }
    })
  }

  startSSE() {
    console.log("Starting SSE connection...")
    this.eventSource = new EventSource('/analytics/stream')

    this.eventSource.addEventListener('metrics_update', (e) => {
      const metrics = JSON.parse(e.data)
      console.log("Received metrics:", metrics)
      this.updateMetrics(metrics)
      this.updateChart(metrics)
    })

    this.eventSource.onopen = () => {
      console.log("SSE connected")
      this.connectionStatusTarget.innerHTML = '<span class="text-success">●</span> Connected'
      this.connectionStatusTarget.classList.remove('bg-warning')
      this.connectionStatusTarget.classList.add('bg-success')
    }

    this.eventSource.onerror = (e) => {
      console.error("SSE error:", e)
      this.connectionStatusTarget.innerHTML = '<span class="text-danger">●</span> Disconnected'
      this.connectionStatusTarget.classList.remove('bg-success')
      this.connectionStatusTarget.classList.add('bg-danger')

      // Reconnect after 5 seconds
      setTimeout(() => {
        if (this.eventSource.readyState === EventSource.CLOSED) {
          console.log("Reconnecting...")
          this.startSSE()
        }
      }, 5000)
    }
  }

  stopSSE() {
    if (this.eventSource) {
      this.eventSource.close()
    }
  }

  updateMetrics(metrics) {
    // Update metric cards
    if (this.hasCampaignsActiveTarget) {
      this.campaignsActiveTarget.textContent = metrics.campaigns_active
    }
    if (this.hasEmailsSentTodayTarget) {
      this.emailsSentTodayTarget.textContent = this.formatNumber(metrics.emails_sent_today)
    }
    if (this.hasOpensLastHourTarget) {
      this.opensLastHourTarget.textContent = metrics.opens_last_hour
    }
    if (this.hasClicksLastHourTarget) {
      this.clicksLastHourTarget.textContent = metrics.clicks_last_hour
    }
    if (this.hasLandingPageVisitsTarget) {
      this.landingPageVisitsTarget.textContent = metrics.landing_page_visits_today
    }
    if (this.hasLandingPageConversionsTarget) {
      this.landingPageConversionsTarget.textContent = metrics.landing_page_conversions_today
    }
    if (this.hasConversionRateTarget) {
      this.conversionRateTarget.textContent = metrics.conversion_rate_today + '%'
    }
    if (this.hasTotalContactsTarget) {
      this.totalContactsTarget.textContent = this.formatNumber(metrics.total_contacts)
    }
    if (this.hasActiveContactsTarget) {
      this.activeContactsTarget.textContent = this.formatNumber(metrics.active_contacts)
    }

    // Update timestamp
    if (this.hasLastUpdateTarget) {
      this.lastUpdateTarget.textContent = new Date(metrics.timestamp).toLocaleTimeString()
    }
  }

  updateChart(metrics) {
    const now = new Date().toLocaleTimeString()

    // Add new data point
    this.engagementChart.data.labels.push(now)
    this.engagementChart.data.datasets[0].data.push(metrics.opens_last_hour)
    this.engagementChart.data.datasets[1].data.push(metrics.clicks_last_hour)

    // Keep last 20 data points
    if (this.engagementChart.data.labels.length > 20) {
      this.engagementChart.data.labels.shift()
      this.engagementChart.data.datasets[0].data.shift()
      this.engagementChart.data.datasets[1].data.shift()
    }

    this.engagementChart.update()
  }

  async loadActivityFeed() {
    try {
      const response = await fetch('/analytics/activity_feed')
      const activities = await response.json()

      if (activities.length === 0) {
        this.activityFeedTarget.innerHTML = `
          <div class="list-group-item text-center text-muted">
            <small>No recent activity</small>
          </div>
        `
        return
      }

      this.activityFeedTarget.innerHTML = activities.map(activity => `
        <div class="list-group-item">
          <div class="d-flex w-100 justify-content-between">
            <small class="mb-1">${activity.icon} ${activity.description}</small>
            <small class="text-muted">${activity.relative_time}</small>
          </div>
        </div>
      `).join('')

      // Refresh every 30 seconds
      setTimeout(() => this.loadActivityFeed(), 30000)
    } catch (error) {
      console.error("Failed to load activity feed:", error)
    }
  }

  async loadTopPerformers() {
    try {
      const response = await fetch('/analytics/top_performers?metric=open_rate&limit=5')
      const performers = await response.json()

      if (performers.length === 0) {
        this.topPerformersTarget.innerHTML = `
          <div class="list-group-item text-center text-muted">
            <small>No data yet</small>
          </div>
        `
        return
      }

      this.topPerformersTarget.innerHTML = performers.map((item, index) => `
        <div class="list-group-item">
          <div class="d-flex w-100 justify-content-between">
            <span class="mb-1">
              <strong>${index + 1}.</strong> ${item.name}
            </span>
            <span class="badge bg-primary">${item.value_formatted}</span>
          </div>
          <small class="text-muted">${item.total_sent || item.total_visits || 0} sent</small>
        </div>
      `).join('')
    } catch (error) {
      console.error("Failed to load top performers:", error)
    }
  }

  async loadHeatmap() {
    try {
      const response = await fetch('/analytics/engagement_heatmap?days=7')
      const heatmapData = await response.json()

      const ctx = this.heatmapChartTarget.getContext('2d')
      this.heatmapChart = new Chart(ctx, {
        type: 'bar',
        data: {
          labels: heatmapData.hourly_data.map(h => h.hour_label),
          datasets: [{
            label: 'Total Engagement',
            data: heatmapData.hourly_data.map(h => h.total_engagement),
            backgroundColor: heatmapData.hourly_data.map(h => {
              const intensity = h.total_engagement / Math.max(...heatmapData.hourly_data.map(d => d.total_engagement))
              return `rgba(75, 192, 192, ${intensity})`
            })
          }]
        },
        options: {
          responsive: true,
          maintainAspectRatio: true,
          scales: {
            y: { beginAtZero: true }
          },
          plugins: {
            legend: { display: false },
            title: {
              display: true,
              text: `Peak hour: ${heatmapData.hourly_data[heatmapData.peak_hour].hour_label}`
            }
          }
        }
      })
    } catch (error) {
      console.error("Failed to load heatmap:", error)
    }
  }

  formatNumber(num) {
    return num.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ",")
  }
}
