import { Controller } from "@hotwired/stimulus"

/**
 * Template Gallery Controller
 *
 * Handles browsing, filtering, and starting workflow templates
 * from the Template Gallery canvas.
 */
export default class extends Controller {
  static targets = ["searchInput", "categoryFilter", "industryFilter", "grid", "card", "resultCount"]

  connect() {
  }

  /**
   * Client-side filter: hides/shows cards based on search text,
   * category dropdown, and industry dropdown.
   */
  filterTemplates() {
    const query = (this.searchInputTarget?.value || "").toLowerCase().trim()
    const selectedCategory = this.categoryFilterTarget?.value || ""
    const selectedIndustry = this.hasIndustryFilterTarget ? (this.industryFilterTarget?.value || "") : ""

    let visibleCount = 0

    this.cardTargets.forEach(card => {
      const name = (card.dataset.name || "").toLowerCase()
      const description = (card.dataset.description || "").toLowerCase()
      const category = card.dataset.category || ""
      const industry = card.dataset.industry || ""
      const tags = (card.dataset.tags || "").toLowerCase()

      let show = true

      // Text search: match against name, description, or tags
      if (query) {
        const matchesSearch = name.includes(query) ||
                              description.includes(query) ||
                              tags.includes(query)
        if (!matchesSearch) show = false
      }

      // Category filter
      if (selectedCategory && category !== selectedCategory) {
        show = false
      }

      // Industry filter
      if (selectedIndustry && industry !== selectedIndustry) {
        show = false
      }

      card.classList.toggle("hidden", !show)
      if (show) visibleCount++
    })

    // Update result count
    if (this.hasResultCountTarget) {
      this.resultCountTarget.textContent = `${visibleCount} template${visibleCount === 1 ? "" : "s"}`
    }
  }

  /**
   * Start a workflow by sending a chat message to Scout.
   * The message triggers the planner to match the template by name.
   */
  startWorkflow(event) {
    const slug = event.params.slug
    const name = event.params.name

    if (!name) {
      console.warn("Template Gallery: No template name provided for startWorkflow")
      return
    }

    const message = `Run the "${name}" workflow`

    // Use the global scoutSendMessage function (defined in scout_controller.js)
    if (typeof window.scoutSendMessage === "function") {
      window.scoutSendMessage(message)
    } else {
      // Fallback: dispatch a custom event that scout_controller listens for
      window.dispatchEvent(new CustomEvent("scout:send-message", {
        detail: { message: message }
      }))
    }
  }
}
