# ScriptPort — personal GitHub publisher

Website: https://neeuqpart.github.io/LoadstringSite/
Repository: https://github.com/neeuqpart/LoadstringSite

Paste or import a Lua/Luau script up to 2 MiB. ScriptPort saves it in scripts/ in this repository and generates a loader using raw.githubusercontent.com. No separate storage backend is used.

## Connect your GitHub account

1. On GitHub, create a fine-grained personal access token with resource owner neeuqpart.
2. Select only the LoadstringSite repository.
3. Grant Contents: Read and write repository permission; choose an expiry.
4. Paste the token into the site's GitHub connection field and connect.

The app verifies that the token belongs to neeuqpart. Repository writes are authorized by GitHub itself. The token is sent only to api.github.com and held in memory for the current tab. It is never stored in localStorage, committed to this repository, embedded in raw links, or sent to a separate backend. Refreshing or disconnecting requires reconnecting. Do not share the token.

Visitors without your GitHub credentials cannot publish. The GitHub Pages interface and repository source remain public, and anyone can read or run scripts available through public raw links. A private repository's authenticated raw URLs are unsuitable for a public Roblox loadstring.

## Features

- Paste or import .lua/.luau/.txt files, up to 2 MiB
- UTF-8 uploads, line numbers, line and byte counters
- Drafts saved on the current browser
- GitHub-backed script list after connecting (up to GitHub Contents API directory limit)
- Copy loadstrings and raw links, download scripts
- HttpGet and Roblox Studio server formats
- Manage links open the source file in GitHub for editing or removal

Titles are also saved locally for display; filenames include a readable title and a random identifier. Script bodies are stored unchanged as UTF-8. Deleting a file from the current branch does not erase its Git history. GitHub raw links may take a short time to become available after publishing.

The website never executes uploaded scripts. HttpGet requires a compatible runtime; ordinary Roblox LocalScripts do not provide it. Studio format requires HTTP requests and ServerScriptService.LoadStringEnabled in a server Script in your own experience.

The previous public upload backend has been restricted to its owner. Existing backend data was not deleted. New scripts and loadstrings use GitHub exclusively.

## Publish the interface

GitHub Pages uses main / (root). index.html, style.css, and app.js are dependency-free static files. Do not commit access tokens.
