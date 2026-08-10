const app = document.querySelector('#app');
const toast = document.querySelector('#toast');
const prefersReducedMotion = matchMedia('(prefers-reduced-motion: reduce)');
let firstRender = true;
let breathingTimer;
let toastTimer;

const defaults = {
  view: location.hash.slice(1) || 'home', mood: null, energy: null,
  activity: 'call', after: null, ssiStage: 0, ssiComplete: false,
  ssiChoices: {}, sharePlan: true,
  drafted: false, approved: false, drafting: false, planned: null,
  voice: true, voiceHeard: false, neglect: false, mirror: false, pictures: true
};
const state = Object.assign({}, defaults, JSON.parse(localStorage.getItem('solace-demo-v3') || '{}'));
state.view = location.hash.slice(1) || state.view || 'home';
const moods = [
  { word:'Good', color:'#7a8b6f', fill:'10%', face:'fa-face-smile', message:'Glad to hear it, let’s keep the good going with one small thing.' },
  { word:'Okay', color:'#9a9b63', fill:'32%', face:'fa-face-smile-beam', message:'Okay is okay, and a small step can help it hold.' },
  { word:'Low', color:'#cba24a', fill:'55%', face:'fa-face-meh', message:'Thanks for being honest, let’s try one gentle thing together.' },
  { word:'Hard', color:'#c0764a', fill:'78%', face:'fa-face-frown-open', message:'Hard days are real, so we’ll keep it to just one small thing.' },
  { word:'Very low', color:'#a8543a', fill:'100%', face:'fa-face-sad-tear', message:'' }
];
const activities = {
  call:{ icon:'fa-phone', title:'Call someone', sub:'A short hello counts.', instruction:'Pick one person, tap call, and keep it as short as you like.', tint:'#dcebea', color:'#477f79' },
  outside:{ icon:'fa-sun', title:'Sit outside', sub:'Two quiet minutes.', instruction:'Find a safe place near a window or outside. Notice one thing you can see and one thing you can hear.', tint:'#f2ead1', color:'#a87935' },
  breathe:{ icon:'fa-wind', title:'Slow breathing', sub:'Four seconds in and out.', instruction:'Take two slow breaths. Breathe in for four seconds, then out for four seconds.', tint:'#e2ecdc', color:'#537d53' },
  walk:{ icon:'fa-person-walking', title:'Walk with walker', sub:'Someone nearby for safety.', instruction:'Walk with your walker for two minutes with someone nearby for safety.', tint:'#e1efdc', color:'#548356', care:true },
  pumps:{ icon:'fa-dumbbell', title:'Ankle pumps', sub:'Ten gentle repetitions.', instruction:'Perform ten seated ankle pumps. Stop if you feel pain, severe dizziness, or new weakness.', tint:'#e1efdc', color:'#548356', care:true, rehab:true },
  plan:{ icon:'fa-map', title:'My small plan', sub:'From your self-guided session.', instruction:'Do one safe movement or rehab exercise while your partner is home.', tint:'#e1efdc', color:'#416e49', plan:true }
};

function save(){ localStorage.setItem('solace-demo-v3', JSON.stringify(state)); }
function notify(message){
  clearTimeout(toastTimer);
  toast.textContent=message;
  toast.classList.remove('show');
  requestAnimationFrame(()=>toast.classList.add('show'));
  toastTimer=setTimeout(()=>toast.classList.remove('show'),2400);
}
function go(view,motion='forward'){
  state.view=view;
  if(location.hash!==`#${view}`) history.pushState({view},'',`#${view}`);
  save();
  render(motion);
  const content=document.querySelector('.phone-content');
  if(content) content.scrollTop=0;
}
function timeNow(){ return new Date().toLocaleTimeString([], {hour:'numeric',minute:'2-digit'}); }
function icon(name, extra=''){ return `<i class="fa-solid ${name} ${extra}" aria-hidden="true"></i>`; }
function downloadPDF(){
  const lines=['Solace Clinician Summary','Sherron - browser demonstration','Mood: steady','Activities completed: 4 of 5','Small actions helped 3 of 4 times','Care plan: walker, sit-to-stand, ankle pumps, weight shifting'];
  const esc=s=>s.replace(/([\\()])/g,'\\$1');
  const stream=['BT','/F1 18 Tf','50 760 Td',`(${esc(lines[0])}) Tj`,'/F1 11 Tf',...lines.slice(1).flatMap(x=>['0 -28 Td',`(${esc(x)}) Tj`]),'ET'].join('\n');
  const objects=['<< /Type /Catalog /Pages 2 0 R >>','<< /Type /Pages /Kids [3 0 R] /Count 1 >>','<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>','<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',`<< /Length ${stream.length} >>\nstream\n${stream}\nendstream`];
  let pdf='%PDF-1.4\n', offsets=[0]; objects.forEach((o,i)=>{offsets.push(pdf.length);pdf+=`${i+1} 0 obj\n${o}\nendobj\n`;});
  const xref=pdf.length;pdf+=`xref\n0 ${objects.length+1}\n0000000000 65535 f \n`;offsets.slice(1).forEach(o=>pdf+=`${String(o).padStart(10,'0')} 00000 n \n`);pdf+=`trailer\n<< /Size ${objects.length+1} /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF`;
  const a=document.createElement('a');a.href=URL.createObjectURL(new Blob([pdf],{type:'application/pdf'}));a.download='solace-clinician-summary.pdf';a.click();
}

