output "pipeline_url" {
  value = "https://${var.region}.console.aws.amazon.com/codesuite/codepipeline/pipelines/${aws_codepipeline.pipeline.name}/view?region=${var.region}"
}

output "tf_state_bucket" {
  value = aws_s3_bucket.tf_state.bucket
}
