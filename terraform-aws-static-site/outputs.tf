output "cloudfront_url" {
  description = "Public HTTPS URL of the deployed site"
  value       = "https://${aws_cloudfront_distribution.site.domain_name}"
}

output "bucket_name" {
  description = "Name of the S3 bucket holding the site"
  value       = aws_s3_bucket.site.id
}
