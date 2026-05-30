# Dukan Flutter UX Prototype

Clickable Flutter prototype for usability testing with Somali shopkeepers. The app is intentionally local-only: no auth, backend, persistence, OCR, barcode, dashboard, or real CRUD.

## Project layout

- `dukan/` — Flutter project root.
- `dukan/lib/main.dart` — Material 3 prototype screens and in-memory state.
- `dukan/lib/mock/mock_data.dart` — 84 bilingual grocery items, 10 suppliers, 15 customers.
- `dukan/lib/l10n/app_en.arb`, `dukan/lib/l10n/app_so.arb` — English/Somali UI strings.

## Run

```sh
cd /Users/nouromar/dukan/app/dukan
flutter pub get
flutter run
```

## Mocked

Sales, receives, payments, and expenses use in-memory mock data only. Confirm actions optimistically clear forms and show a 10-second Undo SnackBar. Language choice is app-state only and resets when the app restarts.

## Known gaps

Payment and Expense are lightweight clickable stubs. Inline `+ New supplier` is a stub message. Bono photo and repeat-last-bono buttons are non-persistent prototype affordances only.
