# GitHub Secrets Configuration

## Required Secrets

Vào GitHub repo → **Settings** → **Secrets and variables** → **Actions** → **New repository secret**

### 1. AWS_ACCESS_KEY_ID
```
AKIA... (IAM user access key)
```

### 2. AWS_SECRET_ACCESS_KEY
```
(IAM user secret key)
```

### 3. AWS_REGION
```
ap-southeast-1
```

### 4. ECR_REPOSITORY
```
ai-inference
```
⚠️ **CHỈ LÀ TÊN REPO, KHÔNG PHẢI FULL URL!**

### 5. EKS_CLUSTER_NAME
```
yolo-eks-cluster
```

### 6. S3_MODEL_BUCKET
```
s3-eks-dang
```

---

## IAM User Permissions Required

IAM user `github-actions-user` cần có policies:
- `AmazonEC2ContainerRegistryPowerUser` (push image to ECR)
- `AmazonEKSClusterPolicy` (deploy to EKS)
- Hoặc custom policy:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "ecr:PutImage",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "eks:DescribeCluster",
        "eks:ListClusters"
      ],
      "Resource": "*"
    }
  ]
}
```