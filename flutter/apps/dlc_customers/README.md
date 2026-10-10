# DLC Clientes

Flutter app source for the customer account and loyalty experience. It connects to Supabase Auth and the shared DLC API. See `../../README.md` for QA configuration and build commands.

Included: registration and email verification deep link, confirmed-email sign-in, password reset and new-password deep link, profile setup, point balance/history, published rewards and campaigns, active branches/services, QR account identity, and logout. The server can link a customer account to a sale and award points after full payment. The QR identifies an account; it does not authorize payment or reward redemption. Spending points in checkout, reward fulfillment, push delivery, company-approved legal text, and account deletion remain incomplete. Framework and uncaught asynchronous errors are logged under `dlc.customer.crash`; collect them with `flutter logs` or `adb logcat`.
