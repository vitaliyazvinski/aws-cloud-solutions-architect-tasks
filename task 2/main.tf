provider "aws" {
  profile = var.aws_profile
  region  = var.aws_region
}

resource "aws_iam_policy" "API_Firehose" {
  name = "API-Firehose"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "firehose:PutRecord",
        ],
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_policy" "Lambda_Cloudwatch" {
  name = "Lambda-CloudWatch"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_policy" "Lambda_Invoke_Policy" {
  name        = "Lambda-Invoke-Policy"
  description = "Policy to allow invoking lambda function"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid    = "",
        Effect = "Allow",
        Action = [
          "lambda:InvokeFunction",
          "lambda:GetFunctionConfiguration"
        ],
        Resource = "${aws_lambda_function.transform_data.arn}:*"
      },
    ]
  })
}

resource "aws_iam_role" "APIGateway_Firehose" {
  name = "APIGateway-Firehose"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "apigateway.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role" "Lambda_Cloudwatch" {
  name = "Lambda-Cloudwatch"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role" "Firehose_S3" {
  name = "Firehose-S3"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "firehose.amazonaws.com"
        },
        Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "Firehose_Lambda" {
  role       = aws_iam_role.Firehose_S3.name
  policy_arn = aws_iam_policy.Lambda_Invoke_Policy.arn
}


resource "aws_iam_role_policy_attachment" "Firehose_S3" {
  role       = aws_iam_role.Firehose_S3.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

resource "aws_iam_role_policy_attachment" "Lambda_Cloudwatch" {
  role       = aws_iam_role.Lambda_Cloudwatch.name
  policy_arn = aws_iam_policy.Lambda_Cloudwatch.arn
}

resource "aws_iam_role_policy_attachment" "APIGateway_Firehose" {
  role       = aws_iam_role.APIGateway_Firehose.name
  policy_arn = aws_iam_policy.API_Firehose.arn

}

resource "aws_s3_bucket" "APIGateway_Firehose" {
  bucket = "architecting-week2-abcd"

}

data "archive_file" "transform_data_package" {
  type        = "zip"
  source_file = "${path.module}/src/transform_data.py"
  output_path = "${path.module}/dist/transform_data_package.zip"
}

resource "aws_lambda_function" "transform_data" {
  function_name    = "transform-data"
  description      = "Transform data from Firehose to S3"
  filename         = data.archive_file.transform_data_package.output_path
  source_code_hash = data.archive_file.transform_data_package.output_base64sha256
  handler          = "transform_data.lambda_handler"
  runtime          = "python3.9"
  role             = aws_iam_role.Lambda_Cloudwatch.arn
  timeout          = 60
}

resource "aws_kinesis_firehose_delivery_stream" "Firehose_S3" {
  name        = "PUT-S3"
  destination = "extended_s3"
  extended_s3_configuration {
    bucket_arn = aws_s3_bucket.APIGateway_Firehose.arn
    role_arn   = aws_iam_role.Firehose_S3.arn
    processing_configuration {
      enabled = true
      processors {
        type = "Lambda"
        parameters {
          parameter_name  = "LambdaArn"
          parameter_value = aws_lambda_function.transform_data.arn
        }
      }
    }
  }
}

resource "aws_s3_bucket_policy" "APIGateway_Firehose" {
  bucket = aws_s3_bucket.APIGateway_Firehose.bucket
  policy = jsonencode({
    Version = "2012-10-17",
    Id      = "PolicyID",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          AWS = aws_iam_role.Firehose_S3.arn
        },
        Action = [
          "s3:AbortMultipartUpload",
          "s3:GetBucketLocation",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:ListBucketMultipartUploads",
          "s3:PutObject",
          "s3:PutObjectAcl"
        ],
        Resource = [
          "${aws_s3_bucket.APIGateway_Firehose.arn}",
          "${aws_s3_bucket.APIGateway_Firehose.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_api_gateway_rest_api" "APIGateway_Firehose" {
  name        = "clickstream-ingest-poc"
  description = "API Gateway for Firehose"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_resource" "APIGateway_Firehose" {
  rest_api_id = aws_api_gateway_rest_api.APIGateway_Firehose.id
  parent_id   = aws_api_gateway_rest_api.APIGateway_Firehose.root_resource_id
  path_part   = "poc"
}

resource "aws_api_gateway_method" "APIGateway_Firehose" {
  rest_api_id   = aws_api_gateway_rest_api.APIGateway_Firehose.id
  resource_id   = aws_api_gateway_resource.APIGateway_Firehose.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "APIGateway_Firehose" {
  rest_api_id             = aws_api_gateway_rest_api.APIGateway_Firehose.id
  resource_id             = aws_api_gateway_resource.APIGateway_Firehose.id
  http_method             = aws_api_gateway_method.APIGateway_Firehose.http_method
  integration_http_method = "POST"
  type                    = "AWS"
  uri                     = "arn:aws:apigateway:${var.aws_region}:firehose:action/PutRecord"
  credentials             = aws_iam_role.APIGateway_Firehose.arn

  request_parameters = {
    "integration.request.header.Content-Type" = "'application/json'"
  }

  request_templates = {
    "application/json" = jsonencode({
      DeliveryStreamName = aws_kinesis_firehose_delivery_stream.Firehose_S3.name,
      Record = {
        Data = "$util.base64Encode($util.escapeJavaScript($input.json('$')).replace('\\', ''))"
      }
    })
  }
}

resource "aws_api_gateway_method_response" "APIGateway_Firehose" {
  rest_api_id = aws_api_gateway_rest_api.APIGateway_Firehose.id
  resource_id = aws_api_gateway_resource.APIGateway_Firehose.id
  http_method = aws_api_gateway_method.APIGateway_Firehose.http_method
  status_code = "200"
}

resource "aws_api_gateway_integration_response" "APIGateway_Firehose" {
  rest_api_id       = aws_api_gateway_rest_api.APIGateway_Firehose.id
  resource_id       = aws_api_gateway_resource.APIGateway_Firehose.id
  http_method       = aws_api_gateway_method.APIGateway_Firehose.http_method
  status_code       = aws_api_gateway_method_response.APIGateway_Firehose.status_code
  selection_pattern = ""
}

resource "aws_api_gateway_deployment" "APIGateway_Firehose" {
  depends_on  = [aws_api_gateway_integration.APIGateway_Firehose]
  rest_api_id = aws_api_gateway_rest_api.APIGateway_Firehose.id
  stage_name  = "prod"
}
