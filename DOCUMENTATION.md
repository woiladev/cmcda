# CMCDA Platform — User Documentation

*A plain-language guide to what the CMCDA Platform is, who uses it, and what it does.*

---

## 1. What is CMCDA?

The **CMCDA Platform** is a mobile and web application for collecting financial contributions from members of the Muslim community in Cameroon. It was built by **WoilaTech** (Ngaoundéré).

- **Where it runs:** Android phones (the main way people use it) and the Web.
- **Why it exists:** to make member contributions simple to pay, easy to track, transparent for everyone, and reliable even when there is little or no internet in the field.
- **Languages:** the whole app is available in **French, English, and Arabic**. Arabic is shown right-to-left, like a normal Arabic app.

---

## 2. Getting Started — Signing Up and Logging In

### Ways to sign in
You can access the app using any of these:
- **Phone number** — you receive a one-time code (OTP) by SMS to confirm it's you.
- **Email and password**.
- **Google account** — one-tap sign-in.

### Signing up (3 simple steps)
1. **Your details** — first and last name, phone, email, password.
2. **Where you are** — your region (all 10 regions of Cameroon are listed), and optionally your department, city, and quarter.
3. **Your preferences** — how often you plan to contribute, your preferred payment method, and your language.

When you join, the app gives you a **unique member number** (for example, `CM-000001`) that identifies you on the platform.

---

## 3. Contribution Basics

### How much and how often
You choose the rhythm that suits you:

| Frequency | Amount |
|-----------|--------|
| Daily | 100 FCFA |
| Monthly | 3,000 FCFA |
| Annual | 36,500 FCFA |

### How you can pay
- **MTN Mobile Money**
- **Orange Money**
- **Bank transfer**
- **Cash** (collected in person)

### How a payment gets confirmed
- **Mobile money** payments are confirmed automatically.
- **Bank transfers** require you to attach a photo of your transfer proof; an admin then reviews and approves it.
- **Cash** is recorded by a focal officer in the field and approved by admins.

Every confirmed payment receives a **receipt number** you can keep as proof.

---

## 4. The Four User Roles

Different people use the app in different ways. Each person has a **role** that decides what they see and can do.

| Role | Who they are | What they manage |
|------|--------------|------------------|
| **Member** | A community member who contributes | Their own contributions |
| **Focal Officer** | A field agent who collects on behalf of others | Members and payments in their zone |
| **Admin** | A platform manager | Members, payments, events, reports, analytics |
| **Super Admin** | The top-level manager | Everything, plus the admin team |

### Member
A member can:
- See a personal **dashboard** with their total amount contributed and recent payment history.
- **Make a payment** by choosing a frequency and payment method.
- View their **receipts and history**, filtered by year and status (pending or confirmed).
- Browse community **events** and share them (e.g. to WhatsApp).
- Read **notifications** (payment updates, reminders, alerts).
- See the **transparency view** — platform-wide totals and contributions by region.
- Set **payment reminders** (daily, monthly, or annual).
- Edit their **profile** and switch language; log out.

### Focal Officer
A focal officer is a trusted field agent who collects contributions for others. They can:
- See their assigned **zone** and the **list of members** there.
- **Search members** by name, member number, or phone.
- **Record cash payments offline, in batches** — even with no internet. Entries sync automatically once back online.
- Track all the **payments they have recorded** and check each payment's status.
- Create and **submit reports** summarising a collection session, and share the report text (e.g. to WhatsApp).
- Manage their **profile** and language; log out.

### Admin
An admin manages the platform day to day. They can:
- See a **dashboard** with key figures: today's and the month's totals, active members, late members, new members, and recent payments.
- Browse and **search all members**, and view member details.
- **Approve or reject payments**, including reviewing bank-transfer proof images.
- **Record a manual payment** on behalf of a member.
- View **analytics** over different periods, with the option to **export to PDF or CSV**.
- Create, edit, and **publish events**.
- Review and approve **focal officer reports**.
- Manage **team roles** (e.g. promote a member to focal officer).
- Track the **treasury/wallet** by payment method and region, and manage **bank details**.
- Send **push notifications** to all members.

