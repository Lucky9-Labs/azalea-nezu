output "medallion_bucket" { value = aws_s3_bucket.medallion.id }
output "artifacts_bucket" { value = aws_s3_bucket.artifacts.id }
output "athena_results_bucket" { value = aws_s3_bucket.results.id }
output "notebook_name" { value = try(aws_sagemaker_notebook_instance.medallion[0].name, null) }
output "gold_reader_role_arn" { value = aws_iam_role.gold_reader.arn }
output "gold_workgroup" { value = aws_athena_workgroup.gold.name }
output "silver_workgroup" { value = aws_athena_workgroup.silver.name }
