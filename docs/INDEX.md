# AMOS Documentation Index

This directory contains all technical documentation for the AMOS platform.

---

## 📂 Directory Structure

```
docs/
├── architecture/        # System architecture and design documents
├── deployment/          # Deployment and setup guides
├── guides/             # How-to guides and tutorials
├── planning/           # Planning documents and project summaries
├── rag/                # RAG system documentation (auto-generated)
└── workflows/          # Workflow templates and execution guides
```

---

## 🏗️ Architecture Documentation

Technical architecture, system design, and integration patterns.

### Core Architecture
- [AGENT_ARCHITECTURE.md](AGENT_ARCHITECTURE.md) - V2 agent system overview
- [WORKFLOW_V2_EXECUTIVE_SUMMARY.md](WORKFLOW_V2_EXECUTIVE_SUMMARY.md) - Phase-based workflow system
- [V2_PURE_IMPLEMENTATION.md](V2_PURE_IMPLEMENTATION.md) - V2 implementation details
- [MULTI_AGENT_ORCHESTRATION_DESIGN.md](architecture/MULTI_AGENT_ORCHESTRATION_DESIGN.md) - Multi-agent patterns

### Integration System
- [INTEGRATION_ARCHITECTURE_V2.md](INTEGRATION_ARCHITECTURE_V2.md) - Integration system design
- [SECURE_INTEGRATION_ARCHITECTURE.md](architecture/SECURE_INTEGRATION_ARCHITECTURE.md) - Security patterns
- [UNIVERSAL_INTEGRATION_SYSTEM.md](architecture/UNIVERSAL_INTEGRATION_SYSTEM.md) - Universal integration approach
- [INTEGRATION_BUILDER_IMPLEMENTATION.md](architecture/INTEGRATION_BUILDER_IMPLEMENTATION.md) - Integration builder
- [INTEGRATION_EXAMPLE.md](INTEGRATION_EXAMPLE.md) - Step-by-step integration guide

### Analytics & Add-ons
- [ANALYTICS_ADDON_INTEGRATION_DESIGN.md](architecture/ANALYTICS_ADDON_INTEGRATION_DESIGN.md) - Analytics add-on design
- [ANALYTICS_ARCHITECTURE.md](ANALYTICS_ARCHITECTURE.md) - Analytics system architecture

---

## 🚀 Deployment & Setup

Guides for deploying and running AMOS in various environments.

- [AWS_DEPLOYMENT_STRIPE_WEBHOOKS.md](deployment/AWS_DEPLOYMENT_STRIPE_WEBHOOKS.md) - AWS deployment with Stripe
- [DOCKER_SETUP.md](deployment/DOCKER_SETUP.md) - Docker containerization
- [LOCAL_DEVELOPMENT.md](deployment/LOCAL_DEVELOPMENT.md) - Local dev environment setup
- [LAUNCH_READY.md](deployment/LAUNCH_READY.md) - Production readiness checklist

---

## 📖 How-To Guides

Step-by-step tutorials and operational guides.

### Testing & Validation
- [AGENT_TESTING_GUIDE.md](AGENT_TESTING_GUIDE.md) - Testing agent workflows
- [ANALYTICS_TESTING_GUIDE.md](guides/ANALYTICS_TESTING_GUIDE.md) - Analytics testing procedures

### Operations
- [RUN_THIS_MIGRATION.md](guides/RUN_THIS_MIGRATION.md) - Migration instructions
- [SUBSCRIPTION_TRACKING.md](guides/SUBSCRIPTION_TRACKING.md) - Subscription management

---

## 🤖 RAG System Documentation

Retrieval-Augmented Generation system (Phases 1-3 complete).

### Overview
- [RAG_COMPLETE_SUMMARY.md](RAG_COMPLETE_SUMMARY.md) - Full 3-phase implementation summary
- [RAG_ARCHITECTURE.md](RAG_ARCHITECTURE.md) - Complete technical architecture
- [RAG_COMPARISON_OTTOMATOR.md](RAG_COMPARISON_OTTOMATOR.md) - Comparison with Ottomator agent

### Implementation Details
- [PHASE2_EMBEDDING_OPTIMIZATION.md](PHASE2_EMBEDDING_OPTIMIZATION.md) - Cache & batch processing
- [PHASE3_ENHANCED_METADATA.md](PHASE3_ENHANCED_METADATA.md) - Metadata & filtering
- [RAG_PERFORMANCE_BENCHMARKS.md](RAG_PERFORMANCE_BENCHMARKS.md) - Performance metrics

