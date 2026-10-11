/* Light theme (option E): content goes light, the sidebar island stays dark.
   One shared rule set, applied to whatever a page draws, so every frozen page gets the same light theme. */
(function(){
  if(location.hash!=='#light')return;document.documentElement.classList.add('lt');
  const INK='16,19,22';
  const ACC={'#5FE0D3':'#128077','#5fe0d3':'#128077','#29C0B4':'#128077','#AFF3EC':'#0E645D','#8FF5EC':'#128077','#C49BF5':'#7A4FC4','#E4D2FF':'#5B3A96','#FFB05C':'#B5650F','#FFD2A8':'#8F4800','#F0BE63':'#9A6400','#6BB4F5':'#1E6FC4','#FF6B6E':'#B0161A','#FF8A8C':'#B0161A','#5CD97E':'#176A2F','#A7ACB8':'#5E6470'};
  const DARKBG=/#(0B0C10|0E1016|08070F|08090C|12151C|101218|161923|1B1F2A)\b/gi;
  function fix(st){
    if(!st)return st;
    // white pill buttons become ink pills
    st=st.replace(/background:\s*#fff(fff)?\b([^;]*);\s*color:\s*#0B0C10/gi,'background:#101316$2;color:#FEFEFE');
    st=st.replace(/rgba\(\s*255\s*,\s*255\s*,\s*255\s*,\s*([\d.]+)\s*\)/g,(m,a)=>`rgba(${INK},${Math.min(1,+a*0.9).toFixed(3)})`);
    st=st.replace(/rgba\(\s*(18|16|14|10|11|24|36|20|9)\s*,\s*(16|13|12|10|22|34|18|9)\s*,\s*(30|26|20|32|38|48|36|15)\s*,\s*([\d.]+)\s*\)/g,()=>'rgba(254,254,252,.93)');
    st=st.replace(/rgba\(\s*(8|11|5)\s*,\s*(7|12|5)\s*,\s*(15|16|10)\s*,\s*([\d.]+)\s*\)/g,(m,a,b,c,d)=>`rgba(242,241,236,${d})`);
    st=st.replace(/rgba\(\s*9\s*,\s*9\s*,\s*15\s*,\s*([\d.]+)\s*\)/g,'rgba(250,249,246,.94)');
    st=st.replace(/rgba\(\s*0\s*,\s*0\s*,\s*0\s*,\s*([\d.]+)\s*\)/g,(m,a)=>+a>0.3?m:`rgba(16,19,22,${(+a*0.18).toFixed(3)})`);
    st=st.replace(DARKBG,'#FFFFFF');
    st=st.replace(/color:\s*#(fff|ffffff|F4F4F6|F5F5F7)\b/gi,'color:#101316');
    st=st.replace(/#[0-9A-Fa-f]{6}\b/g,h=>ACC[h]||ACC[h.toUpperCase()]||h);
    st=st.replace(/#1E212A\b/gi,'#E2E0D8').replace(/#8B90A0\b/gi,'#5C6866').replace(/#7A7F8E\b/gi,'#6D6481').replace(/#656E80\b/gi,'#8A8F9C');
    return st;
  }
  function inIsland(el){return !!el.closest('aside')}
  function apply(root){
    root.querySelectorAll('[style]').forEach(el=>{if(inIsland(el))return;const s=el.getAttribute('style');if(el.dataset.lt===s)return;const n=fix(s);el.setAttribute('style',n);el.dataset.lt=n});
    root.querySelectorAll('canvas.wv').forEach(c=>{if(!inIsland(c))c.dataset.c='#128077'});
  }
  const css=document.createElement('style');
  css.textContent=`main,.pane,.win:not(:has(aside)),.pn{color:#101316!important}
  .win{background:#F2F1EC!important}.desk .win{background:transparent!important}
  .pane{background:#F2F1EC!important}
  main .h,main .t,.pane .h{color:#101316!important;-webkit-text-fill-color:#101316}
  .gt{-webkit-text-fill-color:initial}
  aside{background:#12101E!important}`;
  document.head.appendChild(css);
  let busy=false;
  const run=()=>{if(busy)return;busy=true;apply(document.body);busy=false};
  new MutationObserver(()=>requestAnimationFrame(run)).observe(document.body,{childList:true,subtree:true});
  window.drawHorizon=function(){document.querySelectorAll('canvas.hz').forEach(c=>{const x=c.getContext('2d'),W=c.width,H=c.height,cols=['#5FE0D3','#C49BF5','#FFB05C'];x.fillStyle='#FBFAF7';x.fillRect(0,0,W,H);for(let L=0;L<3;L++){const g=x.createLinearGradient(0,H*.4,0,H);g.addColorStop(0,cols[L]+'88');g.addColorStop(1,cols[L]+'00');x.fillStyle=g;x.globalAlpha=.6-L*.12;x.beginPath();x.moveTo(0,H);for(let i=0;i<=90;i++){const X=i/90*W,e=Math.sin(Math.PI*i/90),h=H*(.15+.45*e*(.5+.5*Math.abs(Math.sin(i*.7+L*2))));x.lineTo(X,H-h)}x.lineTo(W,H);x.fill()}x.globalAlpha=1})};
  addEventListener('load',()=>{run();window.drawHorizon()});run();
})();
