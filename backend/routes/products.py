"""
Products routes - Product management
"""
import os
import time
from flask import Blueprint, request, jsonify
from flask import current_app
from flask_jwt_extended import jwt_required, get_jwt, get_jwt_identity
from werkzeug.utils import secure_filename
from extensions import db
from models.product import Product, Category
from utils.activity_logger import log_activity

products_bp = Blueprint('products', __name__)


def _is_allowed_image_filename(filename: str) -> bool:
    ext = os.path.splitext(filename)[1].lower()
    return ext in {'.png', '.jpg', '.jpeg', '.webp'}


@products_bp.route('/', methods=['GET'])
@jwt_required()
def get_products():
    """Get all products with optional filtering and pagination"""
    try:
        query = Product.query.filter_by(is_active=True)
        
        # Filter by category
        category_id = request.args.get('category_id')
        if category_id:
            query = query.filter_by(category_id=category_id)
        
        # Filter by featured
        is_featured = request.args.get('featured')
        if is_featured:
            query = query.filter_by(is_featured=True)
        
        # Search by name
        search = request.args.get('search')
        if search:
            query = query.filter(Product.name.ilike(f'%{search}%'))
        
        # Low stock filter
        low_stock = request.args.get('low_stock')
        if low_stock:
            query = query.filter(Product.stock_quantity <= Product.low_stock_threshold)
        
        # Pagination
        page = int(request.args.get('page', 1))
        per_page = int(request.args.get('per_page', 20))
        
        # Get total count before pagination
        total_count = query.count()
        
        # Apply pagination
        products = query.offset((page - 1) * per_page).limit(per_page).all()
        
        return jsonify({
            'success': True,
            'data': [p.to_dict() for p in products],
            'pagination': {
                'page': page,
                'per_page': per_page,
                'total': total_count,
                'pages': (total_count + per_page - 1) // per_page,
                'has_next': page * per_page < total_count,
                'has_prev': page > 1
            }
        }), 200
    except Exception as e:
        return jsonify({
            'success': False,
            'message': str(e)
        }), 500


@products_bp.route('/<int:product_id>', methods=['GET'])
@jwt_required()
def get_product(product_id):
    """Get specific product"""
    try:
        product = Product.query.get(product_id)
        if not product:
            return jsonify({
                'success': False,
                'message': 'Product not found'
            }), 404
        return jsonify({
            'success': True,
            'data': product.to_dict()
        }), 200
    except Exception as e:
        return jsonify({
            'success': False,
            'message': str(e)
        }), 500


@products_bp.route('/barcode/<barcode>', methods=['GET'])
@jwt_required()
def get_product_by_barcode(barcode):
    """Get product by barcode"""
    try:
        product = Product.query.filter_by(barcode=barcode, is_active=True).first()
        if not product:
            return jsonify({
                'success': False,
                'message': 'Product not found'
            }), 404
        return jsonify({
            'success': True,
            'data': product.to_dict()
        }), 200
    except Exception as e:
        return jsonify({
            'success': False,
            'message': str(e)
        }), 500


@products_bp.route('/', methods=['POST'])
@jwt_required()
def create_product():
    """Create new product (supervisor only)"""
    try:
        claims = get_jwt()
        if claims.get('role') not in {'supervisor', 'admin', 'superadmin'}:
            return jsonify({
                'success': False,
                'message': 'Supervisor access required'
            }), 403
        
        data = request.get_json() or {}
        
        # Validate required fields
        name = (data.get('name') or '').strip()
        selling_price = data.get('selling_price', None)
        points_cost = data.get('points_cost', 0)

        if isinstance(selling_price, str) and selling_price.strip() == '':
            selling_price = None

        if not name:
            return jsonify({
                'success': False,
                'message': 'Name is required'
            }), 400

        if selling_price is None:
            # Allow reward-only products with points cost.
            try:
                pc = int(points_cost or 0)
            except Exception:
                pc = 0
            if pc > 0:
                selling_price = 0
            else:
                return jsonify({
                    'success': False,
                    'message': 'Selling price is required'
                }), 400

        # Coerce to numeric
        try:
            selling_price = float(selling_price)
        except Exception:
            return jsonify({
                'success': False,
                'message': 'Invalid selling price'
            }), 400
            return jsonify({
                'success': False,
                'message': 'Name and selling price are required'
            }), 400
        
        # Generate SKU if not provided
        sku = data.get('sku')
        if not sku:
            count = Product.query.count() + 1
            sku = f'PRD-{count:04d}'
        
        product = Product(
            sku=sku,
            barcode=data.get('barcode'),
            name=name,
            description=data.get('description'),
            cost_price=data.get('cost_price', 0),
            selling_price=selling_price,
            discount_percent=data.get('discount_percent', 0),
            points_cost=points_cost,
            stock_quantity=data.get('stock_quantity', 0),
            low_stock_threshold=data.get('low_stock_threshold', 10),
            category_id=data.get('category_id'),
            image_url=data.get('image_url'),
            is_featured=data.get('is_featured', False)
        )
        
        db.session.add(product)
        db.session.commit()

        # Audit log (best effort)
        try:
            log_activity(
                user_id=get_jwt_identity(),
                action='Added new product',
                entity_type='product',
                entity_id=product.id,
                details={'product_id': product.id, 'name': product.name},
            )
        except Exception:
            pass
        
        return jsonify({
            'success': True,
            'message': 'Product created successfully',
            'data': product.to_dict()
        }), 201
        
    except Exception as e:
        db.session.rollback()
        return jsonify({
            'success': False,
            'message': str(e)
        }), 500


