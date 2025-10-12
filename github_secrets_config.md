# GitHub Secrets Configuration

Go to: **Your GitHub Repo** → **Settings** → **Secrets and variables** → **Actions** → **New repository secret**

Add these secrets:

## Required Secrets:

```
AWS_ACCESS_KEY_ID=<Your AWS Access Key>
AWS_SECRET_ACCESS_KEY=<Your AWS Secret Key>
AWS_REGION=ap-southeast-1
ECR_REPOSITORY=ai-inference
EKS_CLUSTER_NAME=yolo-inference-cluster
S3_MODEL_BUCKET=s3-eks-dang
```

## How to get AWS credentials:

```bash
# On your EC2 instance
aws configure list

# Or create IAM user for GitHub Actions:
# 1. IAM Console → Users → Create user: github-actions-user
# 2. Attach policies:
#    - AmazonEC2ContainerRegistryPowerUser
#    - AmazonEKSClusterPolicy
#    - AmazonS3ReadOnlyAccess
# 3. Create access key → Copy to GitHub Secrets
```

## Verify Secrets are Set:

After adding secrets, check workflow file uses them correctly:
- `${{ secrets.ECR_REPOSITORY }}` should be `ai-inference`
- `${{ secrets.EKS_CLUSTER_NAME }}` should be `yolo-inference-cluster`

## Create ECR Repository:

```bash
aws ecr create-repository \
  --repository-name ai-inference \
  --region ap-southeast-1
```

## Test Push Manually:

```bash
# Login to ECR
aws ecr get-login-password --region ap-southeast-1 | \
  docker login --username AWS --password-stdin \
  688567276212.dkr.ecr.ap-southeast-1.amazonaws.com

# Build and push
docker build -t 688567276212.dkr.ecr.ap-southeast-1.amazonaws.com/ai-inference:test .
docker push 688567276212.dkr.ecr.ap-southeast-1.amazonaws.com/ai-inference:test
```
