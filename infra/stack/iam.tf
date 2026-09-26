resource "aws_iam_role" "notebook" {
  name = "azalea-nezu-notebook"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "sagemaker.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}

resource "aws_iam_role_policy" "notebook" {
  name = "azalea-nezu-pipeline"
  role = aws_iam_role.notebook.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ListData", Effect = "Allow", Action = ["s3:ListBucket", "s3:GetBucketLocation"],
        Resource = [aws_s3_bucket.medallion.arn, aws_s3_bucket.artifacts.arn, aws_s3_bucket.results.arn]
      },
      {
        Sid      = "ReadArtifacts", Effect = "Allow", Action = ["s3:GetObject"],
        Resource = "${aws_s3_bucket.artifacts.arn}/*"
      },
      {
        Sid      = "ReadWriteMedallion", Effect = "Allow", Action = ["s3:GetObject", "s3:PutObject"],
        Resource = "${aws_s3_bucket.medallion.arn}/*"
      },
      {
        Sid      = "AthenaResults", Effect = "Allow", Action = ["s3:GetObject", "s3:PutObject"],
        Resource = "${aws_s3_bucket.results.arn}/*"
      },
      {
        Sid      = "DecryptData", Effect = "Allow", Action = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey", "kms:DescribeKey"],
        Resource = aws_kms_key.data.arn
      },
      {
        Sid      = "TailnetAuth", Effect = "Allow", Action = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"],
        Resource = "arn:aws:secretsmanager:us-west-2:${data.aws_caller_identity.current.account_id}:secret:azalea-nezu/tailscale/notebook-auth-key-*"
      },
      {
        Sid      = "CatalogRead", Effect = "Allow", Action = ["glue:GetDatabase", "glue:GetDatabases", "glue:GetTable", "glue:GetTables", "glue:GetPartitions"],
        Resource = ["arn:aws:glue:us-west-2:${data.aws_caller_identity.current.account_id}:catalog", "arn:aws:glue:us-west-2:${data.aws_caller_identity.current.account_id}:database/azalea_nezu_*", "arn:aws:glue:us-west-2:${data.aws_caller_identity.current.account_id}:table/azalea_nezu_*/*"]
      },
      {
        Sid      = "AthenaQuery", Effect = "Allow", Action = ["athena:StartQueryExecution", "athena:GetQueryExecution", "athena:GetQueryResults", "athena:StopQueryExecution", "athena:GetWorkGroup"],
        Resource = [aws_athena_workgroup.silver.arn, aws_athena_workgroup.gold.arn]
      },
      {
        Sid = "AssumeGoldDemoRole", Effect = "Allow", Action = "sts:AssumeRole", Resource = aws_iam_role.gold_reader.arn
      }
    ]
  })
}

resource "aws_iam_role" "gold_reader" {
  name        = "azalea-nezu-gold-reader"
  description = "Read-only gold Athena role; trusts the notebook for synthetic demo queries."
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { AWS = aws_iam_role.notebook.arn }, Action = "sts:AssumeRole" }]
  })
}

resource "aws_iam_role_policy" "gold_reader" {
  name = "azalea-nezu-gold-only"
  role = aws_iam_role.gold_reader.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "GoldBucketList", Effect = "Allow", Action = ["s3:ListBucket"],
        Resource  = aws_s3_bucket.medallion.arn,
        Condition = { StringLike = { "s3:prefix" = ["gold", "gold/*"] } }
      },
      {
        Sid      = "GoldObjects", Effect = "Allow", Action = "s3:GetObject",
        Resource = "${aws_s3_bucket.medallion.arn}/gold/*"
      },
      {
        Sid       = "ResultBucket", Effect = "Allow", Action = ["s3:ListBucket"],
        Resource  = aws_s3_bucket.results.arn,
        Condition = { StringLike = { "s3:prefix" = ["gold", "gold/*"] } }
      },
      {
        Sid      = "BucketLocations", Effect = "Allow", Action = ["s3:GetBucketLocation"],
        Resource = [aws_s3_bucket.medallion.arn, aws_s3_bucket.results.arn]
      },
      {
        Sid      = "ResultObjects", Effect = "Allow", Action = ["s3:GetObject", "s3:PutObject"],
        Resource = "${aws_s3_bucket.results.arn}/gold/*"
      },
      {
        Sid      = "GoldCatalog", Effect = "Allow", Action = ["glue:GetDatabase", "glue:GetTable", "glue:GetTables", "glue:GetPartitions"],
        Resource = ["arn:aws:glue:us-west-2:${data.aws_caller_identity.current.account_id}:catalog", aws_glue_catalog_database.tiers["gold"].arn, "arn:aws:glue:us-west-2:${data.aws_caller_identity.current.account_id}:table/azalea_nezu_gold/*"]
      },
      {
        Sid      = "GoldQueries", Effect = "Allow", Action = ["athena:StartQueryExecution", "athena:GetQueryExecution", "athena:GetQueryResults", "athena:StopQueryExecution", "athena:GetWorkGroup"],
        Resource = aws_athena_workgroup.gold.arn
      },
      {
        Sid      = "GoldDecrypt", Effect = "Allow", Action = ["kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey"],
        Resource = aws_kms_key.data.arn
      }
    ]
  })
}
