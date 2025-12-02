# Amos Complete Setup & Testing Guide

## 🚀 Overview

We've successfully migrated Scout to use the Amos orchestration architecture! Here's everything you need to know to test the complete system.

## 🏗️ What We Built

### Core Architecture
- **Amos Orchestrator**: Central coordinator that manages conversations and delegates work
- **Specialized Agents**: Domain-specific workers for different tasks
- **Unified Context**: Centralized state management across all interactions
- **Response Buffer**: Intelligent message ordering and streaming
- **Job Manager**: Robust background job lifecycle management

### Specialized Agents Created
1. **Landing Page Agent** - Creates and manages landing pages
2. **Email Agent** - Handles campaigns, templates, and email operations
3. **Integration Agent** - Manages Stripe, Zapier, and other integrations
4. **Data Agent** - Import/export, cleaning, and data operations
5. **Analytics Agent** - Comprehensive reporting and analytics
6. **General Agent** - Uses Scout tools for everything else

## 📋 Setup Steps

### 1. Run Database Migration
```bash
rails db:migrate
```
This creates the `amos_jobs` table for tracking background jobs.

### 2. Start the Application
```bash
foreman start -f Procfile.dev
```
Make sure all services are running:
- Web server
- SolidQueue workers
- Redis
- Asset pipeline

### 3. Test Basic Connection
Navigate to: `http://localhost:3000/scout`

Try a simple message:
- "Hello" - Should get immediate response from Amos
- "What's my business name?" - Simple query handled directly

## 🧪 Testing All Agents

### Test 1: Landing Page Agent
```
"Create a landing page for my new product"
```
Expected:
- Amos acknowledges and delegates to Landing Page Agent
- Agent asks for product details
- Creates landing page
- Returns URL

### Test 2: Email Agent
```
"Create an email campaign for my customers"
```
Expected:
- Email Agent activated
- Asks for campaign details
- Creates draft campaign
- Confirms completion

### Test 3: Integration Agent
```
"Import my last 10 customers from Stripe"
```
Expected:
- Integration Agent checks Stripe connection
- Imports customer data
- Reports import statistics

### Test 4: Data Agent
```
"Export all my contacts to CSV"
```
Expected:
- Data Agent prepares export
- Generates CSV file
- Provides download link

### Test 5: Analytics Agent
```
"Show me a revenue dashboard for last month"
```
Expected:
- Analytics Agent gathers metrics
- Generates comprehensive report
- Displays key insights

### Test 6: General Agent
```
"Help me write a blog post about marketing"
```
Expected:
- General Agent uses Scout tools
- Generates content
- Provides helpful response

## 🛠️ Utility Commands

### Run Automated Tests
```bash
rails amos:test
```
This runs through all agent types automatically.

### Monitor Active Jobs
```bash
rails amos:monitor
```
Real-time dashboard showing all job statuses.

### Clean Up Test Data
```bash
rails amos:cleanup
```
Cancels active jobs and removes old test data.

## 📊 Architecture Benefits

### Before (Monolithic Scout)
- 2700+ line controller
- Mixed concerns everywhere
- Hard to extend
- Difficult to debug
- All logic in one place

### After (Amos Architecture)
- Clean separation of concerns
- Each agent is self-contained
- Easy to add new capabilities
- Clear debugging path
- Infinitely scalable

## 🔍 Debugging

### Check Amos Logs
```bash
tail -f log/development.log | grep -E "\[Amos\]|\[.*Agent\]"
```

### View Active Jobs
```ruby
# In rails console
Amos::JobRecord.where(status: ['queued', 'running']).each do |job|
  puts "#{job.agent_type}: #{job.status} - #{job.status_message}"
end
```

### Test Specific Agent
```ruby
# In rails console
user = User.first
entity = user.entity
orchestrator = Amos::Orchestrator.new(user, entity, SecureRandom.uuid)

# Test landing page agent
orchestrator.process_message("Create a landing page")
```

## 🚨 Common Issues & Solutions

### Issue: No response from Amos
**Solution**: Check that orchestrator is initialized in ScoutController

### Issue: Jobs not executing
**Solution**: Ensure SolidQueue workers are running in Procfile

### Issue: Agent not found errors
**Solution**: Verify all agent job files are in `app/jobs/agent_jobs/`

### Issue: Context missing in agents
**Solution**: Check that Amos passes full context in job creation

## 🎯 Next Steps

1. **Add More Agents**: Create specialized agents for:
   - SEO optimization
   - Social media management
   - Customer support
   - Content generation

2. **Enhance Existing Agents**: Add more sophisticated features:
   - A/B testing in Landing Page Agent
   - Advanced segmentation in Email Agent
   - Multi-service support in Integration Agent

3. **Improve Monitoring**: Build admin dashboard for:
   - Real-time job monitoring
   - Performance metrics
   - Error tracking
   - Usage analytics

4. **Scale Infrastructure**:
   - Deploy agents to separate workers
   - Add Redis clustering
   - Implement job priorities
   - Add retry mechanisms

## 🎉 Success Metrics

The migration is successful! You now have:
- ✅ Clean, maintainable architecture
- ✅ Easy extensibility for new features
- ✅ Robust error handling
- ✅ Scalable job processing
- ✅ Consistent user experience
- ✅ Clear separation of concerns

## 🚀 The Future

With Amos, adding new capabilities is as simple as:
1. Create a new agent class
2. Add routing logic to orchestrator
3. Deploy!

No more tangled controller code. No more mixed concerns. Just clean, focused agents doing what they do best.

**Remember**: Amos doesn't do the work, it ensures the work gets done well! 🤖✨