@products_bp.route('/<int:product_id>', methods=['PUT'])
@jwt_required()
def update_product(product_id):
    """Update product (supervisor only)"""
    try:
        claims = get_jwt()
        if claims.get('role') not in {'supervisor', 'admin', 'superadmin'}:
            return jsonify({
                'success': False,
                'message': 'Supervisor access required'
            }), 403
        
        product = Product.query.get(product_id)
        if not product:
            return jsonify({
                'success': False,
                'message': 'Product not found'
            }), 404
        
        data = request.get_json()
        
        # Update fields
        updateable_fields = [
            'name', 'description', 'barcode', 'cost_price', 'selling_price',
            'discount_percent', 'points_cost', 'stock_quantity', 'low_stock_threshold',
            'category_id', 'image_url', 'is_active', 'is_featured'
        ]
        
        for field in updateable_fields:
            if field in data:
                setattr(product, field, data[field])
        
        db.session.commit()

        # Audit log (best effort)
        try:
            log_activity(
                user_id=get_jwt_identity(),
                action='Updated product',
                entity_type='product',
                entity_id=product.id,
                details={'product_id': product.id, 'name': product.name},
            )
        except Exception:
            pass
        
        return jsonify({
            'success': True,
            'message': 'Product updated successfully',
            'data': product.to_dict()
        }), 200
        
    except Exception as e:
        db.session.rollback()
        return jsonify({
            'success': False,
            'message': str(e)
        }), 500


@products_bp.route('/<int:product_id>/stock', methods=['PATCH'])
@jwt_required()
def update_stock(product_id):
    """Update product stock"""
    try:
        claims = get_jwt()
        if claims.get('role') != 'supervisor':
            return jsonify({
                'success': False,
                'message': 'Supervisor access required'
            }), 403

        product = Product.query.get(product_id)
        if not product:
            return jsonify({
                'success': False,
                'message': 'Product not found'
            }), 404
        
        data = request.get_json()
        adjustment = data.get('adjustment', 0)
        
        product.stock_quantity += adjustment
        if product.stock_quantity < 0:
            product.stock_quantity = 0
        
        db.session.commit()
        
        return jsonify({
            'success': True,
            'message': 'Stock updated successfully',
            'data': {
                'product_id': product.id,
                'new_stock': product.stock_quantity
            }
        }), 200
        
    except Exception as e:
        db.session.rollback()
        return jsonify({
            'success': False,
            'message': str(e)
        }), 500


@products_bp.route('/<int:product_id>/image', methods=['POST'])
@jwt_required()
def upload_product_image(product_id):
    """Upload/replace a product image (supervisor only)."""
    try:
        claims = get_jwt()
        if claims.get('role') != 'supervisor':
            return jsonify({
                'success': False,
                'message': 'Supervisor access required'
            }), 403

        product = Product.query.get(product_id)
        if not product:
            return jsonify({
                'success': False,
                'message': 'Product not found'
            }), 404

        if 'image' not in request.files:
            return jsonify({
                'success': False,
                'message': 'No image file provided'
            }), 400

        file = request.files['image']
        if not file or not file.filename:
            return jsonify({
                'success': False,
                'message': 'Invalid image file'
            }), 400

        filename = secure_filename(file.filename)
        if not _is_allowed_image_filename(filename):
            return jsonify({
                'success': False,
                'message': 'Unsupported image type. Use png/jpg/jpeg/webp.'
            }), 400

        ext = os.path.splitext(filename)[1].lower()
        unique_name = f'product_{product_id}_{int(time.time())}{ext}'

        upload_dir = os.path.join(
            current_app.root_path,
            'static',
            'uploads',
            'products'
        )
        os.makedirs(upload_dir, exist_ok=True)
        file_path = os.path.join(upload_dir, unique_name)
        file.save(file_path)

        product.image_url = f'/static/uploads/products/{unique_name}'
        db.session.commit()

        return jsonify({
            'success': True,
            'message': 'Image uploaded successfully',
            'data': {
                'image_url': product.image_url,
                'product': product.to_dict()
            }
        }), 200
    except Exception as e:
        db.session.rollback()
        return jsonify({
            'success': False,
            'message': str(e)
        }), 500
