#!/usr/bin/env python3
"""Build Tara's review page: docs/tara-review/index.html.

Every user-visible string, where it appears in plain language, Keep or Change,
the open questions for Tara, and a try-it list for the web admin. The list is
curated by hand from `python3 scripts/extract-copy.py --report` (the extractor
cannot see ternaries or SQL notification bodies), so edit SECTIONS below when
copy changes, run this, and republish the artifact (see docs/copy-review.md).

    python3 scripts/build-tara-review.py                    # both targets
    python3 scripts/build-tara-review.py --target artifact  # docs/tara-review/index.html only
    python3 scripts/build-tara-review.py --target web       # web/review.html only

Two targets from one data block. The artifact (claude.ai) keeps answers in
the phone's localStorage and Tara texts the summary to Alex. The web target
(web/review.html, on the admin site) is the same three tabs, opened as
review.html?t=<token>, and saves to our database through the review-submit
edge function as she types (20260921000010). The web page renders its items
from a JSON block so the copy gate sees only its chrome: the items ARE the
copy under review, already in docs/copy-approved.txt or Tara's own words.
"""
import html, json, pathlib, sys

Y = True  # Tara's own words, tagged on the page

# Saved answers are keyed by this on the server (review_responses.page_version)
# and by item position within it (w<section>-<index>, q<index>, t<index>).
# Bump it when items are inserted, removed or reordered, so old answers stay
# in their own row instead of landing on the wrong item. Rewording an item in
# place keeps its position and needs no bump.
PAGE_VERSION = "2"

