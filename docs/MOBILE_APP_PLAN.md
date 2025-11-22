# Mobile App Plan - AMOS Platform

## Executive Summary

This document outlines the strategy for building a native mobile app (iOS & Android) for the AMOS platform, starting with a focused set of base features that deliver core value to users on-the-go.

**Target Users**: Marketers and business owners who need to manage campaigns, check analytics, and interact with the AI assistant from mobile devices.

**Timeline Philosophy**: Start with essential features, deploy MVP quickly, iterate based on user feedback.

---

## Platform Overview

The AMOS platform is a **conversational AI marketing automation system** built on:
- Rails 8 backend with PostgreSQL
- AWS Bedrock (Claude Sonnet 4.5) for AI
- RESTful API with Bearer token authentication
- Real-time features via SSE and WebSockets
- Integration ecosystem (Stripe, HubSpot, Mailgun, etc.)

---

## Mobile App Architecture

### Technology Stack

**Frontend**
- **Framework**: React Native (Cross-platform iOS/Android)
- **State Management**: Redux Toolkit
- **Real-time Communication**: WebSocket client library (for voice/streaming)
- **HTTP Client**: Axios with token interceptors
- **Local Storage**: SQLite (via Realm or SQLite for React Native)
- **Voice**:
  - iOS: Speech framework + AudioKit
  - Android: android.speech + Media frameworks
- **Push Notifications**: Firebase Cloud Messaging (FCM)

