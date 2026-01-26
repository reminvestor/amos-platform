#!/bin/bash
# Add Test Stage to CodePipeline
# This script creates a CodeBuild project for tests and updates the pipeline

set -e

echo "=========================================="
echo "Adding Test Stage to Production Pipeline"
echo "=========================================="

# Step 1: Create CodeBuild test project
echo ""
echo "Step 1: Creating CodeBuild test project..."
aws codebuild create-project --cli-input-json file://aws/codebuild-test-project.json

if [ $? -eq 0 ]; then
    echo "✅ CodeBuild project 'agent-marketing-test' created"
else
    echo "⚠️  CodeBuild project may already exist, continuing..."
fi

# Step 2: Update pipeline with Test stage
echo ""
echo "Step 2: Updating pipeline with Test stage..."
aws codepipeline update-pipeline --cli-input-json file://aws/pipeline-with-test-stage.json

if [ $? -eq 0 ]; then
    echo "✅ Pipeline updated with Test stage"
else
    echo "❌ Failed to update pipeline"
    exit 1
fi

# Step 3: Verify the update
echo ""
echo "Step 3: Verifying pipeline stages..."
aws codepipeline get-pipeline --name agent-marketing-pipeline | jq '.pipeline.stages[].name'

echo ""
echo "=========================================="
echo "✅ Test stage added successfully!"
echo ""
echo "Pipeline is now: Source → Test → Build → Deploy"
echo ""
echo "The Test stage will run buildspec-test.yml which:"
echo "  - Runs critical path tests"
echo "  - Runs model tests"
echo "  - Runs service tests"
echo "  - Runs controller tests"
echo "  - Runs integration tests"
echo ""
echo "If any test fails, the deploy will be blocked."
echo "=========================================="