SECTIONS = [
 [
  "Sign in and sign up",
  "The first screens a new player sees on the phone",
  [
   [
    "Let's Play.",
    "Under the FXE logo on the sign-in screen",
    Y
   ],
   [
    "Create an account",
    "Button on the sign-in screen",
    False
   ],
   [
    "Forgot password?",
    "Link on the sign-in screen",
    False
   ],
   [
    "Almost there!",
    "Heading of the profile screen after sign-up",
    Y
   ],
   [
    "Are you currently a Foxcroft East Racquet & Swim Club member?",
    "The membership question at sign-up (your Screen 4 wording)",
    Y
   ],
   [
    "Members get 24-hour early access to all clinics",
    "Under the membership question",
    Y
   ],
   [
    "Your tennis rating",
    "Label above the rating pills (2.0 to 5.0+)",
    False
   ],
   [
    "Need Help?",
    "Button that opens the rating guide (your wording)",
    Y
   ],
   [
    "Note for Tara (optional)",
    "Label of the new note box at level entry",
    False
   ],
   [
    "Just coming back from a back injury - probably a low 3.5",
    "The grey example text inside that box (your example)",
    Y
   ],
   [
    "Only Tara sees this.",
    "Under the note box",
    False
   ],
   [
    "Add your name, phone number, and tennis rating. Please answer the membership question to continue",
    "Shown under a greyed-out Continue button",
    Y
   ],
   [
    "Signs you out, you can finish later if needed",
    "Under the Sign out link on the profile screen",
    Y
   ],
   [
    "Clinic updates come through the app. Keep notifications on so you don't miss them.",
    "The notifications permission screen, before the iPhone asks",
    False
   ],
   [
    "Turn on notifications",
    "Its button",
    False
   ],
   [
    "Not now",
    "Its other button",
    False
   ],
   [
    "Waiver",
    "Title of the waiver screen, shown once after the profile",
    False
   ],
   [
    "I have read and agree to the Adult Tennis Participation Waiver and Release.",
    "The required checkbox (from your document)",
    Y
   ],
   [
    "Full legal name",
    "Label of the signature box (your document: 'Participant enters full legal name')",
    False
   ],
   [
    "First and last name",
    "The grey example text inside it",
    False
   ],
   [
    "Agree and sign",
    "The button",
    False
   ],
   [
    "Type your first and last name.",
    "If they type one word",
    False
   ]
  ]
 ],
 [
  "Home",
  "What a signed-in player sees first",
  [
   [
    "Good Morning, Maria!",
    "Greeting (Morning / Afternoon / Evening by the hour)",
    False
   ],
   [
    "MY CLINICS",
    "Section heading",
    False
   ],
   [
    "You're not registered for any clinics this week",
    "When they hold no spot and are in no Player Pool (also under My Clinics, which lists every upcoming week; question 54)",
    Y
   ],
   [
    "View All Clinics",
    "Button under My Clinics; opens their own clinics",
    False
   ],
   [
    "AVAILABLE CLINICS",
    "Section heading for the open list",
    False
   ],
   [
    "No clinics currently open for registration",
    "When no clinic is open for registration",
    Y
   ],
   [
    "View Open Clinics (4)",
    "Button under the list; the number is how many are open",
    False
   ],
   [
    "Turn on notifications",
    "Under the notifications sentence on Home, only while they have turned notifications off; opens their iPhone Settings",
    False
   ]
  ]
 ],
 [
  "Clinics and a clinic",
  "The list, and a single clinic's page",
  [
   [
    "Registration open",
    "Chip on a clinic in the list",
    False
   ],
   [
    "Registration opens Sep 18",
    "Chip when the window has not opened yet",
    False
   ],
   [
    "This week / Next week / Week of Sep 27",
    "Group headings in the list",
    False
   ],
   [
    "Register",
    "The one big button",
    False
   ],
   [
    "Cancel Registration",
    "Same button once they are in",
    False
   ],
   [
    "Leave Player Pool",
    "Same button once they are in the Pool",
    False
   ],
   [
    "Keep my spot",
    "The safe choice on every confirmation",
    False
   ],
   [
    "Yes, cancel my spot",
    "Confirmation before 4 hours",
    False
   ],
   [
    "Yes, leave the pool",
    "Confirmation for leaving the Player Pool",
    False
   ],
   [
    "This cancellation is within 3 hours of clinic and the full clinic fee will apply. If there are circumstances you'd like us to consider, please leave a note below.",
    "Inside 3 hours (your sentence, with the 3 you gave)",
    Y
   ],
   [
    "Note for Tara (optional)",
    "The box under that sentence",
    Y
   ],
   [
    "Cancel my spot",
    "The red button on that sheet",
    False
   ],
   [
    "Accept",
    "For an invitation from the Player Pool",
    False
   ],
   [
    "Decline",
    "Its partner",
    False
   ],
   [
    "Registration has closed for this clinic.",
    "Inside the 3-hour close",
    False
   ],
   [
    "You can still ask Tara to fit you in.",
    "Under it",
    False
   ],
   [
    "Message Tara",
    "The button that sends you their note",
    False
   ],
   [
    "Tara has your message.",
    "After they send it",
    False
   ],
   [
    "She will let you know asap if there is room in this clinic",
    "Under that",
    Y
   ],
   [
    "This clinic has been canceled.",
    "On a canceled clinic",
    False
   ],
   [
    "FROM TARA",
    "Heading above your clinic messages",
    False
   ],
   [
    "Add a card on your Profile to register.",
    "When a card is required and they have none",
    False
   ],
   [
    "Sorry, someone beat you to the punch. Here's the latest!",
    "When someone else acted first (the spot filled, an invite was withdrawn)",
    Y
   ],
   [
    "Couldn't load clinics.",
    "When the phone is offline",
    False
   ],
   [
    "About this clinic",
    "Heading of the ? sheet",
    False
   ],
   [
    "What is 105?",
    "Heading in that sheet (your 105 definition follows it)",
    False
   ],
   [
    "No description yet.",
    "When a clinic has no description",
    False
   ],
   [
    "Sign the waiver first.",
    "If someone reaches Register without having signed",
    False
   ],
   [
    "PAST",
    "Heading at the bottom of My Clinics",
    False
   ],
   [
    "Played · $18 / No-show / Canceled / Canceled late",
    "The outcome on each past clinic, their own only",
    False
   ]
  ]
 ],
 [
  "Profile",
  "Their own details",
  [
   [
    "FXE Member / Non-member",
    "Under their name",
    False
   ],
   [
    "Payment method",
    "Heading of the card section",
    False
   ],
   [
    "Your card will only be charged after the clinic you attended, late cancellations, or no-shows. Cancel at least 3 hours before clinic and you will not be charged.",
    "Under that heading (your sentence)",
    Y
   ],
   [
    "No card on file",
    "Before they add one",
    False
   ],
   [
    "Add a card",
    "The link that opens the card form",
    False
   ],
   [
    "Change card",
    "Same link once a card exists",
    False
   ],
   [
    "Cards aren't set up yet.",
    "Until Stripe is connected",
    False
   ],
   [
    "Saved.",
    "After a card is added",
    False
   ],
   [
    "Edit details",
    "Button",
    False
   ],
   [
    "Set by Tara",
    "Beside their membership on Edit details",
    False
   ],
   [
    "What do the ratings mean?",
    "The ? button, read aloud by VoiceOver",
    False
   ],
   [
    "Rating Guide",
    "Title of the rating chart sheet (the chart itself is the Volee one you approved)",
    False
   ],
   [
    "Sign Out",
    "Button",
    False
   ],
   [
    "Delete my account",
    "Small red link at the bottom of Profile",
    False
   ],
   [
    "Delete your account? Your name, phone, email and card are removed and you are signed out. This can't be undone.",
    "The confirmation before it",
    False
   ],
   [
    "Keep my account",
    "Its safe choice",
    False
   ]
  ]
 ],
 [
  "Notifications",
  "The bell on Home, and the messages the app sends",
  [
   [
    "Notifications",
    "Title of the bell screen",
    False
   ],
   [
    "No notifications yet",
    "When there are none",
    Y
   ],
   [
    "Mark all read",
    "Button",
    False
   ],
   [
    "A spot opened in Tuesday Ladies 3.0+. Accept or decline.",
    "Sent when you invite someone from the Player Pool",
    False
   ],
   [
    "Tuesday Ladies 3.0+ has been canceled.",
    "Sent to everyone when you cancel a clinic",
    False
   ],
   [
    "Maria Alvarez canceled. Late, fee applies. Note: \"Kid has a fever\"",
    "What YOU see when the fee applies and they left a note",
    False
   ]
  ]
 ],
 [
  "Your side of the phone",
  "The Manage tab, only you see it",
  [
   [
    "Manage",
    "Your fourth tab",
    False
   ],
   [
    "ACTION NEEDED",
    "Heading for late requests and unread replies",
    False
   ],
   [
    "asking to get in",
    "Beside a player who messaged you inside the close",
    False
   ],
   [
    "Put them in / No room",
    "Your two answers",
    False
   ],
   [
    "Invite / Cancel Invite",
    "On Player Pool and Response Needed rows",
    False
   ],
   [
    "Came / No-show",
    "The new toggle on each You're In! row",
    False
   ],
   [
    "No court / Court 3",
    "The court menu",
    False
   ],
   [
    "Remove from clinic",
    "In the row menu, with a confirmation",
    False
   ],
   [
    "Message Players",
    "Button; then Everyone / You're In! / Player Pool / Response Needed / Unpaid",
    False
   ],
   [
    "Charge clinic",
    "In the More menu once a clinic has ended",
    False
   ],
   [
    "Charge every card for Tuesday Ladies 3.0+? Attendees pay the clinic fee; no-shows and late cancellations pay the full fee.",
    "Its confirmation",
    False
   ],
   [
    "Charged 6. Already charged 0. No card 1.",
    "What you see after",
    False
   ],
   [
    "Cancel clinic",
    "In the More menu",
    False
   ],
   [
    "Cancel Tuesday Ladies 3.0+? Everyone registered or waiting is told.",
    "Its confirmation",
    False
   ],
   [
    "Players",
    "Your directory; search by name",
    False
   ],
   [
    "Type at least two letters of a name.",
    "Before searching",
    False
   ],
   [
    "Nobody by that name yet. They may need to sign up in the app first.",
    "Empty search",
    False
   ],
   [
    "Private note",
    "Your note on a player",
    False
   ],
   [
    "Only you can see this.",
    "Under it",
    False
   ],
   [
    "Waiver signed / Waiver not signed",
    "On each player's page and beside their name in Players",
    False
   ]
  ]
 ],
 [
  "The web admin (laptop)",
  "fxe-tennis-admin.vercel.app",
  [
   [
    "Admin sign-in.",
    "Under the FXE Tennis title",
    False
   ],
   [
    "First time? Create your account",
    "Button on sign-in",
    False
   ],
   [
    "This week · Players · Money",
    "The three tabs",
    False
   ],
   [
    "New clinic",
    "Button",
    False
   ],
   [
    "Start from a template",
    "In the clinic form",
    False
   ],
   [
    "Description (players see this under the “?”)",
    "A field label",
    False
   ],
   [
    "Date & time / Length (minutes) / Max players",
    "Field labels",
    False
   ],
   [
    "Add a player",
    "Heading of the walk-up box",
    False
   ],
   [
    "For someone who called or grabbed you at the club. They go straight to You're In!",
    "Under it",
    False
   ],
   [
    "Ann finds Anna, Annette, Joann…",
    "Hint under the player search",
    False
   ],
   [
    "Put in clinic",
    "Its button",
    False
   ],
   [
    "Show canceled",
    "Checkbox",
    False
   ],
   [
    "1 canceled clinic hidden.",
    "The count under it",
    False
   ],
   [
    "Really cancel? Everyone is told.",
    "Second click on Cancel clinic",
    False
   ],
   [
    "Late · Fee applies",
    "On a canceled row, inside 3 hours",
    False
   ],
   [
    "Members, 60 min / Members, 90 min / Non-members, 60 min / Non-members, 90 min",
    "The four counts on Money",
    False
   ],
   [
    "Expected / Collected / Still owed",
    "The three money lines",
    False
   ],
   [
    "Card payments",
    "Heading of the ledger",
    False
   ],
   [
    "No card payments yet.",
    "Before any",
    False
   ],
   [
    "Pending / Processing / Paid / Failed / Refund",
    "States beside a charge",
    False
   ],
   [
    "Edited Sep 12, 1:38 PM.",
    "Under a private note",
    False
   ],
   [
    "Payments are switched off. / That player has no card on file. / The clinic hasn't ended yet. / That clinic is full now. / Someone already handled that one. / That clinic is already canceled. / That email or password didn't work. / Couldn't reach the server. Check your connection.",
    "The error lines",
    False
   ],
   [
    "Choose a new password",
    "The password reset page",
    False
   ],
   [
    "Pick something you'll remember. At least 8 characters.",
    "Under the new-password box",
    False
   ],
   [
    "Saved. You can sign in with it now, on your phone or here.",
    "After it saves",
    False
   ],
   [
    "This link has expired or was already used. Go back and request a new one.",
    "An old reset link",
    False
   ]
  ]
 ]
]

