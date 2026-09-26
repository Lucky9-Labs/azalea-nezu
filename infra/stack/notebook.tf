resource "aws_security_group" "notebook" {
  name        = "azalea-nezu-notebook"
  description = "No inbound; HTTPS egress for AWS and Tailscale DERP."
  vpc_id      = data.aws_vpc.core.id
  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "AWS endpoints, package sources, Tailscale control and DERP"
  }
}

locals {
  repo_artifacts = {
    "requirements.txt"                    = "../../requirements.txt"
    "schemas/catalog.json"                = "../../schemas/catalog.json"
    "config/sources.example.json"         = "../../config/sources.example.json"
    "notebooks/01_bronze_to_silver.ipynb" = "../../notebooks/01_bronze_to_silver.ipynb"
    "notebooks/02_silver_to_gold.ipynb"   = "../../notebooks/02_silver_to_gold.ipynb"
    "azalea_pipeline/__init__.py"         = "../../azalea_pipeline/__init__.py"
    "azalea_pipeline/catalog.py"          = "../../azalea_pipeline/catalog.py"
    "azalea_pipeline/bronze.py"           = "../../azalea_pipeline/bronze.py"
    "azalea_pipeline/transform.py"        = "../../azalea_pipeline/transform.py"
    "azalea_pipeline/storage.py"          = "../../azalea_pipeline/storage.py"
    "azalea_pipeline/extract.py"          = "../../azalea_pipeline/extract.py"
    "azalea_pipeline/gold.py"             = "../../azalea_pipeline/gold.py"
  }
}

resource "aws_s3_object" "repo" {
  for_each    = local.repo_artifacts
  bucket      = aws_s3_bucket.artifacts.id
  key         = "repo/${each.key}"
  source      = "${path.module}/${each.value}"
  source_hash = filemd5("${path.module}/${each.value}")
  depends_on  = [aws_s3_bucket_server_side_encryption_configuration.kms]
}

resource "aws_s3_object" "install" {
  bucket      = aws_s3_bucket.artifacts.id
  key         = "runtime/install.sh"
  source      = "${path.module}/runtime/install.sh"
  source_hash = filemd5("${path.module}/runtime/install.sh")
  depends_on  = [aws_s3_bucket_server_side_encryption_configuration.kms]
}

resource "aws_s3_object" "deployment_config" {
  bucket       = aws_s3_bucket.artifacts.id
  key          = "repo/deployment.json"
  content_type = "application/json"
  content = jsonencode({
    region           = data.aws_region.current.region
    medallion_bucket = aws_s3_bucket.medallion.id
  })
  depends_on = [aws_s3_bucket_server_side_encryption_configuration.kms]
}

resource "aws_sagemaker_notebook_instance_lifecycle_configuration" "bootstrap" {
  count = var.enable_notebook ? 1 : 0
  name  = "azalea-nezu-bootstrap"
  on_start = base64encode(templatefile("${path.module}/runtime/on-start.sh.tftpl", {
    artifacts_bucket = aws_s3_bucket.artifacts.id
    secret_name      = "azalea-nezu/tailscale/notebook-auth-key"
  }))
}

resource "aws_sagemaker_notebook_instance" "medallion" {
  count                  = var.enable_notebook ? 1 : 0
  name                   = "azalea-nezu-medallion"
  role_arn               = aws_iam_role.notebook.arn
  instance_type          = "ml.t3.medium"
  subnet_id              = data.aws_subnet.private.id
  security_groups        = [aws_security_group.notebook.id]
  direct_internet_access = "Disabled"
  root_access            = "Disabled"
  volume_size            = 10
  kms_key_id             = aws_kms_key.data.arn
  lifecycle_config_name  = aws_sagemaker_notebook_instance_lifecycle_configuration.bootstrap[0].name
  depends_on             = [aws_s3_object.install, aws_s3_object.repo, aws_s3_object.deployment_config, aws_iam_role_policy.notebook]
}
