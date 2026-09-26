resource "aws_glue_catalog_database" "tiers" {
  for_each = toset(["silver", "gold"])
  name     = "azalea_nezu_${each.key}"
}

resource "aws_glue_catalog_table" "parquet" {
  for_each      = local.tables
  database_name = aws_glue_catalog_database.tiers[each.value.tier].name
  name          = each.value.name
  table_type    = "EXTERNAL_TABLE"
  parameters = {
    EXTERNAL       = "TRUE"
    classification = "parquet"
  }
  storage_descriptor {
    location      = "s3://${aws_s3_bucket.medallion.id}/${each.value.tier}/${each.value.name}/"
    input_format  = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"
    ser_de_info { serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe" }
    dynamic "columns" {
      for_each = each.value.columns
      content {
        name = columns.value.name
        type = columns.value.type
      }
    }
  }
}

resource "aws_athena_workgroup" "silver" {
  name          = "azalea-nezu-silver"
  force_destroy = true
  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true
    result_configuration {
      output_location = "s3://${aws_s3_bucket.results.id}/silver/"
      encryption_configuration {
        encryption_option = "SSE_KMS"
        kms_key_arn       = aws_kms_key.data.arn
      }
    }
  }
}

resource "aws_athena_workgroup" "gold" {
  name          = "azalea-nezu-gold"
  force_destroy = true
  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true
    result_configuration {
      output_location = "s3://${aws_s3_bucket.results.id}/gold/"
      encryption_configuration {
        encryption_option = "SSE_KMS"
        kms_key_arn       = aws_kms_key.data.arn
      }
    }
  }
}
