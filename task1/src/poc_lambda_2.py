import boto3, json, os

client = boto3.client('sns')
sns_arn = os.environ['SNS_TOPIC_ARN']

def lambda_handler(event, context):

    for record in event["Records"]:

        if record['eventName'] == 'INSERT':
            new_record = record['dynamodb']['NewImage']    
            response = client.publish(
                TargetArn=sns_arn,
                Message=json.dumps({'default': json.dumps(new_record)}),
                MessageStructure='json'
            )