terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

data "aws_iam_policy_document" "redirect_bucket_read_access" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["arn:aws:s3:::${var.redirect_bucket}/*"]

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
  }
}

data "aws_iam_policy_document" "file_bucket_read_access" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["arn:aws:s3:::${var.file_bucket}/*"]

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
  }
}

module "certificate" {
  source    = "armorfret/acm-certificate/aws"
  version   = "0.3.2"
  hostnames = concat([var.primary_hostname], var.redirect_hostnames)
}

module "publish_user" {
  source         = "armorfret/s3-publish/aws"
  version        = "0.8.1"
  logging_bucket = var.logging_bucket
  publish_bucket = var.file_bucket
  make_bucket    = false
}

resource "aws_s3_bucket" "redirect" {
  bucket = var.redirect_bucket
}

resource "aws_s3_bucket_public_access_block" "redirect" {
  bucket                  = aws_s3_bucket.redirect.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "redirect" {
  bucket = aws_s3_bucket.redirect.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = var.use_kms ? var.kms_key_arn : null
      sse_algorithm     = var.use_kms ? "aws:kms" : "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "redirect" {
  bucket = aws_s3_bucket.redirect.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_policy" "redirect" {
  bucket = aws_s3_bucket.redirect.id
  policy = data.aws_iam_policy_document.redirect_bucket_read_access.json
}

resource "aws_s3_bucket_logging" "redirect" {
  bucket = aws_s3_bucket.redirect.id

  target_bucket = var.logging_bucket
  target_prefix = "${var.redirect_bucket}/"
}

resource "aws_s3_bucket_website_configuration" "redirect" {
  bucket = aws_s3_bucket.redirect.bucket
  redirect_all_requests_to {
    host_name = var.primary_hostname
    protocol  = "https"
  }
}

resource "aws_cloudfront_distribution" "redirect" {
  origin {
    domain_name = aws_s3_bucket_website_configuration.redirect.website_endpoint
    origin_id   = "redirect-bucket"

    custom_origin_config {
      http_port              = "80"
      https_port             = "443"
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  aliases = var.redirect_hostnames

  enabled = true

  logging_config {
    include_cookies = false
    bucket          = "${var.logging_bucket}.s3.amazonaws.com"
    prefix          = "${var.redirect_bucket}-cdn"
  }

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "redirect-bucket"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 300
    max_ttl                = 300
    compress               = true

    response_headers_policy_id = aws_cloudfront_response_headers_policy.this.id
  }

  price_class = "PriceClass_100"

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    ssl_support_method       = "sni-only"
    minimum_protocol_version = var.tls_level
    acm_certificate_arn      = module.certificate.arn
  }

  web_acl_id = var.waf_id == "" ? null : var.waf_id
}

resource "aws_s3_bucket" "file" {
  bucket = var.file_bucket
}

resource "aws_s3_bucket_public_access_block" "file" {
  bucket                  = aws_s3_bucket.file.id
  block_public_acls       = true
  block_public_policy     = false #tfsec:ignore:aws-s3-block-public-policy
  ignore_public_acls      = true
  restrict_public_buckets = false #tfsec:ignore:aws-s3-no-public-buckets
}

resource "aws_s3_bucket_server_side_encryption_configuration" "file" {
  bucket = aws_s3_bucket.file.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = var.use_kms ? var.kms_key_arn : null
      sse_algorithm     = var.use_kms ? "aws:kms" : "AES256"
    }
  }
}

resource "aws_s3_bucket_policy" "file" {
  bucket = aws_s3_bucket.file.id
  policy = data.aws_iam_policy_document.file_bucket_read_access.json
}

resource "aws_s3_bucket_versioning" "file" {
  bucket = aws_s3_bucket.file.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_logging" "file" {
  bucket = aws_s3_bucket.file.id

  target_bucket = var.logging_bucket
  target_prefix = "${var.file_bucket}/"
}

resource "aws_s3_bucket_website_configuration" "file" {
  bucket = aws_s3_bucket.file.bucket

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = var.error_document
  }
}

resource "aws_cloudfront_distribution" "file" {
  origin {
    domain_name = aws_s3_bucket_website_configuration.file.website_endpoint
    origin_id   = "file-bucket"

    custom_origin_config {
      http_port              = "80"
      https_port             = "443"
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  aliases = [var.primary_hostname]

  enabled             = true
  default_root_object = "index.html"

  logging_config {
    include_cookies = false
    bucket          = "${var.logging_bucket}.s3.amazonaws.com"
    prefix          = "${var.file_bucket}-cdn/"
  }

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "file-bucket"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 0
    max_ttl                = 300
    compress               = true

    response_headers_policy_id = aws_cloudfront_response_headers_policy.this.id
  }

  price_class = "PriceClass_100"

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    ssl_support_method       = "sni-only"
    minimum_protocol_version = var.tls_level
    acm_certificate_arn      = module.certificate.arn
  }

  web_acl_id = var.waf_id == "" ? null : var.waf_id
}

resource "aws_cloudfront_response_headers_policy" "this" {
  name = "${replace(var.primary_hostname, ".", "_")}-policy"

  security_headers_config {
    content_type_options {
      override = true
    }
    frame_options {
      frame_option = "DENY"
      override     = true
    }
    referrer_policy {
      referrer_policy = "same-origin"
      override        = true
    }
    xss_protection {
      mode_block = true
      protection = true
      override   = true
    }
    strict_transport_security {
      access_control_max_age_sec = "63072000"
      include_subdomains         = true
      preload                    = true
      override                   = true
    }
    content_security_policy {
      content_security_policy = var.content_security_policy
      override                = true
    }
  }
}

