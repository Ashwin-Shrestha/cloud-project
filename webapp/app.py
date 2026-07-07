from flask import Flask, render_template, request, redirect, session, url_for
import requests

app = Flask(__name__)
app.secret_key = "cloudcart-demo-secret"

PRODUCTS = [
    {"id": 1, "name": "Wireless Headphones", "price": 79.99, "img": "https://picsum.photos/seed/headphones/400/300", "desc": "Noise-cancelling over-ear headphones with 30hr battery life."},
    {"id": 2, "name": "Smart Watch", "price": 149.99, "img": "https://picsum.photos/seed/watch/400/300", "desc": "Fitness tracking, heart rate monitor, 7-day battery."},
    {"id": 3, "name": "Mechanical Keyboard", "price": 99.99, "img": "https://picsum.photos/seed/keyboard/400/300", "desc": "RGB backlit mechanical keyboard with hot-swappable switches."},
    {"id": 4, "name": "Portable Speaker", "price": 59.99, "img": "https://picsum.photos/seed/speaker/400/300", "desc": "Waterproof Bluetooth speaker with 20hr playtime."},
    {"id": 5, "name": "Laptop Stand", "price": 34.99, "img": "https://picsum.photos/seed/standx/400/300", "desc": "Adjustable aluminum laptop stand for ergonomic setup."},
    {"id": 6, "name": "USB-C Hub", "price": 44.99, "img": "https://picsum.photos/seed/hub/400/300", "desc": "7-in-1 USB-C hub with HDMI, SD card reader, and fast charging."},
]

def get_instance_id():
    try:
        return requests.get("http://169.254.169.254/latest/meta-data/instance-id", timeout=1).text
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
    session["cart"] = []
    return render_template("checkout.html", instance_id=get_instance_id())

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=80)
