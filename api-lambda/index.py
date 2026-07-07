import json
import datetime

def handler(event, context):
    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps({
            "status": "healthy",
            "service": "CloudCart API",
            "timestamp": datetime.datetime.utcnow().isoformat(),
            "architecture": "serverless"
        })
    }
