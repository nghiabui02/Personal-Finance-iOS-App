# Personal Finance — iOS App

A native iOS app for tracking personal finances — wallets, transactions, budgets, debts, saving goals, and recurring payments. Built with SwiftUI and backed by Supabase. Companion to the [web app](https://github.com/nghiabui02/personal-finance-web).

## Features

- **Dashboard** — Net worth overview, monthly income/expense summary, spending chart, budget progress, spending pace vs. your 3-month average, and recent transactions
- **Transactions** — Add/edit expenses and income with category, wallet, and date filters; calendar view and pagination; bank fee on a single row; one-tap chips for frequent amounts and repeat transactions
- **Wallets** — Multiple wallet types (cash, bank, e-wallet, credit card); transfer between wallets; credit card bill payment; reconcile a wallet against its real-world balance
- **Budgets** — Monthly category budgets with progress tracking, month-to-month rollover, pause/resume, and suggested amounts from your spending history
- **Debts** — Track money lent and borrowed; payment history; due date reminders
- **Saving Goals** — Goal tracking with contributions and deadline alerts
- **Recurring Transactions** — Scheduled income/expense automation with pause, resume, and skip
- **Reports** — Period-based (week/month/quarter/year) cash flow, spending breakdown, net worth history chart
- **Notifications** — Smart alerts for overdue debts, exceeded budgets, upcoming recurring payments, and goal deadlines
- **Settings** — Profile, avatar upload, password change

## Tech Stack

| Layer | Technology |
|---|---|
| UI | SwiftUI (Liquid Glass) |
| Local persistence | SwiftData |
| Backend / Auth | Supabase (PostgreSQL + Auth + Storage) |
| Architecture | MVVM + Service Layer |
| Charts | Swift Charts |
| Build SDK | iOS 27 |
| Min deployment | iOS 18 |

Navigation and tab bars use the system's default materials so they pick up Liquid Glass
automatically — the app deliberately avoids `.toolbarBackground` overrides that would
opt it back out.

## Architecture

```
Personal Finance/
├── Config/               # AppConfig reads from Secrets.xcconfig
├── Models/               # LocalModels (SwiftData), RemoteModels (Supabase DTOs)
├── Services/             # One service per domain (WalletService, TransactionService…)
│   └── SyncManager       # Orchestrates full sync from Supabase → SwiftData
├── ViewModels/           # ObservableObject VMs (Auth, Notifications, Transactions)
├── Views/
│   ├── Components/       # Cross-feature UI (SuggestionChip, FlowLayout, CurrencyAmountField…)
│   ├── Auth/
│   ├── Dashboard/
│   ├── Transactions/
│   ├── Wallets/
│   ├── Budgets/
│   ├── Debts/
│   ├── SavingGoals/
│   ├── Reports/
│   ├── Recurring/
│   ├── Categories/
│   ├── Notifications/
│   ├── Settings/
│   └── More/
└── Extensions/           # LedgerDate, SystemCategory, Color+Hex, Double+Currency, View+Helpers
```

Each feature folder keeps screens and calculators at its root, with view pieces under
its own `Components/` subfolder.

**Key patterns:**
- Supabase RLS enforces row-level ownership server-side; all mutating calls also include `.eq("user_id", ...)` client-side as defense-in-depth
- Balance updates go through the `adjust_wallet_balance` Postgres RPC, which reads and writes in one statement — a client-side read-then-write would lose concurrent updates
- Dates are *ledger* dates, not device-local ones: `LedgerDate` pins every date format and "today" calculation to `Asia/Ho_Chi_Minh` so the same data reads identically here, on the web client, and abroad
- `transactions.amount` already includes `bank_fee`; the fee column is stored for display only and is never summed separately
- Balance reconciliations (`adjust_up` / `adjust_down` categories) are excluded from spending totals via `SystemCategory` — they correct the books rather than record real spending. Debt categories stay in, since that money genuinely moves
- Recurring transactions fire from a server-side `pg_cron` job, never from the app — a client-side runner would race the cron and double-post
- `SyncManager` pulls all user data into SwiftData on login/pull-to-refresh; UI reads from local store
- `notification_states` table tracks read/dismissed state; notification content is derived fresh on each fetch

## Prerequisites

- Xcode 27+ (builds against the iOS 27 SDK)
- iOS 18 simulator or device
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

## Tests

```bash
xcodebuild test -project "My Finance.xcodeproj" \
  -scheme "Personal Finance" \
  -destination "platform=iOS Simulator,name=iPhone 17e"
```

## Security Notes

- `Secrets.xcconfig` is excluded from git via `.gitignore`
- Supabase RLS policies enforce data isolation — users can only read/write their own rows
- All mutating service calls include explicit `user_id` filters as a second layer
- SwiftData store is encrypted with `FileProtectionType.completeUnlessOpen`
- App content is blurred in the iOS app switcher via `scenePhase` overlay

## Related

- [Web app (Next.js + Supabase)](https://github.com/nghiabui02/personal-finance-web) — shares the same Supabase backend
