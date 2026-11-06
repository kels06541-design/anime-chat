(function(){
const C=window.APP_CONFIG||{};
const ok=C.url&&C.key&&!/TON-PROJET|COLLE-ICI/.test(C.url+C.key);
window.BLOB=(C.url||'')+'/storage/v1/object/public/media/';
const nid=()=>(crypto.randomUUID?crypto.randomUUID():(Math.random().toString(16).slice(2)+Date.now().toString(16)+Math.random().toString(16).slice(2)).padEnd(32,'0').slice(0,36)).replace(/-/g,'').slice(0,32);
if(!ok){window.claude={use:async()=>null};return}
const sb=supabase.createClient(C.url,C.key,{auth:{persistSession:true,autoRefreshToken:true,detectSessionInUrl:true}});
const emailFor=name=>String(name||'').trim().toLowerCase()+'@animechat.invalid';
window.AnimeAuth={
 signIn:async(name,password)=>{const r=await sb.auth.signInWithPassword({email:emailFor(name),password});if(r.error)throw r.error;return r.data.user},
 signUp:async(name,password)=>{const r=await sb.auth.signUp({email:emailFor(name),password,options:{data:{username:String(name).trim()}}});if(r.error)throw r.error;if(!r.data.session)throw new Error('Confirmation désactivée requise : désactive la confirmation e-mail dans Supabase > Authentication > Providers > Email.');return r.data.user},
 signOut:async()=>{const r=await sb.auth.signOut();if(r.error)throw r.error},
 session:async()=>{const r=await sb.auth.getSession();return r.data.session},
 username:async()=>{const r=await sb.auth.getUser();const u=r.data.user;if(!u)return '';const v=u.user_metadata&&u.user_metadata.username;return String(v||(String(u.email||'').split('@')[0].toLowerCase()==='kems'?'KEMS':String(u.email||'').split('@')[0]))},
 role:async()=>{const r=await sb.rpc('my_chat_role');if(r.error)return 'member';return r.data||'member'}
};
const enc=p=>p.replace(/\//g,':'),CACHE=['profiles','games'];
const snap=a=>({docs:a.map(r=>({id:r.id,exists:true,data:()=>r.data})),size:a.length,empty:!a.length});
function ref(col,id){const c=enc(col);return{id,path:col+'/'+id,
set:async d=>{const{error}=await sb.from('docs').upsert({col:c,id,data:d});if(error)throw error},
update:async p=>{const{data}=await sb.from('docs').select('data').eq('col',c).eq('id',id).maybeSingle();const{error}=await sb.from('docs').upsert({col:c,id,data:Object.assign({},data&&data.data,p)});if(error)throw error},
delete:async()=>{const{error}=await sb.from('docs').delete().eq('col',c).eq('id',id);if(error)throw error},
get:async()=>{const{data}=await sb.from('docs').select('data').eq('col',c).eq('id',id).maybeSingle();return{id,exists:!!data,data:()=>data&&data.data}}}}
function coll(path,f,d,n){const c=enc(path);return{
orderBy:(k,dir)=>coll(path,k,dir||'asc',n),limit:m=>coll(path,f,d,m),
doc:id=>ref(path,id||nid()),
add:async data=>{const id=nid();const{error}=await sb.from('docs').insert({col:c,id,data});if(error)throw error;return ref(path,id)},
onSnapshot(next,err){const M=new Map();let alive=true;
const emit=()=>{const k=f||'ts';let a=[...M.values()].sort((x,y)=>{const p=x.data[k],q=y.data[k];return p>q?1:p<q?-1:0});if(d==='desc')a.reverse();if(n)a=d==='desc'?a.slice(0,n):a.slice(-n);
if(CACHE.includes(path)){try{localStorage.setItem('chat-s:'+c,JSON.stringify(a))}catch(e){}}next(snap(a))};
const load=async()=>{try{const{data,error}=await sb.from('docs').select('id,data').eq('col',c).order('created',{ascending:false}).limit(300);if(error||!alive||!data)return;M.clear();data.forEach(r=>M.set(r.id,r));emit()}catch(e){}};
if(CACHE.includes(path)){try{const a=JSON.parse(localStorage.getItem('chat-s:'+c)||'null');if(a){a.forEach(r=>M.set(r.id,r));emit()}}catch(e){}}
const ch=sb.channel('r'+nid()).on('postgres_changes',{event:'*',schema:'public',table:'docs',filter:'col=eq.'+c},p=>{if(!alive)return;if(p.eventType==='DELETE'){if(p.old&&p.old.col===c)M.delete(p.old.id)}else M.set(p.new.id,{id:p.new.id,data:p.new.data});emit()}).subscribe(s=>{if(s==='SUBSCRIBED')load()});
const on=()=>load();addEventListener('online',on);load();
return()=>{alive=false;removeEventListener('online',on);sb.removeChannel(ch)}}}}
const DB={collection:p=>coll(p),doc:p=>{const i=p.indexOf('/');return ref(p.slice(0,i),p.slice(i+1))}};
const AS={upload:async b=>{const session=await sb.auth.getSession();const uid=session.data.session?.user?.id;if(!uid)throw new Error('Connecte-toi pour envoyer un média.');const id=uid+'/'+nid();const{error}=await sb.storage.from('media').upload(id,b,{contentType:b.type||'application/octet-stream'});if(error)throw error;return{id,url:window.BLOB+id}},
delete:async id=>{await sb.storage.from('media').remove([id])}};
window.claude={use:async n=>({db:DB,user:{id:async()=>{const r=await sb.auth.getSession();return r.data.session?.user?.id||null}},assets:AS}[n]||null)};
})();
