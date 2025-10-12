# GitHub Actions Setup

## Required GitHub Secrets

Go to: **Your GitHub Repo** → **Settings** → **Secrets and variables** → **Actions** → **New repository secret**

### Secrets to Add:

| Secret Name | Value | Example |
|-------------|-------|---------|
| `AWS_ACCESS_KEY_ID` | IAM user access key | `AKIA...` |
| `AWS_SECRET_ACCESS_KEY` | IAM user secret key | `(secret)` |
| `AWS_REGION` | AWS region | `ap-southeast-1` |
| `ECR_REPOSITORY` | ECR repo name | `yolo-test` |
| `EKS_CLUSTER_NAME` | EKS cluster name | `yolo-inference-cluster` |
| `S3_MODEL_BUCKET` | S3 bucket name | `s3-eks-dang` |

⚠️ **Important:**
- `ECR_REPOSITORY`: Only repository name, NOT full URL
- `S3_MODEL_BUCKET`: Only bucket name, without `s3://` prefix

## Create IAM User for GitHub Actions

```bash
# 1. Create IAM user
aws iam create-user --user-name github-actions-user

# 2. Attach policies
aws iam attach-user-policy \
  --user-name github-actions-user \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser

aws iam attach-user-policy \
  --user-name github-actions-user \
  --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy

# 3. Create access key
aws iam create-access-key --user-name github-actions-user
```

Save the Access Key ID and Secret Access Key to GitHub Secrets.

## Workflow File

The workflow is defined in `.github/workflows/deploy.yml`:

```yaml
name: Build and Deploy to EKS

on:
  push:
    branches: [ main ]
  workflow_dispatch:

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v2
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: ${{ secrets.AWS_REGION }}

      # ... build and deploy steps
```

## Trigger Deployment

### Automatic (on push):
```bash
git add .
git commit -m "Update deployment"
git push origin main
```

### Manual:
1. Go to: `https://github.com/YOUR_USERNAME/YOUR_REPO/actions`
2. Click "Build and Deploy to EKS"
3. Click "Run workflow" → Select `main` branch
4. Click "Run workflow"

## Verify Deployment

After GitHub Actions completes (~5-10 min):

```bash
# Check deployment status
kubectl rollout status deployment/yolo-inference -n yolo-inference

# Get LoadBalancer URL
kubectl get svc yolo-service -n yolo-inference

# Test API
curl http://<LOADBALANCER_URL>/health
```

## Troubleshooting

### ECR push fails
```bash
# Verify ECR repo exists
aws ecr describe-repositories --repository-names yolo-test --region ap-southeast-1

# Create if missing
aws ecr create-repository --repository-name yolo-test --region ap-southeast-1
```

### EKS deployment fails
```bash
# Check cluster exists
eksctl get cluster --name yolo-inference-cluster --region ap-southeast-1

# Update kubeconfig
aws eks update-kubeconfig --name yolo-inference-cluster --region ap-southeast-1

# Check kubectl access
kubectl get nodes
```

### Secrets not working
- Verify secret names match exactly (case-sensitive)
- Check workflow file references: `${{ secrets.SECRET_NAME }}`
- Re-create secrets if needed
