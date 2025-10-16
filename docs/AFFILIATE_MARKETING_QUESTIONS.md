# Affiliate Marketing & Admin Panel - Requirements Questions

These questions need to be answered before implementing the affiliate marketing system.

## 1. Affiliate Program Basics

- **How do affiliates sign up?**
  - Separate registration flow?
  - Existing users can become affiliates?
  - Application/approval process?

- **Referral Links/Codes:**
  - Unique link per affiliate?
  - Custom codes allowed?
  - Where are links shared? (email, social, ads?)

- **Commission Structure:**
  - Percentage of first payment?
  - Flat fee per referral?
  - Recurring revenue share?
  - Lifetime value or first month only?

## 2. Tracking & Attribution

- **What counts as a conversion?**
  - User signup?
  - First payment?
  - Active subscription after trial?

- **Tracking Duration:**
  - Cookie duration? (30/60/90 days)
  - Last-click attribution or first-click?

- **Metrics to Track:**
  - Clicks on referral links?
  - Signups (conversions)?
  - Revenue generated?
  - Payout history?

## 3. Affiliate Dashboard (User-Facing)

What should affiliates see in their dashboard?

- [ ] Unique referral link/code
- [ ] Performance stats (clicks, conversions, earnings)
- [ ] Payout history
- [ ] Pending earnings
- [ ] Marketing materials/assets to download
- [ ] Referral leaderboard?
- [ ] Real-time notifications?

## 4. Admin Panel Features

What should admins be able to manage?

- [ ] View all affiliates and their performance
- [ ] Approve/reject affiliate applications
- [ ] Set commission rates (global or per-affiliate)
- [ ] Process payouts (manual approval, automatic, threshold-based)
- [ ] Analytics dashboard (top performers, conversion rates, revenue)
- [ ] Manage affiliate tiers/levels (Bronze, Silver, Gold?)
- [ ] Block/suspend affiliates
- [ ] Export reports (CSV, PDF)
- [ ] Send bulk communications to affiliates

## 5. Commission Structure

- **Rate Type:**
  - Percentage-based? (e.g., 20% of subscription)
  - Flat fee? (e.g., $50 per referral)
  - Hybrid?

- **Recurring vs One-Time:**
  - Lifetime recurring commissions?
  - First month only?
  - First X months?

- **Tier-Based Rates:**
  - Different rates for different subscription plans?
  - Volume-based bonuses? (e.g., 10+ referrals = higher rate)

## 6. Payout System

- **Payment Methods:**
  - PayPal?
  - Stripe Connect?
  - Manual bank transfer?
  - Store credit?

- **Payout Rules:**
  - Minimum payout threshold? ($50, $100, $200?)
  - Payment frequency? (monthly, bi-weekly, on-demand?)
  - Auto-payout or manual request?

- **Tax Handling:**
  - Collect W9/tax forms?
  - Issue 1099s?

## 7. Fraud Prevention

- **How to prevent fraud:**
  - Self-referrals blocked?
  - Cookie stuffing detection?
  - Manual review for suspicious activity?
  - Waiting period before payout? (30/60/90 days)

## 8. Marketing Materials

- **What assets should affiliates have access to:**
  - Banner ads (multiple sizes)?
  - Email templates?
  - Social media graphics?
  - Landing page templates?
  - Video demos?

---

**Next Steps:** Answer these questions, then run `/build-feature affiliate-marketing` to implement the system.
