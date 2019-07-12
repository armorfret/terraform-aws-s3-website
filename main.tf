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
  version   = "0.1.3"
  hostnames = concat([var.primary_hostname], var.redirect_hostnames)
}

module "publish_user" {
  source         = "armorfret/s3-publish/aws"
  version        = "0.1.0"
  logging_bucket = var.logging_bucket
  publish_bucket = var.file_bucket
  make_bucket    = "0"
}

resource "aws_s3_bucket" "redirect" {
  bucket = var.redirect_bucket
  policy = data.aws_iam_policy_document.redirect_bucket_read_access.json

  versioning {
    enabled = "true"
  }

  logging {
    target_bucket = var.logging_bucket
    target_prefix = "${var.redirect_bucket}/"
  }

  website {
    redirect_all_requests_to = "https://${var.primary_hostname}"
  }
}

resource "aws_cloudfront_distribution" "redirect" {
  origin {
    domain_name = aws_s3_bucket.redirect.website_endpoint
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
}

resource "aws_s3_bucket" "file" {
  bucket = var.file_bucket
  policy = data.aws_iam_policy_document.file_bucket_read_access.json

  versioning {
    enabled = "true"
  }

  logging {
    target_bucket = var.logging_bucket
    target_prefix = "${var.file_bucket}/"
  }

  website {
    index_document = "index.html"
    error_document = var.error_document
  }
}

resource "aws_cloudfront_distribution" "file" {
  origin {
    domain_name = aws_s3_bucket.file.website_endpoint
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
}

