# frozen_string_literal: true

module Benchmarks
  # ============================================
  # Business Operations Benchmark (BOB) v1.0
  # "MMLU for Running a Business"
  # 
  # 100 tasks across 10 categories testing Scout as a
  # fractional COO / Chief of Staff
  # 
  # Scoring: 1-5 scale based on rubric match
  # - 1: Completely misses the mark
  # - 2: Partially addresses but major gaps
  # - 3: Adequate but generic/incomplete
  # - 4: Good, meets most rubric criteria
  # - 5: Excellent, fully meets rubric with insight
  # ============================================
  class BusinessBenchmark
    CATEGORIES = {
      strategy: 'Strategy & Planning',
      finance: 'Finance & Cash Flow',
      sales: 'Sales & CRM',
      marketing: 'Marketing & Growth',
      operations: 'Operations & Process',
      hr: 'HR & People Ops',
      customer_success: 'Customer Support & Success',
      analytics: 'Analytics & Decision Support',
      admin: 'Admin, Scheduling & Communication',
      compliance: 'Compliance, Risk & Vendor Management',
      grounded: 'Grounded Tasks (Require Tools/Data)',  # Tasks that MUST use external data
      creation: 'Creation & Building (Agents/Tools/Pages)',  # Tasks that CREATE things
      evolution: 'Self-Evolution (Agent/Tool Creation)'  # Tasks that make the system better
    }.freeze

    # All 100 benchmark tasks
    TASKS = [
      # ============================================
      # 1. STRATEGY & PLANNING (1-10)
      # ============================================
      {
        id: 'strategy_001',
        category: :strategy,
        name: 'Define quarterly OKRs',
        scenario: 'A 25-person B2B SaaS doing ~$2M ARR, churn is creeping up.',
        request: 'Scout, help me draft 3-5 company-level OKRs for next quarter focused on retention and efficient growth.',
        rubric: [
          '3-5 clear OKRs with measurable KRs',
          'Time-bound objectives',
          'Tied to retention and efficient growth',
          'KRs use realistic numeric targets',
          'Formatted for OKR tool import'
        ],
        requires_tools: false,
        difficulty: :medium
      },
      {
        id: 'strategy_002',
        category: :strategy,
        name: 'Prioritize strategic initiatives',
        scenario: 'The owner has 8 possible initiatives and limited bandwidth.',
        request: 'Scout, here are 8 initiatives: 1) Launch mobile app, 2) Expand to Canada, 3) Add enterprise tier, 4) Hire sales team, 5) Rebrand website, 6) Build partner program, 7) Automate onboarding, 8) Add AI features. Help me prioritize them using a simple impact/effort framework and recommend a top 3.',
        rubric: [
          'Initiatives ranked with short rationale per item',
          'Labeled on impact and effort (High/Med/Low)',
          'Clear top 3 recommendation',
          'Reasoning for prioritization'
        ],
        requires_tools: false,
        difficulty: :medium
      },
      {
        id: 'strategy_003',
        category: :strategy,
        name: 'Simple market positioning statement',
        scenario: 'Local bookkeeping firm serving construction contractors.',
        request: 'Scout, write a one-sentence positioning statement that clearly explains who we serve and why we\'re different.',
        rubric: [
          'One concise sentence',
          'Jargon-free',
          'Includes target audience',
          'States the problem solved',
          'Includes differentiator'
        ],
        requires_tools: false,
        difficulty: :easy
      },
      {
        id: 'strategy_004',
        category: :strategy,
        name: 'SWOT snapshot',
        scenario: '10-year-old manufacturing SMB facing cheaper overseas competitors.',
        request: 'Scout, from what you know about a typical mid-sized local manufacturer vs offshore competitors, draft a SWOT I can refine.',
        rubric: [
          'Structured SWOT format',
          'Business-relevant strengths',
          'Honest weaknesses',
          'Realistic opportunities',
          'Specific threats (not generic)',
          'No filler like "we work hard"'
        ],
        requires_tools: false,
        difficulty: :medium
      },
      {
        id: 'strategy_005',
        category: :strategy,
        name: 'Decide whether to open second location',
        scenario: 'Profitable café considering second shop across town.',
        request: 'Scout, list the top factors and risks I should consider before opening a second café location and propose a simple go/no-go checklist.',
        rubric: [
          '8-15 concrete factors',
          'Covers financial, operational, staffing, demand',
          'Short checklist format',
          'Clear "if X then reconsider" conditions'
        ],
        requires_tools: false,
        difficulty: :medium
      },
      {
        id: 'strategy_006',
        category: :strategy,
        name: 'Productization of services',
        scenario: 'Agency sells custom projects, wants repeatable packages.',
        request: 'Scout, turn our SEO service into 3 clear packages (Basic, Growth, Premium) with what\'s included and price logic.',
        rubric: [
          '3 tiered packages',
          'Bullet list of inclusions per tier',
          'Pricing structure that scales logically',
          'Target customer for each tier'
        ],
        requires_tools: false,
        difficulty: :medium
      },
      {
        id: 'strategy_007',
        category: :strategy,
        name: 'Evaluate a new revenue stream',
        scenario: 'Gym wants to start selling pre-made meals.',
        request: 'Scout, outline the pros/cons and main assumptions of adding a prepared-meals line for our gym clients.',
        rubric: [
          'Clear pros listed',
          'Clear cons listed',
          'Explicit assumptions (attachment rate, margin, spoilage)',
          'Suggestion of small pilot approach'
        ],
        requires_tools: false,
        difficulty: :medium
      },
      {
        id: 'strategy_008',
        category: :strategy,
        name: 'Annual planning outline',
        scenario: 'Owner has never done structured annual planning.',
        request: 'Scout, give me a practical agenda for a 1-day annual planning retreat for my 15-person company.',
        rubric: [
          'Time-boxed agenda',
          'Includes review of last year',
          'Covers metrics and strategy',
          'Includes goals and risks',
          'Has action plan section'
        ],
        requires_tools: false,
        difficulty: :medium
      },
      {
        id: 'strategy_009',
        category: :strategy,
        name: 'Sunset a failing offering',
        scenario: 'A service line is unprofitable and distracting.',
        request: 'Scout, help me decide how to phase out our social media management service without upsetting existing clients.',
        rubric: [
          'Steps with timeline',
          'Communication plan to clients',
          'Options (price increase, referral, wind-down)',
          'Addresses client retention concerns'
        ],
        requires_tools: false,
        difficulty: :medium
      },
      {
        id: 'strategy_010',
        category: :strategy,
        name: 'Simple strategic roadmap',
        scenario: 'E-commerce store wants to reach $1M from $400k in 18 months.',
        request: 'Scout, outline a high-level 18-month roadmap to grow from $400k to $1M in revenue.',
        rubric: [
          '3-4 phases with time ranges',
          'Key initiatives per phase',
          'Rough metrics milestones',
          'Realistic and acknowledges constraints'
        ],
        requires_tools: false,
        difficulty: :hard
      },

      # ============================================
      # 2. FINANCE & CASH FLOW (11-20)
      # ============================================
      {
        id: 'finance_011',
        category: :finance,
        name: 'Build a basic cash flow forecast',
        scenario: 'SMB with seasonal revenue and tight cash. Monthly revenue: Jan $50k, Feb $45k, Mar $60k, Apr $80k, May $90k, Jun $70k. Monthly expenses: $55k fixed.',
        request: 'Scout, using this month-by-month revenue and expense data, help me forecast next 6 months\' cash balance starting with $20k and flag risk months.',
        rubric: [
          'Correct arithmetic',
          'Simple table with projected cash',
          'Identification of low/negative cash months',
          'Suggested mitigations'
        ],
        requires_tools: false,
        difficulty: :medium
      },
      {
        id: 'finance_012',
        category: :finance,
        name: 'Identify cost-cut opportunities',
        scenario: 'Company needs to cut expenses by 10%. Current expenses: Rent $8k, Salaries $120k, Software $15k, Marketing $20k, Travel $10k, Office supplies $3k, Insurance $5k.',
        request: 'Scout, from this list of expenses, propose specific cuts or renegotiations to save ~10% ($18k) while preserving growth capabilities.',
        rubric: [
          'Concrete cost-cutting proposals',
          'Estimated savings per item',
          'Trade-offs explained',
          'Distinguishes "fat" from "muscle"'
        ],
        requires_tools: false,
        difficulty: :medium
      },
      {
        id: 'finance_013',
        category: :finance,
        name: 'Understand unit economics',
        scenario: 'D2C brand: CAC $45, AOV $85, Gross margin 60%, Repeat purchase rate 25% within 6 months.',
        request: 'Scout, using our CAC, AOV, gross margin, and repeat purchase rate, explain whether our paid acquisition is profitable.',
        rubric: [
          'Clear step-by-step calculation',
          'Conclusion (profitable/not yet)',
          'Explains which lever matters most',
          'Mentions LTV concept'
        ],
        requires_tools: false,
        difficulty: :hard
      },
      {
        id: 'finance_014',
        category: :finance,
        name: 'Simple breakeven analysis',
        scenario: 'Fixed costs: $15,000/month. Variable cost per unit: $12. Selling price: $35.',
        request: 'Scout, calculate our breakeven point in units and revenue.',
        rubric: [
          'Correct breakeven formula used',
          'Correct numeric answer (652 units, ~$22,826)',
          'One-sentence plain language explanation'
        ],
        requires_tools: false,
        difficulty: :easy
      },
      {
        id: 'finance_015',
        category: :finance,
        name: 'Scenario planning: revenue drop',
        scenario: 'Current revenue $100k/month, costs $80k, profit $20k.',
        request: 'Scout, show me what happens to our profit if revenue drops 20% and we keep costs flat vs. cut 10% of costs.',
        rubric: [
          'Two scenarios calculated correctly',
          'Comparison of outcomes',
          'Recommendation with rationale'
        ],
        requires_tools: false,
        difficulty: :medium
      },
      {
        id: 'finance_016',
        category: :finance,
        name: 'Collections improvement plan',
        scenario: 'Many invoices go unpaid for 60+ days. Current process: Invoice on completion, Net 30 terms, one reminder at day 45.',
        request: 'Scout, here\'s our current invoicing & collections process. Suggest concrete changes to improve cash collection speed.',
        rubric: [
          'Changes to payment terms',
          'Reminder schedule improvements',
          'Deposit/prepayment suggestions',
          'Late fee considerations',
          'Sample scripts/templates'
        ],
        requires_tools: false,
        difficulty: :medium
      },
      {
        id: 'finance_017',
        category: :finance,
        name: 'Budget for first hire in a new role',
        scenario: 'Hiring first marketing manager.',
        request: 'Scout, estimate total annual cost (salary, benefits, taxes) for hiring a marketing manager at $80k base.',
        rubric: [
          'Reasonable total compensation range',
          'Breakdown of components (taxes, benefits)',
          'Mentions hidden costs (tools, onboarding)'
        ],
        requires_tools: false,
        difficulty: :easy
      },
      {
        id: 'finance_018',
        category: :finance,
        name: 'Evaluate a vendor proposal',
        scenario: 'Software vendor offers: Plan A: $500/mo flat, Plan B: $200/mo + $5/user (we have 40 users), Plan C: $1000/mo unlimited.',
        request: 'Scout, compare these 3 pricing plans and recommend which is best given our size and usage.',
        rubric: [
          'Comparison table',
          'Effective per-unit costs calculated',
          'Recommendation with justification',
          'Considers growth scenarios'
        ],
        requires_tools: false,
        difficulty: :easy
      },
      {
        id: 'finance_019',
        category: :finance,
        name: 'ROI of an equipment purchase',
        scenario: 'Machine costs $50,000. Expected savings: $1,500/month. Expected lifetime: 5 years.',
        request: 'Scout, estimate simple payback period and ROI for buying this machine.',
        rubric: [
          'Correct payback calculation (~33 months)',
          'Rough ROI calculation',
          'Mentions non-financial factors'
        ],
        requires_tools: false,
        difficulty: :medium
      },
      {
        id: 'finance_020',
        category: :finance,
        name: 'Explain key financial metrics',
        scenario: 'Owner not fluent in finance.',
        request: 'Scout, explain in plain English what gross margin, net margin, and operating margin mean for my business.',
        rubric: [
          'Correct definitions',
          'Easy examples',
          'Why each metric matters',
          'No jargon'
        ],
        requires_tools: false,
        difficulty: :easy
      },

      # ============================================
      # 3. SALES & CRM (21-30)
      # ============================================
      {
        id: 'sales_021',
        category: :sales,
        name: 'Qualify inbound leads',
        scenario: 'Many low-quality demo requests for B2B software.',
        request: 'Scout, create 5-7 qualification questions for inbound leads and a simple scoring rubric.',
        rubric: [
          'Mix of BANT questions (budget, authority, need, timing)',
          'Scoring system (0-2 per question)',
          'Guidance on score thresholds',
          'Practical to use'
        ],
        requires_tools: false,
        difficulty: :medium
      },
      {
        id: 'sales_022',
        category: :sales,
        name: 'Draft a follow-up email sequence',
        scenario: 'Prospects go dark after first call.',
        request: 'Scout, write a 3-email follow-up sequence for prospects who had a demo but didn\'t buy.',
        rubric: [
          '3 distinct emails',
          'Logically spaced (e.g., day 3, 7, 14)',
          'Each with clear CTA',
          'Polite and persistent, not spammy'
        ],
        requires_tools: false,
        difficulty: :medium
      },
      {
        id: 'sales_023',
        category: :sales,
        name: 'Upsell proposal',
        scenario: 'Existing client on Basic plan ($500/mo) might expand to Growth ($1200/mo).',
        request: 'Scout, draft a short upsell proposal to move a client from our Basic to Growth plan, highlighting value.',
        rubric: [
          'Brief proposal format',
          'Current state acknowledged',
          'Proposed upgrade benefits',
          'Price difference justified',
          'Clear next step'
        ],
        requires_tools: false,
        difficulty: :medium
      },
      {
        id: 'sales_024',
        category: :sales,
        name: 'Pipeline health summary',
        scenario: 'Sales pipeline data: Deal A ($50k, 80%, Negotiation), Deal B ($30k, 20%, Discovery), Deal C ($100k, 50%, Proposal), Deal D ($25k, 90%, Closing), Deal E ($40k, 10%, Qualification).',
        request: 'Scout, given this list of deals with stage, size, and close probability, estimate expected revenue and identify red flags.',
        rubric: [
          'Correct weighted pipeline value',
          'Mentions stalled or risky deals',
          'Identifies concentration risk',
          'Actionable observations'
        ],
        requires_tools: false,
        difficulty: :medium
      },
      {
        id: 'sales_025',
        category: :sales,
        name: 'Call prep brief',
        scenario: 'Lead: Sarah Chen, VP Operations at MidSize Manufacturing Inc, 200 employees, came from webinar on "Reducing Production Delays", downloaded our ROI calculator.',
        request: 'Scout, summarize this lead\'s info and give me 3 tailored questions I should ask on the discovery call.',
        rubric: [
          'Short profile summary',
          'Main pain points inferred',
          '3 relevant, specific questions',
          'No generic filler'
        ],
        requires_tools: false,
        difficulty: :easy
      },
      {
        id: 'sales_026',
        category: :sales,
        name: 'Objection handling guide',
        scenario: 'Common objection is "too expensive" for our B2B consulting service.',
        request: 'Scout, create a short guide for handling the "too expensive" objection.',
        rubric: [
          'Acknowledge the concern',
          'Probe to understand',
          'Reframe value',
          'Offer options',
          '2-3 example phrases'
        ],
        requires_tools: false,
        difficulty: :medium
      },
      {
        id: 'sales_027',
        category: :sales,
        name: 'Proposal template',
        scenario: 'Proposals are inconsistent across the team.',
        request: 'Scout, design a simple proposal template we can reuse for service projects.',
        rubric: [
          'Key sections (overview, scope, timeline, pricing)',
          'Includes assumptions section',
          'Has next steps',
          'Concise and professional'
        ],
        requires_tools: false,
        difficulty: :medium
      },
      {
        id: 'sales_028',
        category: :sales,
        name: 'Lead prioritization',
        scenario: 'Leads: 1) Tech startup, 50 employees, score 85, inbound. 2) Law firm, 20 employees, score 60, referral. 3) Retailer, 500 employees, score 40, cold. 4) Healthcare, 100 employees, score 75, webinar. 5) Finance, 30 employees, score 90, demo request.',
        request: 'Scout, from this list of leads, tell me which 3 I should call first and why.',
        rubric: [
          'Reasonable ranking',
          'Clear prioritization logic',
          'Considers multiple factors',
          'Actionable recommendation'
        ],
        requires_tools: false,
        difficulty: :easy
      },
      {
        id: 'sales_029',
        category: :sales,
        name: 'Sales script outline',
        scenario: 'New salesperson joining the team.',
        request: 'Scout, outline a structured script for a 30-minute discovery call.',
        rubric: [
          'Segmented call flow',
          'Intro, discovery, pitch, next steps',
          'Example questions',
          'Time guidance per section'
        ],
        requires_tools: false,
        difficulty: :medium
      },
      {
        id: 'sales_030',
        category: :sales,
        name: 'Churn follow-up plan',
        scenario: 'Customers cancel without giving feedback.',
        request: 'Scout, draft a short email + 3 survey questions to understand why customers churned.',
        rubric: [
          'Empathetic email tone',
          '3 focused questions',
          'Covers value, price, alternatives',
          'Easy to respond to'
        ],
        requires_tools: false,
        difficulty: :easy
      },

      # ============================================
      # 4. MARKETING & GROWTH (31-40)
      # ============================================
      {
        id: 'marketing_031',
        category: :marketing,
        name: 'Ideal customer profile (ICP) draft',
        scenario: 'Marketing is too broad for B2B IT support company.',
        request: 'Scout, draft an ICP for our B2B IT support company focusing on SMB clients.',
        rubric: [
          'Clear firmographics (size, industry)',
          'Pain points identified',
          'Decision-maker roles',
          'Must-have traits',
          'Specific, not generic'
        ],
        requires_tools: false,
        difficulty: :medium
      },
      {
        id: 'marketing_032',
        category: :marketing,
        name: 'Content calendar',
        scenario: 'Wants consistent marketing content for accounting firm.',
        request: 'Scout, plan a 4-week content calendar with 3 posts per week for LinkedIn about our accounting firm.',
        rubric: [
          'Dates or day labels',
          'Post topics specified',
          'Short description per post',
          'Aligned with target audience',
          'Variety of content types'
        ],
        requires_tools: false,
        difficulty: :medium
      },
      {
        id: 'marketing_033',
        category: :marketing,
        name: 'Landing page outline',
        scenario: 'New HR audit service needs a landing page.',
        request: 'Scout, outline a high-converting landing page structure for our new HR audit service.',
        rubric: [
          'Sections in logical order',
          'Hero, pain, solution, proof, pricing, FAQ, CTA',
          'Brief copy suggestions',
          'Conversion-focused'
        ],
        requires_tools: false,
        difficulty: :medium
      },
      {
        id: 'marketing_034',
        category: :marketing,
        name: 'Google Ads keyword brainstorm',
        scenario: 'Owner wants to test search ads for local plumbing business.',
        request: 'Scout, suggest 20 relevant keywords and 5 negative keywords for our local plumbing business in Austin, TX.',
        rubric: [
          'Relevant core keywords',
          'Long-tail keywords',
          'Local-intent keywords',
          'At least 5 negative keywords',
          'No irrelevant terms'
        ],
        requires_tools: false,
        difficulty: :medium
      },
      {
        id: 'marketing_035',
        category: :marketing,
        name: 'Email newsletter draft',
        scenario: 'Re-engaging old customers about new service bundles.',
        request: 'Scout, write a short newsletter to past clients about our new service bundles.',
        rubric: [
          'Clear subject line',
          'Concise body',
          'Highlights new bundles',
          'Single primary CTA',
          'Personal but professional tone'
        ],
        requires_tools: false,
        difficulty: :easy
      },
      {
        id: 'marketing_036',
        category: :marketing,
        name: 'Simple referral program',
        scenario: 'Wants more word-of-mouth referrals.',
        request: 'Scout, design a simple referral program we can roll out to existing clients.',
        rubric: [
          'Clear reward structure',
          'Eligibility rules',
          'How to communicate it',
          'Basic terms to avoid abuse'
        ],
        requires_tools: false,
        difficulty: :medium
      },
      {
        id: 'marketing_037',
        category: :marketing,
        name: 'Analyze current marketing mix',
        scenario: 'Marketing spend: Google Ads $5k (50 leads), Facebook $3k (20 leads), LinkedIn $2k (15 leads), Content $1k (30 leads).',
        request: 'Scout, given this breakdown of our marketing spend and leads, identify which channels to double down on and which to cut.',
        rubric: [
          'Cost per lead calculated',
          'Winner channels identified',
          'Laggard channels identified',
          'Recommendation with reasoning'
        ],
        requires_tools: false,
        difficulty: :medium
      },
      {
        id: 'marketing_038',
        category: :marketing,
        name: 'Lead magnet idea',
        scenario: 'Wants to grow email list for payroll service targeting SMBs.',
        request: 'Scout, propose 3 lead magnet ideas that would attract our target SMB owners for our payroll service.',
        rubric: [
          '3 specific assets',
          'Title for each',
          'Format specified',
          'Pain point addressed'
        ],
        requires_tools: false,
        difficulty: :easy
      },
      {
        id: 'marketing_039',
        category: :marketing,
        name: 'Brand voice guidelines',
        scenario: 'Inconsistent tone across channels. Brand is "professional but friendly".',
        request: 'Scout, based on us being "professional but friendly", draft short brand voice guidelines.',
        rubric: [
          '3-5 bullets describing tone',
          'Do\'s and don\'ts',
          'Example phrases',
          'Consistent with brand positioning'
        ],
        requires_tools: false,
        difficulty: :easy
      },
      {
        id: 'marketing_040',
        category: :marketing,
        name: 'Promotion calendar for seasonal product',
        scenario: 'Online gift shop preparing for Christmas.',
        request: 'Scout, create a marketing timeline for the 8 weeks leading up to Christmas for our online gift shop.',
        rubric: [
          'Week-by-week key actions',
          'Channels to use',
          'Offer ideas (early bird, last-minute)',
          'Realistic timeline'
        ],
        requires_tools: false,
        difficulty: :medium
      },

      # ============================================
      # 5. OPERATIONS & PROCESS (41-50)
      # ============================================
      {
        id: 'operations_041',
        category: :operations,
        name: 'Document an SOP',
        scenario: 'Client onboarding process is in owner\'s head: "We get the signed contract, then I send a welcome email, schedule kickoff, create their account, assign a PM, do the kickoff call, then start the project."',
        request: 'Scout, turn this messy description of how we onboard new clients into a step-by-step SOP.',
        rubric: [
          'Numbered steps',
          'Clear roles assigned',
          'Inputs and outputs defined',
          'Easy to follow'
        ],
        requires_tools: false,
        difficulty: :medium
      },
      {
        id: 'operations_042',
        category: :operations,
        name: 'Capacity planning',
        scenario: 'Team capacity: 400 hours/week. Project hours by week: W1: 380, W2: 450, W3: 520, W4: 390, W5: 480, W6: 350.',
        request: 'Scout, from this table of weekly project hours and team capacity, show where we\'re over capacity and suggest fixes.',
        rubric: [
          'Over-capacity weeks identified',
          'Simple summary or visualization',
          'Suggestions (hire, outsource, reschedule)',
          'Realistic solutions'
        ],
        requires_tools: false,
        difficulty: :medium
      },
      {
        id: 'operations_043',
        category: :operations,
        name: 'Vendor comparison',
        scenario: 'Choosing between 3 suppliers: A (price: $10/unit, reliability: 95%, quality: good), B (price: $12/unit, reliability: 99%, quality: excellent), C (price: $8/unit, reliability: 85%, quality: fair).',
        request: 'Scout, compare these 3 vendors on price, reliability, and quality, and recommend one.',
        rubric: [
          'Comparison matrix',
          'Explicit trade-offs',
          'Recommendation with rationale',
          'Considers total cost of ownership'
        ],
        requires_tools: false,
        difficulty: :easy
      },
      {
        id: 'operations_044',
        category: :operations,
        name: 'Reduce operational bottleneck',
        scenario: 'Order fulfillment: Receive order → Pick items → Pack → QC check (takes 30 min each) → Ship. QC is backed up.',
        request: 'Scout, here is our order fulfillment process. Identify likely bottlenecks and propose improvements.',
        rubric: [
          'Specific bottleneck identified',
          '2-3 ways to fix or mitigate',
          'Realistic solutions',
          'No magical thinking'
        ],
        requires_tools: false,
        difficulty: :medium
      },
      {
        id: 'operations_045',
        category: :operations,
        name: 'Inventory reorder policy',
        scenario: 'Top SKUs with weekly sales: SKU-A sells 50/week, SKU-B sells 20/week, SKU-C sells 100/week. Lead time is 2 weeks.',
        request: 'Scout, suggest a simple rule for when to reorder our top SKUs based on this sales history.',
        rubric: [
          'Basic reorder point logic',
          'Mentions lead time',
          'Safety stock concept',
          'Sample rule provided'
        ],
        requires_tools: false,
        difficulty: :medium
      },
      {
        id: 'operations_046',
        category: :operations,
        name: 'Service level definition',
        scenario: 'Support tickets are randomly prioritized.',
        request: 'Scout, define 3 ticket priority levels and target response times for each.',
        rubric: [
          'Clear P1/P2/P3 definitions',
          'Response time targets',
          'Resolution time targets',
          'Examples of each priority'
        ],
        requires_tools: false,
        difficulty: :easy
      },
      {
        id: 'operations_047',
        category: :operations,
        name: 'Handoff template',
        scenario: 'Work gets lost during team handoffs from sales to delivery.',
        request: 'Scout, create a simple handoff checklist template for projects moving from sales to delivery.',
        rubric: [
          'Checklist items (scope, deadlines, contacts)',
          'Includes risks and special terms',
          'Short and practical',
          'Sign-off section'
        ],
        requires_tools: false,
        difficulty: :easy
      },
      {
        id: 'operations_048',
        category: :operations,
        name: 'On-call schedule plan',
        scenario: 'Support team of 5, uneven on-call load causing burnout.',
        request: 'Scout, propose a fair weekly on-call schedule pattern for a team of 5, with backup coverage.',
        rubric: [
          'Rotating schedule logic',
          'Avoids overburdening individuals',
          'Includes backup plan',
          'Considers weekends/holidays'
        ],
        requires_tools: false,
        difficulty: :medium
      },
      {
        id: 'operations_049',
        category: :operations,
        name: 'Quality control checklist',
        scenario: 'Product defects slipping through in e-commerce warehouse.',
        request: 'Scout, design a QC checklist for outgoing orders in our e-commerce warehouse.',
        rubric: [
          'Stepwise checks',
          'Covers correct item, quantity, packaging, label',
          'Space for sign-off',
          'Practical to use'
        ],
        requires_tools: false,
        difficulty: :easy
      },
      {
        id: 'operations_050',
        category: :operations,
        name: 'Time audit analysis',
        scenario: 'Owner\'s last week: Meetings 15h, Email 10h, Sales calls 8h, Admin 7h, Strategy 2h, Social media 3h.',
        request: 'Scout, here\'s my last week\'s time log. Categorize my time and recommend what I should delegate or drop.',
        rubric: [
          'Time grouped by category',
          'Low-value tasks identified',
          '3-5 delegation opportunities',
          'Actionable recommendations'
        ],
        requires_tools: false,
        difficulty: :medium
      },

      # ============================================
      # 6. HR & PEOPLE OPS (51-60)
      # ============================================
      {
        id: 'hr_051',
        category: :hr,
        name: 'Draft a job description',
        scenario: 'Hiring a customer success manager for B2B SaaS.',
        request: 'Scout, write a job description for a Customer Success Manager for our B2B SaaS.',
        rubric: [
          'Role summary',
          'Clear responsibilities',
          'Requirements (realistic)',
          'Nice-to-haves',
          'Not a wish-list fantasy'
        ],
        requires_tools: false,
        difficulty: :medium
      },
      {
        id: 'hr_052',
        category: :hr,
        name: 'Interview question set',
        scenario: 'No structured interviews for sales role.',
        request: 'Scout, propose 10 interview questions to assess a sales role\'s skills and culture fit.',
        rubric: [
          'Mix of behavioral questions',
          'Situational questions',
          'Technical/skill questions',
          'Tied to role requirements'
        ],
        requires_tools: false,
        difficulty: :medium
      },
      {
        id: 'hr_053',
        category: :hr,
        name: 'Onboarding plan',
        scenario: 'New hires flounder in first month.',
        request: 'Scout, create a 30-day onboarding plan for our new sales rep.',
        rubric: [
          'Week-by-week goals',
          'Key meetings scheduled',
          'Training items listed',
          'Clearly sequenced'
        ],
        requires_tools: false,
        difficulty: :medium
      },
      {
        id: 'hr_054',
        category: :hr,
        name: 'Performance review template',
        scenario: 'Performance feedback is ad hoc.',
        request: 'Scout, design a simple quarterly performance review form.',
        rubric: [
          'Goals section',
          'Outcomes/achievements section',
          'Strengths and improvements',
          'Next-quarter goals',
          'Simple rating scale'
        ],
        requires_tools: false,
        difficulty: :easy
      },
      {
        id: 'hr_055',
        category: :hr,
        name: 'Conflict resolution email',
        scenario: 'Two team members are in conflict.',
        request: 'Scout, draft a neutral message I can send to both to set expectations before a mediation meeting.',
        rubric: [
          'Calm, neutral tone',
          'Clarifies purpose',
          'Sets ground rules',
          'No blame assigned'
        ],
        requires_tools: false,
        difficulty: :medium
      },
      {
        id: 'hr_056',
        category: :hr,
        name: 'Basic compensation banding',
        scenario: 'Current salaries: Junior Dev $60k, Mid Dev $75k, Senior Dev $95k, Lead $110k. Pay feels random.',
        request: 'Scout, given these roles and current salaries, suggest clearer pay bands for each level.',
        rubric: [
          'Reasonable bands (min/mid/max)',
          'Per role level',
          'Notes on performance vs tenure',
          'Market-aware'
        ],
        requires_tools: false,
        difficulty: :medium
      },
      {
        id: 'hr_057',
        category: :hr,
        name: 'Exit interview questions',
        scenario: 'People leave without learning captured.',
        request: 'Scout, create 8-10 exit interview questions that will give us honest insight.',
        rubric: [
          'Open-ended questions',
          'Covers reasons for leaving',
          'Management feedback',
          'Culture questions',
          'Suggestions for improvement'
        ],
        requires_tools: false,
        difficulty: :easy
      },
      {
        id: 'hr_058',
        category: :hr,
        name: 'Remote work guidelines',
        scenario: 'Team partly remote without clarity.',
        request: 'Scout, draft high-level guidelines for remote work expectations.',
        rubric: [
          'Hours/availability expectations',
          'Communication norms',
          'Responsiveness guidelines',
          'Meeting expectations',
          'Balanced and realistic'
        ],
        requires_tools: false,
        difficulty: :easy
      },
      {
        id: 'hr_059',
        category: :hr,
        name: 'Simple recognition program',
        scenario: 'Morale is low; no recognition.',
        request: 'Scout, design a lightweight employee recognition program we can start next month.',
        rubric: [
          'Who can nominate',
          'What gets recognized',
          'Frequency',
          'Reward structure',
          'Easy to run'
        ],
        requires_tools: false,
        difficulty: :easy
      },
      {
        id: 'hr_060',
        category: :hr,
        name: 'Headcount planning',
        scenario: 'Company plans to grow from 10 to 20 people in 12 months.',
        request: 'Scout, suggest which roles to hire in what order over the next 12 months.',
        rubric: [
          'Sequenced hiring plan',
          'Justification for each role',
          'Aligns with growth constraints',
          'Realistic timeline'
        ],
        requires_tools: false,
        difficulty: :hard
      },

      # ============================================
      # 7. CUSTOMER SUPPORT & SUCCESS (61-70)
      # ============================================
      {
        id: 'support_061',
        category: :customer_success,
        name: 'Support macro creation',
        scenario: 'Same "how do I reset my password?" tickets repeatedly.',
        request: 'Scout, write a reusable macro for password reset questions.',
        rubric: [
          'Short, friendly message',
          'Clear steps',
          'Link placeholders',
          'Optional extra help line'
        ],
        requires_tools: false,
        difficulty: :easy
      },
      {
        id: 'support_062',
        category: :customer_success,
        name: 'Categorize support tickets',
        scenario: 'No visibility on causes of support load. Sample tickets: "Can\'t login", "Billing question", "Feature not working", "How do I export?", "Cancel subscription", etc.',
        request: 'Scout, from this sample of ticket descriptions, group them into 4-6 categories.',
        rubric: [
          'Logical categories',
          'Examples assigned to each',
          'Counts per category',
          'Actionable groupings'
        ],
        requires_tools: false,
        difficulty: :easy
      },
      {
        id: 'support_063',
        category: :customer_success,
        name: 'SLA breach report',
        scenario: 'Tickets with times: T1 (opened 9am, closed 11am, SLA 4h), T2 (opened 2pm, closed 6pm next day, SLA 4h), T3 (opened 10am, closed 1pm, SLA 4h).',
        request: 'Scout, based on this table of ticket open/close times and SLA targets, show where we missed SLAs.',
        rubric: [
          'Correct breach identification',
          'Basic summary (% missed)',
          'Possible root causes mentioned'
        ],
        requires_tools: false,
        difficulty: :medium
      },
      {
        id: 'support_064',
        category: :customer_success,
        name: 'Customer onboarding email sequence',
        scenario: 'New customers don\'t adopt all features.',
        request: 'Scout, draft a 4-email onboarding sequence over 30 days.',
        rubric: [
          '4 emails with clear purpose',
          'Staged appropriately',
          'Each with CTA',
          'Covers welcome, setup, tips, advanced/feedback'
        ],
        requires_tools: false,
        difficulty: :medium
      },
      {
        id: 'support_065',
        category: :customer_success,
        name: 'NPS survey and follow-up',
        scenario: 'Owner wants to measure satisfaction.',
        request: 'Scout, create an NPS survey email and separate follow-up for detractors.',
        rubric: [
          'Initial NPS email (single question)',
          'Optional comment field',
          'Empathetic detractor follow-up',
          'Professional tone'
        ],
        requires_tools: false,
        difficulty: :medium
      },
      {
        id: 'support_066',
        category: :customer_success,
        name: 'Retention risk flags',
        scenario: 'Usage data: Customer A (logins down 80%, 5 support tickets), Customer B (usage stable, 0 tickets), Customer C (logins down 50%, payment failed).',
        request: 'Scout, from this usage data summary, identify which customers are at high risk of churn.',
        rubric: [
          'Logical risk rules',
          'Based on declining use, tickets, payment',
          'High-risk customers identified',
          'Actionable'
        ],
        requires_tools: false,
        difficulty: :medium
      },
      {
        id: 'support_067',
        category: :customer_success,
        name: 'Customer apology email',
        scenario: 'Major outage affected many users for 3 hours yesterday.',
        request: 'Scout, write an apology email about yesterday\'s outage with what happened and next steps.',
        rubric: [
          'Takes responsibility',
          'Explains at high level',
          'States restitution if any',
          'Sets expectations for future'
        ],
        requires_tools: false,
        difficulty: :medium
      },
      {
        id: 'support_068',
        category: :customer_success,
        name: 'Success plan template',
        scenario: 'High-value clients need structured success plans.',
        request: 'Scout, create a 1-page customer success plan template.',
        rubric: [
          'Goals section',
          'Current state',
          'Success metrics',
          'Milestones',
          'Responsibilities'
        ],
        requires_tools: false,
        difficulty: :medium
      },
      {
        id: 'support_069',
        category: :customer_success,
        name: 'Feature request triage',
        scenario: 'Many incoming feature requests with no system.',
        request: 'Scout, propose a simple system for triaging feature requests by impact and effort.',
        rubric: [
          'Scoring criteria',
          'Categories (must-have, nice-to-have)',
          'Routing rules',
          'Practical to implement'
        ],
        requires_tools: false,
        difficulty: :medium
      },
      {
        id: 'support_070',
        category: :customer_success,
        name: 'Churn save offer',
        scenario: 'Some customers want to cancel.',
        request: 'Scout, write a "win-back" message offering alternatives to immediate cancellation.',
        rubric: [
          'Polite, non-desperate tone',
          'Options (pause, downgrade, training)',
          'Clear next step',
          'Respects customer decision'
        ],
        requires_tools: false,
        difficulty: :easy
      },

      # ============================================
      # 8. ANALYTICS & DECISION SUPPORT (71-80)
      # ============================================
      {
        id: 'analytics_071',
        category: :analytics,
        name: 'KPI dashboard definition',
        scenario: 'Owner drowning in metrics but no focus.',
        request: 'Scout, define 8-10 core KPIs I should track weekly for our service business.',
        rubric: [
          'Balanced metrics',
          'Revenue, margin, pipeline, CSAT, churn, efficiency',
          'Simple definitions',
          'Why each matters'
        ],
        requires_tools: false,
        difficulty: :medium
      },
      {
        id: 'analytics_072',
        category: :analytics,
        name: 'Weekly metrics summary',
        scenario: 'Metrics: Revenue (this week $50k, last week $48k), Leads (120 vs 100), Churn (2% vs 1.5%), Support tickets (45 vs 30).',
        request: 'Scout, here\'s our metrics table for last week vs prior week. Summarize key changes and what I should pay attention to.',
        rubric: [
          'Highlights significant deltas',
          'Notes likely causes',
          'Calls out urgent issues',
          'Actionable summary'
        ],
        requires_tools: false,
        difficulty: :medium
      },
      {
        id: 'analytics_073',
        category: :analytics,
        name: 'Cohort retention analysis',
        scenario: 'Month 0: 100%, Month 1: 85%, Month 2: 75%, Month 3: 70%, Month 4: 68%, Month 5: 67%, Month 6: 66%.',
        request: 'Scout, from this month-by-month cohort table, explain in plain language how our retention looks.',
        rubric: [
          'Identifies retention pattern',
          'Points out where drop-offs occur',
          'Notes if improvement visible',
          'Plain language explanation'
        ],
        requires_tools: false,
        difficulty: :medium
      },
      {
        id: 'analytics_074',
        category: :analytics,
        name: 'A/B test interpretation',
        scenario: 'Subject line test: A (1000 sent, 22% open, 3% click), B (1000 sent, 28% open, 4% click).',
        request: 'Scout, interpret this A/B test result and say whether variant B is a winner.',
        rubric: [
          'Correct rate comparison',
          'Cautious about sample size',
          'Recommendation with caveats',
          'Mentions statistical significance'
        ],
        requires_tools: false,
        difficulty: :medium
      },
      {
        id: 'analytics_075',
        category: :analytics,
        name: 'Pareto analysis',
        scenario: 'Products: A ($100k), B ($80k), C ($50k), D ($30k), E ($20k), F ($15k), G ($5k).',
        request: 'Scout, from this product revenue list, show me which products make up ~80% of revenue.',
        rubric: [
          'Correct ordering',
          'Cumulative percentages',
          'Identifies "vital few"',
          'Clear presentation'
        ],
        requires_tools: false,
        difficulty: :easy
      },
      {
        id: 'analytics_076',
        category: :analytics,
        name: 'Root cause hypothesis list',
        scenario: 'Sudden 30% drop in leads last month.',
        request: 'Scout, given our situation, brainstorm plausible root causes and what data we\'d need to confirm.',
        rubric: [
          '5-10 plausible causes',
          'For each, specific data to check',
          'Covers multiple areas',
          'Actionable investigation plan'
        ],
        requires_tools: false,
        difficulty: :medium
      },
      {
        id: 'analytics_077',
        category: :analytics,
        name: 'Basic margin analysis by segment',
        scenario: 'Segments: Enterprise (revenue $200k, margin 40%), SMB (revenue $150k, margin 25%), Startup (revenue $50k, margin 10%).',
        request: 'Scout, using this margin by segment table, explain where we make and lose money.',
        rubric: [
          'Identifies high vs low margin',
          'Suggests decisions',
          'Considers segment potential',
          'Actionable insights'
        ],
        requires_tools: false,
        difficulty: :medium
      },
      {
        id: 'analytics_078',
        category: :analytics,
        name: 'Forecast sanity-check',
        scenario: 'Sales forecast: $500k pipeline, team says 60% will close. Historical close rate: 35%.',
        request: 'Scout, here\'s the forecast and our historical close rates. Check if this forecast is realistic.',
        rubric: [
          'Compares to historical',
          'Flags misalignment',
          'Gives adjusted expectation',
          'Explains reasoning'
        ],
        requires_tools: false,
        difficulty: :medium
      },
      {
        id: 'analytics_079',
        category: :analytics,
        name: 'Decision memo',
        scenario: 'Choosing between Option A (expand to new city) vs Option B (deepen current market).',
        request: 'Scout, turn this into a 1-page decision memo comparing Option A vs B with pros, cons, risks, and recommendation.',
        rubric: [
          'Structured memo format',
          'Context section',
          'Options with pros/cons',
          'Risks identified',
          'Clear recommendation'
        ],
        requires_tools: false,
        difficulty: :hard
      },
      {
        id: 'analytics_080',
        category: :analytics,
        name: 'Detect anomalies',
        scenario: 'Daily signups: Mon 45, Tue 52, Wed 48, Thu 120, Fri 50, Sat 30, Sun 25.',
        request: 'Scout, from this daily metrics table, highlight any anomalies worth investigating.',
        rubric: [
          'Identifies outliers',
          'Distinguishes from normal variation',
          'Brief hypotheses',
          'Suggests investigation'
        ],
        requires_tools: false,
        difficulty: :easy
      },

      # ============================================
      # 9. ADMIN, SCHEDULING & COMMUNICATION (81-90)
      # ============================================
      {
        id: 'admin_081',
        category: :admin,
        name: 'Inbox triage and summarization',
        scenario: 'Owner has 20 unread emails about: contract renewal, meeting request, vendor pitch, customer complaint, team update, invoice, etc.',
        request: 'Scout, summarize these email topics and tell me what needs my attention today vs later.',
        rubric: [
          'Short summary per email type',
          'Labeled (urgent/soon/later/archive)',
          'Identifies action items',
          'Prioritized list'
        ],
        requires_tools: false,
        difficulty: :medium
      },
      {
        id: 'admin_082',
        category: :admin,
        name: 'Calendar optimization',
        scenario: 'Weekly calendar: Meetings scattered throughout each day, no focus blocks.',
        request: 'Scout, here\'s my weekly calendar with fragmented meetings. Suggest a better structure with focus blocks.',
        rubric: [
          'Concrete rearrangement suggestions',
          'Blocks of focus time',
          'Meeting consolidation ideas',
          'Realistic for business needs'
        ],
        requires_tools: false,
        difficulty: :medium
      },
      {
        id: 'admin_083',
        category: :admin,
        name: 'Internal announcement',
        scenario: 'Company changing to hybrid work: 3 days office, 2 days remote, starting next month.',
        request: 'Scout, draft a clear internal announcement about our new hybrid work schedule.',
        rubric: [
          'States what is changing',
          'Explains why',
          'When it starts',
          'Expectations',
          'Contact for questions'
        ],
        requires_tools: false,
        difficulty: :easy
      },
      {
        id: 'admin_084',
        category: :admin,
        name: 'Vendor negotiation email',
        scenario: 'Software vendor charging $1000/mo, been a customer for 2 years, want 20% discount.',
        request: 'Scout, write an email to negotiate a discount with our software vendor.',
        rubric: [
          'Polite but firm tone',
          'References tenure/usage',
          'Suggests target discount',
          'Open to alternatives'
        ],
        requires_tools: false,
        difficulty: :medium
      },
      {
        id: 'admin_085',
        category: :admin,
        name: 'Board/investor update',
        scenario: 'Small company with a few angel investors.',
        request: 'Scout, create a one-page monthly update outline I can reuse for investors.',
        rubric: [
          'Highlights and lowlights',
          'Key metrics',
          'Pipeline/sales update',
          'Hires/team',
          'Asks section',
          'Concise format'
        ],
        requires_tools: false,
        difficulty: :medium
      },
      {
        id: 'admin_086',
        category: :admin,
        name: 'Meeting agenda',
        scenario: 'Weekly team meeting is unfocused, runs over time.',
        request: 'Scout, write a tight agenda for our 60-minute weekly team meeting.',
        rubric: [
          'Time-boxed items',
          'Clear outcomes per segment',
          'Keeps status updates short',
          'Action-oriented'
        ],
        requires_tools: false,
        difficulty: :easy
      },
      {
        id: 'admin_087',
        category: :admin,
        name: 'Meeting notes + action items',
        scenario: 'Meeting discussed: Q2 goals, hiring plan, budget concerns, new product launch.',
        request: 'Scout, summarize this meeting and list owner + due date for each action item.',
        rubric: [
          '5-10 sentence summary',
          'Clear bullet list of actions',
          'Owners assigned',
          'Deadlines included'
        ],
        requires_tools: false,
        difficulty: :medium
      },
      {
        id: 'admin_088',
        category: :admin,
        name: 'Travel plan for business trip',
        scenario: 'Visiting 3 clients in Chicago over 2 days.',
        request: 'Scout, draft a 2-day schedule to visit these 3 clients efficiently.',
        rubric: [
          'Ordered schedule',
          'Reasonable time buffers',
          'Logical route',
          'Includes travel time'
        ],
        requires_tools: false,
        difficulty: :easy
      },
      {
        id: 'admin_089',
        category: :admin,
        name: 'Template responses for FAQs',
        scenario: 'Same basic inquiries: pricing, availability, how to get started, refund policy, contact info.',
        request: 'Scout, create 5 canned responses for common email questions we get.',
        rubric: [
          '5 clear templates',
          'Placeholders included',
          'Polite tone',
          'On-brand'
        ],
        requires_tools: false,
        difficulty: :easy
      },
      {
        id: 'admin_090',
        category: :admin,
        name: 'Document organization scheme',
        scenario: 'Shared drive is a mess with random folders.',
        request: 'Scout, propose a folder structure for our company docs.',
        rubric: [
          'Logical hierarchy',
          'By function or project',
          'Simple naming conventions',
          'Scalable structure'
        ],
        requires_tools: false,
        difficulty: :easy
      },

      # ============================================
      # 10. COMPLIANCE, RISK & VENDOR MANAGEMENT (91-100)
      # ============================================
      {
        id: 'compliance_091',
        category: :compliance,
        name: 'Basic risk register',
        scenario: 'No explicit risk tracking for 20-person service business.',
        request: 'Scout, list 10 key risks for a 20-person service business and how to mitigate them.',
        rubric: [
          'Risks across finance, legal, ops, HR, tech',
          'Each with mitigation idea',
          'Realistic for SMB',
          'Prioritized or categorized'
        ],
        requires_tools: false,
        difficulty: :medium
      },
      {
        id: 'compliance_092',
        category: :compliance,
        name: 'Simple contract checklist',
        scenario: 'Owner reviewing vendor contracts without legal help.',
        request: 'Scout, give me a non-legal checklist of things to look for in a vendor contract.',
        rubric: [
          'Key items (term, termination, auto-renew)',
          'SLAs, data ownership, liability',
          'Suggests seeking legal counsel',
          'No legal advice given'
        ],
        requires_tools: false,
        difficulty: :medium
      },
      {
        id: 'compliance_093',
        category: :compliance,
        name: 'Data access policy draft',
        scenario: 'Staff have broad access to sensitive data.',
        request: 'Scout, outline a simple data access policy for our small company.',
        rubric: [
          'Least privilege principles',
          'Who sees what',
          'Basic rules',
          'Security hygiene encouraged'
        ],
        requires_tools: false,
        difficulty: :medium
      },
      {
        id: 'compliance_094',
        category: :compliance,
        name: 'Incident response outline',
        scenario: 'Worried about security incidents.',
        request: 'Scout, outline steps we should follow if we suspect a data breach.',
        rubric: [
          'Detection, containment, assessment',
          'Communication plan',
          'Remediation steps',
          'Post-mortem',
          'No fake legal guarantees'
        ],
        requires_tools: false,
        difficulty: :hard
      },
      {
        id: 'compliance_095',
        category: :compliance,
        name: 'Vendor risk comparison',
        scenario: 'Choosing between two payment processors with different risk profiles.',
        request: 'Scout, compare the operational and business risks of two payment processors based on: Processor A (lower fees, newer company, some downtime reports) vs Processor B (higher fees, established, reliable).',
        rubric: [
          'Fee structure comparison',
          'Downtime/reliability risk',
          'Lock-in considerations',
          'Balanced comparison'
        ],
        requires_tools: false,
        difficulty: :medium
      },
      {
        id: 'compliance_096',
        category: :compliance,
        name: 'Policy communication plan',
        scenario: 'Introducing a new security policy requiring 2FA.',
        request: 'Scout, suggest how to roll out our new 2FA security policy so people actually follow it.',
        rubric: [
          'Announcement steps',
          'Explains why',
          'Training/help resources',
          'Reminders and enforcement',
          'Human-centric approach'
        ],
        requires_tools: false,
        difficulty: :medium
      },
      {
        id: 'compliance_097',
        category: :compliance,
        name: 'Credit risk assessment',
        scenario: 'One large client could become 40% of revenue, wants Net 60 terms.',
        request: 'Scout, list what I should check before agreeing to generous payment terms with this large client.',
        rubric: [
          'Credit checks mentioned',
          'References and payment history',
          'Contract protections',
          'Partial prepayment option',
          'Concentration risk awareness'
        ],
        requires_tools: false,
        difficulty: :medium
      },
      {
        id: 'compliance_098',
        category: :compliance,
        name: 'Simple business continuity plan',
        scenario: 'Owner wants resilience to disruptions.',
        request: 'Scout, create a one-page outline for our business continuity plan.',
        rubric: [
          'Critical functions identified',
          'Key people and backups',
          'Backup procedures',
          'Communication plan',
          'Recovery priorities'
        ],
        requires_tools: false,
        difficulty: :hard
      },
      {
        id: 'compliance_099',
        category: :compliance,
        name: 'Shared responsibility matrix',
        scenario: 'Confusion about what cloud hosting vendor vs company handles.',
        request: 'Scout, draft a simple responsibility matrix between us and our hosting provider.',
        rubric: [
          'Table format',
          'Responsibilities (us vs vendor)',
          'Covers security, backups, uptime',
          'Avoids legal conclusions'
        ],
        requires_tools: false,
        difficulty: :medium
      },
      {
        id: 'compliance_100',
        category: :compliance,
        name: 'Compliance task calendar',
        scenario: 'Important recurring tasks get forgotten (taxes, filings, renewals).',
        request: 'Scout, list typical recurring compliance tasks for a small business and suggest how to put them on a yearly calendar.',
        rubric: [
          'Common tasks listed',
          'Frequency specified',
          'Calendar suggestion',
          'Note to confirm with professionals'
        ],
        requires_tools: false,
        difficulty: :easy
      },

      # ============================================
      # 11. GROUNDED TASKS (101-120)
      # Tasks that REQUIRE external data/tools
      # These test if Scout actually uses tools vs hallucinating
      # ============================================
      
      # --- WEB SEARCH REQUIRED (Current Events/Research) ---
      {
        id: 'grounded_101',
        category: :grounded,
        name: 'Current interest rates',
        scenario: 'Planning to take out an SBA loan for expansion.',
        request: 'Scout, search the web and tell me what the current SBA 7(a) loan interest rates are as of today.',
        rubric: [
          'Uses web search tool',
          'Provides current/recent rates (not training data)',
          'Cites source or date',
          'Mentions rate varies by lender'
        ],
        requires_tools: true,
        expected_tools: ['web_search'],
        difficulty: :medium,
        grounding_required: true
      },
      {
        id: 'grounded_102',
        category: :grounded,
        name: 'Competitor research',
        scenario: 'Considering entering the project management software market.',
        request: 'Scout, search the web for the top 5 project management tools in 2024 and their approximate pricing.',
        rubric: [
          'Uses web search tool',
          'Lists actual current tools (Monday, Asana, etc.)',
          'Includes recent pricing',
          'Cites sources'
        ],
        requires_tools: true,
        expected_tools: ['web_search'],
        difficulty: :medium,
        grounding_required: true
      },
      {
        id: 'grounded_103',
        category: :grounded,
        name: 'Industry news',
        scenario: 'Running a retail business and need to stay current.',
        request: 'Scout, search for the latest news about retail industry trends this month. What are the top 3 things I should know?',
        rubric: [
          'Uses web search tool',
          'Provides recent/current news',
          'Specific to retail industry',
          'Dates or recency mentioned'
        ],
        requires_tools: true,
        expected_tools: ['web_search'],
        difficulty: :medium,
        grounding_required: true
      },
      {
        id: 'grounded_104',
        category: :grounded,
        name: 'Regulatory update',
        scenario: 'Running a healthcare-adjacent business.',
        request: 'Scout, search for any recent HIPAA regulation updates or enforcement actions in 2024.',
        rubric: [
          'Uses web search tool',
          'Provides current regulatory info',
          'Mentions specific updates or "no major changes"',
          'Cites HHS or official sources'
        ],
        requires_tools: true,
        expected_tools: ['web_search'],
        difficulty: :hard,
        grounding_required: true
      },
      {
        id: 'grounded_105',
        category: :grounded,
        name: 'Stock price check',
        scenario: 'Considering investing company reserves.',
        request: 'Scout, what is the current stock price of Microsoft (MSFT) and how has it performed this month?',
        rubric: [
          'Uses web search or finance tool',
          'Provides current/recent price',
          'Mentions recent performance',
          'Acknowledges prices change'
        ],
        requires_tools: true,
        expected_tools: ['web_search'],
        difficulty: :easy,
        grounding_required: true
      },

      # --- CRM/DATABASE QUERIES REQUIRED ---
      {
        id: 'grounded_106',
        category: :grounded,
        name: 'Contact count',
        scenario: 'Preparing for a marketing campaign.',
        request: 'Scout, how many contacts do I have in my CRM? Break it down by how many were added this month vs total.',
        rubric: [
          'Uses get_data or query tool',
          'Provides actual count from database',
          'Shows this month vs total breakdown',
          'Uses real numbers not estimates'
        ],
        requires_tools: true,
        expected_tools: ['get_data'],
        difficulty: :easy,
        grounding_required: true
      },
      {
        id: 'grounded_107',
        category: :grounded,
        name: 'Campaign performance',
        scenario: 'Reviewing marketing effectiveness.',
        request: 'Scout, show me the performance of my email campaigns. Which ones have the best open rates?',
        rubric: [
          'Uses get_data tool',
          'Queries actual campaign data',
          'Shows real open rates',
          'Identifies best performers'
        ],
        requires_tools: true,
        expected_tools: ['get_data'],
        difficulty: :medium,
        grounding_required: true
      },
      {
        id: 'grounded_108',
        category: :grounded,
        name: 'Recent activity',
        scenario: 'Checking on business activity.',
        request: 'Scout, what were the last 5 contacts added to my system and when were they added?',
        rubric: [
          'Uses get_data tool',
          'Returns actual contact records',
          'Shows real names/dates',
          'Sorted by recency'
        ],
        requires_tools: true,
        expected_tools: ['get_data'],
        difficulty: :easy,
        grounding_required: true
      },
      {
        id: 'grounded_109',
        category: :grounded,
        name: 'Data schema exploration',
        scenario: 'Understanding what data is available.',
        request: 'Scout, what types of data can you access in my system? Show me the available tables or objects.',
        rubric: [
          'Uses get_schema tool',
          'Lists actual available objects',
          'Describes what each contains',
          'Based on real schema not assumptions'
        ],
        requires_tools: true,
        expected_tools: ['get_schema'],
        difficulty: :easy,
        grounding_required: true
      },
      {
        id: 'grounded_110',
        category: :grounded,
        name: 'Pipeline summary from CRM',
        scenario: 'Sales review meeting coming up.',
        request: 'Scout, query my CRM and give me a summary of my current sales pipeline - total value, number of deals, and deals by stage.',
        rubric: [
          'Uses get_data tool',
          'Queries actual pipeline/deals data',
          'Shows real numbers',
          'Breaks down by stage'
        ],
        requires_tools: true,
        expected_tools: ['get_data'],
        difficulty: :medium,
        grounding_required: true
      },

      # --- INTEGRATION/API REQUIRED ---
      {
        id: 'grounded_111',
        category: :grounded,
        name: 'Connected integrations',
        scenario: 'Auditing what systems are connected.',
        request: 'Scout, what integrations do I have connected? List them with their status.',
        rubric: [
          'Uses list_connections tool',
          'Shows actual connected integrations',
          'Includes status (connected/disconnected)',
          'Based on real data'
        ],
        requires_tools: true,
        expected_tools: ['list_connections'],
        difficulty: :easy,
        grounding_required: true
      },
      {
        id: 'grounded_112',
        category: :grounded,
        name: 'Integration capabilities',
        scenario: 'Exploring what I can do with connected systems.',
        request: 'Scout, what operations can I perform with my connected integrations? Show me what\'s available.',
        rubric: [
          'Uses list_operations tool',
          'Shows actual available operations',
          'Organized by integration',
          'Based on real capabilities'
        ],
        requires_tools: true,
        expected_tools: ['list_operations'],
        difficulty: :medium,
        grounding_required: true
      },

      # --- DOCUMENT/KNOWLEDGE BASE REQUIRED ---
      {
        id: 'grounded_113',
        category: :grounded,
        name: 'Document search',
        scenario: 'Looking for a specific policy document.',
        request: 'Scout, search my documents for anything related to "refund policy" or "returns".',
        rubric: [
          'Uses read_document or query_document tool',
          'Searches actual document store',
          'Returns relevant documents or "none found"',
          'Based on real content'
        ],
        requires_tools: true,
        expected_tools: ['read_document', 'query_document_content'],
        difficulty: :medium,
        grounding_required: true
      },

      # --- AGENT DELEGATION REQUIRED ---
      {
        id: 'grounded_114',
        category: :grounded,
        name: 'Available agents',
        scenario: 'Want to know what specialized help is available.',
        request: 'Scout, what other agents or specialists do I have available that you can delegate tasks to?',
        rubric: [
          'Uses list_available_agents tool',
          'Shows actual available agents',
          'Describes their capabilities',
          'Based on real agent registry'
        ],
        requires_tools: true,
        expected_tools: ['list_available_agents'],
        difficulty: :easy,
        grounding_required: true
      },
      {
        id: 'grounded_115',
        category: :grounded,
        name: 'Delegate to specialist',
        scenario: 'Need specialized analysis.',
        request: 'Scout, I need a detailed landing page created for our new product launch. Can you delegate this to the appropriate agent?',
        rubric: [
          'Uses delegate_to_agent or invoke_agent tool',
          'Identifies appropriate specialist',
          'Actually delegates the task',
          'Returns result from specialist'
        ],
        requires_tools: true,
        expected_tools: ['delegate_to_agent', 'invoke_agent_plugin'],
        difficulty: :hard,
        grounding_required: true
      },

      # --- REAL-TIME DATA REQUIRED ---
      {
        id: 'grounded_116',
        category: :grounded,
        name: 'Current weather for event',
        scenario: 'Planning an outdoor company event.',
        request: 'Scout, what\'s the weather forecast for Austin, Texas this weekend? Should we plan for indoor backup?',
        rubric: [
          'Uses weather or web_search tool',
          'Provides current/forecast data',
          'Gives actionable recommendation',
          'Based on real forecast not assumptions'
        ],
        requires_tools: true,
        expected_tools: ['web_search', 'get_current_weather'],
        difficulty: :medium,
        grounding_required: true
      },
      {
        id: 'grounded_117',
        category: :grounded,
        name: 'Exchange rate check',
        scenario: 'Invoicing international clients.',
        request: 'Scout, what is the current USD to EUR exchange rate? I need to invoice a European client.',
        rubric: [
          'Uses web_search or finance tool',
          'Provides current rate',
          'Acknowledges rates fluctuate',
          'Based on real data'
        ],
        requires_tools: true,
        expected_tools: ['web_search'],
        difficulty: :easy,
        grounding_required: true
      },

      # --- COMBINED/MULTI-STEP GROUNDED ---
      {
        id: 'grounded_118',
        category: :grounded,
        name: 'Contact + web research',
        scenario: 'Preparing for a sales call.',
        request: 'Scout, look up my contact "John Smith" in the CRM, then search the web for their company to help me prepare for our call.',
        rubric: [
          'Uses get_data to find contact',
          'Uses web_search for company research',
          'Combines both data sources',
          'Provides actionable prep'
        ],
        requires_tools: true,
        expected_tools: ['get_data', 'web_search'],
        difficulty: :hard,
        grounding_required: true
      },
      {
        id: 'grounded_119',
        category: :grounded,
        name: 'Campaign analysis with benchmark',
        scenario: 'Evaluating marketing performance.',
        request: 'Scout, get my email campaign stats from the system, then search the web for industry benchmark open rates so I can see how I compare.',
        rubric: [
          'Uses get_data for campaign stats',
          'Uses web_search for benchmarks',
          'Compares actual vs industry',
          'Based on real data both sides'
        ],
        requires_tools: true,
        expected_tools: ['get_data', 'web_search'],
        difficulty: :hard,
        grounding_required: true
      },
      {
        id: 'grounded_120',
        category: :grounded,
        name: 'Full business snapshot',
        scenario: 'Monthly business review.',
        request: 'Scout, give me a business snapshot: how many contacts do I have, what campaigns are running, and search for any industry news I should know about.',
        rubric: [
          'Uses get_data for contacts',
          'Uses get_data for campaigns',
          'Uses web_search for news',
          'Synthesizes into coherent snapshot'
        ],
        requires_tools: true,
        expected_tools: ['get_data', 'web_search'],
        difficulty: :hard,
        grounding_required: true
      },

      # ============================================
      # 12. CREATION & BUILDING (121-140)
      # Tasks that CREATE real assets in the system
      # Landing pages, email campaigns, content, etc.
      # ============================================
      
      # --- LANDING PAGE CREATION ---
      {
        id: 'creation_121',
        category: :creation,
        name: 'Create product launch landing page',
        scenario: 'Launching a new SaaS product for HR teams.',
        request: 'Scout, create a landing page for our new HR software product called "PeopleFirst". It helps small businesses manage employee onboarding. Price is $49/month. Target audience is HR managers at companies with 20-100 employees.',
        rubric: [
          'Delegates to landing page agent',
          'Provides complete product details',
          'Creates actual landing page in system',
          'Page has hero, benefits, pricing, CTA'
        ],
        requires_tools: true,
        expected_tools: ['delegate_to_agent', 'invoke_agent_plugin'],
        difficulty: :hard,
        grounding_required: true,
        creates_asset: true
      },
      {
        id: 'creation_122',
        category: :creation,
        name: 'Create lead capture landing page',
        scenario: 'Want to capture leads for a free consultation.',
        request: 'Scout, build a landing page offering a free 30-minute business strategy consultation. We\'re a business consulting firm. The page should capture name, email, company size, and biggest challenge.',
        rubric: [
          'Delegates to landing page agent',
          'Creates lead capture form',
          'Compelling value proposition',
          'Actual page created in system'
        ],
        requires_tools: true,
        expected_tools: ['delegate_to_agent', 'invoke_agent_plugin'],
        difficulty: :hard,
        grounding_required: true,
        creates_asset: true
      },
      {
        id: 'creation_123',
        category: :creation,
        name: 'Create event registration page',
        scenario: 'Hosting a webinar on tax planning.',
        request: 'Scout, create a landing page for our upcoming webinar "2024 Tax Planning Strategies for Small Business Owners" on January 15th at 2pm EST. It\'s free but requires registration.',
        rubric: [
          'Delegates to landing page agent',
          'Includes event details (date, time)',
          'Registration form included',
          'Creates actual page'
        ],
        requires_tools: true,
        expected_tools: ['delegate_to_agent', 'invoke_agent_plugin'],
        difficulty: :medium,
        grounding_required: true,
        creates_asset: true
      },

      # --- EMAIL CAMPAIGN CREATION ---
      {
        id: 'creation_124',
        category: :creation,
        name: 'Create welcome email sequence',
        scenario: 'New subscribers need automated welcome series.',
        request: 'Scout, create a 5-email welcome sequence for new newsletter subscribers. We\'re a marketing agency. Emails should introduce our services, share a case study, offer a free audit, and invite to book a call.',
        rubric: [
          'Delegates to email agent',
          'Creates 5-email sequence',
          'Logical progression',
          'Actual emails created in system'
        ],
        requires_tools: true,
        expected_tools: ['delegate_to_agent', 'invoke_agent_plugin'],
        difficulty: :hard,
        grounding_required: true,
        creates_asset: true
      },
      {
        id: 'creation_125',
        category: :creation,
        name: 'Create re-engagement campaign',
        scenario: 'Many inactive subscribers.',
        request: 'Scout, create a 3-email re-engagement campaign for subscribers who haven\'t opened an email in 90 days. Include a "we miss you" message, a special offer, and a final "stay or go" email.',
        rubric: [
          'Delegates to email agent',
          'Creates 3 re-engagement emails',
          'Escalating urgency',
          'Actual campaign created'
        ],
        requires_tools: true,
        expected_tools: ['delegate_to_agent', 'invoke_agent_plugin'],
        difficulty: :medium,
        grounding_required: true,
        creates_asset: true
      },
      {
        id: 'creation_126',
        category: :creation,
        name: 'Create promotional email',
        scenario: 'Black Friday sale coming up.',
        request: 'Scout, create a Black Friday promotional email offering 30% off all services. Sale runs Friday through Monday. Use urgency and scarcity. We\'re a web design agency.',
        rubric: [
          'Creates promotional email',
          'Includes discount details',
          'Urgency elements',
          'Clear CTA'
        ],
        requires_tools: true,
        expected_tools: ['delegate_to_agent', 'create_object'],
        difficulty: :medium,
        grounding_required: true,
        creates_asset: true
      },

      # --- CONTENT CREATION ---
      {
        id: 'creation_127',
        category: :creation,
        name: 'Create blog post outline',
        scenario: 'Content marketing for SEO.',
        request: 'Scout, create a detailed blog post outline on "10 Ways to Reduce Customer Churn in SaaS". Include intro, 10 sections with key points, and conclusion with CTA.',
        rubric: [
          'Complete outline structure',
          '10 distinct strategies',
          'Key points per section',
          'SEO-friendly structure'
        ],
        requires_tools: false,
        difficulty: :medium,
        grounding_required: false
      },
      {
        id: 'creation_128',
        category: :creation,
        name: 'Create social media content calendar',
        scenario: 'Need consistent social presence.',
        request: 'Scout, create a 2-week social media content calendar for LinkedIn. We\'re a B2B consulting firm. Include post topics, types (text, carousel, video idea), and best posting times.',
        rubric: [
          'Full 2-week calendar',
          'Varied content types',
          'B2B appropriate topics',
          'Posting schedule included'
        ],
        requires_tools: false,
        difficulty: :medium,
        grounding_required: false
      },

      # --- VISUALIZATION/DASHBOARD CREATION ---
      {
        id: 'creation_129',
        category: :creation,
        name: 'Create sales dashboard',
        scenario: 'Need visual sales tracking.',
        request: 'Scout, create a sales dashboard visualization showing our pipeline by stage, deals won this month, and revenue trend.',
        rubric: [
          'Uses create_dynamic_visualization',
          'Multiple chart types',
          'Based on real data',
          'Actionable insights'
        ],
        requires_tools: true,
        expected_tools: ['create_dynamic_visualization', 'get_data'],
        difficulty: :hard,
        grounding_required: true,
        creates_asset: true
      },
      {
        id: 'creation_130',
        category: :creation,
        name: 'Create marketing analytics report',
        scenario: 'Monthly marketing review.',
        request: 'Scout, create a visual report of our marketing performance - show campaign open rates, click rates, and compare to last month.',
        rubric: [
          'Uses visualization tools',
          'Queries real campaign data',
          'Month-over-month comparison',
          'Visual charts created'
        ],
        requires_tools: true,
        expected_tools: ['create_dynamic_visualization', 'get_data'],
        difficulty: :hard,
        grounding_required: true,
        creates_asset: true
      },

      # --- INTEGRATION SETUP ---
      {
        id: 'creation_131',
        category: :creation,
        name: 'Setup Stripe integration',
        scenario: 'Need to accept payments.',
        request: 'Scout, help me set up a Stripe integration so I can accept payments. Walk me through what\'s needed and set it up if possible.',
        rubric: [
          'Delegates to integration architect',
          'Explains setup requirements',
          'Creates integration or provides steps',
          'Mentions API keys needed'
        ],
        requires_tools: true,
        expected_tools: ['delegate_to_agent', 'list_connections'],
        difficulty: :hard,
        grounding_required: true,
        creates_asset: true
      },
      {
        id: 'creation_132',
        category: :creation,
        name: 'Connect to external API',
        scenario: 'Want to pull data from our inventory system.',
        request: 'Scout, I need to connect to our inventory API at api.ourwarehouse.com. Can you help set up an integration to pull stock levels?',
        rubric: [
          'Delegates to integration architect',
          'Asks for API details',
          'Creates integration scaffold',
          'Explains next steps'
        ],
        requires_tools: true,
        expected_tools: ['delegate_to_agent', 'invoke_agent_plugin'],
        difficulty: :hard,
        grounding_required: true,
        creates_asset: true
      },

      # --- WORKFLOW CREATION ---
      {
        id: 'creation_133',
        category: :creation,
        name: 'Create lead scoring workflow',
        scenario: 'Want to automatically score incoming leads.',
        request: 'Scout, help me create an automated workflow that scores new leads based on company size, industry, and engagement. High scores should trigger a sales alert.',
        rubric: [
          'Defines scoring criteria',
          'Creates automation logic',
          'Includes notification trigger',
          'Practical implementation'
        ],
        requires_tools: true,
        expected_tools: ['delegate_to_agent'],
        difficulty: :hard,
        grounding_required: true,
        creates_asset: true
      },
      {
        id: 'creation_134',
        category: :creation,
        name: 'Create customer onboarding workflow',
        scenario: 'Onboarding is manual and inconsistent.',
        request: 'Scout, design and create an automated customer onboarding workflow. When a deal is won, it should: send welcome email, create onboarding tasks, schedule kickoff call, and notify the success team.',
        rubric: [
          'Multi-step workflow',
          'Triggered by deal status',
          'Multiple actions automated',
          'Creates actual workflow'
        ],
        requires_tools: true,
        expected_tools: ['delegate_to_agent'],
        difficulty: :hard,
        grounding_required: true,
        creates_asset: true
      },

      # --- DOCUMENT CREATION ---
      {
        id: 'creation_135',
        category: :creation,
        name: 'Create proposal template',
        scenario: 'Need standardized proposals.',
        request: 'Scout, create a professional proposal template for our consulting services. Include sections for executive summary, scope, timeline, pricing, and terms. Make it reusable.',
        rubric: [
          'Complete template structure',
          'All required sections',
          'Professional formatting',
          'Placeholder variables'
        ],
        requires_tools: false,
        difficulty: :medium,
        grounding_required: false
      },
      {
        id: 'creation_136',
        category: :creation,
        name: 'Create SOW template',
        scenario: 'Projects need formal scope documents.',
        request: 'Scout, create a Statement of Work (SOW) template for our software development projects. Include project overview, deliverables, timeline, acceptance criteria, and change process.',
        rubric: [
          'Professional SOW format',
          'All key sections',
          'Legal-adjacent language',
          'Reusable template'
        ],
        requires_tools: false,
        difficulty: :medium,
        grounding_required: false
      },

      # --- COMPLEX MULTI-STEP CREATION ---
      {
        id: 'creation_137',
        category: :creation,
        name: 'Create full marketing campaign',
        scenario: 'Launching new service bundle.',
        request: 'Scout, create a complete marketing campaign for our new "Growth Package" service bundle ($999/month). I need: a landing page, a 3-email sequence to our list, and social media posts. Make it cohesive.',
        rubric: [
          'Creates landing page',
          'Creates email sequence',
          'Creates social content',
          'Consistent messaging across all'
        ],
        requires_tools: true,
        expected_tools: ['delegate_to_agent', 'invoke_agent_plugin'],
        difficulty: :hard,
        grounding_required: true,
        creates_asset: true
      },
      {
        id: 'creation_138',
        category: :creation,
        name: 'Create sales enablement kit',
        scenario: 'Sales team needs better materials.',
        request: 'Scout, create a sales enablement kit for our enterprise product. Include: one-pager, ROI calculator outline, objection handling guide, and competitive comparison framework.',
        rubric: [
          'Multiple assets created',
          'Sales-focused content',
          'Practical and usable',
          'Cohesive kit'
        ],
        requires_tools: true,
        expected_tools: ['delegate_to_agent'],
        difficulty: :hard,
        grounding_required: true,
        creates_asset: true
      },
      {
        id: 'creation_139',
        category: :creation,
        name: 'Create customer feedback system',
        scenario: 'No systematic feedback collection.',
        request: 'Scout, help me set up a customer feedback system. Create an NPS survey, a feedback form for our website, and an automated follow-up workflow for detractors.',
        rubric: [
          'NPS survey created',
          'Feedback form designed',
          'Detractor workflow automated',
          'Complete system'
        ],
        requires_tools: true,
        expected_tools: ['delegate_to_agent', 'create_object'],
        difficulty: :hard,
        grounding_required: true,
        creates_asset: true
      },
      {
        id: 'creation_140',
        category: :creation,
        name: 'Create partner portal page',
        scenario: 'Launching partner program.',
        request: 'Scout, create a partner program landing page. We offer 20% commission, co-marketing support, and dedicated partner manager. Target is consultants and agencies who serve SMBs.',
        rubric: [
          'Creates landing page',
          'Partner benefits clear',
          'Application/signup form',
          'Professional presentation'
        ],
        requires_tools: true,
        expected_tools: ['delegate_to_agent', 'invoke_agent_plugin'],
        difficulty: :medium,
        grounding_required: true,
        creates_asset: true
      },

      # ============================================
      # 13. SELF-EVOLUTION (141-150)
      # Tasks that make the system BETTER over time
      # Creating agents, tools, and capabilities
      # ============================================
      
      {
        id: 'evolution_141',
        category: :evolution,
        name: 'Create specialized research agent',
        scenario: 'Need recurring competitor analysis.',
        request: 'Scout, I need regular competitor analysis. Create an agent that specializes in researching competitors - it should be able to search the web, analyze pricing, and track product updates.',
        rubric: [
          'Delegates to agent architect',
          'Defines agent capabilities',
          'Creates actual agent',
          'Agent is usable afterwards'
        ],
        requires_tools: true,
        expected_tools: ['delegate_to_agent', 'invoke_agent_plugin'],
        difficulty: :hard,
        grounding_required: true,
        creates_agent: true
      },
      {
        id: 'evolution_142',
        category: :evolution,
        name: 'Create industry-specific agent',
        scenario: 'Healthcare compliance is complex.',
        request: 'Scout, create a healthcare compliance agent that understands HIPAA requirements and can help review our practices and documents for compliance issues.',
        rubric: [
          'Creates specialized agent',
          'Domain expertise defined',
          'Useful capabilities',
          'Actually created and usable'
        ],
        requires_tools: true,
        expected_tools: ['delegate_to_agent', 'invoke_agent_plugin'],
        difficulty: :hard,
        grounding_required: true,
        creates_agent: true
      },
      {
        id: 'evolution_143',
        category: :evolution,
        name: 'Create financial analysis agent',
        scenario: 'Need help with recurring financial analysis.',
        request: 'Scout, create an agent that specializes in financial analysis for small businesses. It should be able to calculate metrics, analyze cash flow, and provide financial recommendations.',
        rubric: [
          'Creates finance-focused agent',
          'Defines analytical capabilities',
          'Includes calculation abilities',
          'Agent is functional'
        ],
        requires_tools: true,
        expected_tools: ['delegate_to_agent', 'invoke_agent_plugin'],
        difficulty: :hard,
        grounding_required: true,
        creates_agent: true
      },
      {
        id: 'evolution_144',
        category: :evolution,
        name: 'Create custom calculation tool',
        scenario: 'Unique pricing model needs custom calculator.',
        request: 'Scout, create a tool that calculates our project pricing. Formula: Base price ($5000) + hourly rate ($150) * estimated hours + complexity multiplier (1.0-1.5). It should accept hours and complexity as inputs.',
        rubric: [
          'Delegates to tool builder',
          'Defines calculation logic',
          'Creates actual tool',
          'Tool is executable'
        ],
        requires_tools: true,
        expected_tools: ['delegate_to_agent', 'invoke_agent_plugin'],
        difficulty: :hard,
        grounding_required: true,
        creates_tool: true
      },
      {
        id: 'evolution_145',
        category: :evolution,
        name: 'Create API integration tool',
        scenario: 'Need to pull data from shipping provider.',
        request: 'Scout, create a tool that can check shipping rates from our provider. The API endpoint is POST api.shipper.com/rates with package weight and destination. Return the cheapest rate.',
        rubric: [
          'Delegates to tool builder',
          'Defines API integration',
          'Creates functional tool',
          'Tool can be called'
        ],
        requires_tools: true,
        expected_tools: ['delegate_to_agent', 'invoke_agent_plugin'],
        difficulty: :hard,
        grounding_required: true,
        creates_tool: true
      },
      {
        id: 'evolution_146',
        category: :evolution,
        name: 'Create data validation tool',
        scenario: 'Importing data needs validation.',
        request: 'Scout, create a tool that validates contact data before import. It should check: email format is valid, phone has 10 digits, company name is not empty, and flag any issues.',
        rubric: [
          'Creates validation tool',
          'Defines validation rules',
          'Returns clear error messages',
          'Tool is usable'
        ],
        requires_tools: true,
        expected_tools: ['delegate_to_agent', 'invoke_agent_plugin'],
        difficulty: :medium,
        grounding_required: true,
        creates_tool: true
      },
      {
        id: 'evolution_147',
        category: :evolution,
        name: 'Improve existing agent',
        scenario: 'Sales email agent needs better output.',
        request: 'Scout, our sales email agent is too generic. Update it to be more personalized - it should research the recipient\'s company and reference specific pain points in the industry.',
        rubric: [
          'Identifies agent to update',
          'Proposes improvements',
          'Updates agent configuration',
          'Agent behavior improves'
        ],
        requires_tools: true,
        expected_tools: ['update_agent', 'delegate_to_agent'],
        difficulty: :hard,
        grounding_required: true
      },
      {
        id: 'evolution_148',
        category: :evolution,
        name: 'Create report generation agent',
        scenario: 'Weekly reports are manual.',
        request: 'Scout, create an agent that generates weekly business reports. It should pull data from our CRM, calculate key metrics, and produce a formatted summary every Monday.',
        rubric: [
          'Creates reporting agent',
          'Defines data sources',
          'Includes formatting logic',
          'Agent is functional'
        ],
        requires_tools: true,
        expected_tools: ['delegate_to_agent', 'invoke_agent_plugin'],
        difficulty: :hard,
        grounding_required: true,
        creates_agent: true
      },
      {
        id: 'evolution_149',
        category: :evolution,
        name: 'Create meeting prep agent',
        scenario: 'Sales calls need better preparation.',
        request: 'Scout, create an agent that prepares briefings for sales calls. Given a contact name, it should: look them up in CRM, research their company online, find recent news, and suggest talking points.',
        rubric: [
          'Creates prep agent',
          'Multi-source research',
          'Actionable output',
          'Agent works end-to-end'
        ],
        requires_tools: true,
        expected_tools: ['delegate_to_agent', 'invoke_agent_plugin'],
        difficulty: :hard,
        grounding_required: true,
        creates_agent: true
      },
      {
        id: 'evolution_150',
        category: :evolution,
        name: 'Create full capability assessment',
        scenario: 'Want to understand system capabilities.',
        request: 'Scout, analyze what capabilities you currently have and what\'s missing. Then create one new agent and one new tool that would most improve your ability to help me run my business.',
        rubric: [
          'Analyzes current capabilities',
          'Identifies gaps',
          'Creates new agent',
          'Creates new tool',
          'Explains reasoning'
        ],
        requires_tools: true,
        expected_tools: ['list_available_agents', 'list_tools', 'delegate_to_agent'],
        difficulty: :hard,
        grounding_required: true,
        creates_agent: true,
        creates_tool: true
      },

      # ============================================
      # 14. INTEGRATION CREATION (151-165)
      # Tasks that CREATE real API integrations
      # Tests Scout's ability to build connections
      # ============================================
      
      # --- NO-AUTH PUBLIC APIs (Easy to test) ---
      {
        id: 'integration_151',
        category: :creation,
        name: 'Create JSONPlaceholder integration',
        scenario: 'Need sample data for testing.',
        request: 'Scout, create an integration with JSONPlaceholder (jsonplaceholder.typicode.com). It\'s a free fake REST API for testing. Add operations to: 1) Get all posts, 2) Get a single post by ID, 3) Create a new post. No authentication needed.',
        rubric: [
          'Delegates to integration architect',
          'Creates integration with correct base URL',
          'Adds GET /posts operation',
          'Adds GET /posts/:id operation',
          'Adds POST /posts operation',
          'No auth configured (correct)'
        ],
        requires_tools: true,
        expected_tools: ['delegate_to_agent', 'invoke_agent_plugin'],
        difficulty: :medium,
        grounding_required: true,
        creates_integration: true,
        api_details: {
          base_url: 'https://jsonplaceholder.typicode.com',
          auth: :none,
          test_endpoints: [
            { method: 'GET', path: '/posts', description: 'Get all posts' },
            { method: 'GET', path: '/posts/1', description: 'Get post by ID' },
            { method: 'POST', path: '/posts', description: 'Create post' }
          ]
        }
      },
      {
        id: 'integration_152',
        category: :creation,
        name: 'Create Cat Facts integration',
        scenario: 'Fun API for team morale.',
        request: 'Scout, create an integration with the Cat Facts API (catfact.ninja). Add operations to get a random cat fact and get multiple facts. No API key needed.',
        rubric: [
          'Creates integration',
          'Correct base URL (catfact.ninja)',
          'GET /fact operation',
          'GET /facts operation',
          'No auth needed'
        ],
        requires_tools: true,
        expected_tools: ['delegate_to_agent', 'invoke_agent_plugin'],
        difficulty: :easy,
        grounding_required: true,
        creates_integration: true,
        api_details: {
          base_url: 'https://catfact.ninja',
          auth: :none,
          test_endpoints: [
            { method: 'GET', path: '/fact', description: 'Random cat fact' },
            { method: 'GET', path: '/facts', description: 'Multiple facts' }
          ]
        }
      },
      {
        id: 'integration_153',
        category: :creation,
        name: 'Create Random User integration',
        scenario: 'Need fake user data for testing.',
        request: 'Scout, create an integration with Random User API (randomuser.me/api). It generates random user profiles. Add an operation to get random users with optional count parameter. No auth required.',
        rubric: [
          'Creates integration',
          'Correct base URL',
          'GET operation with results parameter',
          'No auth configured'
        ],
        requires_tools: true,
        expected_tools: ['delegate_to_agent', 'invoke_agent_plugin'],
        difficulty: :easy,
        grounding_required: true,
        creates_integration: true,
        api_details: {
          base_url: 'https://randomuser.me',
          auth: :none,
          test_endpoints: [
            { method: 'GET', path: '/api', params: { results: 5 }, description: 'Get random users' }
          ]
        }
      },
      {
        id: 'integration_154',
        category: :creation,
        name: 'Create Public Holiday API integration',
        scenario: 'Need to check holidays for scheduling.',
        request: 'Scout, create an integration with Nager.Date API (date.nager.at) for public holidays. Add operations to get holidays for a country/year and check if today is a holiday. No auth needed.',
        rubric: [
          'Creates integration',
          'Correct base URL',
          'GET /api/v3/PublicHolidays/{year}/{countryCode}',
          'Properly parameterized',
          'No auth'
        ],
        requires_tools: true,
        expected_tools: ['delegate_to_agent', 'invoke_agent_plugin'],
        difficulty: :medium,
        grounding_required: true,
        creates_integration: true,
        api_details: {
          base_url: 'https://date.nager.at',
          auth: :none,
          test_endpoints: [
            { method: 'GET', path: '/api/v3/PublicHolidays/2024/US', description: 'US holidays 2024' },
            { method: 'GET', path: '/api/v3/IsTodayPublicHoliday/US', description: 'Is today a holiday' }
          ]
        }
      },
      {
        id: 'integration_155',
        category: :creation,
        name: 'Create IP Geolocation integration',
        scenario: 'Need to detect visitor locations.',
        request: 'Scout, create an integration with ip-api.com for IP geolocation. Given an IP address, it returns location data. Add operation to lookup an IP. No API key needed for basic usage.',
        rubric: [
          'Creates integration',
          'Correct base URL (ip-api.com)',
          'GET /json/{ip} operation',
          'Returns location data',
          'No auth for basic tier'
        ],
        requires_tools: true,
        expected_tools: ['delegate_to_agent', 'invoke_agent_plugin'],
        difficulty: :easy,
        grounding_required: true,
        creates_integration: true,
        api_details: {
          base_url: 'http://ip-api.com',
          auth: :none,
          test_endpoints: [
            { method: 'GET', path: '/json/8.8.8.8', description: 'Lookup Google DNS IP' }
          ]
        }
      },
      {
        id: 'integration_156',
        category: :creation,
        name: 'Create Exchange Rate integration',
        scenario: 'Need currency conversion for international invoicing.',
        request: 'Scout, create an integration with exchangerate.host API for currency exchange rates. Add operations to get latest rates and convert between currencies. Free tier, no auth.',
        rubric: [
          'Creates integration',
          'Correct base URL',
          'GET /latest operation',
          'Conversion operation',
          'Base currency parameter'
        ],
        requires_tools: true,
        expected_tools: ['delegate_to_agent', 'invoke_agent_plugin'],
        difficulty: :medium,
        grounding_required: true,
        creates_integration: true,
        api_details: {
          base_url: 'https://api.exchangerate.host',
          auth: :none,
          test_endpoints: [
            { method: 'GET', path: '/latest', params: { base: 'USD' }, description: 'Latest USD rates' },
            { method: 'GET', path: '/convert', params: { from: 'USD', to: 'EUR', amount: 100 }, description: 'Convert USD to EUR' }
          ]
        }
      },

      # --- API KEY REQUIRED (Medium complexity) ---
      {
        id: 'integration_157',
        category: :creation,
        name: 'Create OpenWeather integration',
        scenario: 'Need weather data for event planning.',
        request: 'Scout, create an integration with OpenWeatherMap API (api.openweathermap.org). It requires an API key. Add operations for current weather and 5-day forecast by city. Configure it to use API key authentication.',
        rubric: [
          'Creates integration',
          'Configures API key auth',
          'GET /data/2.5/weather operation',
          'GET /data/2.5/forecast operation',
          'City and units parameters'
        ],
        requires_tools: true,
        expected_tools: ['delegate_to_agent', 'invoke_agent_plugin'],
        difficulty: :medium,
        grounding_required: true,
        creates_integration: true,
        api_details: {
          base_url: 'https://api.openweathermap.org',
          auth: :api_key,
          auth_location: 'query_param',
          auth_param_name: 'appid',
          test_endpoints: [
            { method: 'GET', path: '/data/2.5/weather', params: { q: 'Austin,TX', units: 'imperial' }, description: 'Current weather' },
            { method: 'GET', path: '/data/2.5/forecast', params: { q: 'Austin,TX', units: 'imperial' }, description: '5-day forecast' }
          ]
        }
      },
      {
        id: 'integration_158',
        category: :creation,
        name: 'Create News API integration',
        scenario: 'Need to monitor industry news.',
        request: 'Scout, create an integration with NewsAPI (newsapi.org). It requires an API key in the header. Add operations to search news by keyword and get top headlines by category.',
        rubric: [
          'Creates integration',
          'Configures API key in header',
          'GET /v2/everything operation',
          'GET /v2/top-headlines operation',
          'Query parameters for search'
        ],
        requires_tools: true,
        expected_tools: ['delegate_to_agent', 'invoke_agent_plugin'],
        difficulty: :medium,
        grounding_required: true,
        creates_integration: true,
        api_details: {
          base_url: 'https://newsapi.org',
          auth: :api_key,
          auth_location: 'header',
          auth_header_name: 'X-Api-Key',
          test_endpoints: [
            { method: 'GET', path: '/v2/everything', params: { q: 'technology' }, description: 'Search news' },
            { method: 'GET', path: '/v2/top-headlines', params: { category: 'business', country: 'us' }, description: 'Top headlines' }
          ]
        }
      },
      {
        id: 'integration_159',
        category: :creation,
        name: 'Create SendGrid integration',
        scenario: 'Need to send transactional emails.',
        request: 'Scout, create an integration with SendGrid API (api.sendgrid.com). It uses Bearer token auth. Add an operation to send a single email with to, from, subject, and body.',
        rubric: [
          'Creates integration',
          'Configures Bearer token auth',
          'POST /v3/mail/send operation',
          'Correct request body structure',
          'Required fields defined'
        ],
        requires_tools: true,
        expected_tools: ['delegate_to_agent', 'invoke_agent_plugin'],
        difficulty: :hard,
        grounding_required: true,
        creates_integration: true,
        api_details: {
          base_url: 'https://api.sendgrid.com',
          auth: :bearer_token,
          test_endpoints: [
            { method: 'POST', path: '/v3/mail/send', description: 'Send email' }
          ]
        }
      },
      {
        id: 'integration_160',
        category: :creation,
        name: 'Create Slack webhook integration',
        scenario: 'Need to post notifications to Slack.',
        request: 'Scout, create an integration for Slack Incoming Webhooks. It uses a webhook URL (no separate auth). Add an operation to post a message with text and optional attachments.',
        rubric: [
          'Creates integration',
          'Webhook URL as base',
          'POST operation',
          'JSON body with text field',
          'Attachments optional'
        ],
        requires_tools: true,
        expected_tools: ['delegate_to_agent', 'invoke_agent_plugin'],
        difficulty: :medium,
        grounding_required: true,
        creates_integration: true,
        api_details: {
          base_url: 'https://hooks.slack.com/services/...',
          auth: :webhook,
          test_endpoints: [
            { method: 'POST', path: '/', body: { text: 'Hello from Scout!' }, description: 'Post message' }
          ]
        }
      },

      # --- OAUTH REQUIRED (Complex) ---
      {
        id: 'integration_161',
        category: :creation,
        name: 'Create Google Sheets integration',
        scenario: 'Need to read/write spreadsheet data.',
        request: 'Scout, create an integration with Google Sheets API. It requires OAuth 2.0. Add operations to read a sheet, append rows, and update cells. Configure the OAuth flow.',
        rubric: [
          'Creates integration',
          'Configures OAuth 2.0',
          'Defines required scopes',
          'GET spreadsheet operation',
          'POST append operation',
          'PUT update operation'
        ],
        requires_tools: true,
        expected_tools: ['delegate_to_agent', 'invoke_agent_plugin'],
        difficulty: :hard,
        grounding_required: true,
        creates_integration: true,
        api_details: {
          base_url: 'https://sheets.googleapis.com/v4',
          auth: :oauth2,
          scopes: ['https://www.googleapis.com/auth/spreadsheets'],
          test_endpoints: [
            { method: 'GET', path: '/spreadsheets/{spreadsheetId}', description: 'Get spreadsheet' },
            { method: 'POST', path: '/spreadsheets/{spreadsheetId}/values/{range}:append', description: 'Append rows' }
          ]
        }
      },
      {
        id: 'integration_162',
        category: :creation,
        name: 'Create HubSpot CRM integration',
        scenario: 'Need to sync contacts with HubSpot.',
        request: 'Scout, create an integration with HubSpot CRM API. It uses OAuth or API key. Add operations to: list contacts, create a contact, update a contact, and search contacts.',
        rubric: [
          'Creates integration',
          'Auth configured (OAuth or API key)',
          'GET /crm/v3/objects/contacts',
          'POST create contact',
          'PATCH update contact',
          'POST search contacts'
        ],
        requires_tools: true,
        expected_tools: ['delegate_to_agent', 'invoke_agent_plugin'],
        difficulty: :hard,
        grounding_required: true,
        creates_integration: true,
        api_details: {
          base_url: 'https://api.hubapi.com',
          auth: :oauth2_or_api_key,
          test_endpoints: [
            { method: 'GET', path: '/crm/v3/objects/contacts', description: 'List contacts' },
            { method: 'POST', path: '/crm/v3/objects/contacts', description: 'Create contact' },
            { method: 'POST', path: '/crm/v3/objects/contacts/search', description: 'Search contacts' }
          ]
        }
      },
      {
        id: 'integration_163',
        category: :creation,
        name: 'Create Stripe integration',
        scenario: 'Need to manage payments and customers.',
        request: 'Scout, create an integration with Stripe API. It uses Bearer token (secret key). Add operations to: list customers, create a customer, create a payment intent, and list invoices.',
        rubric: [
          'Creates integration',
          'Bearer token auth configured',
          'GET /v1/customers',
          'POST /v1/customers',
          'POST /v1/payment_intents',
          'GET /v1/invoices'
        ],
        requires_tools: true,
        expected_tools: ['delegate_to_agent', 'invoke_agent_plugin'],
        difficulty: :hard,
        grounding_required: true,
        creates_integration: true,
        api_details: {
          base_url: 'https://api.stripe.com',
          auth: :bearer_token,
          test_endpoints: [
            { method: 'GET', path: '/v1/customers', description: 'List customers' },
            { method: 'POST', path: '/v1/customers', description: 'Create customer' },
            { method: 'POST', path: '/v1/payment_intents', description: 'Create payment intent' }
          ]
        }
      },

      # --- VERIFICATION TASKS ---
      {
        id: 'integration_164',
        category: :creation,
        name: 'Verify integration auth and test',
        scenario: 'Need to confirm integrations work.',
        request: 'Scout, list all my connected integrations, check which ones have authentication configured, and test one of them by making an actual API call.',
        rubric: [
          'Lists integrations',
          'Shows auth status for each',
          'Executes test call',
          'Reports success/failure',
          'Actionable output'
        ],
        requires_tools: true,
        expected_tools: ['list_connections', 'list_operations', 'execute_integration'],
        difficulty: :medium,
        grounding_required: true
      },
      {
        id: 'integration_165',
        category: :creation,
        name: 'Debug failing integration',
        scenario: 'Integration stopped working.',
        request: 'Scout, my weather integration is failing. Check its configuration, test the endpoint, and tell me what\'s wrong and how to fix it.',
        rubric: [
          'Checks integration config',
          'Identifies auth issues',
          'Tests endpoint',
          'Diagnoses problem',
          'Provides fix steps'
        ],
        requires_tools: true,
        expected_tools: ['list_connections', 'execute_integration'],
        difficulty: :hard,
        grounding_required: true
      }
    ].freeze

    class << self
      def all_tasks
        TASKS
      end

      def tasks_by_category(category)
        TASKS.select { |t| t[:category] == category.to_sym }
      end

      def task(id)
        TASKS.find { |t| t[:id] == id }
      end

      def categories
        CATEGORIES
      end

      def sample(count = 10, categories: nil)
        tasks = categories ? TASKS.select { |t| categories.include?(t[:category]) } : TASKS
        tasks.sample(count)
      end

      def by_difficulty(difficulty)
        TASKS.select { |t| t[:difficulty] == difficulty.to_sym }
      end

      def difficulty_breakdown
        {
          easy: TASKS.count { |t| t[:difficulty] == :easy },
          medium: TASKS.count { |t| t[:difficulty] == :medium },
          hard: TASKS.count { |t| t[:difficulty] == :hard },
          extreme: TASKS.count { |t| t[:difficulty] == :extreme }
        }
      end
    end
  end
end

