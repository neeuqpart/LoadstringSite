# ScriptPort — script gallery

A simple, dark gray Roblox script gallery at https://neeuqpart.github.io/LoadstringSite/.

Click a game card to copy its GitHub raw loadstring. All six script files are .lua, including Pack An Underground Artist. Thumbnails are the six game images supplied by the owner. The gallery includes search, keyboard-accessible cards, clipboard feedback, and a manual-copy fallback.

The website has no uploader or token form. Manage scripts directly in GitHub. Anyone can browse and copy the listed loadstrings; repository writes still require GitHub authorization. The previous public upload backend remains restricted to its owner.

## Updating

Game data and .lua filenames live in app.js. Game images live in assets/. Script source lives in scripts/. Keep each slug matched across the .lua and .png files. The interface never fetches or executes script code; it only copies a loader string.

GitHub Pages publishes main / (root). This is a dependency-free static website.