### Alternatives & Clarifications
- [PGVECTOR_ALTERNATIVE.md](PGVECTOR_ALTERNATIVE.md) - Free pgvector alternative
- [REDIS_USAGE_CLARIFICATION.md](REDIS_USAGE_CLARIFICATION.md) - Redis vs RAG memory

---

## 📋 Planning & Project Management

Project planning, roadmaps, and historical summaries.

- [INTEGRATION_CONSOLIDATION_PLAN.md](planning/INTEGRATION_CONSOLIDATION_PLAN.md) - Integration consolidation
- [UX_IMPROVEMENTS_NEEDED.md](planning/UX_IMPROVEMENTS_NEEDED.md) - UX enhancement backlog
- [COMPLETE_DAY_SUMMARY.md](planning/COMPLETE_DAY_SUMMARY.md) - Daily work summaries

---

## 🔄 Workflow System

Phase-based workflow templates and execution documentation.

- [WORKFLOW_TEMPLATES_GUIDE.md](WORKFLOW_TEMPLATES_GUIDE.md) - Creating workflow templates
- Workflow templates: See `app/workflow_templates/*.yml`

---

## 📊 Quick Reference

### For Developers
- **Getting Started**: [LOCAL_DEVELOPMENT.md](deployment/LOCAL_DEVELOPMENT.md)
- **Agent System**: [AGENT_ARCHITECTURE.md](AGENT_ARCHITECTURE.md)
- **Testing**: [AGENT_TESTING_GUIDE.md](AGENT_TESTING_GUIDE.md)
- **RAG System**: [RAG_COMPLETE_SUMMARY.md](RAG_COMPLETE_SUMMARY.md)

### For DevOps
- **Docker Setup**: [DOCKER_SETUP.md](deployment/DOCKER_SETUP.md)
- **AWS Deployment**: [AWS_DEPLOYMENT_STRIPE_WEBHOOKS.md](deployment/AWS_DEPLOYMENT_STRIPE_WEBHOOKS.md)
- **Production Checklist**: [LAUNCH_READY.md](deployment/LAUNCH_READY.md)

### For Architects
- **System Overview**: [WORKFLOW_V2_EXECUTIVE_SUMMARY.md](WORKFLOW_V2_EXECUTIVE_SUMMARY.md)
- **Integration Design**: [INTEGRATION_ARCHITECTURE_V2.md](INTEGRATION_ARCHITECTURE_V2.md)
- **Analytics Design**: [ANALYTICS_ARCHITECTURE.md](ANALYTICS_ARCHITECTURE.md)
- **RAG Architecture**: [RAG_ARCHITECTURE.md](RAG_ARCHITECTURE.md)

---

## 📝 Project Instructions

For Claude Code instructions and project-specific guidance, see:
- [CLAUDE.md](../CLAUDE.md) - Root project instructions
- [.claude/agents/](../.claude/agents/) - Agent-specific instructions

---

## 🔍 Finding Documentation

**By Topic**:
- Agent system → `AGENT_*.md`
- Workflow system → `WORKFLOW_*.md`
- Integration system → `INTEGRATION_*.md`
- RAG system → `RAG_*.md`
- Analytics → `ANALYTICS_*.md`

**By Activity**:
- Building features → `architecture/`
- Deploying → `deployment/`
- Testing → `guides/` + `*_TESTING_GUIDE.md`
- Planning → `planning/`

---

## 📚 Documentation Standards

All documentation follows these standards:

1. **Markdown Format**: GitHub-flavored markdown
2. **Structure**: Title, overview, sections, examples
3. **Code Examples**: Syntax-highlighted with explanations
4. **Visual Aids**: ASCII diagrams for architecture
5. **Cross-References**: Links to related docs
6. **Date Stamps**: Include "Last Updated" when relevant

---

## 🆕 Recent Additions

**October 2025**:
- ✅ RAG Phase 3 complete (enhanced metadata & filtering)
- ✅ Redis usage clarification document
- ✅ Complete RAG implementation summary
- ✅ Performance benchmarks documented

**September 2025**:
- ✅ V2 workflow system implementation
- ✅ Multi-agent orchestration design
- ✅ Analytics architecture

---

**Need help finding something?** Check the topic-specific directories or search by keyword.
