'use strict';
(() => {
  const scripts = [
    {name:'Pack An Underground Artist',slug:'pack-an-underground-artist',description:'Artist RNG · The full collection'},
    {name:"bLockerman’s Minesweeper",slug:'blockerman-mine-sweeper',description:'Minesweeper · Mine ESP & auto-play',keywords:'blockerman mine sweeper blocker'},
    {name:'Lotteryworld',slug:'lotteryworld',description:'Scratch tickets · Lottery tools'},
    {name:'Chop a Forest',slug:'chop-a-forest',description:'The Forest · Chopping & automation'},
    {name:'Ball Picker',slug:'ball-picker',description:'Golf Ball Picker · Collect & sell'},
    {name:'Catch the Artist',slug:'catch-the-artist',description:'Catch the Artist · Word reader'}
  ];
  const $ = id => document.getElementById(id);
  const copyIcon = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" aria-hidden="true"><rect x="8" y="8" width="12" height="12" rx="2"/><path d="M16 8V5a2 2 0 0 0-2-2H5a2 2 0 0 0-2 2v9a2 2 0 0 0 2 2h3"/></svg>';
  let toastTimer, copySequence = 0;
  const cards = [];
  function loadstring(script) {return `loadstring(game:HttpGet("https://raw.githubusercontent.com/neeuqpart/lualemon/main/scripts/${script.slug}.lua"))()`;}
  async function copyScript(script, card) {
    const sequence = ++copySequence;
    try {
      await navigator.clipboard.writeText(loadstring(script));
      if(sequence !== copySequence) return;
      cards.forEach(item=>{item.card.classList.remove('copied');item.label.textContent='Copy loadstring';});
      card.classList.add('copied');card.querySelector('.action-label').textContent='Copied to clipboard';
      $('toast-name').textContent=script.name;$('toast').hidden=false;
      clearTimeout(toastTimer);toastTimer=setTimeout(()=>{$('toast').hidden=true;card.classList.remove('copied');card.querySelector('.action-label').textContent='Copy loadstring';},3000);
    } catch {
      if(sequence !== copySequence) return;
      $('dialog-title').textContent=script.name;$('manual-code').value=loadstring(script);$('copy-dialog').showModal();$('manual-code').focus();$('manual-code').select();
    }
  }
  for(const [index,script] of scripts.entries()) {
    const card=document.createElement('button');card.type='button';card.className='card';card.dataset.slug=script.slug;card.setAttribute('aria-label',`Copy loadstring for ${script.name}`);
    const artwork=document.createElement('div');artwork.className='artwork';
    const image=document.createElement('img');image.src=`assets/${script.slug}.png`;image.alt=script.name;image.width=768;image.height=432;image.loading=index<3?'eager':'lazy';image.decoding='async';
    const file=document.createElement('span');file.className='file-type';file.textContent='.LUA';artwork.append(image,file);
    const info=document.createElement('div');info.className='card-info';const name=document.createElement('h2');name.textContent=script.name;const description=document.createElement('p');description.className='card-description';description.textContent=script.description;
    const action=document.createElement('div');action.className='card-action';const label=document.createElement('span');label.className='action-label';label.textContent='Copy loadstring';const icon=document.createElement('span');icon.innerHTML=copyIcon;action.append(label,icon);info.append(name,description,action);card.append(artwork,info);card.addEventListener('click',()=>copyScript(script,card));$('grid').append(card);cards.push({script,card,label});
  }
  function filter(){const query=$('search').value.trim().toLocaleLowerCase();let count=0;for(const {script,card} of cards){const matches=`${script.name} ${script.description} ${script.keywords||''}`.toLocaleLowerCase().includes(query);card.hidden=!matches;if(matches)count++;}$('count').textContent=String(count);$('empty').hidden=count>0;}
  $('search').addEventListener('input',filter);$('reset').addEventListener('click',()=>{$('search').value='';filter();$('search').focus();});
})();
