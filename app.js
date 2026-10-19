'use strict';
const API = 'https://scriptport-pastes.airyseal4.chatgpt.site';
const LIMIT = 2 * 1024 * 1024;
const $ = id => document.getElementById(id);
let current = null, publishing = false, draftTimer;
const bytes = text => new TextEncoder().encode(text).byteLength;
const sizeLabel = n => n < 1024 ? `${n} B` : n < 1048576 ? `${(n / 1024).toFixed(1)} KB` : `${(n / 1048576).toFixed(2)} MiB`;
function readLocal(key, fallback) { try { return JSON.parse(localStorage.getItem(key)) ?? fallback; } catch { return fallback; } }
let history = readLocal('scriptport-pastes-v1', []);
if (!Array.isArray(history)) history = [];
history = history.filter(p => p && /^[a-f0-9]{32}$/.test(p.id) && typeof p.title === 'string' && typeof p.deleteToken === 'string');
function writeHistory() { try { localStorage.setItem('scriptport-pastes-v1',JSON.stringify(history)); } catch { $('feedback').textContent = 'Saved online, but this browser could not save your history or deletion key. Keep a backup of the key: ' + (current?.deleteToken || ''); } }
function loader(rawUrl) { const url = JSON.stringify(rawUrl); return $('runtime').value === 'studio' ? `local source = game:GetService("HttpService"):GetAsync(${url})\nlocal run, err = loadstring(source)\nassert(run, err)\nrun()` : `loadstring(game:HttpGet(${url}))()`; }
function showResult(paste) { current = paste; const rawUrl = `${API}/raw/${paste.id}`; $('result').hidden = false; $('loader').textContent = loader(rawUrl); $('result-title').textContent = paste.title || 'Your script is live.'; $('raw').href = rawUrl; $('feedback').textContent = ''; }
function updateStats() {
  const code = $('script').value, count = code.split('\n').length, size = bytes(code);
  $('stats').textContent = `${count.toLocaleString()} ${count === 1 ? 'line' : 'lines'} · ${sizeLabel(size)}${size > LIMIT ? ' — over 2 MiB limit' : ''}`;
  const lineHeight = 22, scrollLine = Math.floor($('script').scrollTop / lineHeight), visible = Math.ceil($('script').clientHeight / lineHeight) + 2;
  $('line-numbers').textContent = Array.from({length:Math.min(visible,Math.max(0,count-scrollLine))},(_,i)=>scrollLine+i+1).join('\n');
  $('line-numbers').style.paddingTop = `${20 - $('script').scrollTop % lineHeight}px`;
  $('publish').disabled = publishing || !code.trim() || size > LIMIT;
}
function saveDraft() {
  clearTimeout(draftTimer); draftTimer = setTimeout(() => {
    try { localStorage.setItem('scriptport-draft-v1',JSON.stringify({title:$('title').value,code:$('script').value})); $('draft-status').textContent = 'Draft saved on this device'; }
    catch { $('draft-status').textContent = 'Draft could not be saved locally'; }
  },450);
}
function newPaste() { if ($('script').value.trim() && !confirm('Clear the current editor and start a new paste? Published scripts will stay saved.')) return; $('script').value = ''; $('title').value = ''; $('result').hidden = true; current = null; $('error').textContent = ''; updateStats(); saveDraft(); $('script').focus(); }
function renderHistory() {
  $('history').replaceChildren(); $('empty-history').hidden = history.length > 0; $('count').textContent = String(history.length);
  for(const paste of history) {
    const row = document.createElement('div'); row.className = 'history-row';
    const info = document.createElement('div'); info.className = 'history-info';
    const title = document.createElement('b'); title.textContent = paste.title;
    const meta = document.createElement('small'); const date = new Date(paste.createdAt); meta.textContent = `${sizeLabel(Number(paste.bytes) || 0)} · ${Number.isNaN(date.getTime()) ? '' : date.toLocaleString()}`;
    info.append(title,meta); const actions = document.createElement('div'); actions.className = 'history-actions';
    const copy = document.createElement('button'); copy.className = 'quiet'; copy.textContent = 'Get loadstring'; copy.addEventListener('click',()=>{showResult(paste); $('result').scrollIntoView({behavior:'smooth',block:'nearest'});});
    const raw = document.createElement('a'); raw.textContent = 'Raw ↗'; raw.href = `${API}/raw/${paste.id}`; raw.target = '_blank'; raw.rel = 'noopener noreferrer';
    const remove = document.createElement('button'); remove.className = 'quiet delete'; remove.textContent = 'Delete'; remove.addEventListener('click',()=>deletePaste(paste,remove));
    actions.append(copy,raw,remove); row.append(info,actions); $('history').append(row);
  }
}
async function deletePaste(paste, button) {
  if(!confirm(`Delete “${paste.title}” from hosting? Its loadstring will stop working. This cannot be undone.`)) return;
  button.disabled = true;
  try { const response = await fetch(`${API}/api/pastes/${paste.id}`,{method:'DELETE',headers:{'X-Delete-Token':paste.deleteToken}}); const data = await response.json(); if(!response.ok && response.status !== 404) throw new Error(data.error || 'Could not delete script.'); history = history.filter(p=>p.id!==paste.id); writeHistory(); renderHistory(); if(current?.id===paste.id) { $('result').hidden=true; current=null; } }
  catch(error) { $('error').textContent=error.message; } finally { button.disabled=false; }
}
async function copyText(text) {
  try { await navigator.clipboard.writeText(text); $('feedback').textContent = 'Copied to clipboard.'; }
  catch { $('feedback').textContent = 'Clipboard unavailable. Select and copy the code or link manually.'; const range = document.createRange(); range.selectNodeContents($('loader')); const selection=window.getSelection(); selection.removeAllRanges(); selection.addRange(range); }
}
$('publish').addEventListener('click',async()=>{
  if(publishing) return;
  const code = $('script').value;
  $('error').textContent = '';
  if(!code.trim()) { $('error').textContent='Paste your script first.'; return; }
  if(bytes(code)>LIMIT) { $('error').textContent='Your script exceeds 2 MiB. Try a smaller file.'; return; }
  publishing=true; updateStats(); $('publish').textContent='Publishing…';
  const controller = new AbortController(); const timeout=setTimeout(()=>controller.abort(),60000);
  try {
    const response = await fetch(`${API}/api/pastes?title=${encodeURIComponent($('title').value.trim() || 'Untitled script')}`,{method:'POST',headers:{'Content-Type':'text/plain; charset=utf-8'},body:code,signal:controller.signal});
    const data = await response.json().catch(()=>({error:'The storage service returned an unexpected response.'}));
    if(!response.ok) throw new Error(data.error || 'Could not save your script. Try again.');
    if(!/^[a-f0-9]{32}$/.test(data.id) || !data.deleteToken) throw new Error('The service did not return a valid saved script.');
    history.unshift(data); showResult(data); writeHistory(); renderHistory(); $('result').scrollIntoView({behavior:'smooth',block:'nearest'});
  } catch(error) { $('error').textContent= error.name === 'AbortError' ? 'The upload timed out. The script may have been saved; retrying will create a new paste.' : error instanceof TypeError ? 'Could not reach script storage. Check your connection and try again.' : error.message; }
  finally { clearTimeout(timeout); publishing=false; $('publish').textContent='Publish & get loadstring ↗'; updateStats(); }
});
$('runtime').addEventListener('change',()=>{ $('runtime-note').textContent = $('runtime').value === 'studio' ? 'Server Script only. Enable HTTP requests and ServerScriptService.LoadStringEnabled in your own experience.' : 'For environments that provide game:HttpGet and loadstring. Ordinary Roblox LocalScripts do not provide this API.'; if(current) showResult(current); });
$('copy').addEventListener('click',()=>copyText($('loader').textContent));
$('copy-link').addEventListener('click',()=>current && copyText(`${API}/raw/${current.id}`));
$('download').addEventListener('click',async()=>{ if(!current)return; const button=$('download'); button.disabled=true; try { const response=await fetch(`${API}/raw/${current.id}`); if(!response.ok)throw new Error('Could not download this script.'); const url=URL.createObjectURL(await response.blob()); const a=document.createElement('a'); a.href=url; a.download=`${current.id}.lua`; a.click(); setTimeout(()=>URL.revokeObjectURL(url),1000); } catch(error){$('feedback').textContent=error.message;} finally{button.disabled=false;} });
$('import').addEventListener('click',()=>$('file').click());
$('file').addEventListener('change',async()=>{ const file=$('file').files[0]; if(!file)return; $('error').textContent=''; if(file.size>LIMIT){$('error').textContent='This file exceeds 2 MiB.';$('file').value='';return;} try { const code=new TextDecoder('utf-8',{fatal:true}).decode(await file.arrayBuffer()); if($('script').value.trim()&&!confirm('Replace the current editor with this file?'))return; $('script').value=code; if(!$('title').value)$('title').value=file.name.slice(0,120); updateStats(); saveDraft(); }catch{$('error').textContent='Could not read this file. Use a UTF-8 text script.';}finally{$('file').value='';} });
$('new').addEventListener('click',newPaste); $('clear').addEventListener('click',newPaste);
$('script').addEventListener('input',()=>{updateStats();saveDraft();}); $('script').addEventListener('scroll',updateStats); window.addEventListener('resize',updateStats); $('title').addEventListener('input',saveDraft);
$('script').addEventListener('keydown',event=>{if(event.key==='Tab'&&!event.shiftKey){event.preventDefault();const input=$('script'),start=input.selectionStart,end=input.selectionEnd;input.setRangeText('    ',start,end,'end');updateStats();saveDraft();}});
const draft=readLocal('scriptport-draft-v1',{}); if(typeof draft.code==='string'&&bytes(draft.code)<=LIMIT){$('script').value=draft.code;$('title').value=typeof draft.title==='string'?draft.title.slice(0,120):'';}
renderHistory(); updateStats();
