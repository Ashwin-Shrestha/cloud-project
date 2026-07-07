import json

def handler(event, context):
    for record in event["Records"]:
        if record["eventName"] == "INSERT":
            new_order = record["dynamodb"]["NewImage"]
            order_id = new_order.get("order_id", {}).get("S", "unknown")
            total = new_order.get("total", {}).get("S", "unknown")
            print(f"Order confirmation triggered: Order {order_id}, Total ${total}")
            print("(In production, this would send a confirmation email/SMS to the customer)")
    return {"statusCode": 200, "body": json.dumps("Processed")}
