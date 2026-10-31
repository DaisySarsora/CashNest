# CashNest: deploy with GitHub + Supabase + Vercel

CashNest is a single web page (`index.html`). **Supabase** stores the data and handles sign-in, **GitHub** holds the code, and **Vercel** serves the site and redeploys automatically whenever you change something on GitHub.

```
cashnest/
├── index.html            ← the app
├── config.js             ← your Supabase URL + key go here (step 2)
├── README.md             ← this guide
└── supabase/
    └── schema.sql        ← database tables + security rules (step 1)
```

Total time: about 15 minutes. No coding or build tools needed.

---

## Step 1: Set up the database in Supabase

1. Go to **supabase.com** → **New project**. Give it a name (e.g. `cashnest`), set a database password (save it somewhere), and pick the region closest to you. Wait 1–2 minutes for it to finish.
2. In the left menu, open **SQL Editor** → **New query**.
3. Open `supabase/schema.sql` from this folder, copy **everything**, paste it in, and click **Run**.
   You should see *"Success. No rows returned"*. (Running it again later is safe.)
4. Get your two connection values. Open **Project Settings** (gear icon) → **API Keys** (on some dashboards it's **Data API**, or the **Connect** button at the top):
   - **Project URL**, which looks like `https://abcdefghijkl.supabase.co`
   - **Publishable key** (starts with `sb_publishable_…`) **or** the legacy **anon public** key (starts with `eyJ…`). Either works.

   ⚠️ Never use the **secret** / **service_role** key in CashNest. It bypasses all security rules.

5. Sign-in settings: open **Authentication** → **Sign In / Providers** → **Email** and make sure it's **enabled**.
   - **Confirm email** ON (default): new users must click a link in an email before they can sign in. Safer.
   - **Confirm email** OFF: people can sign in right after creating an account. Handy for a small private group.

> 📧 Supabase's built-in email sender only allows a few emails per hour. That's fine for you and a few friends.
> If you'll have more people, add your own email provider under **Authentication → Emails → SMTP Settings**.

## Step 2: Put your keys in `config.js`

Open `config.js` in any text editor (Notepad, TextEdit, VS Code) and replace the two placeholders:

```js
window.CASHNEST_CONFIG = {
  supabaseUrl: "https://abcdefghijkl.supabase.co",
  supabaseAnonKey: "sb_publishable_xxxxxxxxxxxxxxxx"
};
```

Save the file. The publishable/anon key is **meant to be public**, so it's fine on GitHub. Your data is protected by the security rules you installed in Step 1:
- each person only sees their own Daily Spending, Budget, Goals and Future plan
- people only see the Split & Share groups they created or were invited to

## Step 3: Put the code on GitHub

**Option A: in the browser (easiest)**
1. On **github.com**, click **+** → **New repository**. Name it `cashnest`, choose **Private** or Public, and click **Create repository**.
2. On the new repo page, click **uploading an existing file**.
3. Drag in `index.html`, `config.js`, `README.md` **and the `supabase` folder**, then click **Commit changes**.

**Option B: from a terminal**
```bash
cd cashnest
git init
git add .
git commit -m "CashNest"
git branch -M main
git remote add origin https://github.com/YOUR-USERNAME/cashnest.git
git push -u origin main
```

## Step 4: Deploy on Vercel

1. On **vercel.com** → **Add New…** → **Project**.
2. Find your `cashnest` repository and click **Import**. If it isn't listed, click **Adjust GitHub App Permissions** and give Vercel access to it.
3. Settings:
   - **Framework Preset:** `Other`
   - **Root Directory:** leave as `./`
   - **Build Command / Output Directory:** leave empty (it's a plain HTML site)
   - No environment variables needed
4. Click **Deploy**. After ~30 seconds you get a link like `https://cashnest-yourname.vercel.app`. Copy it.

## Step 5: Tell Supabase your site's address

This is needed so sign-in and confirmation emails send people back to your site, not to `localhost`.

1. In Supabase, open **Authentication** → **URL Configuration**.
2. **Site URL:** paste your Vercel link exactly, e.g. `https://cashnest-yourname.vercel.app` (no slash at the end).
3. **Redirect URLs** → **Add URL**: `https://cashnest-yourname.vercel.app/**`
   (If you later add your own domain, add it here too, e.g. `https://cashnest.yourdomain.com/**`.)
4. Click **Save**.

## Step 6: Try it

1. Open your Vercel link → **Create account** → sign in.
2. Add a spending entry and reload the page. It should still be there. Sign in on your phone and you'll see the same data.
3. **Split & Share:** create a group → click **👥 Invite** → **Copy** → send the link to a friend. When they open it and sign in, they join the group.
   Each person picks **"You are: …"** under the group name so CashNest knows which member they are.

---

## Changing things later

Edit a file on GitHub (pencil icon → **Commit changes**) or push from your computer, and Vercel redeploys automatically within a minute.

## Moving your data over from the claude.ai version

- **Split & Share:** in the old version, open each group → **⬇ Download Excel**. In the new site, create or open the group → **⬆ Import Excel** → choose that file (expenses and payments come across).
- **Daily Spending:** old version → Daily Spending → **⬇ Excel**. New site → Daily Spending → **⬆ Import**.
- Budgets, savings goals and My Future settings are quick to re-enter by hand.

## Troubleshooting

| What you see | Fix |
|---|---|
| Yellow banner "Not connected to Supabase yet" | `config.js` still has the placeholders, or wasn't uploaded. Check Step 2 and that `config.js` is in the repo next to `index.html`. |
| "Invalid API key" when signing in | Wrong key in `config.js`. Copy the **publishable/anon** key again (not the secret key). |
| "Email not confirmed" | Click the link in the confirmation email, or turn off **Confirm email** (Step 1.5). |
| The email link opens `localhost` or an error page | Site URL / Redirect URLs not set. Do Step 5. |
| "Couldn't save" / "row-level security" errors | The database setup didn't run. Repeat Step 1.3 (it's safe to run again). |
| No email arrives | Check spam. The built-in sender is rate-limited; wait a bit or set up SMTP (Step 1 note). |
| Friend's invite link says it doesn't work | The group was deleted. Open the group and copy a fresh **Invite** link. |

## How the security works (for the curious)

All data is stored in one table, `docs`, where each row has a path such as `groups/<id>/expenses/<id>` or `data/users/<your-user-id>/me/spending/<id>`. A database trigger works out the owner/group from the path (the browser can't fake it). Row-level security then only lets you read or change:
- rows under your own `data/users/<your-id>/…`
- rows of groups you're a member of (you become a member by creating the group or opening an invite link)

Changes made by other group members show up within about 15 seconds, or right away when you switch back to the tab.
