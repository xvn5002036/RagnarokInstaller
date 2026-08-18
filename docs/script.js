const navToggle=document.querySelector('.nav-toggle');
const nav=document.querySelector('#site-nav');
navToggle?.addEventListener('click',()=>{const open=nav.classList.toggle('open');navToggle.setAttribute('aria-expanded',String(open));});
nav?.querySelectorAll('a').forEach(link=>link.addEventListener('click',()=>{nav.classList.remove('open');navToggle?.setAttribute('aria-expanded','false');}));

const tabs=[...document.querySelectorAll('[role="tab"]')];
tabs.forEach(tab=>tab.addEventListener('click',()=>{tabs.forEach(item=>{const selected=item===tab;item.setAttribute('aria-selected',String(selected));document.getElementById(item.getAttribute('aria-controls')).hidden=!selected;});}));

const search=document.querySelector('#command-search');
const cards=[...document.querySelectorAll('#command-grid article')];
const empty=document.querySelector('#empty-state');
search?.addEventListener('input',()=>{const query=search.value.trim().toLocaleLowerCase('zh-Hant');let visible=0;cards.forEach(card=>{const match=!query||`${card.textContent} ${card.dataset.search}`.toLocaleLowerCase('zh-Hant').includes(query);card.classList.toggle('hidden',!match);if(match)visible++;});empty.hidden=visible!==0;});

const toast=document.querySelector('.toast');
let toastTimer;
document.querySelectorAll('[data-copy]').forEach(button=>button.addEventListener('click',async()=>{try{await navigator.clipboard.writeText(button.dataset.copy);toast.textContent=`已複製：${button.dataset.copy}`;}catch{toast.textContent='無法自動複製，請手動選取文字。';}toast.classList.add('show');clearTimeout(toastTimer);toastTimer=setTimeout(()=>toast.classList.remove('show'),2200);}));

const sectionLinks=[...document.querySelectorAll('#site-nav a[href^="#"]')];
const sections=sectionLinks.map(link=>document.querySelector(link.getAttribute('href'))).filter(Boolean);
if('IntersectionObserver'in window){const observer=new IntersectionObserver(entries=>entries.forEach(entry=>{if(entry.isIntersecting){sectionLinks.forEach(link=>link.classList.toggle('active',link.getAttribute('href')===`#${entry.target.id}`));}}),{rootMargin:'-25% 0px -65%'});sections.forEach(section=>observer.observe(section));}

const progressBar=document.querySelector('.scroll-progress span');
let scrollFrame;
const updateScrollProgress=()=>{scrollFrame=null;const distance=document.documentElement.scrollHeight-window.innerHeight;const ratio=distance>0?window.scrollY/distance:0;progressBar?.style.setProperty('--scroll-progress',String(Math.min(1,Math.max(0,ratio))));};
window.addEventListener('scroll',()=>{if(!scrollFrame)scrollFrame=requestAnimationFrame(updateScrollProgress);},{passive:true});
updateScrollProgress();

if('IntersectionObserver'in window&&!window.matchMedia('(prefers-reduced-motion: reduce)').matches){
  const revealTargets=document.querySelectorAll('.section-heading,.step-card,.requirement-grid article,.guide-steps>li,.scenario-grid article,.command-grid article,.compare-grid article,.path-list,.faq-list details,.final-cta');
  document.documentElement.classList.add('reveal-ready');
  const revealObserver=new IntersectionObserver(entries=>entries.forEach(entry=>{if(entry.isIntersecting){entry.target.classList.add('is-visible');revealObserver.unobserve(entry.target);}}),{rootMargin:'0px 0px -8%',threshold:.08});
  revealTargets.forEach((element,index)=>{element.classList.add('reveal-target');element.style.setProperty('--reveal-delay',`${Math.min(index%4,3)*55}ms`);revealObserver.observe(element);});
}