**API Communication**
- Base URL: `https://api.yourdomain.com`
- Authentication: Bearer token (user's API key)
- Headers: Standard REST with JSON
- Error Handling: Standardized error response codes
- Rate Limiting: Respect server-side limits with exponential backoff

### Data Synchronization Model

```
Local Device
├── SQLite Cache (Users, Entities, Contacts, Campaigns)
├── Session Store (Auth tokens, user preferences)
└── Offline Queue (Queued API requests)

↕ Sync Strategy

Server API
├── Contact endpoints (batch create/update)
├── Campaign endpoints (list, create, update, get_details)
├── Landing page endpoints (list, create, publish)
└── Chat/AI endpoints (streaming responses)
```

**Sync Patterns**:
- **Pull-based**: User opens campaigns tab → fetch latest from server
- **Push-based**: Server sends campaign updates via push notifications
- **Queue-based**: Offline actions queued locally, synced on reconnect

---

## Base Features (Phase 1 - MVP)

### 1. Authentication & Onboarding
**Purpose**: Get users authenticated and ready to use the app

**Features**:
- [ ] Login with email/password
- [ ] "Remember me" functionality (30-day token refresh)
- [ ] Logout
- [ ] Password reset flow
- [ ] Biometric authentication (Face ID/Touch ID) - optional flag in settings
- [ ] API key display and management in settings
- [ ] Account profile viewing (entity name, plan tier, user role)

**API Endpoints Used**:
```
POST /api/auth/login (custom endpoint or via Devise)
POST /api/auth/logout
POST /api/auth/refresh_token
GET /api/v1/users/profile
PATCH /api/v1/users/profile
```

**User Stories**:
- "As a user, I want to quickly sign in so I can check my campaigns"
- "As a busy marketer, I want biometric login so I don't have to type my password"

---

### 2. Scout AI Assistant (Simplified Chat)
**Purpose**: Access the core AI assistant on mobile

**Features**:
- [ ] Simple text input → AI response chat interface
- [ ] Message history (loaded from cache, paginated from server)
- [ ] Streaming responses with real-time text rendering
- [ ] Basic markdown formatting in responses
- [ ] Clear conversation history option
- [ ] Voice input (tap-to-record, auto-transcription via API)
- [ ] Voice output (optional: tap to hear response)
- [ ] Quick action buttons (common tasks like "create campaign", "add contacts")
- [ ] Document/image attachment support (simplified - no RAG initially)
- [ ] Response caching to reduce API calls

**API Endpoints Used**:
```
POST /scout/chat_stream (streaming responses)
POST /api/voice/sessions (voice transcription)
POST /api/tts/synthesize (text-to-speech)
GET /scout/history (pagination)
DELETE /scout/conversation (clear history)
```

**Technical Considerations**:
- Implement SSE/WebSocket streaming in React Native
- Queue non-critical responses locally
- Cache AI responses for common queries
- Graceful degradation if voice APIs unavailable

**User Stories**:
- "As a user, I want to chat with the AI assistant from my phone"
- "As a busy exec, I want to send voice messages to avoid typing"
- "As a user, I want to see my previous conversations"

---

### 3. Campaign Dashboard (Read-Only View + Quick Actions)
**Purpose**: Monitor campaigns and key metrics from mobile

**Features**:
- [ ] Campaign list with status badges (draft, scheduled, in-progress, completed)
- [ ] Campaign card showing:
  - Subject line
  - Created date
  - Status
  - Contact count
  - Open/click rates (if available)
  - Last send date
- [ ] Campaign detail view:
  - Full campaign info
  - Email template preview
  - Contact group details
  - Mailgun analytics (opens, clicks, bounces)
  - Timeline of sends
- [ ] Search/filter campaigns (by status, date range)
- [ ] Pagination for large campaign lists
- [ ] Pull-to-refresh
- [ ] Quick actions:
  - View campaign details
  - Pause/resume campaign (if in-progress)
  - Duplicate campaign
  - View analytics

**API Endpoints Used**:
```
GET /api/v1/campaigns (list with filters, pagination)
GET /api/v1/campaigns/:id (campaign details)
PATCH /api/v1/campaigns/:id (pause, resume, update)
GET /api/v1/campaigns/:id/analytics (mailgun stats)
```

**Local Storage**:
- Cache campaigns list (refresh every 5 minutes)
- Cache individual campaign details (10 minute TTL)
- Invalidate on create/update

**User Stories**:
- "As a marketer, I want to check my campaign performance while traveling"
- "As a manager, I want to see campaign status without opening desktop"
- "As a user, I want to quickly pause a campaign if something goes wrong"

---

### 4. Contact Management (Import & View)
**Purpose**: Manage contacts on the go

**Features**:
- [ ] Contact list with search/filter
- [ ] Contact detail view:
  - Email
  - Status (active, inactive, unsubscribed)
  - Metadata (company, role, etc.)
  - Campaign enrollments
  - Email sequence status
- [ ] Quick contact add:
  - Add single contact via form
  - Quick email entry + optional fields
- [ ] Bulk contact import:
  - CSV paste/upload
  - Mapping UI for columns
  - Queue job, show progress
  - Duplicate detection
- [ ] Contact groups viewing and management
- [ ] Unsubscribe/reactivate contacts

**API Endpoints Used**:
```
GET /api/v1/contacts (list, pagination, search)
GET /api/v1/contacts/:id (detail)
POST /api/v1/contacts (single create)
POST /api/v1/contacts/bulk (batch create/update)
PATCH /api/v1/contacts/:id (update status)
GET /api/v1/contact_groups (list)
GET /api/v1/jobs/:id (track bulk import progress)
```

**Offline Support**:
- Cache recent contacts (last 500)
- Queue new contacts while offline
- Show "Syncing..." indicator

**User Stories**:
- "As a recruiter, I want to quickly add a contact I just met at a conference"
- "As a user, I want to import my contact list from CSV on my phone"
- "As an admin, I want to view contact status and manage subscriptions"

---

### 5. Landing Page Management
**Purpose**: Create and publish landing pages from mobile

**Features**:
- [ ] Landing page list (draft and published)
- [ ] Landing page detail view:
  - Page title/slug
  - Status (draft/published)
  - Form submissions count
  - View count
  - Creation/publish date
- [ ] Create new landing page:
  - Simple form: title, description
  - Trigger AI generation via Scout chat
  - Template selection (optional: basic templates)
- [ ] Publish/unpublish pages
- [ ] View submission list (submitted forms)
- [ ] Quick copy landing page URL
- [ ] Analytics:
  - Form submission count
  - Submission list with email, date, data

**API Endpoints Used**:
```
GET /api/v1/landing_pages (list)
GET /api/v1/landing_pages/:id (detail)
POST /api/v1/landing_pages (create)
PATCH /api/v1/landing_pages/:id (publish/unpublish)
GET /api/v1/landing_page_submissions (list for a page)
POST /api/v1/landing_page_submissions/:id/process (save submission)
```

**User Stories**:
- "As a marketer, I want to create a landing page while away from my desk"
- "As a user, I want to see form submissions in real-time"
- "As a content creator, I want to quickly publish a page"

---

### 6. Push Notifications & Real-time Updates
**Purpose**: Keep users informed of important events

**Features**:
- [ ] Push notification settings:
  - Campaign status changes
  - Form submissions on landing pages
  - Important AI responses (pinged tasks)
  - Scheduled reminder for pending campaigns
- [ ] In-app notification center:
  - View recent notifications
  - Mark as read
  - Notification history
- [ ] Deep linking from notifications:
  - Notification → Campaign detail
  - Notification → Landing page submissions
  - Notification → AI chat context

**Implementation**:
- Firebase Cloud Messaging (FCM) for delivery
- Custom notification preferences per entity
- Backend sends notifications via FCM API
- App handles deep links on launch

**API Endpoints**:
```
POST /api/v1/push_tokens (register device token)
DELETE /api/v1/push_tokens/:token_id (deregister)
PATCH /api/v1/notification_preferences (update settings)
GET /api/v1/notifications (notification history)
```

**User Stories**:
- "As a busy marketer, I want to know immediately when a campaign sends"
- "As a user, I want to be notified of form submissions in real-time"

---

### 7. Settings & Account Management
**Purpose**: Configure app behavior and account

**Features**:
- [ ] App preferences:
  - Theme (light/dark)
  - Font size
  - Biometric auth toggle
  - Auto-refresh interval
  - Push notification categories
- [ ] Entity/organization view:
  - Entity name
  - Current subscription plan
  - Users in organization
- [ ] User account:
  - Name, email
  - Role/permissions
  - API key management
  - Login history (last 10 logins with timestamps)
- [ ] Help/Support:
  - Links to docs/help center
  - Contact support form
  - App version and build number
- [ ] Logout

**User Stories**:
- "As a user, I want to configure notification settings"
- "As a developer, I want to manage my API key from the app"

---

## Phase 2+ Features (Future Roadmap)

Not included in MVP but planned for future releases:

### Extended Features
- [ ] Email template editor/preview on mobile
- [ ] Advanced campaign creation wizard in app
- [ ] Social media integration (Facebook, Instagram, LinkedIn)
- [ ] Document management (view/tag documents)
- [ ] Affiliate program dashboard
- [ ] Integration configuration (OAuth flows)
- [ ] Advanced analytics/charts
- [ ] A/B testing results
- [ ] Email preview in multiple clients
- [ ] Offline mode (full sync strategy)
- [ ] Collaboration features (comments, mentions)

### Technical Enhancements
- [ ] Offline-first architecture
- [ ] End-to-end encryption for sensitive data
- [ ] Advanced caching strategies
- [ ] Progressive Web App (PWA) version
- [ ] Tablet optimization (iPad/Android tablet layouts)
- [ ] Accessibility improvements (WCAG 2.1 AA)
- [ ] Performance monitoring and crash reporting
- [ ] A/B testing of mobile UX

---

## Technical Specifications

### API Requirements

**Authentication Flow**:
```javascript
// 1. User login (credentials → API key)
POST /api/auth/login
{
  "email": "user@example.com",
  "password": "password123"
}
// Response: { api_key, user, entity, token_expiry }

// 2. Store API key locally and use as Bearer token
Authorization: Bearer {api_key}

// 3. Refresh token if near expiry
POST /api/auth/refresh_token
Authorization: Bearer {old_api_key}
```

**Error Handling**:
```javascript
{
  "error": true,
  "message": "Campaign not found",
  "code": "CAMPAIGN_NOT_FOUND",
  "status": 404
}
```

**Rate Limiting**:
- Implement exponential backoff (2s, 4s, 8s, 16s)
- Local queue for offline requests
- Status badge showing sync status

### Device Requirements

**Minimum Specs**:
- **iOS**: 13.0+ (covers ~95% of users)
- **Android**: 7.0+ (API 24+)
- **Screen Sizes**: 4.5" to 6.7" phones, tablets (8"+ iPads)

**Connectivity**:
- Offline capability for cached data
- Graceful handling of poor network conditions
- Automatic reconnection and sync

---

## Development Approach

### Folder Structure
```
mobile-app/
├── src/
│   ├── screens/
│   │   ├── auth/
│   │   │   ├── LoginScreen.tsx
│   │   │   ├── OnboardingScreen.tsx
│   │   │   └── ForgotPasswordScreen.tsx
│   │   ├── chat/
│   │   │   ├── ChatScreen.tsx
│   │   │   └── VoiceInputModal.tsx
│   │   ├── campaigns/
│   │   │   ├── CampaignListScreen.tsx
│   │   │   ├── CampaignDetailScreen.tsx
│   │   │   └── CampaignCreateScreen.tsx
│   │   ├── contacts/
│   │   ├── landing-pages/
│   │   └── settings/
│   ├── components/
│   │   ├── common/
│   │   ├── campaign/
│   │   ├── contact/
│   │   └── landing-page/
│   ├── services/
│   │   ├── api.ts (Axios instance)
│   │   ├── auth.ts
│   │   ├── campaigns.ts
│   │   ├── contacts.ts
│   │   ├── landing-pages.ts
│   │   └── voice.ts
│   ├── store/
│   │   ├── authSlice.ts
│   │   ├── campaignsSlice.ts
│   │   ├── contactsSlice.ts
│   │   └── uiSlice.ts
│   ├── utils/
│   │   ├── formatters.ts
│   │   ├── validators.ts
│   │   └── storage.ts
│   └── types/
│       └── index.ts
├── __tests__/
├── app.json
├── package.json
└── README.md
```

### Development Phases

**Phase 1 (Weeks 1-4): Core Infrastructure**
1. Project setup (React Native + TypeScript + Redux)
2. Navigation structure (React Navigation)
3. API client with auth
4. Login/logout flows
5. Basic error handling

**Phase 2 (Weeks 5-8): Scout Chat**
6. Chat screen with text input
7. Message history (pagination)
8. Streaming response handling
9. Voice input (basic)
10. Quick action buttons

**Phase 3 (Weeks 9-12): Campaigns Dashboard**
11. Campaign list with status badges
12. Campaign detail view with analytics
13. Search/filter/pagination
14. Quick actions (pause/resume)
15. Pull-to-refresh

**Phase 4 (Weeks 13-16): Contact Management**
16. Contact list and detail views
17. Single contact creation
18. Bulk contact import
19. Contact group management
20. Offline contact queueing

**Phase 5 (Weeks 17-20): Landing Pages + Settings**
21. Landing page list and creation
22. Page publishing/unpublishing
23. Submission tracking
24. Settings and preferences
25. Push notification setup

**Phase 6 (Weeks 21+): Polish & Optimization**
26. Performance optimization
27. Accessibility improvements
28. Comprehensive testing
29. App store submission
30. Launch and monitoring

---

## Success Metrics

### Adoption
- [ ] Downloads by app store tier
- [ ] Daily/monthly active users
- [ ] User retention (Day 7, Day 30)

### Engagement
- [ ] Average session length
- [ ] Feature usage (campaigns viewed, contacts added, etc.)
- [ ] Chat message frequency
- [ ] Voice input adoption

### Quality
- [ ] Crash rate < 0.1%
- [ ] Average app rating > 4.5 stars
- [ ] Support ticket volume for app
- [ ] API performance (P95 < 500ms)

### Business
- [ ] % of users on mobile vs web
- [ ] Mobile-driven campaign creation
- [ ] Contact imports via mobile
- [ ] LTV for mobile vs web users

---

## MVP Acceptance Criteria

**Must-Have Features**:
✓ User authentication (email/password + API key management)
✓ Scout chat with text and voice input
✓ Campaign list with filtering and detail view
✓ Contact list and creation
✓ Landing page list and viewing
✓ Push notifications for key events
✓ Settings and account management
✓ Offline caching for campaigns/contacts
✓ iOS and Android release (beta)

**Quality Gates**:
✓ Test coverage > 60%
✓ Crash rate < 1% (beta)
✓ API response time < 2s (95th percentile)
✓ Bundle size < 50MB
✓ Battery/memory usage acceptable (< 10% per hour)

---

## Risks & Mitigation

| Risk | Impact | Mitigation |
|------|--------|-----------|
| Streaming SSE on mobile | Medium | Test early, use WebSocket as fallback |
| Voice API reliability | Medium | Implement fallback to text input, queue offline |
| App store approval delays | Low | Submit 2-3 weeks before target launch |
| User adoption | High | Beta program with key customers, feedback loops |
| API rate limiting | Low | Implement local caching and request queuing |
| Offline sync complexity | Medium | Start with read-only offline, expand later |

---

## Key Dependencies

**Infrastructure**:
- Stable API endpoints with appropriate mobile rate limits
- Firebase Cloud Messaging (FCM) for push notifications
- Voice transcription APIs (Eleven Labs, Deepgram)

**Team**:
- React Native developer(s)
- Mobile UX/UI designer
- QA engineer (mobile testing)
- Backend engineer (API additions/updates)

**Third-party Libraries**:
- React Native
- React Navigation
- Redux Toolkit
- Axios
- Realm (local database)
- Firebase Cloud Messaging
- React Native Voice (voice input)

---

## Next Steps

1. **Get stakeholder approval** on feature set and timeline
2. **Create detailed wireframes/mockups** for each screen
3. **Set up React Native project** with CI/CD pipeline
4. **Implement authentication flow** first (gating for other features)
5. **Start Phase 1 development** with core infrastructure
6. **Plan beta release** with select users at week 8
7. **Iterate on feedback** from beta users throughout development

---

## Appendix: API Contracts (Mobile Specific)

### Pagination Example
```javascript
GET /api/v1/campaigns?page=1&per_page=20

Response:
{
  "data": [...],
  "pagination": {
    "page": 1,
    "per_page": 20,
    "total": 150,
    "total_pages": 8,
    "has_next": true,
    "has_prev": false
  }
}
```

### Streaming Response Example
```
POST /scout/chat_stream
Authorization: Bearer {api_key}
Content-Type: application/json

{
  "message": "Create a campaign for Q4 sales",
  "context": "previous_messages_ids"
}

Response (Server-Sent Events):
event: content
data: {"text": "I'll help you create..."}

event: content
data: {"text": " a Q4 sales campaign"}

event: tool_start
data: {"tool": "create_object_tool", "args": {...}}

event: tool_end
data: {"status": "success", "result": {...}}
```

### Error Response Example
```json
{
  "error": true,
  "message": "Invalid campaign state",
  "code": "INVALID_STATE",
  "status": 400,
  "details": {
    "field": "status",
    "reason": "Cannot pause a completed campaign"
  }
}
```
