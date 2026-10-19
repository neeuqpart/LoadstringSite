# ScriptPort

A dependency-free, responsive GitHub Pages website that generates Roblox script loaders. Includes URL validation, GitHub-to-raw conversion, two loader formats, copy, and Lua download. The website does not fetch, validate availability of, store, or execute scripts.

## Publish on GitHub Pages

1. Create a GitHub repository and upload index.html, style.css, app.js, and .nojekyll to its root.
2. Open repository Settings > Pages.
3. Select Deploy from a branch, choose main and / (root), then Save.
4. Open the URL GitHub displays when deployment finishes.

Reference: https://docs.github.com/en/pages/getting-started-with-github-pages/configuring-a-publishing-source-for-your-github-pages-site

No build command, backend, API key, or dependencies are required. Relative asset paths work with project Pages URLs.

## Host your scripts

Add scripts/example.lua to the same repository. Its published URL is https://YOUR-NAME.github.io/YOUR-REPO/scripts/example.lua. Paste that URL into the tool, or use a public GitHub file URL. Never point a loader at index.html: the loader needs Lua source, not a webpage.

For GitHub branches containing slashes, paste the file's Raw URL to avoid ambiguous branch/path interpretation. For fixed script versions, use a raw URL containing the commit SHA rather than a moving branch name. Public hosting exposes source code; it does not hide or protect it.

## Roblox environments

The Studio format uses HttpService:GetAsync and loadstring in a server Script in your own experience. Enable HTTP requests and ServerScriptService.LoadStringEnabled in Studio. Only run trusted source code.

The game:HttpGet format requires a compatible environment; it is not an ordinary Roblox LocalScript API. Generation does not prove runtime compatibility or script availability.

Documentation:
- https://create.roblox.com/docs/reference/engine/classes/HttpService
- https://create.roblox.com/docs/reference/engine/classes/ServerScriptService/LoadStringEnabled

## Customize

Change the name and text in index.html and the colors in style.css. All application logic lives in app.js. User input is displayed as text, never inserted as HTML.
