# Vivian Cosmetic Shop - Python Backend

## Setup Instructions

### Prerequisites
1. **Python 3.9+** installed
2. **XAMPP** installed and MySQL running
3. **pip** package manager

### Installation

1. **Navigate to backend directory:**
   ```bash
   cd backend
   ```

2. **Create virtual environment:**
   ```bash
   python -m venv venv
   ```

3. **Activate virtual environment:**
   - Windows:
     ```bash
     venv\Scripts\activate
     ```
   - macOS/Linux:
     ```bash
     source venv/bin/activate
     ```

4. **Install dependencies:**
   ```bash
   pip install -r requirements.txt
   ```

5. **Configure environment:**
   - Copy `.env.example` to `.env`
   - Update database credentials if needed (default XAMPP has no password)

### Email OTP (Forgot Password) Setup

The **Forgot Password** flow sends a 6-digit OTP to the user's email via SMTP.

1. In `backend/.env`, set at least:
    - `SMTP_HOST`
    - `SMTP_PORT` (default `587`)
    - `SMTP_USERNAME`
    - `SMTP_PASSWORD`
    - `SMTP_FROM` (optional; defaults to `SMTP_USERNAME`)
    - `SMTP_USE_TLS` (default `true`)

2. Optional (password reset email text):
    - `PWD_RESET_EMAIL_SUBJECT`
    - `PWD_RESET_EMAIL_BODY_TEMPLATE` (use `{otp}` placeholder)

Notes:
- For Gmail, use an **App Password** (not your normal login password).
- Make sure the user account you're testing has a valid `email` value in the database.

6. **Create database:**
   - Open XAMPP Control Panel
   - Start MySQL
   - Open phpMyAdmin (http://localhost/phpmyadmin)
   - Import `database/schema.sql` or run it in SQL tab

7. **Run the server:**
   ```bash
   python app.py
   ```

The API will be available at `http://localhost:5000`

### API Endpoints

#### Authentication
| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/api/auth/login` | Login with username/password or PIN |
| POST | `/api/auth/logout` | Logout current user |
| POST | `/api/auth/refresh` | Refresh access token |
| GET | `/api/auth/me` | Get current user info |
| GET | `/api/auth/verify` | Verify token validity |
| POST | `/api/auth/change-password` | Change password |
| POST | `/api/auth/set-pin` | Set/update PIN |
| POST | `/api/auth/password-reset/request` | Request email OTP for password reset |
| POST | `/api/auth/password-reset/confirm` | Confirm OTP and set new password |

#### Users (Supervisor only)
| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/users` | Get all users |
| GET | `/api/users/:id` | Get specific user |
| POST | `/api/users` | Create new user |
| PUT | `/api/users/:id` | Update user |
| DELETE | `/api/users/:id` | Deactivate user |

#### Products
| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/products` | Get all products |
| GET | `/api/products/:id` | Get specific product |
| GET | `/api/products/barcode/:code` | Get product by barcode |
| POST | `/api/products` | Create product (supervisor) |
| PUT | `/api/products/:id` | Update product (supervisor) |
| PATCH | `/api/products/:id/stock` | Update stock |

#### Categories
| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/categories` | Get all categories |
| POST | `/api/categories` | Create category (supervisor) |
| PUT | `/api/categories/:id` | Update category (supervisor) |
| DELETE | `/api/categories/:id` | Remove category (supervisor; soft delete) |

#### Transactions
| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/transactions` | Get transactions |
| GET | `/api/transactions/:id` | Get specific transaction |
| POST | `/api/transactions` | Create transaction (checkout) |
| POST | `/api/transactions/:id/void` | Void transaction (supervisor) |

#### Customers
| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/customers` | Get all customers |
| POST | `/api/customers` | Create customer |
| PUT | `/api/customers/:id` | Update customer |

#### Reports
| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/reports/daily` | Daily sales report |
| GET | `/api/reports/weekly` | Weekly sales report |
| GET | `/api/reports/monthly` | Monthly sales report |
| GET | `/api/reports/top-products` | Top selling products |
| GET | `/api/reports/low-stock` | Low stock alerts |

#### Settings
| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/settings` | Get all settings |
| PUT | `/api/settings` | Update settings (supervisor) |

### Login Example

**Request:**
```json
POST /api/auth/login
{
    "username": "admin",
    "password": "admin123"
}
```

**Response:**
```json
{
    "success": true,
    "message": "Login successful",
    "data": {
        "access_token": "eyJ...",
        "refresh_token": "eyJ...",
        "user": {
            "id": 1,
            "username": "admin",
            "full_name": "Admin User",
            "role": "supervisor"
        }
    }
}
```

### Default Users

| Username | Password | PIN | Role |
|----------|----------|-----|------|
| admin | admin123 | 1234 | supervisor |
| cashier1 | cashier123 | - | cashier |

**Note:** For first-time setup, you'll need to create users with proper password hashes. Run the following after setting up the database:

```python
from app import app, db
from models.user import User

with app.app_context():
    # Create admin user
    admin = User(
        username='admin',
        first_name='Admin',
        last_name='User',
        password='admin123',
        role='supervisor',
        email='admin@viviancosmetics.com'
    )
    admin.set_pin('1234')
    db.session.add(admin)
    
    # Create cashier
    cashier = User(
        username='cashier1',
        first_name='Maria',
        last_name='Santos',
        password='cashier123',
        role='cashier',
        email='cashier1@viviancosmetics.com'
    )
    db.session.add(cashier)
    
    db.session.commit()
    print("Users created successfully!")
```