QUESTIONS = [
 [
  "\"Set by Tara\"",
  "Under a player's membership line on Edit details the app says \"Set by Tara\", so they know why they can't change it. You wrote \"Do we need anything?\" Keep it, or drop it?"
 ],
 [
  "After they message you",
  "Inside the 3-hour close a player can message you. Afterwards the app says \"Tara has your message.\" You chose Change and left it blank. What should it say?"
 ],
 [
  "\"This week\" under My Clinics",
  "Your line \"You're not registered for any clinics this week\" also shows under My Clinics, which lists every upcoming clinic, not only this week's. Keep it, or \"You're not registered for any clinics\"?"
 ],
 [
  "Let's Play",
  "Under the logo: \"Let's Play.\" or \"Let's play!\"? You wrote both."
 ],
 [
  "Your policy text",
  "Your cancellation policy block still says 4 hours, the courtesy paragraph and the emergency email. The app shows only your two sentences today. Do you want a rewritten block (3 hours, no courtesy) shown somewhere? If so, where, and in what words?"
 ],
 [
  "\"Stripe needs to be connected\"",
  "Before cards are set up, the app says \"Cards aren't set up yet.\" You wrote \"Stripe needs to be connected\": a note to us, or the words a player should see?"
 ]
]

TASKS = [
 [
  "Sign in on your laptop",
  "Go to fxe-tennis-admin.vercel.app and sign in with your admin email. Does it open to This week?"
 ],
 [
  "Make a template",
  "Templates card → New template. Use one of your real clinics (name, day, time, length, max players, your description). It saves the prices for you."
 ],
 [
  "Publish this week's real clinics",
  "New clinic → Start from a template → check the date and time → Save, then Publish. Do the member and public open dates look right on the card?"
 ],
 [
  "Edit one",
  "Change the time on a published clinic. Does the card update?"
 ],
 [
  "Show canceled",
  "Cancel a clinic you made by mistake (two clicks), then tick Show canceled to see it again. Nothing is deleted."
 ],
 [
  "Money tab",
  "Open Money. The numbers are zero until players register; does the layout make sense to you?"
 ],
 [
  "Players tab",
  "Search a name. Empty until members sign up; the app will list them here."
 ],
 [
  "Forgot password",
  "Sign out, click Forgot password, and finish the reset from the email. Tell me if the email never arrives or lands in spam."
 ],
 [
  "The phone app",
  "Not yet. It needs Apple's approval of the FXE Tennis, LLC account before it can go on your phone. Everything above is what you can try today."
 ]
]

