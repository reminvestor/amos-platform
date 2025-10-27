#!/bin/bash

# Script to create CodePipeline for dev environment
set -e

echo "🚀 Creating CodePipeline for dev environment..."

# Colors
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

# Variables
PIPELINE_NAME="agent-marketing-dev-pipeline"
CODEBUILD_PROJECT="agent-marketing-dev-build"
CONNECTION_ARN=$(aws codestar-connections list-connections --query "Connections[?ConnectionName=='github-connection'].ConnectionArn" --output text)

echo -e "${YELLOW}Using GitHub connection: $CONNECTION_ARN${NC}"

# 1. Create CodeBuild project for dev
echo -e "\n${YELLOW}1. Creating CodeBuild project...${NC}"
cat > /tmp/codebuild-dev.json << EOF
{
  "name": "${CODEBUILD_PROJECT}",
  "source": {
    "type": "CODEPIPELINE",
    "buildspec": "buildspec-dev.yml"
  },
  "artifacts": {
    "type": "CODEPIPELINE"
  },
  "environment": {
    "type": "LINUX_CONTAINER",
    "image": "aws/codebuild/standard:7.0",
    "computeType": "BUILD_GENERAL1_SMALL",
    "privilegedMode": true,
    "environmentVariables": [
      {"name": "AWS_REGION", "value": "us-east-1"},
      {"name": "AWS_ACCOUNT_ID", "value": "637423327454"},
      {"name": "IMAGE_REPO_NAME", "value": "agent-marketing-dev"},
      {"name": "IMAGE_TAG", "value": "latest"},
      {"name": "CONTAINER_NAME", "value": "agent-marketing-dev"},
      {"name": "ECS_CLUSTER_NAME", "value": "agent-marketing-dev-cluster"},
      {"name": "ECS_SERVICE_NAME", "value": "agent-marketing-dev"},
      {"name": "TASK_DEFINITION_FAMILY", "value": "agent-marketing-dev"},
      {"name": "ENVIRONMENT", "value": "dev"}
    ]
  },
  "serviceRole": "arn:aws:iam::637423327454:role/agent-marketing-dev-codebuild-role"
}
EOF

aws codebuild create-project --cli-input-json file:///tmp/codebuild-dev.json 2>/dev/null && \
    echo -e "${GREEN}✓ CodeBuild project created${NC}" || echo -e "${YELLOW}CodeBuild project already exists${NC}"

# 2. Create CodePipeline
echo -e "\n${YELLOW}2. Creating CodePipeline...${NC}"
cat > /tmp/pipeline-dev.json << EOF
{
  "pipeline": {
    "name": "${PIPELINE_NAME}",
    "roleArn": "arn:aws:iam::637423327454:role/agent-marketing-dev-codepipeline-role",
    "artifactStore": {
      "type": "S3",
      "location": "agent-marketing-dev-codepipeline-artifacts-637423327454"
    },
    "stages": [
      {
        "name": "Source",
        "actions": [
          {
            "name": "Source",
            "actionTypeId": {
              "category": "Source",
              "owner": "AWS",
              "provider": "CodeStarSourceConnection",
              "version": "1"
            },
            "configuration": {
              "ConnectionArn": "${CONNECTION_ARN}",
              "FullRepositoryId": "NuvolaNetworks/agent_marketing",
              "BranchName": "dev",
              "OutputArtifactFormat": "CODEPIPELINE_DEFAULT"
            },
            "outputArtifacts": [
              {
                "name": "source_output"
              }
            ]
          }
        ]
      },
      {
        "name": "Build",
        "actions": [
          {
            "name": "Build",
            "actionTypeId": {
              "category": "Build",
              "owner": "AWS",
              "provider": "CodeBuild",
              "version": "1"
            },
            "configuration": {
              "ProjectName": "${CODEBUILD_PROJECT}"
            },
            "inputArtifacts": [
              {
                "name": "source_output"
              }
            ],
            "outputArtifacts": [
              {
                "name": "build_output"
              }
            ]
          }
        ]
      },
      {
        "name": "Deploy",
        "actions": [
          {
            "name": "Deploy",
            "actionTypeId": {
              "category": "Deploy",
              "owner": "AWS",
              "provider": "ECS",
              "version": "1"
            },
            "configuration": {
              "ClusterName": "agent-marketing-dev-cluster",
              "ServiceName": "agent-marketing-dev",
              "FileName": "imagedefinitions.json"
            },
            "inputArtifacts": [
              {
                "name": "build_output"
              }
            ]
          }
        ]
      }
    ]
  }
}
EOF

# Check if pipeline exists
PIPELINE_EXISTS=$(aws codepipeline get-pipeline --name ${PIPELINE_NAME} 2>/dev/null && echo "true" || echo "false")

if [ "$PIPELINE_EXISTS" == "false" ]; then
    aws codepipeline create-pipeline --cli-input-json file:///tmp/pipeline-dev.json && \
        echo -e "${GREEN}✓ CodePipeline created${NC}"
else
    # Update existing pipeline
    aws codepipeline update-pipeline --cli-input-json file:///tmp/pipeline-dev.json > /dev/null && \
        echo -e "${GREEN}✓ CodePipeline updated${NC}"
fi

# 3. Start the pipeline
echo -e "\n${YELLOW}3. Starting pipeline execution...${NC}"
aws codepipeline start-pipeline-execution --name ${PIPELINE_NAME} > /dev/null && \
    echo -e "${GREEN}✓ Pipeline started${NC}"

# Cleanup
rm -f /tmp/codebuild-dev.json /tmp/pipeline-dev.json

echo -e "\n${GREEN}🎉 Dev pipeline created successfully!${NC}"
echo -e "\n${YELLOW}Pipeline Information:${NC}"
echo -e "  Name: ${PIPELINE_NAME}"
echo -e "  Trigger: Pushes to 'dev' branch"
echo -e "  Repository: NuvolaNetworks/agent_marketing"
echo -e "\n${YELLOW}View pipeline:${NC}"
echo -e "  https://console.aws.amazon.com/codesuite/codepipeline/pipelines/${PIPELINE_NAME}/view"
echo -e "\n${YELLOW}The pipeline will now automatically deploy when you push to the dev branch!${NC}"
