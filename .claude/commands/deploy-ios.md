---
description: Deploy the Flutter mobile app to iOS (TestFlight or App Store)
allowed-tools: Bash, Read, Glob, Grep
---

# Deploy iOS to TestFlight

You are deploying the Flutter mobile app to TestFlight. Follow these steps:

## Step 1: Analyze Recent Changes

First, get the git log since the last TestFlight deployment to understand what changed:

```bash
cd /Volumes/ExtremeSSD/agent_marketing && git log --oneline --no-merges -20 -- flutter_mobile/
```

Look at the commit messages to understand what features were added, bugs were fixed, or improvements made.

## Step 2: Generate Release Notes

Based on the git commits, generate concise "What to Test" notes for TestFlight testers. The notes should:
- Be 2-4 bullet points
- Focus on user-facing changes
- Use plain language (not technical jargon)
- Mention any new features, bug fixes, or UI changes

Example format:
```
• Added Face ID login for trusted devices
• Fixed scanner not saving business cards
• Improved chat response speed
```

## Step 3: Run the Deployment

Execute the deployment with the generated notes:

```bash
cd /Volumes/ExtremeSSD/agent_marketing/flutter_mobile && ./deploy-ios.sh --testflight --notes "YOUR_GENERATED_NOTES_HERE"
```

## Step 4: Report Results

After deployment completes, report:
- The version and build number deployed
- The release notes used
- Any errors encountered

## Prerequisites

The deployment script requires these environment variables (already configured in `.env.production` and `ios/.env`):
- `API_BASE_URL` - Production API URL
- `FASTLANE_APPLE_APPLICATION_SPECIFIC_PASSWORD` - App-specific password
- `MATCH_PASSWORD` - Fastlane Match encryption password

## Manual Override

If the user provides specific notes with their request, use those instead of auto-generating.
