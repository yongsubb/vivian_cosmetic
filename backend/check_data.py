from app import app, db
from models.product import Product
from models.transaction import Transaction
from models.loyalty import LoyaltyMember
from models.customer import Customer

with app.app_context():
    products = Product.query.count()
    transactions = Transaction.query.count()
    members = LoyaltyMember.query.count()
    customers = Customer.query.count()
    
    print(f"Products: {products}")
    print(f"Transactions: {transactions}")
    print(f"Loyalty Members: {members}")
    print(f"Customers: {customers}")
    
    if products == 0:
        print("\n⚠️ No products in database!")
    else:
        print(f"\n✅ Found {products} products")
        
    if transactions == 0:
        print("⚠️ No transactions in database!")
    else:
        print(f"✅ Found {transactions} transactions")
