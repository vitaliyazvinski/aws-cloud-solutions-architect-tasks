provider "aws" {
  profile = var.aws_profile
  region  = var.aws_region
}

// create aws iam policy to allow to put item to dynamodb and describe table
resource "aws_iam_policy" "Lambda-Write-DynamoDB" {
  name        = "Lambda-Write-DynamoDB"
  description = "Allow to put item to dynamodb and describe table"
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Action" : [
          "dynamodb:PutItem",
          "dynamodb:DescribeTable"
        ],
        "Resource" : "*"
      }
    ]
  })
}

resource "aws_iam_policy" "Lambda-SNS-Publish" {
  name        = "Lambda-SNS-Publish"
  description = "Allow to publish to SNS"
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Action" : [
          "sns:Publish",
          "sns:GetTopicAttributes",
          "sns:ListTopics"
        ],
        "Resource" : "*"
      }
    ]
  })
}

resource "aws_iam_policy" "Lambda-Read-SQS" {
  name        = "Lambda-Read-SQS"
  description = "Allow to read from SQS"
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Action" : [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:ChangeMessageVisibility"
        ],
        "Resource" : "*"
      }
    ]
  })
}

resource "aws_iam_policy" "Lambda-DynamoDBStreams-Read" {
  name        = "Lambda-DynamoDBStreams-Read"
  description = "Allow to read from DynamoDB Streams"
  policy = jsonencode({
    "Version" : "2012-10-17",
    Statement : [
      {
        "Effect" : "Allow",
        "Action" : [
          "dynamodb:GetShardIterator",
          "dynamodb:DescribeStream",
          "dynamodb:ListStreams",
          "dynamodb:GetRecords"
        ],
        "Resource" : "*"
      }
    ]
  })
}

resource "aws_iam_role" "Lambda-SQS-DynamoDB" {
  name = "Lambda-SQS-DynamoDB"

  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Principal" : {
          "Service" : "lambda.amazonaws.com"
        }
        "Action" : "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role" "Lambda-DynamoDBStreams-SNS" {
  name = "Lambda-DynamoDBStreams-SNS"

  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Principal" : {
          "Service" : "lambda.amazonaws.com"
        }
        "Action" : "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role" "APIGateway-SQS" {
  name = "APIGateway-SQS"

  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Principal" : {
          "Service" : "apigateway.amazonaws.com"
        }
        "Action" : "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "Lambda-Write-DynamoDB" {
  role       = aws_iam_role.Lambda-SQS-DynamoDB.name
  policy_arn = aws_iam_policy.Lambda-Write-DynamoDB.arn
}

resource "aws_iam_role_policy_attachment" "Lambda-Read-SQS" {
  role       = aws_iam_role.Lambda-SQS-DynamoDB.name
  policy_arn = aws_iam_policy.Lambda-Read-SQS.arn
}

resource "aws_iam_role_policy_attachment" "Lambda-SNS-Publish" {
  role       = aws_iam_role.Lambda-DynamoDBStreams-SNS.name
  policy_arn = aws_iam_policy.Lambda-SNS-Publish.arn
}

resource "aws_iam_role_policy_attachment" "Lambda-DynamoDBStreams-SNS" {
  role       = aws_iam_role.Lambda-DynamoDBStreams-SNS.name
  policy_arn = aws_iam_policy.Lambda-DynamoDBStreams-Read.arn
}

resource "aws_iam_role_policy_attachment" "APIGateway-SQS" {
  role       = aws_iam_role.APIGateway-SQS.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}

resource "aws_dynamodb_table" "orders" {
  name         = "orders"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "orderID"
  attribute {
    name = "orderID"
    type = "S"
  }
  stream_enabled = true
  stream_view_type = "NEW_IMAGE"
}


resource "aws_sqs_queue" "POC_Queue" {
  name = "POC-Queue"
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Principal" : {
          "Service" : "apigateway.amazonaws.com"
        },
        "Action" : "sqs:SendMessage",
        "Resource" : aws_iam_role.APIGateway-SQS.arn
      },
      {
        "Effect" : "Allow",
        "Principal" : {
          "Service" : "lambda.amazonaws.com"
        },
        "Action" : "sqs:ReceiveMessage",
        "Resource" : aws_iam_role.Lambda-SQS-DynamoDB.arn
      }
    ]
  })
}


data "archive_file" "POC_Lambda_1_package" {  
  type = "zip"  
  source_file = "${path.module}/src/poc_lambda_1.py" 
  output_path = "${path.module}/dist/poc_lambda_1_package.zip"
}

