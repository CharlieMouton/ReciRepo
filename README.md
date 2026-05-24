# ReciRepo

A social recipe-sharing app. Save recipes from anywhere, cook through them with a built-in timer, and share your collection with friends.

Built as a **single HTML file** that deploys straight to GitHub Pages — no build step, no bundler, no server.

---

## Features

- **Recipe feed** — browse and search by title, author, or tag
- **Cooking mode** — step-by-step view with per-step countdown timers and an ingredients tab
- **Three ways to add a recipe:**
  - **Type it out** — manual entry form with title, time, servings, tags, ingredients, and steps
  - **Paste a link** — paste any URL from NYT Cooking, Smitten Kitchen, AllRecipes, Bon Appétit, etc.; the app extracts the JSON-LD recipe schema and pre-fills the form
  - **Snap a photo** — photograph a cookbook page or recipe card; the app OCRs it and pre-fills the form. Also accepts pasted raw text via a smart-parse helper in the manual form
- **Bookmarks** — save recipes to your personal collection
- **Cook log** — marks a recipe as cooked when you finish; counts shown on each card
- **Profile** — your recipes and saved count
- **Search** — live filter across the feed by title, author, or tag
- **Desktop layout** — responsive two-column view at ≥ 900 px with a detail panel
- **Auth** — email/password sign-up and sign-in via Supabase

---

## Tech stack

| Layer | What |
|---|---|
| UI | React 18 (CDN UMD build) + JSX via Babel Standalone |
| Backend | [Supabase](https://supabase.com) — Postgres + Auth + Row Level Security |
| URL extraction | [allorigins.win](https://allorigins.win) CORS proxy + JSON-LD `@type: Recipe` parsing |
| Image OCR | [OCR.space](https://ocr.space) free API |
| Fonts | Bricolage Grotesque · Hanken Grotesk · IBM Plex Mono (Google Fonts) |
| Hosting | GitHub Pages |

No npm, no bundler, no `node_modules`. The entire app is `index.html`.

---

## Getting started

### Sign up

Hit the site and create an account with an email and password. Choose a username — it's how your recipes are credited across the feed. Once you're in, you land on the recipe feed.

### Browse the feed

The feed shows every recipe that's been added, newest first. Each card shows the title, author, cook time, and a count of how many people have cooked it. Click any card to open the recipe.

Use the search bar at the top to filter by name, author, or tag. It updates as you type — searching for `layla` surfaces everything Layla has posted; searching `pasta` finds anything tagged or titled accordingly.

### Add a recipe

Tap the **add a recipe** button (the red one in the corner, or the sidebar on desktop). Three paths open up:

- **Type it out.** The manual entry form. Give it a title, cook time, servings, and some tags, then fill in ingredients and steps one by one. Good for recipes you know by heart or are adapting from somewhere.

- **Paste a link.** Drop in a URL from NYT Cooking, Smitten Kitchen, Bon Appétit, AllRecipes, or most other major recipe sites. The app reads the page, extracts the recipe structure buried in the HTML, and drops you into the manual form pre-filled — title, time, servings, ingredients, and steps already there. You review, adjust, and save. You can also paste raw recipe text directly into the form if you've copied it from somewhere without a clean URL.

- **Snap a photo.** Point your camera at a cookbook page, a recipe card, a handwritten note, a screenshot — anything with readable text. The app sends it through an OCR engine and does the same pre-fill dance. Works best on clean, well-lit text; the messier the image, the more you'll want to tidy up before saving.

### Cook a recipe

Open any recipe and tap through it. The cooking view splits into two tabs: **ingredients** (the full list with quantities) and **steps** (one at a time). Each step can have a countdown timer — hit play and it runs in the background while you work. When you finish the last step and mark it done, a cook is logged against the recipe. That number shows up on the card.

### Save and revisit

The bookmark icon on any recipe card or in the cooking view adds it to your saved collection, accessible from the **saved** tab. Your own recipes live in the **profile** tab, along with a count of everything you've cooked.

---

## Deploying your own copy

### 1. Fork and enable GitHub Pages

Fork this repo, then go to **Settings → Pages → Source** and set it to deploy from the `main` branch root. Your site will be live at `https://<your-username>.github.io/ReciRepo/`.

The app runs in demo mode without any backend configured — it shows sample recipes and lets you explore the UI.

### 2. Set up Supabase (optional but recommended)

1. Create a free project at [supabase.com](https://supabase.com)
2. In the Supabase SQL Editor, run the contents of [`schema.sql`](schema.sql) to create all tables, views, and Row Level Security policies
3. Find your **Project URL** and **anon key** at **Settings → API**
4. Edit `index.html` and replace the two placeholder values near the top:

```js
const SUPABASE_URL      = 'https://your-project.supabase.co';
const SUPABASE_ANON_KEY = 'your-anon-key-here';
```

Commit and push — GitHub Pages will redeploy automatically.

### 3. Configure OCR (optional)

The "snap a photo" flow uses [OCR.space](https://ocr.space/OCRAPI). The default key (`helloworld`) is a public demo key limited to 500 requests/day. For higher limits, sign up for a free personal key and set it near the top of `index.html`:

```js
const OCR_SPACE_KEY = 'your-ocr-space-key';
```

### 4. Run locally

```bash
npx serve .
```

Then open `http://localhost:3000`.

---

## Database schema

Six tables, one view. Everything has Row Level Security enabled.

```
profiles        — one row per auth user (username, created_at)
recipes         — title, author_id, time_text, servings, color, accent, source_url, image_url
recipe_tags     — recipe_id + tag (many-to-many)
ingredients     — recipe_id, qty, item, sort_order
steps           — recipe_id, text, timer_seconds, sort_order
saves           — user_id + recipe_id (bookmarks)
cook_logs       — user_id + recipe_id + cooked_at

recipe-images   ← Supabase Storage bucket (public) for cover photos
recipes_with_meta  ← view: recipes joined with author username, cook count, tags, and image_url
```

A new `profiles` row is created automatically via a Postgres trigger whenever a user signs up.

---

## Project structure

```
ReciRepo/
├── index.html   ← the entire app
├── favicon.svg  ← SVG icon
└── schema.sql   ← run once in your Supabase SQL editor
```

All React components, hooks, utilities, and styles live in `index.html`. The rough layout inside the `<script type="text/babel">` block:

```
Config constants
Design tokens + sample data
URL/image extraction utilities (parseDuration, parseIngredient, extractRecipeFromUrl, parseRecipeText, extractRecipeFromImage)
Hooks (useAuth, useRecipes, useSaves)
Primitive components (Icon, Avatar, FoodPlaceholder, Sticker, Wordmark, …)
Screen components (HomeScreen, AuthScreen, LinkScreen, ManualScreen, ScanScreen, CookingScreen, SavedScreen, ProfileScreen, …)
DesktopLayout
App (root, routing, draftRecipe state)
```

---

## Design

Colors: `#FCEDE2` cream · `#2F2A2A` ink · `#D94F4F` red · `#F6C26B` yellow  
Fonts: [Bricolage Grotesque](https://fonts.google.com/specimen/Bricolage+Grotesque) (display headings) · [Hanken Grotesk](https://fonts.google.com/specimen/Hanken+Grotesk) (body) · [IBM Plex Mono](https://fonts.google.com/specimen/IBM+Plex+Mono) (labels/metadata)

The mobile UI renders inside a 390 × 844 px phone shell centered on a dark `#1a1815` background. The desktop layout kicks in at ≥ 900 px.
