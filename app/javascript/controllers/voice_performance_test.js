/**
 * Voice Assistant Performance Testing Suite
 *
 * Usage in browser console:
 * 1. Open Scout page
 * 2. Paste this file's content
 * 3. Run: await VoicePerformanceTest.runFullTest()
 * 4. View detailed timing breakdown
 */

class VoicePerformanceTest {
  constructor() {
    this.results = []
    this.metrics = {}
  }

  /**
   * Run comprehensive performance test
   */
  static async runFullTest() {
    const tester = new VoicePerformanceTest()

    console.log("🧪 =====================================")
    console.log("🧪 VOICE ASSISTANT PERFORMANCE TEST")
    console.log("🧪 =====================================")
    console.log("")

    // Test 1: Measure each initialization step
    await tester.testInitializationSteps()

    // Test 2: Test parallel vs sequential API calls
    await tester.testParallelVsSequential()

    // Test 3: Test microphone initialization alone
    await tester.testMicrophoneOnly()

    // Test 4: Test connection pooling/caching opportunities
    await tester.testConnectionCaching()

    // Display results
    tester.displayResults()

    return tester
  }

  /**
   * Test 1: Measure each initialization step individually
   */
  async testInitializationSteps() {
    console.log("📊 Test 1: Individual Step Timing")
    console.log("─".repeat(50))

    const steps = []

    try {
      // Step 1: Microphone access
      let start = performance.now()
      const stream = await navigator.mediaDevices.getUserMedia({
        audio: {
          sampleRate: 48000,
          channelCount: 1,
          echoCancellation: true,
          noiseSuppression: true,
          autoGainControl: true
        }
      })
      let duration = performance.now() - start
      steps.push({ name: "Microphone Access", duration })
      console.log(`  ✓ Microphone Access: ${duration.toFixed(0)}ms`)

      // Clean up
      stream.getTracks().forEach(track => track.stop())

      // Step 2: Create voice session
      start = performance.now()
      const sessionResponse = await fetch("/api/voice/sessions", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content
        }
      })
      const session = await sessionResponse.json()
      duration = performance.now() - start
      steps.push({ name: "Create Session API", duration })
      console.log(`  ✓ Create Session: ${duration.toFixed(0)}ms`)

      const sessionId = session.session_id

      // Step 3: Get Deepgram credentials
      start = performance.now()
      await fetch(`/api/voice/sessions/${sessionId}/deepgram_key`)
      duration = performance.now() - start
      steps.push({ name: "Get Deepgram Credentials", duration })
      console.log(`  ✓ Get Deepgram Creds: ${duration.toFixed(0)}ms`)

      // Step 4: Get Polly credentials
      start = performance.now()
      await fetch(`/api/voice/sessions/${sessionId}/polly_credentials`)
      duration = performance.now() - start
      steps.push({ name: "Get Polly Credentials", duration })
      console.log(`  ✓ Get Polly Creds: ${duration.toFixed(0)}ms`)

      // Step 5: Action Cable connection (simulate)
      start = performance.now()
      // We'll measure this separately since it requires actual cable setup
      // For now, estimate based on WebSocket handshake
      duration = 200 // Typical WebSocket handshake time
      steps.push({ name: "Action Cable Connect (estimated)", duration })
      console.log(`  ⚠ Action Cable: ~${duration}ms (estimated)`)

      // Clean up session
      await fetch(`/api/voice/sessions/${sessionId}`, {
        method: "DELETE",
        headers: {
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content
        }
      })

      const totalSequential = steps.reduce((sum, step) => sum + step.duration, 0)
      console.log(`  ─────────────────────────────────`)
      console.log(`  📊 Total Sequential: ${totalSequential.toFixed(0)}ms`)
      console.log("")