resource "aws_lambda_function" "POC_Lambda_1" {
  function_name = "POC-Lambda-1"
  filename = data.archive_file.POC_Lambda_1_package.output_path
  source_code_hash = data.archive_file.POC_Lambda_1_package.output_base64sha256
  handler = "poc_lambda_1.lambda_handler"
  runtime = "python3.9"
  role = aws_iam_role.Lambda-SQS-DynamoDB.arn

}

resource "aws_lambda_event_source_mapping" "POC_Lambda_1" {
  event_source_arn = aws_sqs_queue.POC_Queue.arn
  function_name = aws_lambda_function.POC_Lambda_1.function_name
  batch_size = 1
}

resource "aws_sns_topic" "POC_Topic" {
  name = "POC-Topic"
}

resource "aws_sns_topic_subscription" "POC_Topic_Subscription" {
  topic_arn = aws_sns_topic.POC_Topic.arn
  protocol = "email"
  endpoint = var.subscription_email
}

data "archive_file" "POC_Lambda_2_package" {  
  type = "zip"  
  source_file = "${path.module}/src/poc_lambda_2.py" 
  output_path = "${path.module}/dist/poc_lambda_2_package.zip"
}

resource "aws_lambda_function" "POC_Lambda_2" {
  function_name = "POC-Lambda-2"
  filename = data.archive_file.POC_Lambda_2_package.output_path
  source_code_hash = data.archive_file.POC_Lambda_2_package.output_base64sha256
  handler = "poc_lambda_2.lambda_handler"
  runtime = "python3.9"
  role = aws_iam_role.Lambda-DynamoDBStreams-SNS.arn
  environment {
    variables = {
      SNS_TOPIC_ARN = aws_sns_topic.POC_Topic.arn
    }
  }
  timeout = 10
}

resource "aws_lambda_event_source_mapping" "POC_Lambda_2" {
  event_source_arn = aws_dynamodb_table.orders.stream_arn
  function_name = aws_lambda_function.POC_Lambda_2.function_name
  batch_size = 1
  starting_position = "LATEST"
}

resource "aws_api_gateway_rest_api" "POC_API" {
  name = "POC-API"
  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_resource" "poc_resource" {
  rest_api_id = aws_api_gateway_rest_api.POC_API.id
  parent_id   = aws_api_gateway_rest_api.POC_API.root_resource_id
  path_part   = "poc"
}

resource "aws_api_gateway_method" "poc_post" {
  rest_api_id   = aws_api_gateway_rest_api.POC_API.id
  resource_id   = aws_api_gateway_resource.poc_resource.id
  http_method   = "POST"
  authorization = "NONE"
}
resource "aws_api_gateway_integration" "poc_post_integration" {
  rest_api_id             = aws_api_gateway_rest_api.POC_API.id
  resource_id             = aws_api_gateway_resource.poc_resource.id
  http_method             = aws_api_gateway_method.poc_post.http_method
  integration_http_method = "POST"
  type                    = "AWS"
  uri                     = "arn:aws:apigateway:${var.aws_region}:sqs:path/${var.aws_account_id}/${aws_sqs_queue.POC_Queue.name}"
  credentials             = aws_iam_role.APIGateway-SQS.arn

  request_parameters = {
    "integration.request.header.Content-Type" = "'application/x-www-form-urlencoded'"
  }

  request_templates = {
    "application/json" = "Action=SendMessage&MessageBody=$input.body"
  }

  content_handling = "CONVERT_TO_TEXT"
}

resource "aws_api_gateway_method_response" "poc_post_response" {
  rest_api_id = aws_api_gateway_rest_api.POC_API.id
  resource_id = aws_api_gateway_resource.poc_resource.id
  http_method = aws_api_gateway_method.poc_post.http_method
  status_code = "200"
}

resource "aws_api_gateway_integration_response" "poc_post_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.POC_API.id
  resource_id = aws_api_gateway_resource.poc_resource.id
  http_method = aws_api_gateway_method.poc_post.http_method
  status_code = aws_api_gateway_method_response.poc_post_response.status_code
  selection_pattern = ""
}

resource "aws_api_gateway_deployment" "poc_api_deployment" {
  depends_on = [aws_api_gateway_integration.poc_post_integration]
  rest_api_id = aws_api_gateway_rest_api.POC_API.id
  stage_name  = "prod"
}
