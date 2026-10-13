# Connect 4 Online

Two-player multiplayer Connect 4, responsive on phones, tablets and computers. Invite friends with a room URL. No player accounts required.

## How it works

- Frontend: Vite + vanilla JavaScript.
- Shared state: Supabase Postgres; server-side SQL functions enforce turn order, gravity, wins, draws and room capacity.
- Sync: each client polls the database every 1.5 seconds (near-real-time; no Realtime subscription needed).
- Security: unguessable player tokens stay in browser localStorage; only their SHA-256 hashes are stored in Postgres. Tables have RLS enabled and no direct public access. Anyone with a fresh room invite link can claim the vacant second-player seat. A room code is not a player credential.

## 1. Create a Supabase project

1. Go to https://supabase.com/dashboard and create a project.
2. Open **SQL Editor** > **New query**.
3. Copy the entire `supabase/schema.sql` file into the editor and press **Run**.
4. In **Project Settings > API** (or **Connect** in the updated dashboard), find your **Project URL** and **publishable key** (`sb_publishable_...`, or the legacy `anon` key). Never use the `service_role`/secret key in this frontend.

## 2. Run locally (optional)

Install Node.js 20.19+ and run:

```bash
npm install
cp .env.example .env
```

Edit `.env` to add your actual URL and publishable key, then:

```bash
npm run dev
```

Open the displayed local URL. The game needs Supabase configured to work.

## 3. Publish to Vercel

1. Create a new GitHub repository at https://github.com/new .
2. Upload all the project files and folders (including `src`, `supabase`, `package.json`, `index.html`, `vercel.json`). Do not upload your `.env` file.
3. Go to https://vercel.com/new , sign in using GitHub, and **Import** your repository.
4. Framework preset: **Vite** (normally detected). Build command: `npm run build`. Output directory: `dist`.
5. Add two **Environment Variables** for **Production**:
   - `VITE_SUPABASE_URL` = your Supabase Project URL
   - `VITE_SUPABASE_PUBLISHABLE_KEY` = your Supabase publishable/anon key
6. Click **Deploy**. Vercel gives you a public URL ending in `.vercel.app`.
7. If you add or change environment variables after deploying, **Redeploy** so Vite includes them in the build.

## 4. Test with two separate devices

1. On phone A, open your public Vercel URL and select **Create a game**.
2. Select **Copy invite link** and send it to phone B (different network is fine).
3. On phone B, open the invite link and select **Join game**.
4. Play alternating moves. Check that the board updates on both phones within a couple of seconds.
5. Connect four, then try **Play again**. Either player can trigger a rematch immediately.

## Rules

Players alternate turns, starting with red. Select any non-full column to drop your disc. Discs fall to the lowest free row. Four of your colour horizontally, vertically or diagonally wins. A full board without a winner is a draw.

## Notes

- Polling provides near-real-time updates, typically within 1.5 seconds plus network latency; not guaranteed instantaneous.
- This is a casual game, not a tournament platform. There is no authentication, spectator mode, anti-spam throttling or room expiry automation.
- Room state remains in Supabase until deleted. For ongoing use, set up a scheduled database cleanup for old rooms.
- If you leave a room, the browser retains its seat token. Reopening the room link in that same browser restores your seat. Clearing browser storage loses the seat.
- Only two player tokens can access a room's state; sharing a link with a third person won't grant access after the second seat is claimed.
