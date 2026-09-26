terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }
  backend "s3" {
    bucket       = "terraform-lucky9"
    key          = "azalea-nezu/bootstrap/terraform.tfstate"
    region       = "us-west-2"
    profile      = "Lucky9 Root"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region  = "us-west-2"
  profile = "Lucky9 Root"
  default_tags { tags = { project = "azalea-nezu", environment = "hackathon", ManagedBy = "terraform" } }
}

data "aws_caller_identity" "current" {}

resource "aws_iam_role" "deployer" {
  name = "azalea-nezu-terraform-deployer"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow", Action = "sts:AssumeRole",
      Principal = { AWS = aws_iam_user.source.arn }
    }]
  })
}

resource "aws_iam_user" "source" {
  name = "azalea-nezu-deployer-source"
}

resource "aws_iam_user_policy" "source" {
  name = "assume-azalea-deployer-only"
  user = aws_iam_user.source.name
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = "sts:AssumeRole", Resource = aws_iam_role.deployer.arn }]
  })
}

# Service permissions are limited to the Azalea names and region wherever the
# AWS service permits resource scoping. Describe and create APIs that do not
# accept resource ARNs are separately listed.
resource "aws_iam_role_policy" "deployer" {
  name = "azalea-nezu-deploy"
  role = aws_iam_role.deployer.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "ReadStateBucket", Effect = "Allow",
        Action    = ["s3:ListBucket", "s3:GetBucketLocation", "s3:GetBucketVersioning"],
        Resource  = "arn:aws:s3:::terraform-lucky9",
        Condition = { StringLike = { "s3:prefix" = ["azalea-nezu/*"] } }
      },
      {
        Sid      = "ManageStateObjects", Effect = "Allow",
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"],
        Resource = "arn:aws:s3:::terraform-lucky9/azalea-nezu/*"
      },
      {
        Sid      = "ManageAzaleaBuckets", Effect = "Allow", Action = ["s3:*"],
        Resource = ["arn:aws:s3:::azalea-nezu-*", "arn:aws:s3:::azalea-nezu-*/*"]
      },
      {
        Sid    = "S3GlobalRead", Effect = "Allow",
        Action = ["s3:ListAllMyBuckets"], Resource = "*"
      },
      {
        Sid      = "NetworkDescribe", Effect = "Allow",
        Action   = ["ec2:Describe*"],
        Resource = "*"
      },
      {
        Sid      = "AzaleaSecurityGroups", Effect = "Allow",
        Action   = ["ec2:CreateSecurityGroup", "ec2:DeleteSecurityGroup", "ec2:AuthorizeSecurityGroupEgress", "ec2:RevokeSecurityGroupEgress", "ec2:AuthorizeSecurityGroupIngress", "ec2:RevokeSecurityGroupIngress", "ec2:CreateTags", "ec2:DeleteTags"],
        Resource = "*", Condition = { StringEquals = { "aws:RequestedRegion" = "us-west-2" } }
      },
      {
        Sid      = "NotebookNetworkInterfaces", Effect = "Allow",
        Action   = ["ec2:CreateNetworkInterface", "ec2:DeleteNetworkInterface"],
        Resource = "*", Condition = { StringEquals = { "aws:RequestedRegion" = "us-west-2" } }
      },
      {
        Sid      = "AzaleaIamRoles", Effect = "Allow",
        Action   = ["iam:CreateRole", "iam:DeleteRole", "iam:GetRole", "iam:TagRole", "iam:UntagRole", "iam:ListRoleTags", "iam:ListRolePolicies", "iam:ListAttachedRolePolicies", "iam:GetRolePolicy", "iam:PutRolePolicy", "iam:DeleteRolePolicy", "iam:PassRole", "iam:UpdateAssumeRolePolicy"],
        Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/azalea-nezu-*"
      },
      {
        Sid       = "AzaleaKmsCreate", Effect = "Allow", Action = ["kms:CreateKey", "kms:ListAliases"], Resource = "*",
        Condition = { StringEquals = { "aws:RequestedRegion" = "us-west-2" } }
      },
      {
        Sid      = "AzaleaKmsManage", Effect = "Allow", Action = ["kms:DescribeKey", "kms:GetKeyPolicy", "kms:PutKeyPolicy", "kms:GetKeyRotationStatus", "kms:EnableKeyRotation", "kms:DisableKeyRotation", "kms:ScheduleKeyDeletion", "kms:CancelKeyDeletion", "kms:CreateAlias", "kms:DeleteAlias", "kms:UpdateAlias", "kms:ListResourceTags", "kms:TagResource", "kms:UntagResource", "kms:Encrypt", "kms:Decrypt", "kms:GenerateDataKey", "kms:CreateGrant"],
        Resource = ["arn:aws:kms:us-west-2:${data.aws_caller_identity.current.account_id}:key/*", "arn:aws:kms:us-west-2:${data.aws_caller_identity.current.account_id}:alias/azalea-nezu-*"]
      },
      {
        Sid      = "AzaleaSecrets", Effect = "Allow", Action = ["secretsmanager:CreateSecret", "secretsmanager:DeleteSecret", "secretsmanager:DescribeSecret", "secretsmanager:GetResourcePolicy", "secretsmanager:TagResource", "secretsmanager:UntagResource"],
        Resource = "arn:aws:secretsmanager:us-west-2:${data.aws_caller_identity.current.account_id}:secret:azalea-nezu/*"
      },
      {
        Sid      = "AzaleaGlue", Effect = "Allow", Action = ["glue:CreateDatabase", "glue:DeleteDatabase", "glue:GetDatabase", "glue:UpdateDatabase", "glue:CreateTable", "glue:DeleteTable", "glue:GetTable", "glue:GetTables", "glue:UpdateTable", "glue:GetPartitions", "glue:TagResource", "glue:UntagResource", "glue:GetTags"],
        Resource = ["arn:aws:glue:us-west-2:${data.aws_caller_identity.current.account_id}:catalog", "arn:aws:glue:us-west-2:${data.aws_caller_identity.current.account_id}:database/azalea_nezu_*", "arn:aws:glue:us-west-2:${data.aws_caller_identity.current.account_id}:table/azalea_nezu_*/*"]
      },
      {
        Sid      = "AzaleaAthena", Effect = "Allow", Action = ["athena:CreateWorkGroup", "athena:DeleteWorkGroup", "athena:GetWorkGroup", "athena:UpdateWorkGroup", "athena:TagResource", "athena:UntagResource", "athena:ListTagsForResource"],
        Resource = "arn:aws:athena:us-west-2:${data.aws_caller_identity.current.account_id}:workgroup/azalea-nezu-*"
      },
      {
        Sid      = "AzaleaSagemaker", Effect = "Allow", Action = ["sagemaker:CreateNotebookInstance", "sagemaker:DeleteNotebookInstance", "sagemaker:DescribeNotebookInstance", "sagemaker:UpdateNotebookInstance", "sagemaker:StartNotebookInstance", "sagemaker:StopNotebookInstance", "sagemaker:CreateNotebookInstanceLifecycleConfig", "sagemaker:DeleteNotebookInstanceLifecycleConfig", "sagemaker:DescribeNotebookInstanceLifecycleConfig", "sagemaker:UpdateNotebookInstanceLifecycleConfig", "sagemaker:ListTags", "sagemaker:AddTags", "sagemaker:DeleteTags"],
        Resource = ["arn:aws:sagemaker:us-west-2:${data.aws_caller_identity.current.account_id}:notebook-instance/azalea-nezu-*", "arn:aws:sagemaker:us-west-2:${data.aws_caller_identity.current.account_id}:notebook-instance-lifecycle-config/azalea-nezu-*"]
      }
    ]
  })
}

resource "aws_secretsmanager_secret" "tailscale_auth" {
  name                    = "azalea-nezu/tailscale/notebook-auth-key"
  description             = "Populate out of band with a tagged Tailscale auth key before enabling the notebook."
  recovery_window_in_days = 7
}

output "deployer_role_arn" { value = aws_iam_role.deployer.arn }
output "source_user_name" { value = aws_iam_user.source.name }
output "tailscale_auth_secret_arn" { value = aws_secretsmanager_secret.tailscale_auth.arn }
