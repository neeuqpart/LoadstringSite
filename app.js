'use strict';
function normalizeSource(value) {
  let url;
  try { url = new URL(value.trim()); } catch { throw new Error('Enter a complete HTTPS URL.'); }
  if (url.protocol !== 'https:' || url.username || url.password || url.port) throw new Error('Use an HTTPS URL without credentials or a custom port.');
  if (url.hostname === 'github.com') {
    const parts = url.pathname.split('/').filter(Boolean);
    if (parts.length < 5 || parts[2] !== 'blob') throw new Error('Open the script file on GitHub and paste its file link.');
    url = new URL('https://raw.githubusercontent.com/' + [parts[0], parts[1], ...parts.slice(3)].join('/'));
  } else if (url.hostname === 'raw.githubusercontent.com') {
    if (url.pathname.split('/').filter(Boolean).length < 4) throw new Error('Include the owner, repository, revision, and script path.');
  } else if (!url.hostname.endsWith('.github.io')) {
    throw new Error('Use a GitHub file link, raw.githubusercontent.com link, or github.io script URL.');
  }
  url.hash = ''; url.search = '';
  return url.href;
}
function makeLoader(url, runtime) {
  const quoted = JSON.stringify(url);
  return runtime === 'httpget' ? `loadstring(game:HttpGet(${quoted}))()` : `local source = game:GetService("HttpService"):GetAsync(${quoted})\nlocal run, err = loadstring(source)\nassert(run, err)\nrun()`;
}
const $ = id => document.getElementById(id);
let generated = '';
function clearOutput() { generated = ''; $('copy').disabled = $('download').disabled = true; $('status').textContent = 'WAITING'; $('code').textContent = '-- Your next script starts here.\n-- Add a source link to generate your loader.'; $('source').hidden = true; $('source').removeAttribute('href'); $('source-empty').hidden = false; $('feedback').textContent = ''; }
$('url').addEventListener('input', () => { clearOutput(); $('error').textContent = ''; });
$('runtime').addEventListener('change', () => { clearOutput(); $('runtime-note').textContent = $('runtime').value === 'studio' ? 'For your own experience: enable HTTP requests and ServerScriptService.LoadStringEnabled. Run from a server Script.' : 'Requires an environment that provides game:HttpGet and loadstring. This format is not supported by ordinary Roblox LocalScripts.'; });
$('builder').addEventListener('submit', event => {
  event.preventDefault(); clearOutput(); $('error').textContent = '';
  try { const url = normalizeSource($('url').value); generated = makeLoader(url, $('runtime').value); $('code').textContent = generated; $('source').textContent = url; $('source').href = url; $('source').hidden = false; $('source-empty').hidden = true; $('copy').disabled = $('download').disabled = false; $('status').textContent = 'GENERATED'; } catch (error) { $('error').textContent = error.message; }
});
$('copy').addEventListener('click', async () => { try { await navigator.clipboard.writeText(generated); $('feedback').textContent = 'Copied to clipboard.'; } catch { const range = document.createRange(); range.selectNodeContents($('code')); const selection = window.getSelection(); selection.removeAllRanges(); selection.addRange(range); $('feedback').textContent = 'Clipboard unavailable. Code selected; press Ctrl+C or Command+C.'; } });
$('download').addEventListener('click', () => { const url = URL.createObjectURL(new Blob([generated + '\n'], {type:'text/plain'})); const a = document.createElement('a'); a.href = url; a.download = 'loader.lua'; a.click(); setTimeout(() => URL.revokeObjectURL(url), 1000); });