TEMPLATE = "<title>FXE Tennis, Tara's Review</title>\n<link rel=\"preconnect\" href=\"https://fonts.googleapis.com\">\n<link rel=\"stylesheet\" href=\"https://fonts.googleapis.com/css2?family=Fraunces:opsz,wght@9..144,600;9..144,700&display=swap\">\n<style>\n:root {\n  --navy:#0E1239; --ink:#1B1F3A; --muted:#5F6478; --line:#DDD9CE; --ground:#FAF7F1; --card:#FFFFFF;\n  --green:#3E7C55; --green-soft:#E7F0E7; --brass:#7A5E24; --brass-soft:#F5EBD8; --red:#992E22;\n  --chip:#F1EEE6; --chip-on:#0E1239; --chip-on-ink:#F6F3EA;\n}\n@media (prefers-color-scheme: dark) { :root:not([data-theme=\"light\"]) {\n  --navy:#C9CFF2; --ink:#EDEBE4; --muted:#A9ADBF; --line:#3A3D52; --ground:#15172A; --card:#1E2136;\n  --green:#8FCB9F; --green-soft:#24372B; --brass:#D9B86A; --brass-soft:#3A3120; --red:#F0907F;\n  --chip:#2A2D44; --chip-on:#E9E6DD; --chip-on-ink:#15172A;\n} }\n:root[data-theme=\"dark\"] {\n  --navy:#C9CFF2; --ink:#EDEBE4; --muted:#A9ADBF; --line:#3A3D52; --ground:#15172A; --card:#1E2136;\n  --green:#8FCB9F; --green-soft:#24372B; --brass:#D9B86A; --brass-soft:#3A3120; --red:#F0907F;\n  --chip:#2A2D44; --chip-on:#E9E6DD; --chip-on-ink:#15172A;\n}\nbody { background:var(--ground); color:var(--ink); font: 16px/1.5 -apple-system, \"SF Pro Text\", \"Helvetica Neue\", Arial, sans-serif; padding-block:0 48px; }\n.wrap { max-width:680px; margin:0 auto; padding:0 16px; }\nheader.top { padding:28px 0 12px; }\nh1 { font-family:\"Fraunces\", Georgia, \"Times New Roman\", serif; font-weight:700; font-size:34px; line-height:1.1; color:var(--navy); margin:0 0 8px; text-wrap:balance; }\n.lede { color:var(--muted); margin:0; max-width:60ch; }\nnav.tabs { position:sticky; top:env(safe-area-inset-top, 0px); background:var(--ground); display:flex; gap:6px; padding:12px 0 10px; border-bottom:1px solid var(--line); z-index:2; }\nnav.tabs button { flex:1; border:1px solid var(--line); background:var(--card); color:var(--ink); border-radius:999px; padding:10px 8px; font:inherit; font-weight:600; font-size:15px; cursor:pointer; }\nnav.tabs button[aria-selected=\"true\"] { background:var(--chip-on); color:var(--chip-on-ink); border-color:var(--chip-on); }\nnav.tabs button:focus-visible, .chip:focus-visible, textarea:focus-visible, .copy:focus-visible { outline:3px solid var(--green); outline-offset:2px; }\n.progress { font-size:14px; color:var(--muted); padding:12px 0 4px; font-variant-numeric:tabular-nums; }\nsection.screen { margin-top:22px; }\nh2 { font-family:\"Fraunces\", Georgia, serif; font-weight:600; font-size:24px; color:var(--navy); margin:0; text-wrap:balance; }\n.sub { margin:2px 0 12px; color:var(--muted); font-size:14px; }\n.item { background:var(--card); border:1px solid var(--line); border-radius:14px; padding:14px 14px 12px; margin:0 0 10px; }\n.where { font-size:12.5px; letter-spacing:.02em; text-transform:uppercase; color:var(--muted); display:flex; gap:8px; align-items:center; flex-wrap:wrap; }\n.tag { text-transform:none; letter-spacing:0; font-size:12px; padding:2px 8px; border-radius:999px; background:var(--brass-soft); color:var(--brass); font-weight:600; }\nblockquote.blurb { margin:8px 0 10px; padding:0 0 0 12px; border-left:3px solid var(--navy); font-size:17px; line-height:1.45; }\n.choices { display:flex; gap:8px; }\n.chip { border:1px solid var(--line); background:var(--chip); color:var(--ink); border-radius:999px; padding:8px 16px; font:inherit; font-weight:600; font-size:15px; min-height:40px; cursor:pointer; }\n.chip[aria-pressed=\"true\"] { background:var(--chip-on); color:var(--chip-on-ink); border-color:var(--chip-on); }\n.chip[aria-pressed=\"true\"][data-choice=\"keep\"] { background:var(--green); border-color:var(--green); color:#fff; }\ntextarea { width:100%; box-sizing:border-box; margin-top:10px; border:1px solid var(--line); border-radius:10px; padding:10px 12px; font:inherit; font-size:16px; background:var(--card); color:var(--ink); min-height:64px; resize:vertical; }\nh3 { margin:6px 0 4px; font-size:18px; color:var(--navy); }\n.item p { margin:0; }\nlabel.task { display:flex; gap:12px; align-items:flex-start; cursor:pointer; }\nlabel.task input { width:22px; height:22px; margin:2px 0 0; accent-color:var(--green); flex:none; }\n.send { margin-top:28px; padding:16px; border:1px dashed var(--line); border-radius:14px; background:var(--card); }\n.send h2 { font-size:20px; }\n.copy { margin-top:10px; border:0; background:var(--chip-on); color:var(--chip-on-ink); border-radius:999px; padding:12px 18px; font:inherit; font-weight:700; font-size:16px; cursor:pointer; }\n.copied { margin-left:10px; color:var(--green); font-weight:600; }\npre.summary { white-space:pre-wrap; font: 13.5px/1.45 ui-monospace, Menlo, monospace; background:var(--chip); border-radius:10px; padding:12px; margin-top:12px; max-height:340px; overflow:auto; }\n.panel[hidden] { display:none; }\n@media (prefers-reduced-motion: no-preference) { .chip, nav.tabs button { transition: background .15s, color .15s; } }\n</style>\n\n<div class=\"wrap\">\n<header class=\"top\">\n  <h1>Tara, this is your app's words</h1>\n  <p class=\"lede\">Every sentence a player or you will read, with where it shows up. Tap Keep, or Change and write it your way. Your answers stay on this phone; when you're done, copy the summary at the bottom and text it to Alex.</p>\n</header>\n\n<nav class=\"tabs\" role=\"tablist\">\n  <button role=\"tab\" data-tab=\"words\" aria-selected=\"true\">Words</button>\n  <button role=\"tab\" data-tab=\"questions\" aria-selected=\"false\">Questions</button>\n  <button role=\"tab\" data-tab=\"try\" aria-selected=\"false\">Try it</button>\n</nav>\n\n<div class=\"panel\" id=\"panel-words\">\n  <div class=\"progress\" id=\"progress-words\">0 of @@TOTAL@@ decided</div>\n  @@WORDS@@\n</div>\n\n<div class=\"panel\" id=\"panel-questions\" hidden>\n  <div class=\"progress\">@@NQ@@ questions. One line each is plenty.</div>\n  @@QUESTIONS@@\n</div>\n\n<div class=\"panel\" id=\"panel-try\" hidden>\n  <div class=\"progress\">On your laptop, with your real account. Whatever you set up here is real: it is your schedule.</div>\n  @@TASKS@@\n</div>\n\n<div class=\"send\">\n  <h2>Send it to Alex</h2>\n  <p class=\"lede\">This gathers everything you've decided across all three tabs.</p>\n  <button class=\"copy\" id=\"copy\">Copy my answers</button><span class=\"copied\" id=\"copied\" hidden>Copied</span>\n  <pre class=\"summary\" id=\"summary\"></pre>\n</div>\n</div>\n\n<script>\nconst DATA = @@DATA@@;\nconst KEY = \"fxe-tara-review-v1\";\nlet state = {};\ntry { state = JSON.parse(localStorage.getItem(KEY) || \"{}\"); } catch (e) { state = {}; }\nconst save = () => { try { localStorage.setItem(KEY, JSON.stringify(state)); } catch (e) {} };\n\n// tabs\ndocument.querySelectorAll('nav.tabs [role=tab]').forEach(b => b.addEventListener('click', () => {\n  document.querySelectorAll('nav.tabs [role=tab]').forEach(x => x.setAttribute('aria-selected', String(x === b)));\n  for (const n of ['words','questions','try']) document.getElementById('panel-' + n).hidden = (n !== b.dataset.tab);\n  try { localStorage.setItem(KEY + ':tab', b.dataset.tab); } catch (e) {}\n}));\ntry { const t = localStorage.getItem(KEY + ':tab'); if (t) document.querySelector(`[data-tab=\"${t}\"]`)?.click(); } catch (e) {}\n\n// words\nfunction renderItem(el) {\n  const id = el.dataset.id, s = state[id] || {};\n  el.querySelectorAll('.chip').forEach(c => c.setAttribute('aria-pressed', String(s.choice === c.dataset.choice)));\n  const alt = el.querySelector('.alt');\n  if (alt) { alt.hidden = s.choice !== 'change'; if (s.alt !== undefined && alt.value !== s.alt) alt.value = s.alt; }\n}\ndocument.querySelectorAll('#panel-words .item').forEach(el => {\n  renderItem(el);\n  el.querySelectorAll('.chip').forEach(c => c.addEventListener('click', () => {\n    const id = el.dataset.id; state[id] = { ...(state[id] || {}), choice: c.dataset.choice }; save(); renderItem(el); progress(); summary();\n    if (c.dataset.choice === 'change') el.querySelector('.alt').focus();\n  }));\n  el.querySelector('.alt')?.addEventListener('input', e => { const id = el.dataset.id; state[id] = { ...(state[id] || {}), alt: e.target.value }; save(); summary(); });\n});\nfunction progress() {\n  const n = DATA.sections.flatMap(s => s.items).filter(i => state[i.id]?.choice).length;\n  document.getElementById('progress-words').textContent = `${n} of @@TOTAL@@ decided`;\n}\n// questions and tasks\ndocument.querySelectorAll('#panel-questions textarea, #panel-try textarea').forEach(t => {\n  const id = t.id; if (state[id] !== undefined) t.value = state[id];\n  t.addEventListener('input', e => { state[id] = e.target.value; save(); summary(); });\n});\ndocument.querySelectorAll('#panel-try input[type=checkbox]').forEach(c => {\n  if (state[c.id]) c.checked = true;\n  c.addEventListener('change', e => { state[c.id] = e.target.checked; save(); summary(); });\n});\nfunction summary() {\n  const lines = [\"FXE Tennis review, \" + new Date().toLocaleDateString(), \"\"];\n  lines.push(\"WORDS\");\n  for (const s of DATA.sections) for (const i of s.items) {\n    const st = state[i.id]; if (!st?.choice) continue;\n    if (st.choice === 'keep') lines.push(`keep: ${i.text}`);\n    else lines.push(`CHANGE: \"${i.text}\" -> \"${(st.alt || '').trim() || '(no replacement written yet)'}\"`);\n  }\n  lines.push(\"\", \"QUESTIONS\");\n  for (const q of DATA.questions) { const a = (state[q.id + '-ans'] || '').trim(); if (a) lines.push(`${q.title}: ${a}`); }\n  lines.push(\"\", \"TRIED\");\n  for (const t of DATA.tasks) { const done = state[t.id + '-done'], note = (state[t.id + '-note'] || '').trim(); if (done || note) lines.push(`${done ? '[x]' : '[ ]'} ${t.title}${note ? ': ' + note : ''}`); }\n  document.getElementById('summary').textContent = lines.join(\"\\n\");\n}\ndocument.getElementById('copy').addEventListener('click', async () => {\n  summary();\n  const text = document.getElementById('summary').textContent;\n  try { await navigator.clipboard.writeText(text); document.getElementById('copied').hidden = false; setTimeout(() => document.getElementById('copied').hidden = true, 2500); }\n  catch (e) { const r = document.createRange(); r.selectNodeContents(document.getElementById('summary')); const sel = getSelection(); sel.removeAllRanges(); sel.addRange(r); const c = document.getElementById('copied'); c.textContent = 'Selected. Press and hold to copy.'; c.hidden = false; }\n});\nprogress(); summary();\n</script>\n"


