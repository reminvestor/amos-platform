# AMOS Mobile Use Cases

This document tracks mobile use cases for the AMOS Mobile app. The mobile app is designed to complement the full-featured web app, focusing on quick actions and on-the-go management for small to medium-sized businesses.

## Design Principles

- **Mobile-first**: Features should be optimized for quick, on-the-go interactions
- **Complementary**: Work alongside the web app, not replace it
- **Action-oriented**: Focus on doing, not configuring
- **Voice-friendly**: Support voice input where appropriate

---

## Campaign Management

### UC-001: Check Campaign Performance
**Status**: Planned
**Priority**: High
**Description**: View real-time campaign stats (opens, clicks, bounces) while away from desk
**User Story**: "As a business owner, I want to check how my email blast is performing while I'm at a meeting"

### UC-002: Quick Launch Campaign
**Status**: Planned
**Priority**: Medium
**Description**: Launch a pre-built email campaign to a contact group with one tap
**User Story**: "As a marketer, I want to send that follow-up campaign now without opening my laptop"

### UC-003: Pause Active Campaign
**Status**: Planned
**Priority**: Medium
**Description**: Stop a running campaign immediately if something is wrong
**User Story**: "As a business owner, I need to pause that campaign immediately because I found an error"

---

## Quick Content Creation

### UC-004: Mobile Social Post
**Status**: Planned
**Priority**: High
**Description**: Draft and schedule social media posts with photos taken on-site
**User Story**: "As an event coordinator, I want to post to social while I'm at the event"

### UC-005: Voice-to-Content Note
**Status**: Partial (voice input exists)
**Priority**: High
**Description**: Voice-to-text note that gets processed by AI into draft content
**User Story**: "As a busy entrepreneur, I want to record a quick idea for content while driving"

### UC-006: Approve AI Content
**Status**: Planned
**Priority**: Medium
**Description**: Review and publish content that agents created
**User Story**: "As a content manager, I want to approve the AI-generated content from my phone"

---

## Contact & Lead Management

### UC-007: Quick Add Contact
**Status**: Planned
**Priority**: High
**Description**: Quick-add a contact after a networking event or meeting
**User Story**: "As a sales rep, I want to add this person I just met before I forget their details"

### UC-008: Update Lead Status
**Status**: Planned
**Priority**: Medium
**Description**: Update contact status or add notes immediately after a conversation
**User Story**: "As a sales rep, I want to tag this lead as hot right after our call"

### UC-009: View Email Engagement
**Status**: Planned
**Priority**: Medium
**Description**: Check who opened your last email before a follow-up call
**User Story**: "As a sales rep, I want to see who opened my last email before I call them"

---

## Task & Workflow Monitoring

### UC-010: View Agent Activity
**Status**: Implemented (Inbox screen)
**Priority**: High
**Description**: View active agent tasks and their progress
**User Story**: "As a business owner, I want to know what my AI agent is working on"

### UC-011: Answer Agent Questions
**Status**: Implemented (Inbox screen)
**Priority**: High
**Description**: Respond to clarification requests from running workflows
**User Story**: "As a manager, I need to answer this agent's question so the workflow can continue"

### UC-012: Check Task Status
**Status**: Planned
**Priority**: Medium
**Description**: View scheduled task status and results
**User Story**: "As a business owner, I want to check if that automated task completed successfully"

---

## Analytics & Insights

### UC-013: Quick Dashboard
**Status**: Planned
**Priority**: High
**Description**: Quick dashboard with key metrics (leads, conversions, revenue)
**User Story**: "As a business owner, I want to see how we're doing this week at a glance"

### UC-014: Top Performing Content
**Status**: Planned
**Priority**: Low
**Description**: See which campaigns/posts are getting the best engagement
**User Story**: "As a marketer, I want to show my boss our top performing content"

---

## Communication

### UC-015: Reply to Inquiries
**Status**: Implemented (DM Messages)
**Priority**: High
**Description**: Respond to messages from the inbox
**User Story**: "As a customer service rep, I need to reply to that customer inquiry quickly"

### UC-016: AI-Assisted Replies
**Status**: Implemented (Amos Chat)
**Priority**: High
**Description**: Use AI to help compose professional replies
**User Story**: "As a busy professional, I want to ask Amos to draft a response for me"

---

## Document & File Management

### UC-017: Quick Document Scan
**Status**: Planned
**Priority**: Medium
**Description**: Scan business cards, receipts, or documents and auto-process
**User Story**: "As a sales rep, I want to scan this business card and add them as a contact"

### UC-018: View Recent Documents
**Status**: Planned
**Priority**: Low
**Description**: Access recently uploaded or generated documents
**User Story**: "As a business owner, I want to pull up that proposal I generated earlier"

---

## Currently Implemented Features

| Feature | Screen | Status |
|---------|--------|--------|
| AI Chat (Amos) | Chat Screen | ✅ Implemented |
| Personal Notes | Notes Screen | ✅ Implemented |
| Direct Messages | DM List/Chat | ✅ Implemented |
| Agent Inbox | Inbox Screen | ✅ Implemented |
| Answer Agent Questions | Inbox Screen | ✅ Implemented |
| Tools Hub | Toolbox | ✅ Implemented |
| Settings | Profile/Settings | ✅ Implemented |
| Voice Input | Chat Screen | ✅ Implemented |
| Push Notifications | Background | ✅ Implemented |

---

## Implementation Priority

### Phase 1 - Quick Wins
- [ ] UC-007: Quick Add Contact
- [ ] UC-013: Quick Dashboard
- [ ] UC-001: Check Campaign Performance

### Phase 2 - Content Creation
- [ ] UC-004: Mobile Social Post
- [ ] UC-005: Voice-to-Content Note (enhance existing)
- [ ] UC-006: Approve AI Content

### Phase 3 - Full Campaign Management
- [ ] UC-002: Quick Launch Campaign
- [ ] UC-003: Pause Active Campaign
- [ ] UC-009: View Email Engagement

### Phase 4 - Advanced Features
- [ ] UC-017: Quick Document Scan
- [ ] UC-008: Update Lead Status
- [ ] UC-012: Check Task Status

---

## Notes

- All use cases should work offline where possible (queue actions for sync)
- Voice input should be available for all text fields
- Push notifications should alert users to time-sensitive items
- Deep links from notifications should go directly to relevant screens
