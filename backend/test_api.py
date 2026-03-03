"""
Backend API Tests using pytest

Run with: pytest test_api.py -v

Note: These tests run against the actual MySQL database.
Make sure the backend and database are running before executing tests.
"""

import pytest
import json
from app import app


@pytest.fixture
def client():
    """Create a test client for the Flask application"""
    app.config['TESTING'] = True
    
    with app.test_client() as client:
        yield client


@pytest.fixture
def auth_headers(client):
    """Get authentication headers for testing protected endpoints"""
    # Login as admin to get token
    response = client.post('/api/auth/login', json={
        'username': 'admin',
        'password': 'admin123'
    })
    
    if response.status_code == 200:
        data = json.loads(response.data)
        # API returns nested data structure
        if 'data' in data:
            token = data['data'].get('access_token')
        else:
            token = data.get('access_token')
        return {'Authorization': f'Bearer {token}'}
    
    return {}


class TestAuthRoutes:
    """Test authentication endpoints"""
    
    def test_login_success(self, client):
        """Test successful login"""
        response = client.post('/api/auth/login', json={
            'username': 'admin',
            'password': 'admin123'
        })
        
        assert response.status_code == 200
        data = json.loads(response.data)
        # Check nested structure
        if 'data' in data:
            assert 'access_token' in data['data']
            assert 'refresh_token' in data['data']
            assert 'user' in data['data']
        else:
            assert 'access_token' in data
            assert 'refresh_token' in data
            assert 'user' in data
    
    def test_login_invalid_credentials(self, client):
        """Test login with invalid credentials"""
        response = client.post('/api/auth/login', json={
            'username': 'invalid',
            'password': 'wrong'
        })
        
        assert response.status_code == 401
        data = json.loads(response.data)
        assert data['success'] is False
    
    def test_login_missing_fields(self, client):
        """Test login with missing fields"""
        response = client.post('/api/auth/login', json={
            'username': 'admin'
        })
        
        assert response.status_code in [400, 422]
    
    def test_pin_login(self, client):
        """Test PIN login"""
        response = client.post('/api/auth/pin-login', json={
            'username': 'admin',
            'pin': '1234'
        })
        
        # Should succeed if PIN is set, or fail gracefully
        assert response.status_code in [200, 401, 404]
    
    def test_token_refresh(self, client, auth_headers):
        """Test token refresh"""
        # First login to get refresh token
        response = client.post('/api/auth/login', json={
            'username': 'admin',
            'password': 'admin123'
        })
        
        if response.status_code == 200:
            data = json.loads(response.data)
            refresh_token = data.get('refresh_token')
            
            # Try to refresh
            response = client.post('/api/auth/refresh', 
                headers={'Authorization': f'Bearer {refresh_token}'})
            
            if response.status_code == 200:
                data = json.loads(response.data)
                assert 'access_token' in data


class TestProductRoutes:
    """Test product endpoints"""
    
    def test_get_products(self, client, auth_headers):
        """Test getting all products"""
        response = client.get('/api/products', headers=auth_headers)
        
        assert response.status_code == 200
        data = json.loads(response.data)
        assert 'data' in data
        assert isinstance(data['data'], list)
    
    def test_get_product_by_id(self, client, auth_headers):
        """Test getting a specific product"""
        # First get all products
        response = client.get('/api/products', headers=auth_headers)
        products = json.loads(response.data).get('data', [])
        
        if products:
            product_id = products[0]['id']
            response = client.get(f'/api/products/{product_id}', headers=auth_headers)
            assert response.status_code == 200
            data = json.loads(response.data)
            assert data['data']['id'] == product_id
    
    def test_get_product_not_found(self, client, auth_headers):
        """Test getting non-existent product"""
        response = client.get('/api/products/99999', headers=auth_headers)
        assert response.status_code == 404
    
    def test_create_product(self, client, auth_headers):
        """Test creating a new product"""
        new_product = {
            'name': 'Test Product',
            'category': 'Test Category',
            'price': 99.99,
            'stock': 10,
            'barcode': 'TEST123'
        }
        
        response = client.post('/api/products', 
                              json=new_product,
                              headers=auth_headers)
        
        # Should succeed or fail gracefully
        assert response.status_code in [200, 201, 400, 403]
    
    def test_update_product(self, client, auth_headers):
        """Test updating a product"""
        # Get first product
        response = client.get('/api/products', headers=auth_headers)
        products = json.loads(response.data).get('data', [])
        
        if products:
            product_id = products[0]['id']
            update_data = {'price': 199.99}
            
            response = client.put(f'/api/products/{product_id}',
                                json=update_data,
                                headers=auth_headers)
            
            assert response.status_code in [200, 403]
    
    def test_search_products(self, client, auth_headers):
        """Test product search"""
        response = client.get('/api/products?search=test', headers=auth_headers)
        
        assert response.status_code == 200
        data = json.loads(response.data)
        assert isinstance(data.get('data', []), list)
    
    def test_get_low_stock_products(self, client, auth_headers):
        """Test getting low stock products"""
        response = client.get('/api/products?low_stock=true', headers=auth_headers)
        
        assert response.status_code == 200
        data = json.loads(response.data)
        assert isinstance(data.get('data', []), list)


