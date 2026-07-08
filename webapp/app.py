from flask import Flask, render_template, request, redirect, session, url_for
import requests
import boto3
import uuid
import datetime

app = Flask(__name__)
app.secret_key = "cloudcart-demo-secret"

PRODUCTS = [
    {"id": 1, "name": "Wireless Headphones", "price": 79.99, "img": "https://ashwin-cloudcart-images.s3.eu-central-1.amazonaws.com/headphones.jpg", "desc": "Noise-cancelling over-ear headphones with 30hr battery life."},
    {"id": 2, "name": "Smart Watch", "price": 149.99, "img": "https://ashwin-cloudcart-images.s3.eu-central-1.amazonaws.com/watch.jpg", "desc": "Fitness tracking, heart rate monitor, 7-day battery."},
    {"id": 3, "name": "Mechanical Keyboard", "price": 99.99, "img": "https://ashwin-cloudcart-images.s3.eu-central-1.amazonaws.com/keyboard.jpg", "desc": "RGB backlit mechanical keyboard with hot-swappable switches."},
    {"id": 4, "name": "Portable Speaker", "price": 59.99, "img": "https://ashwin-cloudcart-images.s3.eu-central-1.amazonaws.com/speaker.jpg", "desc": "Waterproof Bluetooth speaker with 20hr playtime."},
    {"id": 5, "name": "Laptop Stand", "price": 34.99, "img": "https://ashwin-cloudcart-images.s3.eu-central-1.amazonaws.com/standx.jpg", "desc": "Adjustable aluminum laptop stand for ergonomic setup."},
    {"id": 6, "name": "USB-C Hub", "price": 44.99, "img": "https://ashwin-cloudcart-images.s3.eu-central-1.amazonaws.com/hub.jpg", "desc": "7-in-1 USB-C hub with HDMI, SD card reader, and fast charging."},
]

def get_instance_id():
    try:
        token = requests.put(
            "http://169.254.169.254/latest/api/token",
            headers={"X-aws-ec2-metadata-token-ttl-seconds": "21600"},
            timeout=1
        ).text
        response = requests.get(
            "http://169.254.169.254/latest/meta-data/instance-id",
            headers={"X-aws-ec2-metadata-token": token},
            timeout=1
        )
        return response.text if response.text else "local-dev"
    except Exception:
        return "local-dev"

@app.route("/")
def index():
    return render_template("index.html", products=PRODUCTS, instance_id=get_instance_id())

@app.route("/product/<int:product_id>")
def product_detail(product_id):
    product = next((p for p in PRODUCTS if p["id"] == product_id), None)
    return render_template("product.html", product=product, instance_id=get_instance_id())

@app.route("/add-to-cart/<int:product_id>")
def add_to_cart(product_id):
    cart = session.get("cart", [])
    cart.append(product_id)
    session["cart"] = cart
    return redirect(url_for("view_cart"))

@app.route("/cart")
def view_cart():
    cart_ids = session.get("cart", [])
    cart_items = [p for p in PRODUCTS if p["id"] in cart_ids]
    total = sum(p["price"] for p in cart_items)
    return render_template("cart.html", items=cart_items, total=total, instance_id=get_instance_id())

@app.route("/remove-from-cart/<int:product_id>")
def remove_from_cart(product_id):
    cart = session.get("cart", [])
    if product_id in cart:
        cart.remove(product_id)
    session["cart"] = cart
    return redirect(url_for("view_cart"))

@app.route("/checkout", methods=["POST"])
def checkout():
    cart_ids = session.get("cart", [])
    cart_items = [p for p in PRODUCTS if p["id"] in cart_ids]
    total = sum(p["price"] for p in cart_items)

    order_id = str(uuid.uuid4())
    try:
        table = boto3.resource("dynamodb", region_name="eu-central-1").Table("cloudcart-orders")
        table.put_item(Item={
            "order_id": order_id,
            "items": [p["name"] for p in cart_items],
            "total": str(total),
            "timestamp": datetime.datetime.utcnow().isoformat(),
            "instance_id": get_instance_id()
        })
        db_status = "saved"
    except Exception as e:
        db_status = f"error: {str(e)}"

    session["cart"] = []
    return render_template("checkout.html", instance_id=get_instance_id(), order_id=order_id, db_status=db_status)

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=80)
