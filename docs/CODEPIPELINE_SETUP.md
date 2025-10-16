# CodePipeline Setup for Automatic Deployments

## Option 1: GitHub Integration

If your code is on GitHub:

1. Create a GitHub personal access token:
   - Go to GitHub Settings > Developer settings > Personal access tokens
   - Create a token with `repo` scope
   - Save the token securely

2. Apply the CodePipeline Terraform configuration:
   ```bash
   cd aws/terraform
   terraform apply -var="domain_name=cruxmarketing.ai" -var="github_token=YOUR_GITHUB_TOKEN"
   ```

## Option 2: AWS CodeCommit

If you want to use AWS CodeCommit:

1. Create a CodeCommit repository:
   ```bash
   aws codecommit create-repository --repository-name agent-marketing
   ```

2. Add CodeCommit as a remote:
   ```bash
   git remote add codecommit https://git-codecommit.us-east-1.amazonaws.com/v1/repos/agent-marketing
   ```

3. Push your code:
   ```bash
   git push codecommit main
   ```

4. Update the CodePipeline configuration to use CodeCommit instead of GitHub.

## How It Works

Once set up, CodePipeline will:
1. **Monitor** your main branch for changes
2. **Build** a new Docker image using CodeBuild
3. **Push** the image to ECR
4. **Deploy** automatically to ECS

No more manual deployments needed!

## Current Manual Deployment

Until CodePipeline is set up, use:
```bash
./aws/deploy.sh
```
