# ScriptPort

A public Lua/Luau paste publisher. Paste or import a script up to 2 MiB, publish it, and copy a loadstring pointing at the saved raw source.

## Hosting

Frontend: https://neeuqpart.github.io/LoadstringSite/
Storage API: https://scriptport-pastes.airyseal4.chatgpt.site

GitHub Pages serves index.html, style.css, and app.js from main / (root). The server backend uses Cloudflare R2 for script bodies and D1 for upload counters, deployed through Sites. GitHub Pages alone cannot store anonymous uploads or serve dynamic raw routes.

## Features

- Public publishing without an account
- 2 MiB UTF-8 script limit; .lua/.luau/.txt file imports
- Line numbers and byte/line counters
- Local draft recovery
- Copyable HttpGet or Roblox Studio server loadstrings
- Raw script links and script downloads
- Recent pastes and deletion keys saved in the publishing browser
- 20 uploads/hour and 100/day per connection; shared service cap 1,000/day

Scripts are stored as text and never executed by this website. Anyone with a raw link can read the source. Links are unlisted, not private. Recent pastes and deletion keys are browser-local; clearing browser storage removes those records and the ability to delete them through this UI. Save important source code separately. There is no automatic expiry or uptime/permanent-retention guarantee.

HttpGet format requires an environment that supplies game:HttpGet and loadstring. Studio format runs in a server Script in your own experience and requires HTTP requests and ServerScriptService.LoadStringEnabled. Only execute trusted source.

Generated format:

    loadstring(game:HttpGet("https://scriptport-pastes.airyseal4.chatgpt.site/raw/PASTE_ID"))()

## Validation

Backend type check and production build; local exact round trip of a 1.45 MB Unicode script; raw Content-Type; CORS; wrong deletion-key rejection; successful deletion and subsequent 404; oversized, empty, and foreign-origin rejection. No submitted scripts are executed during verification.