# The web target. Same look: the artifact's stylesheet is reused verbatim
# (sliced out of TEMPLATE below), and its light palette is then pointed at
# web/tokens.css so the page matches the admin site; the dark palette stays
# the artifact's, because tokens.css is light only. Items render from the
# JSON block, see the module docstring.
WEB_TEMPLATE = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>FXE Tennis, Tara's Review</title>
<link rel="stylesheet" href="./tokens.css">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Fraunces:opsz,wght@9..144,600;9..144,700&display=swap">
@@CSS@@
<style>
:root { --navy:var(--fxe-navy); --ink:var(--fxe-text-primary); --muted:var(--fxe-text-secondary); --line:var(--fxe-hairline); --ground:var(--fxe-surface); --card:var(--fxe-surface-raised); --green:var(--fxe-court); --brass:var(--fxe-status-pool-ink); --brass-soft:var(--fxe-status-pool-tint); --red:var(--fxe-status-canceled-ink); --chip-on:var(--fxe-navy); --chip-on-ink:var(--fxe-text-on-navy); }
body { margin:0; }
.sync { margin:10px 0 0; font-size:14px; color:var(--muted); min-height:1.5em; }
.sync[data-state="error"] { color:var(--red); }
.sync[data-state="saved"] { color:var(--green); }
</style>
</head>
<body>
<div class="wrap">
<header class="top">
  <h1>Tara, this is your app's words</h1>
  <p class="lede">Every sentence a player or you will read, with where it shows up. Tap Keep, or Change and write it your way. Your answers save as you go.</p>
  <p class="sync" id="sync" aria-live="polite"></p>
