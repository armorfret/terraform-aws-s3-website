output "site-dns-name" {
  value = "${aws_cloudfront_distribution.site_distribution.domain_name}"
}

output "redirect-dns-name" {
  value = "${aws_cloudfront_distribution.redirect_distribution.domain_name}"
}

output "cloudfront-zone-id" {
  value = "${aws_cloudfront_distribution.site_distribution.hosted_zone_id}"
}
