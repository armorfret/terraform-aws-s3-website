output "site_dns_name" {
  value = aws_cloudfront_distribution.file.domain_name
}

output "redirect_dns_name" {
  value = aws_cloudfront_distribution.redirect.domain_name
}

output "cloudfront_zone_id" {
  value = aws_cloudfront_distribution.file.hosted_zone_id
}