</header>

<nav class="tabs" role="tablist">
  <button role="tab" data-tab="words" aria-selected="true">Words</button>
  <button role="tab" data-tab="questions" aria-selected="false">Questions</button>
  <button role="tab" data-tab="try" aria-selected="false">Try it</button>
</nav>

<div class="panel" id="panel-words">
  <div class="progress" id="progress-words"></div>
</div>

<div class="panel" id="panel-questions" hidden>
  <div class="progress" id="progress-questions"></div>
</div>

<div class="panel" id="panel-try" hidden>
  <div class="progress">On your laptop, with your real account. Whatever you set up here is real: it is your schedule.</div>
</div>

<div class="send">
  <h2>Your answers as text</h2>
  <p class="lede">Alex sees your answers as they save. Copy them here if you want to text them as well.</p>
  <button class="copy" id="copy">Copy my answers</button><span class="copied" id="copied" hidden>Copied</span>
  <pre class="summary" id="summary"></pre>
</div>
</div>

<script id="review-data" type="application/json">@@DATA@@</script>
<script type="module">
import { CONFIG } from "./config.js";

const DATA = JSON.parse(document.getElementById('review-data').textContent);
const token = new URLSearchParams(location.search).get('t') || '';
const FN = CONFIG.url + '/functions/v1/review-submit';
// One local copy per link, so two links on one phone never share answers.
const KEY = 'fxe-tara-review-web:' + (token || 'local');
const esc = (s) => String(s ?? '').replace(/[&<>"']/g, m => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[m]));

let state = {}, localStamp = null;
try { const l = JSON.parse(localStorage.getItem(KEY) || '{}'); state = l.state || {}; localStamp = l.stamp || null; } catch (e) {}
const saveLocal = () => { try { localStorage.setItem(KEY, JSON.stringify({ state, stamp: localStamp })); } catch (e) {} };

// ---- render from DATA
const total = DATA.sections.reduce((n, s) => n + s.items.length, 0);
document.getElementById('panel-words').insertAdjacentHTML('beforeend', DATA.sections.map(s => `<section class="screen"><h2>${esc(s.name)}</h2><p class="sub">${esc(s.sub)}</p>` + s.items.map(i => `<div class="item" data-id="${i.id}">
  <div class="where">${esc(i.where)} ${i.yours ? '<span class="tag yours">Your words</span>' : ''}</div>
  <blockquote class="blurb">${esc(i.text)}</blockquote>
  <div class="choices">
    <button class="chip" data-choice="keep">Keep</button>
    <button class="chip" data-choice="change">Change</button>
  </div>
  <textarea class="alt" id="${i.id}-alt" placeholder="Write it the way you'd say it" hidden></textarea>
</div>`).join('') + '</section>').join(''));
document.getElementById('progress-questions').textContent = `${DATA.questions.length} questions. One line each is plenty.`;
document.getElementById('panel-questions').insertAdjacentHTML('beforeend', DATA.questions.map((q, i) =>
  `<div class="item" data-id="${q.id}"><div class="where">${i + 1} of ${DATA.questions.length}</div><h3>${esc(q.title)}</h3><p>${esc(q.text)}</p><textarea class="ans" id="${q.id}-ans" placeholder="Your answer"></textarea></div>`).join(''));
document.getElementById('panel-try').insertAdjacentHTML('beforeend', DATA.tasks.map(t =>
  `<div class="item" data-id="${t.id}"><label class="task"><input type="checkbox" id="${t.id}-done"><span><strong>${esc(t.title)}</strong><br>${esc(t.text)}</span></label><textarea class="ans" id="${t.id}-note" placeholder="What happened? Anything odd?"></textarea></div>`).join(''));

// ---- tabs
document.querySelectorAll('nav.tabs [role=tab]').forEach(b => b.addEventListener('click', () => {
  document.querySelectorAll('nav.tabs [role=tab]').forEach(x => x.setAttribute('aria-selected', String(x === b)));
  for (const n of ['words','questions','try']) document.getElementById('panel-' + n).hidden = (n !== b.dataset.tab);
  try { localStorage.setItem(KEY + ':tab', b.dataset.tab); } catch (e) {}
}));
try { const t = localStorage.getItem(KEY + ':tab'); if (t) document.querySelector(`[data-tab="${t}"]`)?.click(); } catch (e) {}

// ---- state -> screen
function renderItem(el) {
  const id = el.dataset.id, s = state[id] || {};
  el.querySelectorAll('.chip').forEach(c => c.setAttribute('aria-pressed', String(s.choice === c.dataset.choice)));
  const alt = el.querySelector('.alt');
  if (alt) { alt.hidden = s.choice !== 'change'; if (s.alt !== undefined && alt.value !== s.alt) alt.value = s.alt; }
}
function renderAll() {
  document.querySelectorAll('#panel-words .item').forEach(renderItem);
  document.querySelectorAll('#panel-questions textarea, #panel-try textarea').forEach(t => { t.value = state[t.id] !== undefined ? state[t.id] : ''; });
  document.querySelectorAll('#panel-try input[type=checkbox]').forEach(c => { c.checked = !!state[c.id]; });
  progress(); summary();
}
function progress() {
  const n = DATA.sections.flatMap(s => s.items).filter(i => state[i.id]?.choice).length;
  document.getElementById('progress-words').textContent = `${n} of ${total} decided`;
}
// The text Alex reads on the admin page and the text under Copy my answers
// are one function, so they cannot drift: the page saves its own summary
// alongside the raw state.
function formatSummary(data, st) {
  const lines = ["FXE Tennis review, " + new Date().toLocaleDateString(), ""];
  lines.push("WORDS");
  for (const s of data.sections) for (const i of s.items) {
    const x = st[i.id]; if (!x?.choice) continue;
    if (x.choice === 'keep') lines.push(`keep: ${i.text}`);
    else lines.push(`CHANGE: "${i.text}" -> "${(x.alt || '').trim() || '(no replacement written yet)'}"`);
  }
  lines.push("", "QUESTIONS");
  for (const q of data.questions) { const a = (st[q.id + '-ans'] || '').trim(); if (a) lines.push(`${q.title}: ${a}`); }
  lines.push("", "TRIED");
  for (const t of data.tasks) { const done = st[t.id + '-done'], note = (st[t.id + '-note'] || '').trim(); if (done || note) lines.push(`${done ? '[x]' : '[ ]'} ${t.title}${note ? ': ' + note : ''}`); }
  return lines.join("\\n");
}
function summary() { document.getElementById('summary').textContent = formatSummary(DATA, state); }

// ---- every change: this phone first, the server 1.5 s later
function changed() { localStamp = new Date().toISOString(); saveLocal(); summary(); scheduleServer(); }
document.querySelectorAll('#panel-words .item').forEach(el => {
  el.querySelectorAll('.chip').forEach(c => c.addEventListener('click', () => {
    const id = el.dataset.id; state[id] = { ...(state[id] || {}), choice: c.dataset.choice }; renderItem(el); progress(); changed();
    if (c.dataset.choice === 'change') el.querySelector('.alt').focus();
  }));
  el.querySelector('.alt')?.addEventListener('input', e => { const id = el.dataset.id; state[id] = { ...(state[id] || {}), alt: e.target.value }; changed(); });
});
document.querySelectorAll('#panel-questions textarea, #panel-try textarea').forEach(t => t.addEventListener('input', e => { state[t.id] = e.target.value; changed(); }));
document.querySelectorAll('#panel-try input[type=checkbox]').forEach(c => c.addEventListener('change', e => { state[c.id] = e.target.checked; changed(); }));

// ---- server. Debounced 1.5 s after the last change, and flushed when the
// page goes to the background (keepalive lets the request outlive the tab).
const sync = document.getElementById('sync');
const setSync = (text, st) => { sync.textContent = text; sync.dataset.state = st || ''; };
let timer = null, dirty = false, inflight = false;
function scheduleServer() { if (!token) return; dirty = true; clearTimeout(timer); timer = setTimeout(pushServer, 1500); }
async function pushServer(keepalive = false) {
  if (!token || !dirty || inflight) return;
  inflight = true; dirty = false; setSync('Saving\\u2026', 'saving');
  const body = JSON.stringify({ token, page_version: DATA.version, answers: { state, summary: formatSummary(DATA, state), page_version: DATA.version, saved_from: localStamp } });
  try {
    const r = await fetch(FN, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body, keepalive });
    if (!r.ok) throw new Error(String(r.status));
    setSync('Saved', 'saved');
  } catch (e) {
    dirty = true; setSync("Couldn't save, still on this phone", 'error');
  } finally { inflight = false; if (dirty) scheduleServer(); }
}
document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'hidden') { clearTimeout(timer); pushServer(true); } });

