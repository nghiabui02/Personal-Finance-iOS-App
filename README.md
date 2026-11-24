# Personal Finance for iOS

A SwiftUI app for tracking personal finances in Vietnamese đồng (VND). It shares a Supabase backend with the web app, so you can use the same account and ledger on both when they point to the same project. [Companion web app](https://github.com/nghiabui02/Personal-Finance)

## Features

- **Overview and reports** — See monthly income, expenses, budget progress, and net worth. Explore cash flow and spending by week, month, quarter, or year.
- **Transactions and wallets** — Log income and expenses with optional bank fees. Browse, filter, or reuse frequent transactions. Transfer between wallets, pay credit card bills, and reconcile balances.
- **Categories** — Open **More → Categories → Category Store** to find templates in English or Vietnamese and add them individually or in batches. Create custom categories, or remove and restore categories while keeping their transaction history.
- **Budgets, debts, and saving goals** — Set monthly budgets with optional rollover, track money lent and borrowed, record repayments, and contribute to saving goals.
- **Recurring transactions and alerts** — Schedule income or expenses, pause a rule, or skip its next occurrence. Get in-app alerts for budgets, debts, recurring transactions, and saving goals.
- **Account settings** — Edit your profile, upload an avatar, or change your password. Choose English or Vietnamese in **Settings → Language**. The preference is saved to your account, and Store category names follow it until you rename them.

## Getting started

### Requirements

- Xcode 27 or later with the iOS SDK.
- An iPhone or simulator with iOS 18 or later, or an iPad with iPadOS 18 or later.
- A Supabase project configured with the Personal Finance schema, database functions, and email/password authentication. The Category Store also needs the shared template catalog. Avatar uploads use a configured Storage bucket. [Backend setup in the web repository](https://github.com/nghiabui02/Personal-Finance#3-database)

### Configure and run

1. Clone the repository and copy the configuration template.

   ```sh
   git clone https://github.com/nghiabui02/Personal-Finance-iOS-App.git
   cd Personal-Finance-iOS-App
   cp Config/Secrets.xcconfig.example Config/Secrets.xcconfig
   ```

2. Fill in `Config/Secrets.xcconfig` with your project values.

   ```xcconfig
   SUPABASE_HOST = your-project-ref.supabase.co
   SUPABASE_ANON_KEY = your-supabase-publishable-or-anon-key
   SUPABASE_AVATAR_BUCKET = Avatar
   ```

   Enter the hostname without `https://`. Use a publishable key or legacy `anon` key. The app bundles this client key, so keep privileged keys on the server. Git ignores the local configuration file. [Supabase API keys](https://supabase.com/docs/guides/api/api-keys)

3. Open `My Finance.xcodeproj`, select the **Personal Finance** scheme and a simulator, then run with **⌘R**. For a physical device, select your development team under **Signing & Capabilities**.

## How the app works

- **Data and offline access** — Supabase stores the shared ledger. SwiftData keeps an on-device cache for offline reading. Writes require a connection. The app refreshes the cache on sign-in, when returning to the foreground, and when the connection returns. [SyncManager.swift](Personal%20Finance/Services/SyncManager.swift)
- **Ledger calculations** — Ledger dates use `Asia/Ho_Chi_Minh`. VND keeps Vietnamese number formatting in either app language. Transaction amounts already include bank fees. Spending totals exclude wallet balance adjustments. [LedgerDate.swift](Personal%20Finance/Extensions/LedgerDate.swift)
- **Category membership** — Supabase stores templates in `categories` and account categories in `user_categories`. Removing a category marks it inactive. An active budget for the current month or an active recurring rule can block removal. [CategoryService.swift](Personal%20Finance/Services/CategoryService.swift)
- **Recurring schedules and notifications** — The backend generates scheduled transactions. iOS derives in-app alerts and saves read and dismissed states in Supabase. [NotificationService.swift](Personal%20Finance/Services/NotificationService.swift)
- **Localization** — UI translations live in a single Xcode String Catalog. Category template names come from the shared catalog in Supabase. [Localizable.xcstrings](Personal%20Finance/Localizable.xcstrings)

## Command-line build and tests

```sh
xcodebuild -project "My Finance.xcodeproj" \
  -scheme "Personal Finance" \
  -destination "generic/platform=iOS Simulator" CODE_SIGNING_ALLOWED=NO build
```

To run the scheme's unit tests, use an installed simulator. Find its UDID with `xcrun simctl list devices available`.

```sh
xcodebuild -project "My Finance.xcodeproj" \
  -scheme "Personal Finance" \
  -destination "platform=iOS Simulator,id=<SIMULATOR_UDID>" test
```