      this.results.push({
        test: "Individual Steps",
        steps,
        totalSequential
      })

    } catch (error) {
      console.error("❌ Test 1 failed:", error)
      this.results.push({
        test: "Individual Steps",
        error: error.message
      })
    }
  }

  /**
   * Test 2: Compare parallel vs sequential API calls
   */
  async testParallelVsSequential() {
    console.log("📊 Test 2: Parallel vs Sequential API Calls")
    console.log("─".repeat(50))

    try {
      // Create session first
      const sessionResponse = await fetch("/api/voice/sessions", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content
        }
      })
      const session = await sessionResponse.json()
      const sessionId = session.session_id

      // Sequential test
      let start = performance.now()
      await fetch(`/api/voice/sessions/${sessionId}/deepgram_key`)
      await fetch(`/api/voice/sessions/${sessionId}/polly_credentials`)
      const sequentialTime = performance.now() - start
      console.log(`  Sequential: ${sequentialTime.toFixed(0)}ms`)

      // Create new session for parallel test
      const session2Response = await fetch("/api/voice/sessions", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content
        }
      })
      const session2 = await session2Response.json()
      const sessionId2 = session2.session_id

      // Parallel test
      start = performance.now()
      await Promise.all([
        fetch(`/api/voice/sessions/${sessionId2}/deepgram_key`),
        fetch(`/api/voice/sessions/${sessionId2}/polly_credentials`)
      ])
      const parallelTime = performance.now() - start
      console.log(`  Parallel: ${parallelTime.toFixed(0)}ms`)

      const improvement = ((sequentialTime - parallelTime) / sequentialTime * 100).toFixed(1)
      console.log(`  ✅ Improvement: ${improvement}% faster`)
      console.log("")

      // Clean up
      await fetch(`/api/voice/sessions/${sessionId}`, { method: "DELETE", headers: { "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content }})
      await fetch(`/api/voice/sessions/${sessionId2}`, { method: "DELETE", headers: { "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content }})

      this.results.push({
        test: "Parallel vs Sequential",
        sequentialTime,
        parallelTime,
        improvement: `${improvement}%`
      })

    } catch (error) {
      console.error("❌ Test 2 failed:", error)
      this.results.push({
        test: "Parallel vs Sequential",
        error: error.message
      })
    }
  }

  /**
   * Test 3: Microphone initialization alone
   */
  async testMicrophoneOnly() {
    console.log("📊 Test 3: Microphone Initialization")
    console.log("─".repeat(50))

    const runs = 3
    const times = []

    try {
      for (let i = 0; i < runs; i++) {
        const start = performance.now()
        const stream = await navigator.mediaDevices.getUserMedia({
          audio: {
            sampleRate: 48000,
            channelCount: 1,
            echoCancellation: true,
            noiseSuppression: true,
            autoGainControl: true
          }
        })
        const duration = performance.now() - start
        times.push(duration)
        console.log(`  Run ${i + 1}: ${duration.toFixed(0)}ms`)

        stream.getTracks().forEach(track => track.stop())

        // Small delay between runs
        await new Promise(resolve => setTimeout(resolve, 100))
      }

      const avgTime = times.reduce((sum, t) => sum + t, 0) / times.length
      const minTime = Math.min(...times)
      const maxTime = Math.max(...times)

      console.log(`  ─────────────────────────────────`)
      console.log(`  Average: ${avgTime.toFixed(0)}ms`)
      console.log(`  Min: ${minTime.toFixed(0)}ms`)
      console.log(`  Max: ${maxTime.toFixed(0)}ms`)
      console.log("")

      this.results.push({
        test: "Microphone Initialization",
        times,
        avgTime,
        minTime,
        maxTime
      })

    } catch (error) {
      console.error("❌ Test 3 failed:", error)
      this.results.push({
        test: "Microphone Initialization",
        error: error.message
      })
    }
  }

  /**
   * Test 4: Test connection caching/preloading opportunities
   */
  async testConnectionCaching() {
    console.log("📊 Test 4: Connection Caching Opportunities")
    console.log("─".repeat(50))

    try {
      // Test: Pre-create session on page load
      console.log("  Testing session pre-creation...")
      const start1 = performance.now()
      const sessionResponse = await fetch("/api/voice/sessions", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content
        }
      })
      const session = await sessionResponse.json()
      const sessionCreateTime = performance.now() - start1
      console.log(`    Session creation: ${sessionCreateTime.toFixed(0)}ms`)

      // Test: Pre-fetch credentials
      const start2 = performance.now()
      const [deepgramResp, pollyResp] = await Promise.all([
        fetch(`/api/voice/sessions/${session.session_id}/deepgram_key`),
        fetch(`/api/voice/sessions/${session.session_id}/polly_credentials`)
      ])
      const credsTime = performance.now() - start2
      console.log(`    Credentials fetch: ${credsTime.toFixed(0)}ms`)

      // Parse responses
      const deepgramCreds = await deepgramResp.json()
      const pollyCreds = await pollyResp.json()

      console.log("")
      console.log("  💡 OPTIMIZATION OPPORTUNITY:")
      console.log(`    If we pre-create session + fetch creds on page load,`)
      console.log(`    we save ${(sessionCreateTime + credsTime).toFixed(0)}ms from button click time!`)
      console.log(`    User would only wait for: Microphone (~300ms) + Deepgram WS (~200ms)`)
      console.log(`    = Total ~500ms instead of ~1250ms`)
      console.log("")

      // Clean up
      await fetch(`/api/voice/sessions/${session.session_id}`, {
        method: "DELETE",
        headers: { "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content }
      })

      this.results.push({
        test: "Connection Caching",
        sessionCreateTime,
        credsTime,
        potentialSavings: sessionCreateTime + credsTime,
        recommendation: "Pre-create session and fetch credentials on page load"
      })

    } catch (error) {
      console.error("❌ Test 4 failed:", error)
      this.results.push({
        test: "Connection Caching",
        error: error.message
      })
    }
  }

  /**
   * Display comprehensive results
   */
  displayResults() {
    console.log("")
    console.log("🎯 =====================================")
    console.log("🎯 PERFORMANCE TEST SUMMARY")
    console.log("🎯 =====================================")
    console.log("")

    // Calculate current total time
    const currentSteps = this.results.find(r => r.test === "Individual Steps")
    if (currentSteps && currentSteps.totalSequential) {
      console.log(`📊 Current Total Time: ${currentSteps.totalSequential.toFixed(0)}ms`)
    }

    // Show optimization opportunity
    const caching = this.results.find(r => r.test === "Connection Caching")
    if (caching && caching.potentialSavings) {
      console.log(`💡 Potential Optimized Time: ~500ms`)
      console.log(`✨ Possible Improvement: ${((caching.potentialSavings / currentSteps.totalSequential) * 100).toFixed(0)}% faster`)
    }

    console.log("")
    console.log("🔧 RECOMMENDED OPTIMIZATIONS:")
    console.log("─".repeat(50))
    console.log("1. Pre-create voice session on page load")
    console.log("   - Move session creation to Scout page initialization")
    console.log("   - Keep session alive for quick mic button response")
    console.log("")
    console.log("2. Pre-fetch credentials on page load")
    console.log("   - Fetch Deepgram + Polly credentials immediately")
    console.log("   - Cache them until mic button is clicked")
    console.log("")
    console.log("3. Pre-connect WebSocket (optional)")
    console.log("   - Connect Deepgram WebSocket in 'paused' state")
    console.log("   - Start streaming when mic is clicked")
    console.log("")
    console.log("4. Show immediate visual feedback")
    console.log("   - Animate mic button instantly on click")
    console.log("   - Hide latency with UI animations")
    console.log("")

    // Store full results
    this.metrics = {
      currentTime: currentSteps?.totalSequential || 0,
      optimizedTime: 500,
      improvement: caching?.potentialSavings || 0,
      results: this.results
    }

    console.log("📋 Full results stored in: VoicePerformanceTest.metrics")
    console.log("")

    return this.metrics
  }
}

// Auto-run if in browser console
if (typeof window !== 'undefined') {
  window.VoicePerformanceTest = VoicePerformanceTest
  console.log("✅ VoicePerformanceTest loaded!")
  console.log("Run: await VoicePerformanceTest.runFullTest()")
}
