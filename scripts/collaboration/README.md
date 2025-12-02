# Agent Collaboration System - Deployment Scripts

This directory contains scripts for deploying and managing the Agent Collaboration System.

## Overview

The Agent Collaboration System replaces Agent Lightning with an internal agent improvement system that includes:
- **Energy Economy**: Agents earn/spend energy based on task performance
- **Agent School**: Rehabilitation for agents that hit 0 energy
- **Collaboration Requests**: Agents can ask each other for help
- **A/B Testing**: Statistical comparison of agent variants

## Scripts

### Local Development (Docker)

```bash
# Full setup - runs migrations, initializes energy, shows status
./scripts/collaboration/setup_local.sh
```

### AWS Environments (Dev/Prod)

```bash
# Full setup - migrations + energy initialization
./scripts/collaboration/setup_aws.sh dev
./scripts/collaboration/setup_aws.sh prod

# Run migrations only
./scripts/collaboration/run_migration_aws.sh dev
./scripts/collaboration/run_migration_aws.sh prod

# Initialize energy states only
./scripts/collaboration/init_energy_aws.sh dev
./scripts/collaboration/init_energy_aws.sh prod

# Check system status
./scripts/collaboration/status_aws.sh dev
./scripts/collaboration/status_aws.sh prod
```

## Rake Tasks

The following rake tasks are available for manual operations:

```bash
# Initialize energy states for all agents
rails agent_energy:init

# Regenerate energy for all agents
rails agent_energy:regenerate

# Distribute community pool to struggling agents
rails agent_energy:distribute

# Show energy status for all agents
rails agent_energy:status

# Enroll zero-energy agents in school
rails agent_energy:enroll_struggling

# Recalibrate capability beliefs
rails agent_energy:recalibrate

# Update decision boundaries
rails agent_energy:update_boundaries

# Show collaboration statistics
rails agent_energy:collab_stats

# Show school statistics
rails agent_energy:school_stats
```

## Dashboards

After deployment, access the dashboards at:

### Local Development
- User Dashboard: http://localhost:3000/dashboard/energy
- Admin Dashboard: http://localhost:3000/admin/agent_collaboration/dashboard

### Dev Environment
- User Dashboard: https://dev.amoslabs.com/dashboard/energy
- Admin Dashboard: https://dev.amoslabs.com/admin/agent_collaboration/dashboard

### Production
- User Dashboard: https://app.amoslabs.com/dashboard/energy
- Admin Dashboard: https://app.amoslabs.com/admin/agent_collaboration/dashboard

## Scheduled Jobs

The following jobs run automatically:

| Job | Frequency | Description |
|-----|-----------|-------------|
| `EnergyRegenerationJob` | Hourly | Regenerate energy + distribute community pool |
| `AgentDecisionBoundaryUpdateJob` | Daily | Update ask-for-help thresholds |
| `AgentCapabilityRecalibrationJob` | Weekly | Recalculate specializations |

## Database Tables

The system uses these tables:
- `agent_energy_states` - Energy tracking per agent
- `agent_energy_transactions` - Immutable ledger
- `agent_collaboration_requests` - Help requests
- `agent_relationships` - Learned collaboration patterns
- `agent_capability_beliefs` - Per-task-type performance
- `agent_decision_boundaries` - Bayesian thresholds
- `agent_school_enrollments` - Rehabilitation tracking
- `agent_ab_tests` - Statistical comparison
- `community_energy_pools` - Tax redistribution

## Troubleshooting

### Migrations fail
Check the database connection and ensure the schema is up to date:
```bash
rails db:migrate:status
```

### Energy states not initializing
Ensure agents exist in the database:
```bash
rails runner "puts AgentPlugin.count"
```

### School enrollments stuck
Check for agents with 0 energy that aren't enrolled:
```bash
rails runner "puts AgentPlugin.where(status: 'active').joins(:energy_state).where('agent_energy_states.current_energy <= 0').count"
```

### Logs
- Local: Check `log/development.log`
- AWS: Check CloudWatch logs at `/ecs/<task-family>`

