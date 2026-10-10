# DLC Flutter

Workspace mobile and web Flutter is the human-test port of the existing SwiftUI product. The API remains the authority for identity, permissions, operational rules, persistence, and audit history. This source does not contain database secrets.

## Windows setup

1. Install Flutter stable with Dart 3.10 or later, Android Studio/Android SDK, Android platform tools, and Java 17.
2. Add Flutter and Android SDK tools to PATH; run `flutter doctor -v`.
3. From this directory run `powershell -ExecutionPolicy Bypass -File .\tool\bootstrap_flutter_windows.ps1`. It adds only missing platform folders and runs `flutter pub get` for both packages.
4. Start the API and its PostgreSQL/Supabase-backed worker in a QA environment reachable from the device. Never point the test apps at production data.
5. For Android emulator local API use `--dart-define=DLC_API_BASE_URL=http://10.0.2.2:4000/api/v1` (the server default is port 4000). The bootstrap allows cleartext HTTP in Android debug only. For a physical device or release build configure a reachable HTTPS URL.
6. Build Operaciones with `cd apps/dlc_operations; flutter analyze; flutter build apk --debug --dart-define=DLC_API_BASE_URL=<QA_URL>`.
7. Build Clientes separately with `cd apps/dlc_customers; flutter analyze; flutter build apk --debug --dart-define=DLC_API_BASE_URL=<QA_API_URL> --dart-define=SUPABASE_URL=<QA_SUPABASE_URL> --dart-define=SUPABASE_PUBLISHABLE_KEY=<QA_PUBLISHABLE_KEY> --dart-define=SUPABASE_AUTH_REDIRECT_URL=sv.com.dlc.dlc_customers://login-callback/ --dart-define=CUSTOMER_TERMS_VERSION=qa-draft-v1`.
8. Run `powershell -ExecutionPolicy Bypass -File ..\..\tool\diagnostico_windows.ps1` to create a sanitized `diagnostico_flutter.txt` when sharing environment failures.

`apps/dlc_operations` contains connected source flows for login/session, branch dashboard, dispenser detail/incidents, meter baselines, operational cuts/reconciliation, report snapshots/export, procurement, cash/POS, promotions, loyalty policy administration, shifts, and maintenance. The source has not been built here because this work runtime has no Flutter, Dart, or Android SDK; run `flutter analyze` and QA builds locally.

`apps/dlc_customers` has Supabase email/password signup, confirmed-email login, password reset, profile capture, points/history, published rewards/campaigns, active branches, account QR identity, and logout. The API links customer accounts to sales and awards loyalty points after eligible paid tenders. A cashier can request a short-lived points payment quote and the signed-in customer can confirm or decline it in this app. Keep conversion at zero outside disposable QA until point reversals for returns are implemented and tested. Reward fulfillment, remote push notifications, and approved legal content remain incomplete. It needs Supabase project URL/publishable key and a customer organization UUID on the API.

For the customer QA build, pass `--dart-define=DLC_API_BASE_URL=<QA_API_URL> --dart-define=SUPABASE_URL=<QA_SUPABASE_URL> --dart-define=SUPABASE_PUBLISHABLE_KEY=<QA_PUBLISHABLE_KEY> --dart-define=SUPABASE_AUTH_REDIRECT_URL=sv.com.dlc.dlc_customers://login-callback/ --dart-define=CUSTOMER_TERMS_VERSION=qa-draft-v1`. Configure the API with `CUSTOMER_ORGANIZATION_ID`, `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`, and matching `CUSTOMER_TERMS_VERSION`. Add `sv.com.dlc.dlc_customers://login-callback/` to Supabase Auth's allowed redirects. The Flutter app only receives the publishable key; never put a Supabase secret/service-role key in the app. The bootstrap script registers the Android callback scheme; email confirmation and password recovery return to the app. The current profile checkbox is QA copy and must be replaced with company-approved terms/privacy text before real customer enrollment.

Before using a physical device, configure the QA API URL with HTTPS. Do not commit credentials, access tokens, Supabase service-role keys, real customer data, or debug build artifacts.
