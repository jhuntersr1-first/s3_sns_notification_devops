import json
import boto3
import os
import traceback
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

sns_client = boto3.client('sns')
SNS_TOPIC_ARN = os.environ.get('SNS_TOPIC_ARN', '')


def lambda_handler(event, context):
    try:
        if not SNS_TOPIC_ARN:
            logger.error("SNS_TOPIC_ARN environment variable is missing or empty")
            return {
                "statusCode": 500,
                "body": json.dumps("SNS_TOPIC_ARN environment variable is missing")
            }

        if not isinstance(event, dict):
            logger.error("Event is not a dict")
            return {"statusCode": 400, "body": "Invalid event format"}

        records = event.get('Records', [])
        if not records:
            logger.warning("No records found in event")
            return {"statusCode": 400, "body": "No records found"}

        sent_count = 0
        for i, record in enumerate(records):
            try:
                s3_data = record.get('s3', {})
                bucket_data = s3_data.get('bucket', {})
                object_data = s3_data.get('object', {})

                bucket_name = bucket_data.get('name', 'Unknown')
                object_key = object_data.get('key', 'Unknown')
                event_time = record.get('eventTime', 'Unknown')
                event_name = record.get('eventName', 'Unknown')
                region = record.get('awsRegion', 'Unknown')
                object_size = object_data.get('size', 'Unknown')

                logger.info(f"Processing record {i+1}: bucket={bucket_name}, key={object_key}")

                message = (
                    f"New S3 Upload Notification\n\n"
                    f"Bucket: {bucket_name}\n"
                    f"File: {object_key}\n"
                    f"Size: {object_size} bytes\n"
                    f"Event Time: {event_time}\n"
                    f"Region: {region}\n"
                    f"Event Type: {event_name}\n\n"
                    f"View the file: https://s3.console.aws.amazon.com/s3/object/{bucket_name}"
                    f"?region={region}&prefix={object_key}"
                )

                sns_client.publish(
                    TopicArn=SNS_TOPIC_ARN,
                    Message=message,
                    Subject="S3 Upload Notification"
                )

                logger.info(f"Successfully sent notification for {object_key}")
                sent_count += 1

            except Exception as record_error:
                logger.error(f"Failed to process record {i+1}: {str(record_error)}\n{traceback.format_exc()}")
                continue

        return {
            "statusCode": 200,
            "body": json.dumps(f"Successfully sent {sent_count} notifications")
        }

    except Exception as e:
        logger.error(f"Lambda handler failed: {str(e)}\n{traceback.format_exc()}")
        return {
            "statusCode": 500,
            "body": json.dumps(f"Lambda execution failed: {str(e)}")
        }
