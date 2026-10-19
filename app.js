'use strict';
(() => {
const OWNER = 'neeuqpart', REPO = 'LoadstringSite', BRANCH = 'main';
const API = `https://api.github.com/repos/${OWNER}/${REPO}`;
const LIMIT = 2 * 1024 * 1024;
const $ = id => document.getElementById(id);
let token = '', current = null, publishing = false, connecting = false, syncing = false, draftTimer, generation = 0;
const bytes = text => new TextEncoder().encode(text).byteLength;
const sizeLabel = n => n < 1024 ? `${n} B` : n < 1048576 ? `${(n / 1024).toFixed(1)} KB` : `${(n / 1048576).toFixed(2)} MiB`;
function readLocal(key, fallback) { try { return JSON.parse(localStorage.getItem(key)) ?? fallback; } catch { return fallback; } }
let saved = readLocal('scriptport-github-titles-v1', {}); if (!saved || typeof saved !== 'object' || Array.isArray(saved)) saved = {};
let scripts = [];
function safePath(path) { return typeof path === 'string' && /^scripts\/[a-zA-Z0-9_.-]+\.lua(?:u)?$/.test(path); }
function rawUrl(path) { if(!safePath(path)) throw new Error('Invalid script path.'); return `https://raw.githubusercontent.com/${OWNER}/${REPO}/${BRANCH}/${path.split('/').map(encodeURIComponent).join('/')}`; }
function encodeCode(code) { const data = new TextEncoder().encode(code); let binary=''; for(let i=0;i<data.length;i+=16384)binary+=String.fromCharCode(...data.subarray(i,i+16384));return btoa(binary); }
function loader(url) { const quoted = JSON.stringify(url); return $('runtime').value === 'studio' ? `local source = game:GetService("HttpService"):GetAsync(${quoted})\nlocal run, err = loadstring(source)\nassert(run, err)\nrun()` : `loadstring(game:HttpGet(${quoted}))()`; }
function showResult(script) { current = script; $('result').hidden=false; $('loader').textContent=loader(rawUrl(script.path)); $('result-title').textContent=script.title; $('raw').href=rawUrl(script.path); $('feedback').textContent=''; }
async function github(path, options = {}, auth = token) {
  if(!auth) throw new Error('Connect your GitHub account first.');
  const url = path === '/user' ? 'https://api.github.com/user' : API + path;
  const controller = new AbortController(), timeout=setTimeout(()=>controller.abort(),60000);
  try {
    const response=await fetch(url,{...options,signal:controller.signal,headers:{'Accept':'application/vnd.github+json','Authorization':`Bearer ${auth}`,'X-GitHub-Api-Version':'2022-11-28',...(options.body?{'Content-Type':'application/json'}:{}),...options.headers}});
    const data=await response.json().catch(()=>null);
    if(!response.ok){ const error=new Error(response.status===401?'GitHub rejected the token. Check it or create a new one.':response.status===403?'GitHub denied this request. Check Contents: Read and write permission, branch rules, and API limits.':response.status===409?'The repository changed. Refresh your scripts and try again.':response.status===404?'GitHub could not find this file or grant access to the repository.':`GitHub request failed (${response.status}). ${data?.message || ''}`); error.status=response.status; throw error; }
    return data;
  } catch(error){if(error.name==='AbortError')throw new Error('GitHub took too long to respond. Check your repository before retrying to avoid duplicate uploads.');throw error;}
  finally{clearTimeout(timeout);}
}
async function syncScripts() {
  if(!token || syncing)return; syncing=true; const epoch=generation;
  try {
    let list; try {list=await github(`/contents/scripts?ref=${BRANCH}`);} catch(error){if(error.status===404)list=[];else throw error;}
    if(epoch!==generation || !token)return;
    scripts=(Array.isArray(list)?list:[]).filter(file=>file.type==='file'&&safePath(file.path)).map(file=>({path:file.path,sha:file.sha,bytes:file.size,title:typeof saved[file.path]==='string'?saved[file.path]:file.name.replace(/\.lua(?:u)?$/,'')})).reverse();renderHistory();
    $('empty-history').textContent=scripts.length?'':'No saved scripts yet. Paste a script and publish it.';
  } finally {syncing=false;}
}
function updateStats() {
  const code=$('script').value,count=code.split('\n').length,size=bytes(code);
  $('stats').textContent=`${count.toLocaleString()} ${count===1?'line':'lines'} · ${sizeLabel(size)}${size>LIMIT?' — over 2 MiB limit':''}`;
  const scrollLine=Math.floor($('script').scrollTop/22),visible=Math.ceil($('script').clientHeight/22)+2;
  $('line-numbers').textContent=Array.from({length:Math.min(visible,Math.max(0,count-scrollLine))},(_,i)=>scrollLine+i+1).join('\n'); $('line-numbers').style.paddingTop=`${20-$('script').scrollTop%22}px`;
  $('publish').disabled=!token || publishing || !code.trim() || size>LIMIT; $('disconnect').disabled=publishing;
}
function saveDraft(){clearTimeout(draftTimer);draftTimer=setTimeout(()=>{try{localStorage.setItem('scriptport-draft-v1',JSON.stringify({title:$('title').value,code:$('script').value}));$('draft-status').textContent='Draft saved on this device';}catch{$('draft-status').textContent='Draft could not be saved locally';}},450);}
function newPaste(){if($('script').value.trim()&&!confirm('Clear the current editor and start a new paste? Saved scripts stay in GitHub.'))return;$('script').value='';$('title').value='';$('result').hidden=true;current=null;$('error').textContent='';updateStats();saveDraft();$('script').focus();}
function renderHistory(){
  $('history').replaceChildren();$('empty-history').hidden=scripts.length>0;$('count').textContent=String(scripts.length);
  for(const script of scripts){
    const row=document.createElement('div');row.className='history-row';const info=document.createElement('div');info.className='history-info';const title=document.createElement('b');title.textContent=script.title;const meta=document.createElement('small');meta.textContent=`${sizeLabel(script.bytes)} · ${script.path}`;info.append(title,meta);
    const actions=document.createElement('div');actions.className='history-actions';const get=document.createElement('button');get.className='quiet';get.textContent='Get loadstring';get.addEventListener('click',()=>{showResult(script);$('result').scrollIntoView({behavior:'smooth',block:'nearest'});});
    const raw=document.createElement('a');raw.textContent='Raw ↗';raw.href=rawUrl(script.path);raw.target='_blank';raw.rel='noopener noreferrer';
    const manage=document.createElement('a');manage.textContent='Manage ↗';manage.href=`https://github.com/${OWNER}/${REPO}/blob/${BRANCH}/${script.path.split('/').map(encodeURIComponent).join('/')}`;manage.target='_blank';manage.rel='noopener noreferrer';
    actions.append(get,raw,manage);row.append(info,actions);$('history').append(row);
  }
}
$('connect-form').addEventListener('submit',async event=>{
  event.preventDefault();if(connecting)return;const candidate=$('github-token').value.trim();$('github-token').value='';$('auth-error').textContent='';if(!candidate){$('auth-error').textContent='Enter a GitHub access token.';return;}
  connecting=true;$('connect').disabled=true;$('connect').textContent='Connecting…';
  try{const user=await github('/user',{},candidate);if(user.login?.toLowerCase()!==OWNER)throw new Error(`Only ${OWNER} can publish here. This token belongs to a different GitHub account.`);const repo=await github('',{},candidate);if(repo.full_name?.toLowerCase()!==`${OWNER}/${REPO}`.toLowerCase()||repo.permissions?.push===false)throw new Error('This token does not have write access to LoadstringSite.');token=candidate;generation++;$('connect-form').hidden=true;$('disconnect').hidden=false;$('account-title').textContent=`Connected as ${OWNER}`;$('account-status').textContent='Saving to LoadstringSite / scripts. Token stays in this tab only.';await syncScripts();}
  catch(error){$('auth-error').textContent=error.message;}
  finally{connecting=false;$('connect').disabled=false;$('connect').textContent='Connect GitHub ↗';updateStats();}
});
$('disconnect').addEventListener('click',()=>{if(publishing)return;token='';generation++;scripts=[];renderHistory();$('connect-form').hidden=false;$('disconnect').hidden=true;$('account-title').textContent='Owner access';$('account-status').textContent='Connect as neeuqpart to publish to your repository.';$('empty-history').textContent='Connect GitHub to load your scripts.';$('auth-error').textContent='';current=null;$('result').hidden=true;updateStats();});
$('publish').addEventListener('click',async()=>{
  if(publishing)return;$('error').textContent='';const code=$('script').value,title=$('title').value.trim()||'Untitled script';if(!token){$('error').textContent='Connect GitHub as neeuqpart first.';return;}if(!code.trim()||bytes(code)>LIMIT){$('error').textContent='Paste a script of up to 2 MiB.';return;}
  publishing=true;updateStats();$('publish').textContent='Saving to GitHub…';
  try{const id=Array.from(crypto.getRandomValues(new Uint8Array(16)),b=>b.toString(16).padStart(2,'0')).join('');const slug=title.toLowerCase().replace(/[^a-z0-9]+/g,'-').replace(/^-+|-+$/g,'').slice(0,45)||'script';const path=`scripts/${slug}-${id}.lua`;
    const data=await github(`/contents/${path}`,{method:'PUT',body:JSON.stringify({message:`Publish script: ${title.slice(0,120)}`,content:encodeCode(code),branch:BRANCH})});
    if(!data?.content?.sha)throw new Error('GitHub did not return a saved file. Check the repository before retrying.');
    const script={path,title,sha:data.content.sha,bytes:bytes(code)};saved[path]=title;try{localStorage.setItem('scriptport-github-titles-v1',JSON.stringify(saved));}catch{} scripts.unshift(script);showResult(script);renderHistory();$('feedback').textContent='Saved to GitHub. The raw link may take a moment to become available.';$('result').scrollIntoView({behavior:'smooth',block:'nearest'});
  }catch(error){$('error').textContent=error instanceof TypeError?'Could not reach GitHub. Check your connection and repository before retrying.':error.message;}
  finally{publishing=false;$('publish').textContent='Publish & get loadstring ↗';updateStats();}
});
async function copyText(text){try{await navigator.clipboard.writeText(text);$('feedback').textContent='Copied to clipboard.';}catch{$('feedback').textContent='Clipboard unavailable. Select and copy the code or raw link manually.';}}
$('runtime').addEventListener('change',()=>{$('runtime-note').textContent=$('runtime').value==='studio'?'Server Script only. Enable HTTP requests and ServerScriptService.LoadStringEnabled in your own experience.':'For environments that provide game:HttpGet and loadstring. Ordinary Roblox LocalScripts do not provide this API.';if(current)showResult(current);});
$('copy').addEventListener('click',()=>copyText($('loader').textContent));$('copy-link').addEventListener('click',()=>current&&copyText(rawUrl(current.path)));
$('download').addEventListener('click',async()=>{if(!current)return;const button=$('download');button.disabled=true;try{const response=await fetch(rawUrl(current.path));if(!response.ok)throw new Error('GitHub raw is not available yet. Try again shortly.');const url=URL.createObjectURL(await response.blob());const link=document.createElement('a');link.href=url;link.download=current.path.split('/').pop();link.click();setTimeout(()=>URL.revokeObjectURL(url),1000);}catch(error){$('feedback').textContent=error.message;}finally{button.disabled=false;}});
$('import').addEventListener('click',()=>$('file').click());$('file').addEventListener('change',async()=>{const file=$('file').files[0];if(!file)return;$('error').textContent='';if(file.size>LIMIT){$('error').textContent='This file exceeds 2 MiB.';$('file').value='';return;}try{const code=new TextDecoder('utf-8',{fatal:true}).decode(await file.arrayBuffer());if($('script').value.trim()&&!confirm('Replace the current editor with this file?'))return;$('script').value=code;if(!$('title').value)$('title').value=file.name.slice(0,120);updateStats();saveDraft();}catch{$('error').textContent='Could not read this file. Use a UTF-8 script.';}finally{$('file').value='';}});
$('new').addEventListener('click',newPaste);$('clear').addEventListener('click',newPaste);$('script').addEventListener('input',()=>{updateStats();saveDraft();});$('script').addEventListener('scroll',updateStats);window.addEventListener('resize',updateStats);$('title').addEventListener('input',saveDraft);$('script').addEventListener('keydown',event=>{if(event.key==='Tab'&&!event.shiftKey){event.preventDefault();const input=$('script');input.setRangeText('    ',input.selectionStart,input.selectionEnd,'end');updateStats();saveDraft();}});
const draft=readLocal('scriptport-draft-v1',{});if(typeof draft.code==='string'&&bytes(draft.code)<=LIMIT){$('script').value=draft.code;$('title').value=typeof draft.title==='string'?draft.title.slice(0,120):'';}renderHistory();updateStats();
})();