// On load: the server copy wins when it is at least as new as this phone's;
// otherwise this phone is ahead (it saved offline) and pushes.
async function pullServer() {
  if (!token) { setSync('This link has no code, answers stay on this phone.', ''); return; }
  try {
    const r = await fetch(FN + '?token=' + encodeURIComponent(token) + '&page_version=' + encodeURIComponent(DATA.version));
    if (r.status === 404) { setSync("This link isn't active, answers stay on this phone.", 'error'); return; }
    if (!r.ok) throw new Error(String(r.status));
    const { answers, saved_at } = await r.json();
    const serverNewer = answers?.state && (!localStamp || (saved_at && new Date(saved_at) >= new Date(localStamp)));
    if (serverNewer) { state = answers.state; localStamp = saved_at; saveLocal(); renderAll(); setSync('Saved', 'saved'); }
    else if (localStamp) { setSync('', ''); scheduleServer(); }
    else setSync('', '');
  } catch (e) { setSync("Couldn't load saved answers, still on this phone", 'error'); }
}

document.getElementById('copy').addEventListener('click', async () => {
  summary();
  const text = document.getElementById('summary').textContent;
  try { await navigator.clipboard.writeText(text); document.getElementById('copied').hidden = false; setTimeout(() => document.getElementById('copied').hidden = true, 2500); }
  catch (e) { const r = document.createRange(); r.selectNodeContents(document.getElementById('summary')); const sel = getSelection(); sel.removeAllRanges(); sel.addRange(r); const c = document.getElementById('copied'); c.textContent = 'Selected. Press and hold to copy.'; c.hidden = false; }
});
renderAll();
pullServer();
</script>
</body>
</html>
"""


def esc(s):
    return html.escape(s, quote=True)


def item_html(sec_i, i, text, where, yours):
    iid = f"w{sec_i}-{i}"
    tag = '<span class="tag yours">Your words</span>' if yours else ''
    return f'''<div class="item" data-id="{iid}">
  <div class="where">{esc(where)} {tag}</div>
  <blockquote class="blurb">{esc(text)}</blockquote>
  <div class="choices">
    <button class="chip" data-choice="keep">Keep</button>
    <button class="chip" data-choice="change">Change</button>
  </div>
  <textarea class="alt" id="{iid}-alt" placeholder="Write it the way you\'d say it" hidden></textarea>
</div>'''


ROOT = pathlib.Path(__file__).resolve().parent.parent


def artifact_page():
    """docs/tara-review/index.html, unchanged in behaviour: answers in localStorage."""
    words = "".join(
        f'<section class="screen"><h2>{esc(name)}</h2><p class="sub">{esc(sub)}</p>'
        + "".join(item_html(si, i, t, w, y) for i, (t, w, y) in enumerate(items)) + '</section>'
        for si, (name, sub, items) in enumerate(SECTIONS))
    qs = "".join(
        f'''<div class="item" data-id="q{i}"><div class="where">{i+1} of {len(QUESTIONS)}</div><h3>{esc(t)}</h3><p>{esc(q)}</p><textarea class="ans" id="q{i}-ans" placeholder="Your answer"></textarea></div>'''
        for i, (t, q) in enumerate(QUESTIONS))
    ts = "".join(
        f'''<div class="item" data-id="t{i}"><label class="task"><input type="checkbox" id="t{i}-done"><span><strong>{esc(t)}</strong><br>{esc(d)}</span></label><textarea class="ans" id="t{i}-note" placeholder="What happened? Anything odd?"></textarea></div>'''
        for i, (t, d) in enumerate(TASKS))
    data = {
        "sections": [{"name": n, "items": [{"id": f"w{si}-{i}", "text": t} for i, (t, w, y) in enumerate(items)]}
                     for si, (n, s, items) in enumerate(SECTIONS)],
        "questions": [{"id": f"q{i}", "title": t} for i, (t, q) in enumerate(QUESTIONS)],
        "tasks": [{"id": f"t{i}", "title": t} for i, (t, d) in enumerate(TASKS)],
    }
    total = sum(len(s[2]) for s in SECTIONS)
    return (TEMPLATE.replace("@@WORDS@@", words).replace("@@QUESTIONS@@", qs).replace("@@TASKS@@", ts)
            .replace("@@DATA@@", json.dumps(data)).replace("@@TOTAL@@", str(total)).replace("@@NQ@@", str(len(QUESTIONS))))


def web_page():
    """web/review.html: the same page, rendered from a JSON block, saving to the server."""
    data = {
        "version": PAGE_VERSION,
        "sections": [{"name": n, "sub": s, "items": [{"id": f"w{si}-{i}", "text": t, "where": w, "yours": bool(y)}
                                                     for i, (t, w, y) in enumerate(items)]}
                     for si, (n, s, items) in enumerate(SECTIONS)],
        "questions": [{"id": f"q{i}", "title": t, "text": q} for i, (t, q) in enumerate(QUESTIONS)],
        "tasks": [{"id": f"t{i}", "title": t, "text": d} for i, (t, d) in enumerate(TASKS)],
    }
    css = TEMPLATE[TEMPLATE.index("<style>"):TEMPLATE.index("</style>") + len("</style>")]
    # "</" inside a JSON script block would end the block early; JSON allows the escape.
    blob = json.dumps(data).replace("</", "<\\/")
    return WEB_TEMPLATE.replace("@@CSS@@", css).replace("@@DATA@@", blob)


def main():
    target = sys.argv[sys.argv.index("--target") + 1] if "--target" in sys.argv else "both"
    if target not in ("artifact", "web", "both"):
        sys.exit(f"unknown --target {target}: artifact, web, or omit for both")
    total = sum(len(s[2]) for s in SECTIONS)
    if target in ("artifact", "both"):
        out = ROOT / "docs" / "tara-review" / "index.html"
        page = artifact_page()
        out.write_text(page)
        print(f"{out}: {total} strings, {len(QUESTIONS)} questions, {len(TASKS)} tasks, {len(page)} bytes")
    if target in ("web", "both"):
        out = ROOT / "web" / "review.html"
        page = web_page()
        out.write_text(page)
        print(f"{out}: {total} strings, {len(QUESTIONS)} questions, {len(TASKS)} tasks, {len(page)} bytes, page version {PAGE_VERSION}")


if __name__ == "__main__":
    main()
