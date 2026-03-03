import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vivian_cosmetic_shop_application/core/widgets/error_display.dart';

void main() {
  group('ErrorDisplay Widget Tests', () {
    testWidgets('ErrorDisplay should show error message', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: ErrorDisplay(message: 'Test error message')),
        ),
      );

      expect(find.text('Test error message'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('ErrorDisplay should show retry button when onRetry provided', (
      WidgetTester tester,
    ) async {
      bool retryCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ErrorDisplay(
              message: 'Test error',
              onRetry: () {
                retryCalled = true;
              },
            ),
          ),
        ),
      );

      expect(find.text('Try Again'), findsOneWidget);

      await tester.tap(find.text('Try Again'));
      await tester.pump();

      expect(retryCalled, true);
    });

    testWidgets('ErrorDisplay compact mode should show inline error', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ErrorDisplay(message: 'Compact error', compact: true),
          ),
        ),
      );

      expect(find.text('Compact error'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('ErrorDisplay compact mode should show retry button', (
      WidgetTester tester,
    ) async {
      bool retryCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ErrorDisplay(
              message: 'Compact error',
              compact: true,
              onRetry: () {
                retryCalled = true;
              },
            ),
          ),
        ),
      );

      expect(find.text('Retry'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pump();

      expect(retryCalled, true);
    });
  });

  group('LoadingOrError Widget Tests', () {
    testWidgets(
      'LoadingOrError should show loading indicator when isLoading is true',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: LoadingOrError(isLoading: true, child: Text('Content')),
            ),
          ),
        );

        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(find.text('Content'), findsNothing);
      },
    );

    testWidgets('LoadingOrError should show loading message when provided', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LoadingOrError(
              isLoading: true,
              loadingMessage: 'Loading data...',
              child: Text('Content'),
            ),
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Loading data...'), findsOneWidget);
    });

    testWidgets('LoadingOrError should show error when error is not null', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LoadingOrError(
              isLoading: false,
              error: 'Test error',
              child: Text('Content'),
            ),
          ),
        ),
      );

      expect(find.byType(ErrorDisplay), findsOneWidget);
      expect(find.text('Content'), findsNothing);
    });

    testWidgets(
      'LoadingOrError should show content when not loading and no error',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: LoadingOrError(
                isLoading: false,
                error: null,
                child: Text('Content'),
              ),
            ),
          ),
        );

        expect(find.text('Content'), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.byType(ErrorDisplay), findsNothing);
      },
    );

    testWidgets(
      'LoadingOrError should call onRetry when error retry is tapped',
      (WidgetTester tester) async {
        bool retryCalled = false;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: LoadingOrError(
                isLoading: false,
                error: 'Test error',
                onRetry: () {
                  retryCalled = true;
                },
                child: const Text('Content'),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Try Again'));
        await tester.pump();

        expect(retryCalled, true);
      },
    );
  });

  group('ErrorSnackbarExtension Tests', () {
    testWidgets('showErrorSnackbar should display error snackbar', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () {
                      context.showErrorSnackbar('Test error');
                    },
                    child: const Text('Show Error'),
                  ),
                ),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Show Error'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('An error occurred. Please try again.'), findsOneWidget);
      expect(find.text('Dismiss'), findsOneWidget);
    });

    testWidgets('showSuccessSnackbar should display success snackbar', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () {
                      context.showSuccessSnackbar('Success message');
                    },
                    child: const Text('Show Success'),
                  ),
                ),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Show Success'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Success message'), findsOneWidget);
    });

    testWidgets('showInfoSnackbar should display info snackbar', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () {
                      context.showInfoSnackbar('Info message');
                    },
                    child: const Text('Show Info'),
                  ),
                ),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Show Info'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Info message'), findsOneWidget);
    });
  });
}
