# Personal Finance — iOS App

A native iOS app for tracking personal finances — wallets, transactions, budgets, debts, saving goals, and recurring payments. Built with SwiftUI and backed by Supabase. Companion to the [web app](https://github.com/nghiabui02/personal-finance-web).

## Features

- **Dashboard** — Net worth overview, monthly income/expense summary, spending chart, budget progress, and recent transactions
- **Transactions** — Add/edit expenses and income with category, wallet, and date filters; calendar view and pagination
- **Wallets** — Multiple wallet types (cash, bank, e-wallet, credit card); transfer between wallets; credit card bill payment
- **Budgets** — Monthly category budgets with progress tracking
- **Debts** — Track money lent and borrowed; payment history; due date reminders
- **Saving Goals** — Goal tracking with contributions and deadline alerts
- **Recurring Transactions** — Scheduled income/expense automation
- **Reports** — Period-based (week/month/quarter/year) cash flow, spending breakdown, net worth history chart
- **Notifications** — Smart alerts for overdue debts, exceeded budgets, upcoming recurring payments, and goal deadlines
- **Settings** — Profile, avatar upload, password change

## Tech Stack

| Layer | Technology |
|---|---|
| UI | SwiftUI |
| Local persistence | SwiftData |
| Backend / Auth | Supabase (PostgreSQL + Auth + Storage) |
| Architecture | MVVM + Service Layer |
| Charts | Swift Charts (iOS 16+) |
| Min deployment | iOS 17 |

## Architecture

```
Personal Finance/
├── Config/               # AppConfig reads from Secrets.xcconfig
├── Models/               # LocalModels (SwiftData), RemoteModels (Supabase DTOs)
├── Services/             # One service per domain (WalletService, TransactionService…)
│   └── SyncManager       # Orchestrates full sync from Supabase → SwiftData
├── ViewModels/           # ObservableObject VMs (Auth, Notifications, Transactions)
├── Views/
│   ├── Dashboard/
│   ├── Transactions/
│   ├── Wallets/
│   ├── Budgets/
│   ├── Debts/
│   ├── SavingGoals/
│   ├── Reports/
│   ├── Recurring/
│   ├── Notifications/
│   └── Settings/
└── Extensions/           # Color+Hex, Double+Currency, View+Helpers
```

**Key patterns:**
- Supabase RLS enforces row-level ownership server-side; all mutating calls also include `.eq("user_id", ...)` client-side as defense-in-depth
- Balance updates go through a Postgres RPC (`apply_wallet_balance_delta`) to avoid TOCTOU races
- `SyncManager` pulls all user data into SwiftData on login/pull-to-refresh; UI reads from local store
- `notification_states` table tracks read/dismissed state; notification content is derived fresh on each fetch

## Prerequisites

- Xcode 16+
- iOS 17 simulator or device
- A [Supabase](https://supabase.com) project

## Setup

**1. Clone the repo**
```bash
git clone https://github.com/nghiabui02/Personal-Finance-iOS-App.git
cd Personal-Finance-iOS-App
```

**2. Create your secrets file**
```bash
cp Config/Secrets.xcconfig.example Config/Secrets.xcconfig
```

Edit `Config/Secrets.xcconfig` with your Supabase project values:
```
SUPABASE_HOST = your-project-ref.supabase.co
SUPABASE_ANON_KEY = your-anon-key
SUPABASE_AVATAR_BUCKET = Avatar
```

> `Secrets.xcconfig` is git-ignored and never committed.

**3. Open in Xcode and run**

Open `My Finance.xcodeproj` and press ▶.

## Security Notes

- `Secrets.xcconfig` is excluded from git via `.gitignore`
- Supabase RLS policies enforce data isolation — users can only read/write their own rows
- All mutating service calls include explicit `user_id` filters as a second layer
- SwiftData store is encrypted with `FileProtectionType.completeUnlessOpen`
- App content is blurred in the iOS app switcher via `scenePhase` overlay

## Related

- [Web app (Next.js + Supabase)](https://github.com/nghiabui02/personal-finance-web) — shares the same Supabase backend