function nav(active='home'){
  return `<nav class="ios-nav">
    <button class="${active==='home'?'selected':''}" data-go="home">${icon('fa-house')}<small>Home</small></button>
    <button class="${active==='activities'?'selected':''}" data-go="activities">${icon('fa-seedling')}<small>Activities</small></button>
    <button class="${active==='safety'?'selected':''}" data-go="safety">${icon('fa-heart')}<small>Safety</small></button>
  </nav>`;
}
function context(care=false){
  return `<div class="demo-context"><span class="eyebrow">${care?'CAREBRIDGE APP':'SOLACE APP'}</span>
    <h1>${care?'Care partners see what matters, without taking over.':'A web demo of the full Solace iOS experience.'}</h1>
    <p>${care?'Review progress, receive a shared self-guided plan, and turn clinical notes into patient-ready activities.':'This browser version follows the native SwiftUI app’s core workflow and accessibility patterns.'}</p>
    <div class="context-actions"><button class="primary" data-switch="${care?'home':'care'}">Switch to ${care?'Solace':'CareBridge'}</button><button class="secondary" data-reset>Reset demo</button><a class="secondary source-button" href="https://github.com/Sherron-T/Solace#readme" target="_blank" rel="noopener noreferrer">${icon('fa-code-branch')} View Project README ${icon('fa-arrow-up-right-from-square')}</a></div>
    <div class="context-note"><strong>Try the full flow</strong><span>${care?'Draft the sample note, approve the activities, then switch to Solace and open Activities.':'Check in, choose an energy level, complete an activity, and answer the after-check. The One Small Plan and accessibility settings are also interactive.'}</span></div></div>`;
}
function frame(content, active='home', care=false){
  return `<div class="demo-layout"><div class="phone ${care?'care-phone':''}"><div class="phone-screen ${state.neglect?'anchor-on':''}">
    <div class="dynamic-island"></div><div class="statusbar"><span>${timeNow()}</span><span class="status-icons">${icon('fa-signal')}${icon('fa-wifi')}${icon('fa-battery-three-quarters')}</span></div>
    <div class="phone-content ${care?'care-content':''}">${content}</div>${care?'':nav(active)}</div></div>${context(care)}</div>`;
}
function header(title='', subtitle='', back='home'){
  return `<div class="native-header"><div class="native-title">${subtitle?`<small>${subtitle}</small>`:''}${title?`<h2>${title}</h2>`:''}</div><div class="header-actions"><button class="round-button" data-read aria-label="Read screen aloud">${icon('fa-volume-high')}</button>${back?`<button class="round-button back-button" data-go="${back}" aria-label="Go back">${icon('fa-chevron-left')}</button>`:''}</div></div>`;
}
function home(){
  const now=new Date(), hour=now.getHours(), greeting=hour<12?'Good morning':hour<17?'Good afternoon':'Good evening';
  const date=now.toLocaleDateString(undefined,{weekday:'long',month:'long',day:'numeric'});
  return frame(`<div class="home-head"><div><h2>${greeting}</h2><p>${date}</p></div><button class="streak" data-go="trend"><strong>5</strong><small>DAYS</small></button></div>
    <div class="quick-icons"><button class="round-button" data-read aria-label="Read home screen aloud">${icon('fa-volume-high')}</button><button class="round-button" data-go="settings" aria-label="Open accessibility settings">${icon('fa-sliders')}</button></div>
    <section class="checkin-hero"><h1>How are you<br>feeling today?</h1><button class="checkin-orb" data-go="mood">${icon('fa-face-smile')}<strong>Check in</strong></button><p>Takes about a minute</p></section>
    <div class="home-cards">
      <button class="ios-card warm" data-go="safety"><span>${icon('fa-heart')}</span><div><small>WE NOTICED</small><strong>This week looks heavy</strong><p>Support is here if you want it, no pressure.</p></div>${icon('fa-chevron-right','card-chevron')}</button>
      ${state.planned?`<button class="ios-card" data-activity="${state.planned}"><span>${icon('fa-clock')}</span><div><small>SAVED FOR TODAY</small><strong>${activities[state.planned].title}</strong></div>${icon('fa-chevron-right','card-chevron')}</button>`:''}
      <button class="ios-card" data-action="startSSI"><span>${icon('fa-map')}</span><div><small>${state.ssiComplete?'YOUR SMALL PLAN':'ONE SMALL PLAN'}</small><strong>${state.ssiComplete?'Review your small plan':'Build your plan for today'}</strong><p>About 5 minutes, stop any time</p></div>${icon('fa-chevron-right','card-chevron')}</button>
      <button class="ios-card" data-go="activities"><span>${icon('fa-sun')}</span><div><small>ONE SMALL THING</small><strong>Pick something to do today</strong></div>${icon('fa-chevron-right','card-chevron')}</button>
    </div>`, 'home');
}
function moodView(){
  return frame(`${header('How low or steady do you feel?','', 'home')}
    <div class="mood-list native-moods">${moods.map((m,i)=>`<button class="mood-row ${state.mood===i?'chosen':''}" style="--mood:${m.color}" data-mood="${i}"><span class="disc" style="--fill:${m.fill}"></span>${state.pictures?`<span class="mini-face">${icon(m.face)}</span>`:''}<strong>${m.word}</strong>${state.mood===i?icon('fa-check','selected-check'):''}</button>`).join('')}</div>
    <button class="voice-pill ${state.voiceHeard?'heard':''}" data-action="voiceMood">${icon(state.voiceHeard?'fa-wave-square':'fa-microphone')} <span>${state.voiceHeard?'Heard: “It’s been really rough.” → Hard':'Say it instead'}</span></button>
    ${state.mood===null?'<p class="tap-hint">Tap the one that fits</p>':'<button class="wide-primary" data-action="saveMood">Continue</button>'}`, 'home');
}
function energyView(){
  return frame(`${header('How is your energy?','', 'mood')}<div class="energy-spacer"></div><div class="energy-list">
    ${[['fa-battery-quarter','Tired'],['fa-battery-half','Steady'],['fa-battery-full','Energetic']].map((x,i)=>`<button class="energy-row" data-energy="${i}"><span>${icon(x[0])}</span><strong>${x[1]}</strong>${icon('fa-chevron-right','row-chevron')}</button>`).join('')}</div>
    <button class="skip-button" data-action="skipEnergy">Skip</button><button class="voice-pill" data-action="voiceEnergy">${icon('fa-microphone')} <span>Say your energy</span></button>`, 'home');
}
function confirmView(){
  const m=moods[state.mood ?? 2];
  return frame(`${header('','',null)}<div class="confirm-screen"><div class="confirm-face" style="--mood:${m.color}">${icon(m.face)}</div><small>YOU SAID YOU FEEL</small><h2>${m.word}</h2><p>${m.message}</p><button class="compact-primary" data-go="activities">Next</button></div>`, 'home');
}
function activityList(){
  const ids=['call','outside','breathe',...(state.approved?['walk','pumps']:[]),...(state.ssiComplete?['plan']:[])];
  return frame(`${header('One small thing','Pick just one, that’s plenty.','home')}<div class="activity-list">${ids.map(id=>{const a=activities[id];return `<button class="activity-card" data-activity="${id}"><span style="background:${a.tint};color:${a.color}">${icon(a.icon)}</span><div><strong>${a.title}</strong><small>${a.sub}</small></div><div class="activity-tags">${a.rehab?'<em>REHAB WIN</em>':''}${a.care?'<em>CARE PLAN</em>':''}${a.plan?'<em>MY PLAN</em>':''}</div></button>`}).join('')}</div><button class="voice-pill" data-action="voiceActivity">${icon('fa-microphone')} <span>Say the one you want</span></button>`, 'activities');
}
function doingView(){
  const a=activities[state.activity]||activities.call;
  return frame(`${header('','', 'activities')}<div class="doing-screen"><div class="doing-icon" style="background:${a.tint};color:${a.color}">${icon(a.icon)}</div><h2>${a.title}</h2><p>${a.instruction}</p>${a.care?`<span class="provenance">${icon('fa-stethoscope')} From your care team</span>`:''}${a.plan?`<span class="provenance">${icon('fa-map')} From your own plan</span>`:''}</div>
    <button class="wide-primary bottom-cta" data-action="didActivity">${icon('fa-check')} &nbsp; I did it</button>${state.planned===state.activity?'':'<button class="save-later" data-action="saveLater">Save it for later today</button>'}<p class="no-rush">No rush, it’ll be here later</p>`, 'activities');
}
function afterView(){
  return frame(`${header('','',null)}<div class="after-title"><span>${icon('fa-circle-check')}</span><h2>You did it.</h2><p>How do you feel right now?</p></div><div class="after-list">
    <button data-after="better"><span>${icon('fa-arrow-up')}</span><strong>A bit better</strong></button><button data-after="same"><span>${icon('fa-equals')}</span><strong>About the same</strong></button><button data-after="hard"><span>${icon('fa-cloud')}</span><strong>Still hard</strong></button></div><button class="skip-button" data-after="skip">Skip</button>`, 'activities');
}
function doneView(){
  const message=state.after==='better'?'That small action helped a bit. Your brain noticed.':state.after==='hard'?'Showing up on a hard day still matters.':'Doing it still counts, even when the feeling stays the same.';
  return frame(`${header('','',null)}<div class="done-screen"><div class="streak-ring"><strong>5</strong><small>DAY STREAK</small></div><h2>That counts.</h2><p>${message}</p><span class="tally"><b>4 things</b> done this week</span><button class="outline-button" data-go="trend">See your week</button><button class="wide-primary" data-go="home">Done for now</button></div>`, 'home');
}
function safetyView(){
  return frame(`${header('','', 'home')}<div class="safety-native"><div class="safety-heart">${icon('fa-heart')}</div><h2>It sounds really hard right now.</h2><p>You don’t have to get through this on your own. Reach a real person, right now.</p><button class="wide-danger" data-action="call988">${icon('fa-phone')} &nbsp; Call the 988 crisis line</button><button class="care-message" data-action="messageCare">${icon('fa-user')} &nbsp; Message my care team</button><button class="safe-back" data-go="home">I’m okay, go back</button></div>`, 'safety');
}
function settingsView(){
  const rows=[['voice','Voice-only mode','Solace listens and moves through screens with spoken answers.'],['pictures','Picture support','Faces and symbols reinforce simple language.'],['neglect','Visual-neglect line','A bright edge anchor helps guide attention.'],['mirror','One-hand mirroring','Moves controls toward the survivor’s working side.']];
  return frame(`${header('Accessibility','Designed around you','home')}<div class="setting-list">${rows.map(([key,title,sub])=>`<div class="setting-row"><div><strong>${title}</strong><small>${sub}</small></div><button class="toggle ${state[key]?'on':''}" data-setting="${key}"><i></i></button></div>`).join('')}</div><div class="voice-card"><strong>Natural Azure voice</strong><p>When configured, Azure neural voice reads each screen in a soothing, human-sounding voice. Apple’s on-device voice remains available as a fallback.</p></div><div class="voice-card"><strong>AI answer matching</strong><p>Spoken answers are matched to the best visible choice. Safety decisions always use explicit rules, never an AI guess.</p></div>`, 'home');
}
function trendView(){
  const days=[['M',3],['T',2],['W',2],['T',1],['F',2],['S',1],['Today',1]];
  return frame(`${header('Your last 7 days','Small steps add up','home')}<div class="trend-card"><div class="trend-bars">${days.map(([d,m])=>`<div><span style="height:${32+(4-m)*18}px;background:${moods[m].color}"></span><small>${d}</small></div>`).join('')}</div></div><div class="trend-summary"><strong>4 things done this week</strong><p>Small things helped you feel better 3 of 4 times.</p></div><div class="voice-card"><strong>This week looks heavy.</strong><p>Support is available whenever you want it—without pressure.</p><button class="text-button" data-go="safety">See support options</button></div>`, 'home');
}
function ssiView(){
  const screens=[
    `<div class="ssi-center"><div class="ssi-icon">${icon('fa-map')}</div><h2>Build one small plan for today.</h2><p>This takes about 5 minutes, you can stop any time, and nothing is lost.</p><div class="privacy-note">${icon('fa-lock')} <span>If sharing is on, your care team can see the plan you make. You choose at the end.</span></div></div>`,
    `<div class="ssi-center"><h2>Take two slow breaths before we make the plan.</h2><div class="breathing"><span>Breathe in</span></div><p>Four seconds in, four seconds out.</p></div>`,
    optionScreen('What feels hardest right now?','Pick the one that fits best.',['Feeling disconnected from people','Feeling tired or low-energy','Feeling like I lost independence','Feeling stuck'],2,2),
    optionScreen('What would tell you things are getting a little better?','Pick one hope.',['Feel more like myself','Take one rehab or movement step','Reach out to someone','Rebuild part of my daily routine'],3,1),
    optionScreen('What is one small thing you could do in the next few days?','Pick what feels doable.',['Talk with a friend','Do a safe movement or rehab exercise','Sit outside or near a window','Practice slow breathing'],4,1),
    `<div class="ifthen"><div class="ssi-icon">${icon('fa-code-branch')}</div><small>YOUR IF–THEN PLAN</small><h2>If feeling tired shows up…</h2><p>then I’ll begin with just two minutes while my partner is home.</p></div>`,
    `<div class="complete-card"><span>${icon('fa-check')}</span><h3>You did something supportive for yourself today.</h3><p>Your plan is saved in Solace. You can share it with your care team and return to it any time.</p><div class="share-line"><span>Share with care team</span><button class="toggle ${state.sharePlan?'on':''}" data-action="toggleShare" aria-label="Toggle plan sharing"><i></i></button></div></div>`
  ];
  const labels=['Start','Skip for now','Continue','Continue','Build my plan','Save plan','Finish'];
  return frame(`${header('','', 'home')}<div class="ssi-progress"><i style="width:${Math.max(2,(state.ssiStage+1)/screens.length*100)}%"></i></div>${screens[state.ssiStage]||screens[0]}<button class="wide-primary ssi-cta" data-action="nextSSI">${labels[state.ssiStage]||'Continue'}</button><button class="support-link" data-go="safety">Need support right now?</button>`, 'activities');
}
function optionScreen(title,sub,options,key,fallback){ const selected=state.ssiChoices?.[key] ?? fallback;return `<h2 class="screen-title">${title}</h2><p class="ios-lead">${sub}</p><div class="option-list">${options.map((x,i)=>`<button class="option-row ${i===selected?'chosen':''}" data-ssi-key="${key}" data-ssi-option="${i}">${x}${i===selected?icon('fa-check'):''}</button>`).join('')}</div>`; }
function careView(){
  const drafts=[['Walk with walker','Walk with your walker 2–3 times daily with someone nearby for safety.'],['Sit-to-stand','Practice sit-to-stand 10 times, 2–3 times per day.'],['Ankle pumps','Perform ankle pumps, seated marches, and knee extensions: 10 repetitions each.'],['Weight shifting','Stand at the kitchen counter and practice weight shifting side to side.']];
  const active=state.approved?`<section class="care-section active-plan"><div class="care-section-title"><strong>Active in patient app</strong><button data-action="clearPlan">Clear</button></div>${drafts.map((x,i)=>careActivity(x,i,false)).join('')}</section>`:'';
  return frame(`<div class="care-header"><h2>${icon('fa-leaf')} CareBridge</h2><p>Sherron never has to type, taps become these updates.</p></div><div class="firebase-card"><span>${icon('fa-cloud')}</span><div><strong>Connected to Solace</strong><small>Firebase sync · local backup ready</small></div></div>
    <section class="care-card person-card"><div class="person-row"><span>S</span><div><strong>Sherron</strong><small>Last update just now</small></div><div class="care-streak"><b>5</b><small>DAY STREAK</small></div></div><div class="goal-row"><span>This week</span><span>4 of 5 activities</span></div><div class="goal-bar"><i></i></div><button class="care-primary" data-action="familyUpdate">${icon('fa-paper-plane')} Send update to family</button><button class="care-outline" data-action="export">${icon('fa-file-pdf')} Export clinician summary (PDF)</button></section>
    <section class="care-card plain-words"><small>${icon('fa-wand-magic-sparkles')} THE WEEK IN PLAIN WORDS</small><p>Sherron checked in most days and completed four activities. Small actions improved mood three of four times.</p><em>Composed from check-ins. No clinical diagnosis is generated.</em></section>
    ${state.ssiComplete?`<section class="care-section"><small>PATIENT’S OWN PLAN</small><div class="care-card patient-plan"><strong>${icon('fa-map')} Sherron built a plan, self-guided</strong><p>Working on: feeling like independence was lost</p><p>Hoping to: take one rehab or movement step</p><p>If/then: if tiredness shows up → begin with two minutes</p></div></section>`:''}
    <section class="care-section"><small>CARE PLAN BUILDER</small><div class="care-card care-builder"><div class="builder-title"><span>${icon('fa-file-medical')}</span><div><strong>Turn notes into small steps</strong><small>Paste care-team or PT instructions and review the draft before it appears in Solace.</small></div></div><textarea>PT Daily Note — Patient tolerated gait training with walker. Practice sit-to-stand, ankle pumps, seated marches, knee extensions, and supported weight shifting.</textarea><button class="care-primary" data-action="draft">${icon(state.drafting?'fa-spinner':'fa-wand-magic-sparkles',state.drafting?'fa-spin':'')} ${state.drafting?'Drafting…':'Draft patient steps'}</button>${state.drafted?`<div class="ai-note">${icon('fa-wand-magic-sparkles')} Apple Intelligence: Drafted on device, review before approving.</div><div class="draft-label">Draft for review</div><div class="draft-cards">${drafts.map((x,i)=>careActivity(x,i,true)).join('')}</div><button class="care-primary" data-action="approve">${icon('fa-circle-check')} Approve for Solace</button>`:''}</div></section>${active}
    <section class="care-section"><small>AUTOMATIC UPDATES</small><div class="feed-card"><span>${icon('fa-circle-check')}</span><p>Sherron completed “Sit outside,” and says it helped a bit.<small>Just now</small></p></div><div class="feed-card"><span>${icon('fa-circle-check')}</span><p>Sherron checked in, feeling okay; energy is steady.<small>Today</small></p></div></section>`, 'home', true);
}
function careActivity(x,i,draft){ return `<div class="draft-card"><span>${icon(i===2?'fa-dumbbell':'fa-person-walking')}</span><div><strong>${x[0]} ${i?'<em>PT</em>':''}</strong><p>${x[1]}</p>${draft?'<small>Source: PT Daily Note · Diagnosis: CVA</small>':''}</div></div>`; }

