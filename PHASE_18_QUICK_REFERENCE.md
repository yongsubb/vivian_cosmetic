# Phase 18 Testing - Quick Reference

## 🚀 Quick Test Commands

### Flutter Tests
```bash
# Run all tests
flutter test

# Run with verbose output
flutter test --verbose

# Run specific test file
flutter test test/models/models_test.dart

# Run with coverage
flutter test --coverage
```

### Backend Tests
```bash
# Navigate to backend directory
cd backend

# Run all tests
python -m pytest test_api.py -v

# Run with short output
python -m pytest test_api.py -q

# Run specific test class
python -m pytest test_api.py::TestAuthRoutes -v

# Run specific test
python -m pytest test_api.py::TestAuthRoutes::test_login_success -v

# Show test output even for passing tests
python -m pytest test_api.py -v -s
```

## 📊 Current Test Status

### Flutter: ✅ 46/46 PASSING
- Models: 13 tests
- Error Handler: 11 tests  
- Network Retry: 10 tests
- Validation: 6 tests
- Widgets: 6 tests

### Backend: ✅ 28/28 PASSING
- Auth: 5 tests
- Products: 7 tests
- Transactions: 3 tests
- Categories: 2 tests
- Reports: 2 tests
- Users: 2 tests
- Error Handling: 4 tests
- Validation: 3 tests

### Total: ✅ 74/74 (100%)

## 🔧 Troubleshooting

### Flutter Tests Not Running?
```bash
# Clean and rebuild
flutter clean
flutter pub get
flutter test
```

### Backend Tests Failing with Import Errors?
```bash
# Ensure you're in backend directory
cd backend

# Install dependencies
pip install -r requirements.txt

# Run tests
python -m pytest test_api.py -v
```

### Backend Tests Failing with Database Errors?
- Ensure MySQL is running
- Check database credentials in `config/database.py`
- Verify admin user exists (username: 'admin', password: 'admin123')

### Authentication Tests Failing?
- Check JWT secret key in environment
- Verify user credentials
- Check auth_headers fixture in test_api.py

## 📁 Test File Locations

### Flutter Tests
```
test/
├── models/models_test.dart
├── services/
│   ├── error_handler_test.dart
│   ├── network_retry_test.dart
│   └── validation_service_test.dart
├── widgets/error_display_test.dart
└── integration/app_integration_test.dart
```

### Backend Tests
```
backend/
└── test_api.py
```

## 📚 Documentation

- **Full Summary**: [PHASE_18_TESTING_SUMMARY.md](./PHASE_18_TESTING_SUMMARY.md)
- **Detailed Guide**: [PHASE_18_TESTING_GUIDE.md](./PHASE_18_TESTING_GUIDE.md)
- **Implementation Report**: [PHASE_18_IMPLEMENTATION_REPORT.md](./PHASE_18_IMPLEMENTATION_REPORT.md)

## 🎯 Test Coverage Goals

- [x] Unit tests for models
- [x] Unit tests for services
- [x] Widget tests for UI
- [x] Integration tests
- [x] API endpoint tests
- [x] Error handling tests
- [x] Validation tests

## ⚡ Pro Tips

### Run Tests on File Save
```bash
# Flutter (use with watchman or similar)
flutter test --watch

# Backend (use with pytest-watch)
pip install pytest-watch
ptw backend/test_api.py
```

### Generate Coverage Reports
```bash
# Flutter
flutter test --coverage
genhtml coverage/lcov.info -o coverage/html
open coverage/html/index.html

# Backend  
pip install pytest-cov
pytest backend/test_api.py --cov=backend --cov-report=html
open htmlcov/index.html
```

### CI/CD Integration
```yaml
# .github/workflows/tests.yml
name: Tests
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - uses: subosito/flutter-action@v2
      - run: flutter test
      - run: pip install -r backend/requirements.txt
      - run: pytest backend/test_api.py
```

---

**Last Updated**: December 22, 2025  
**Status**: All 74 tests passing ✅