### Super Admin
A super admin can do **everything an admin can do**, and in addition manages the **admin team** — assigning and changing admin roles — with safeguards (for example, the last super admin cannot be removed).

---

## 5. Key Features at a Glance

- **Works offline** — focal officers can record cash collections without a signal; everything syncs when the connection returns.
- **Transparency** — members can see how much the whole community has contributed, broken down by region.
- **Three languages** — French, English, and Arabic, switchable at any time.
- **Notifications** — payment confirmations, contribution reminders, and system alerts.
- **Events** — community events that members can browse and share.
- **Receipts** — every confirmed contribution gets a traceable receipt number.

---

## 6. Settings and Shared Screens

Available across the app:
- **Language** — switch between French, English, and Arabic (applies everywhere).
- **Reminders** — turn payment reminders on or off and choose how often.
- **Payment preferences** — set your preferred payment method and contribution frequency.
- **Help, About, and Privacy Policy** — reachable from within the app.

---

## 7. Screenshots

> **Note:** Image files are not yet committed. Place your screenshots in a `docs/screenshots/` folder using the filenames below, and they will appear automatically when this document is viewed. Until then, the links act as a checklist of the screens worth capturing.

### Onboarding & Authentication
| Screen | Image |
|--------|-------|
| Splash / launch | ![Launch](docs/screenshots/launch.png) |
| Onboarding | ![Onboarding](docs/screenshots/onboarding.png) |
| Login | ![Login](docs/screenshots/login.png) |
| Sign-up (3 steps) | ![Sign-up](docs/screenshots/signup.png) |

### Member
| Screen | Image |
|--------|-------|
| Dashboard | ![Member dashboard](docs/screenshots/member_dashboard.png) |
| Make a payment | ![Make payment](docs/screenshots/member_payment.png) |
| Receipts & history | ![Receipts](docs/screenshots/member_receipts.png) |
| Events | ![Events](docs/screenshots/member_events.png) |
| Transparency / treasury | ![Transparency](docs/screenshots/member_transparency.png) |
| Profile | ![Profile](docs/screenshots/member_profile.png) |

### Focal Officer
| Screen | Image |
|--------|-------|
| Dashboard | ![Focal dashboard](docs/screenshots/focal_dashboard.png) |
| Members list | ![Focal members](docs/screenshots/focal_members.png) |
| Offline cash session | ![Cash session](docs/screenshots/focal_session.png) |
| Reports | ![Focal reports](docs/screenshots/focal_reports.png) |

### Admin & Super Admin
| Screen | Image |
|--------|-------|
| Dashboard (KPIs) | ![Admin dashboard](docs/screenshots/admin_dashboard.png) |
| Members | ![Admin members](docs/screenshots/admin_members.png) |
| Payments (approve/reject) | ![Admin payments](docs/screenshots/admin_payments.png) |
| Manual payment | ![Manual payment](docs/screenshots/admin_manual_payment.png) |
| Analytics | ![Analytics](docs/screenshots/admin_analytics.png) |
| Events management | ![Admin events](docs/screenshots/admin_events.png) |
| Treasury / wallet | ![Wallet](docs/screenshots/admin_wallet.png) |
| Settings | ![Settings](docs/screenshots/admin_settings.png) |

### How to capture screenshots
- **Android:** run the app (`flutter run -d android`) and use the device screenshot shortcut, or `flutter screenshot`.
- **Web:** run `flutter run -d chrome` and use your browser's screenshot tool.
- Save each image with the matching filename above into `docs/screenshots/`.

---

*This document describes the app from a user's point of view. For technical and developer details, see `CLAUDE.md`.*