function render(motion='refresh'){
  clearInterval(breathingTimer);
  const views={home,mood:moodView,energy:energyView,confirm:confirmView,activities:activityList,doing:doingView,after:afterView,done:doneView,safety:safetyView,settings:settingsView,trend:trendView,ssi:ssiView,care:careView};
  const activeMotion=firstRender?'initial':motion;
  app.dataset.motion=activeMotion;
  app.innerHTML=(views[state.view]||home)(); bind();
  prepareMotion(activeMotion);
  firstRender=false;
}
function prepareMotion(motion){
  const content=app.querySelector('.phone-content');
  const screen=app.querySelector('.phone-screen');
  if(content&&motion!=='refresh') content.classList.add(`motion-${motion}`);
  if(screen&&motion==='success') screen.classList.add('motion-success');
  if(motion==='initial'||motion==='switch') app.querySelector('.demo-context')?.classList.add('context-enter');

  if(motion!=='refresh'){
    const groupSelector=state.view==='care'
      ? '.care-content'
      : '.home-cards, .native-moods, .energy-list, .activity-list, .after-list, .setting-list, .option-list';
    app.querySelectorAll(groupSelector).forEach(group=>{
      Array.from(group.children).slice(0,10).forEach((item,index)=>{
        item.classList.add('motion-item');
        item.style.setProperty('--stagger',`${index*42}ms`);
      });
    });
  }

  const breathingLabel=app.querySelector('.breathing span');
  if(!breathingLabel) return;
  if(prefersReducedMotion.matches){ breathingLabel.textContent='Breathe slowly'; return; }
  let breathingIn=true;
  breathingTimer=setInterval(()=>{
    breathingIn=!breathingIn;
    breathingLabel.textContent=breathingIn?'Breathe in':'Breathe out';
  },4000);
}
function bind(){
  document.querySelectorAll('[data-go]').forEach(b=>b.onclick=()=>{
    const movingBack=b.classList.contains('back-button')||b.classList.contains('safe-back')||(b.dataset.go==='home'&&state.view!=='home');
    go(b.dataset.go,movingBack?'back':'forward');
  });
  document.querySelectorAll('[data-switch]').forEach(b=>b.onclick=()=>go(b.dataset.switch,'switch'));
  document.querySelectorAll('[data-mood]').forEach(b=>b.onclick=()=>{state.mood=+b.dataset.mood;state.voiceHeard=false;save();render();});
  document.querySelectorAll('[data-energy]').forEach(b=>b.onclick=()=>{state.energy=+b.dataset.energy;save();go('confirm');});
  document.querySelectorAll('[data-activity]').forEach(b=>b.onclick=()=>{state.activity=b.dataset.activity;save();go('doing');});
  document.querySelectorAll('[data-after]').forEach(b=>b.onclick=()=>{state.after=b.dataset.after;save();go('done','success');});
  document.querySelectorAll('[data-setting]').forEach(b=>b.onclick=()=>{const key=b.dataset.setting;state[key]=!state[key];save();render();});
  document.querySelectorAll('[data-ssi-option]').forEach(b=>b.onclick=()=>{state.ssiChoices[b.dataset.ssiKey]=+b.dataset.ssiOption;save();render();});
  document.querySelectorAll('[data-read]').forEach(b=>b.onclick=()=>notify('Reading this screen aloud with the configured natural voice.'));
  document.querySelectorAll('[data-reset]').forEach(b=>b.onclick=()=>{localStorage.removeItem('solace-demo-v3');location.hash='home';location.reload();});
  document.querySelectorAll('[data-action]').forEach(b=>b.onclick=()=>action(b.dataset.action));
}
function action(type){
  if(type==='saveMood'){ if(state.mood===4)return go('safety'); return go('energy'); }
  if(type==='skipEnergy') return go('confirm');
  if(type==='voiceMood'){ state.voiceHeard=true;state.mood=3;save();render();return notify('AI answer matching selected “Hard.”'); }
  if(type==='voiceEnergy'){ state.energy=1;save();notify('Heard “pretty steady.”');return setTimeout(()=>go('confirm'),500); }
  if(type==='voiceActivity') return notify('Say “call someone,” “sit outside,” or another visible choice.');
  if(type==='didActivity') return go('after');
  if(type==='saveLater'){ state.planned=state.activity;save();notify('Saved for later today.');return go('home'); }
  if(type==='startSSI'){ state.ssiStage=0;save();return go('ssi'); }
  if(type==='toggleShare'){ state.sharePlan=!state.sharePlan;save();return render(); }
  if(type==='nextSSI'){ if(state.ssiStage<6){state.ssiStage++;save();return render('step');}state.ssiComplete=true;state.ssiStage=0;save();notify('Your plan is saved and shared with CareBridge.');return go('home','success'); }
  if(type==='draft'){ state.drafting=true;save();render();setTimeout(()=>{state.drafting=false;state.drafted=true;save();render('reveal');notify('Four patient steps are ready for review.');},700);return; }
  if(type==='approve'){ state.approved=true;state.drafted=false;save();notify('Approved activities are now active in Solace.');return render('success'); }
  if(type==='clearPlan'){ state.approved=false;save();return render(); }
  if(type==='export'){ downloadPDF();return notify('Clinician summary PDF downloaded.'); }
  if(type==='familyUpdate') return notify('A warm, shareable family update is ready.');
  if(type==='call988') return notify('On iPhone, this opens a call to 988.');
  if(type==='messageCare') return notify('On iPhone, this opens the care-team message option.');
}
addEventListener('popstate',()=>{state.view=location.hash.slice(1)||'home';save();render('back');});
document.querySelector('.brand')?.addEventListener('click',event=>{event.preventDefault();go('home','back');});
render('initial');