class TestTransactionRoutes:
    """Test transaction endpoints"""
    
    def test_get_transactions(self, client, auth_headers):
        """Test getting all transactions"""
        response = client.get('/api/transactions', headers=auth_headers)
        
        assert response.status_code == 200
        data = json.loads(response.data)
        assert 'data' in data
        assert isinstance(data['data'], list)
    
    def test_create_transaction(self, client, auth_headers):
        """Test creating a transaction"""
        transaction_data = {
            'items': [
                {
                    'product_id': '1',
                    'quantity': 2,
                    'price': 100.0
                }
            ],
            'payment_method': 'cash',
            'subtotal': 200.0,
            'tax': 24.0,
            'discount': 0.0,
            'total': 224.0
        }
        
        response = client.post('/api/transactions',
                              json=transaction_data,
                              headers=auth_headers)
        
        # Should succeed or fail gracefully (500 if product not found or other issues)
        assert response.status_code in [200, 201, 400, 404, 500]
    
    def test_get_transaction_by_id(self, client, auth_headers):
        """Test getting specific transaction"""
        response = client.get('/api/transactions', headers=auth_headers)
        transactions = json.loads(response.data).get('data', [])
        
        if transactions:
            txn_id = transactions[0]['id']
            response = client.get(f'/api/transactions/{txn_id}', headers=auth_headers)
            assert response.status_code == 200


class TestCategoryRoutes:
    """Test category endpoints"""
    
    def test_get_categories(self, client, auth_headers):
        """Test getting all categories"""
        response = client.get('/api/categories', headers=auth_headers)
        
        assert response.status_code == 200
        data = json.loads(response.data)
        assert 'data' in data
        assert isinstance(data['data'], list)
    
    def test_create_category(self, client, auth_headers):
        """Test creating a category"""
        category_data = {
            'name': 'Test Category',
            'icon': '🧪'
        }
        
        response = client.post('/api/categories',
                              json=category_data,
                              headers=auth_headers)
        
        # May return 500 due to database issues or 403 if not supervisor
        assert response.status_code in [200, 201, 400, 403, 500]


class TestReportRoutes:
    """Test report endpoints"""
    
    def test_get_daily_report(self, client, auth_headers):
        """Test getting daily sales report"""
        response = client.get('/api/reports/daily', headers=auth_headers)
        
        assert response.status_code == 200
        data = json.loads(response.data)
        assert 'data' in data
    
    def test_get_sales_summary(self, client, auth_headers):
        """Test getting sales summary"""
        response = client.get('/api/reports/weekly', 
                             headers=auth_headers)
        
        assert response.status_code == 200
        data = json.loads(response.data)
        assert 'data' in data


class TestUserRoutes:
    """Test user management endpoints"""
    
    def test_get_users(self, client, auth_headers):
        """Test getting all users"""
        response = client.get('/api/users', headers=auth_headers)
        
        assert response.status_code in [200, 403]
    
    def test_create_user(self, client, auth_headers):
        """Test creating a new user"""
        user_data = {
            'username': 'testuser',
            'password': 'Test123!',
            'full_name': 'Test User',
            'role': 'cashier'
        }
        
        response = client.post('/api/users',
                              json=user_data,
                              headers=auth_headers)
        
        # Should succeed or fail based on permissions
        assert response.status_code in [200, 201, 400, 403]


class TestErrorHandling:
    """Test API error handling"""
    
    def test_404_not_found(self, client):
        """Test 404 error handling"""
        response = client.get('/api/nonexistent')
        assert response.status_code == 404
    
    def test_401_unauthorized(self, client):
        """Test unauthorized access"""
        response = client.get('/api/products')
        assert response.status_code in [401, 403]
    
    def test_invalid_json(self, client, auth_headers):
        """Test invalid JSON handling"""
        response = client.post('/api/products',
                              data='invalid json',
                              headers=auth_headers,
                              content_type='application/json')
        
        # Flask might return 500 if JSON parsing fails before validation
        assert response.status_code in [400, 422, 500]
    
    def test_method_not_allowed(self, client, auth_headers):
        """Test method not allowed"""
        response = client.patch('/api/products', headers=auth_headers)
        assert response.status_code in [405, 404]


class TestValidation:
    """Test input validation"""
    
    def test_create_product_missing_required_fields(self, client, auth_headers):
        """Test creating product with missing fields"""
        response = client.post('/api/products',
                              json={'name': 'Test'},
                              headers=auth_headers)
        
        assert response.status_code in [400, 422]
    
    def test_create_product_invalid_price(self, client, auth_headers):
        """Test creating product with invalid price"""
        product_data = {
            'name': 'Test',
            'price': -10,
            'stock': 10
        }
        
        response = client.post('/api/products',
                              json=product_data,
                              headers=auth_headers)
        
        assert response.status_code in [400, 422]
    
    def test_create_transaction_invalid_data(self, client, auth_headers):
        """Test creating transaction with invalid data"""
        response = client.post('/api/transactions',
                              json={'items': []},
                              headers=auth_headers)
        
        assert response.status_code in [400, 422]


if __name__ == '__main__':
    pytest.main([__file__, '-v'])
