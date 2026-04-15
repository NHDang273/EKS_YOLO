# GitHub Actions and CI/CD Access

This guide describes how to grant GitHub Actions access to the EKS cluster and how CI/CD should interact with this repository.

## Current CI/CD Model

The repository currently documents an IAM user based integration:

- IAM user: `github-actions-user`
- cluster access: mapped into `aws-auth` through `eksctl`
- deployment path: render manifests and run the same update flow used locally

This works, but it is not the strongest long-term production model. A role-based CI/CD path would be preferable.

## Required Repository Secrets

Add these repository secrets in GitHub Actions:

`Settings` -> `Secrets and variables` -> `Actions`

| Secret Name | Purpose |
|-------------|---------|
| `AWS_ACCESS_KEY_ID` | IAM user access key |
| `AWS_SECRET_ACCESS_KEY` | IAM user secret key |
| `AWS_REGION` | cluster region |
| `ECR_REPOSITORY` | image repository name |
| `EKS_CLUSTER_NAME` | target EKS cluster |
| `S3_MODEL_BUCKET` | bucket containing model weights |

Keep these aligned with the environment values used locally.

## Create the IAM User

```bash
aws iam create-user --user-name github-actions-user

aws iam attach-user-policy \
  --user-name github-actions-user \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser

aws iam attach-user-policy \
  --user-name github-actions-user \
  --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy

aws iam create-access-key --user-name github-actions-user
```

Store the generated access key and secret in GitHub repository secrets.

## Grant Cluster Access

After the cluster exists, run:

```bash
./scripts/setup-github.sh
```

This script:

- updates kubeconfig
- verifies or creates the IAM identity mapping
- maps `github-actions-user` into `aws-auth`
- prints the GitHub secret values that must stay aligned with `.env`

Verify the mapping:

```bash
kubectl get configmap aws-auth -n kube-system
```

## CI/CD Responsibilities

The workflow should:

1. build the Docker image
2. push the image to ECR
3. authenticate to AWS
4. update kubeconfig for the target cluster
5. render manifests using `./scripts/render-manifests.sh`
6. deploy using the same logic as local updates, preferably `./scripts/update.sh`

This keeps CI/CD behavior aligned with operator behavior and reduces configuration drift.

## Post-Run Verification

After a workflow completes:

```bash
kubectl rollout status deployment/yolo-inference -n yolo-inference
kubectl get pods -n yolo-inference
kubectl get svc yolo-service -n yolo-inference
```

## Production Concerns

Current concerns with the documented CI/CD path:

- `setup-github.sh` maps the CI identity to `system:masters`
- the flow is IAM user based instead of role based
- permissions are broader than least-privilege production practice

Recommended next step:

- replace IAM user credentials with a role-based GitHub federation pattern
- reduce cluster access from `system:masters` to the minimum operational scope
