(function(){
window.BizForum = window.BizForum || {};
var categories = [
{ id: 'startups', name: 'Стартапы', slug: 'startups' },
{ id: 'finance', name: 'Финансы', slug: 'finance' },
{ id: 'marketing', name: 'Маркетинг', slug: 'marketing' },
{ id: 'sales', name: 'Продажи', slug: 'sales' },
{ id: 'law', name: 'Юридическое', slug: 'law' },
{ id: 'tax', name: 'Налоги', slug: 'tax' },
{ id: 'hr', name: 'HR и команда', slug: 'hr' },
{ id: 'tech', name: 'IT и автоматизация', slug: 'tech' },
{ id: 'export', name: 'Экспорт и импорт', slug: 'export' },
{ id: 'everyday', name: 'Житейское', slug: 'everyday' }
];
var posts = [];
var comments = {};
function getCategories(){ return Promise.resolve(categories); }
function getCommentCount(postId){
var base = (comments[postId] || []).length;
var extra = (getStored(STORAGE_COMMENTS, {})[postId] || []).length;
return base + extra;
}
function getReactionScore(postId){
var r = getReactions(postId); var sum = 0; REACTION_TYPES.forEach(function(t){ sum += r[t] || 0; }); return sum;
}
function getAllPostsList(){
var userPosts = getStored(STORAGE_POSTS, []);
var list = [];
userPosts.forEach(function(p){
var commentCount = getCommentCount(p.id);
var reactScore = getReactionScore(p.id);
list.push({ id: p.id, categoryId: p.categoryId, title: p.title, excerpt: p.excerpt || (p.body && p.body.slice(0,120)), body: p.body, createdAt: p.createdAt, author: p.author || 'Гость', commentsCount: commentCount, score: reactScore });
});
return list;
}
function getPosts(opts){
opts = opts || {};
var list = getAllPostsList();
if(opts.categoryId) list = list.filter(function(p){ return p.categoryId === opts.categoryId; });
var sort = opts.sort || 'new';
if(sort === 'recommended'){ var now = Date.now(); var pos = function(p){ var s = p.score || 0; var fu = (p.reactions && p.reactions.fu) || 0; return Math.max(0, s - fu); }; var maxEng = 0; list.forEach(function(p){ var e = Math.log(1 + pos(p) + 2*(p.commentsCount||0) + 0.5*Math.log(1+(p.views||0))); if(e > maxEng) maxEng = e; }); if(maxEng < 1) maxEng = 1; list.forEach(function(p){ var ageHours = (now - new Date(p.createdAt).getTime()) / 3600000; var recency = 1 / (1 + ageHours / 24); var engagement = Math.log(1 + pos(p) + 2*(p.commentsCount||0) + 0.5*Math.log(1+(p.views||0))) / maxEng; p._feedScore = 0.6 * recency + 0.4 * engagement; }); list.sort(function(a,b){ return (b._feedScore || 0) - (a._feedScore || 0); }); }
if(sort === 'new') list.sort(function(a,b){ return new Date(b.createdAt) - new Date(a.createdAt); });
if(sort === 'hot') list.sort(function(a,b){ return (b.score || 0) - (a.score || 0); });
if(sort === 'comments') list.sort(function(a,b){ return (b.commentsCount || 0) - (a.commentsCount || 0); });
if(sort === 'views') list.sort(function(a,b){ return (getViews(b.id) || 0) - (getViews(a.id) || 0); });
var limit = opts.limit || 0;
var offset = opts.offset || 0;
if(limit > 0) list = list.slice(offset, offset + limit); else if(offset > 0) list = list.slice(offset);
return Promise.resolve(list);
}
function getPost(id){
var userPosts = getStored(STORAGE_POSTS, []);
var p = userPosts.find(function(x){ return x.id === id; });
if(p){ var commentCount = getCommentCount(p.id); var reactScore = getReactionScore(p.id); return Promise.resolve({ id: p.id, categoryId: p.categoryId, title: p.title, excerpt: p.excerpt || (p.body && p.body.slice(0,120)), body: p.body, createdAt: p.createdAt, author: p.author || 'Гость', commentsCount: commentCount, score: reactScore }); }
return Promise.resolve(null);
}
function getCategory(id){ return Promise.resolve(categories.find(function(c){ return c.id === id; }) || null); }
function updatePost(postId, data){
var userPosts = getStored(STORAGE_POSTS, []);
var p = userPosts.find(function(x){ return x.id === postId; });
if(!p) return Promise.resolve(null);
p.title = data.title; p.body = data.body || ''; p.excerpt = (data.body || '').slice(0, 200);
setStored(STORAGE_POSTS, userPosts);
return Promise.resolve(p);
}
function createPost(data){
var userPosts = getStored(STORAGE_POSTS, []);
var id = 'p' + Date.now();
var p = { id: id, categoryId: data.categoryId, title: data.title, excerpt: (data.body || '').slice(0, 200), body: data.body || '', createdAt: new Date().toISOString(), author: data.author || 'Гость' };
userPosts.unshift(p);
setStored(STORAGE_POSTS, userPosts);
return Promise.resolve(p);
}
function getMyDrafts(){ return Promise.resolve([]); }
function publishPost(){ return Promise.reject(new Error('Черновики доступны при подключённой базе Supabase')); }
function getFavorites(){ var f = getStored(STORAGE_FAVORITES, []); return Array.isArray(f) ? f : []; }
function toggleFavorite(postId){ var f = getFavorites(); var i = f.indexOf(postId); if(i >= 0) f.splice(i, 1); else f.push(postId); setStored(STORAGE_FAVORITES, f); return Promise.resolve(f); }
function isFavorite(postId){ return getFavorites().indexOf(postId) >= 0; }
var STORAGE_VIEWS = 'bizforum_views';
var STORAGE_REACTIONS = 'bizforum_reactions';
var STORAGE_USER_REACTIONS = 'bizforum_user_reactions';
var STORAGE_COMMENTS = 'bizforum_comments';
var STORAGE_POSTS = 'bizforum_posts';
var STORAGE_FAVORITES = 'bizforum_favorites';
function getStored(key, def){ try { var v = localStorage.getItem(key); return v ? JSON.parse(v) : (def || {}); } catch(e){ return def || {}; } }
function setStored(key, val){ try { localStorage.setItem(key, JSON.stringify(val)); } catch(e){} }
function getViews(postId){ var v = getStored(STORAGE_VIEWS, {}); return Number(v[postId]) || 0; }
function incrementView(postId){ var v = getStored(STORAGE_VIEWS, {}); v[postId] = (Number(v[postId]) || 0) + 1; setStored(STORAGE_VIEWS, v); return v[postId]; }
var REACTION_TYPES = ['muzhik','koroleva','rzhaka','fire','fu','grustno','babki','hahaha'];
function emptyReactions(){ var o = {}; REACTION_TYPES.forEach(function(t){ o[t] = 0; }); return o; }
function getReactions(postId){ var r = getStored(STORAGE_REACTIONS, {}); var out = r[postId]; if(!out){ return emptyReactions(); } REACTION_TYPES.forEach(function(t){ if(out[t] === undefined) out[t] = 0; }); return out; }
function getUserReaction(postId){ var u = getStored(STORAGE_USER_REACTIONS, {}); return u[postId] || null; }
function setReaction(postId, type){ var r = getStored(STORAGE_REACTIONS, {}); var u = getStored(STORAGE_USER_REACTIONS, {}); var prev = u[postId]; if(!r[postId]) r[postId] = emptyReactions(); if(prev && r[postId][prev] > 0) r[postId][prev]--; r[postId][type] = (r[postId][type] || 0) + 1; u[postId] = type; setStored(STORAGE_REACTIONS, r); setStored(STORAGE_USER_REACTIONS, u); return r[postId]; }
function unsetReaction(postId){ var r = getStored(STORAGE_REACTIONS, {}); var u = getStored(STORAGE_USER_REACTIONS, {}); var prev = u[postId]; if(prev && r[postId] && r[postId][prev] > 0){ r[postId][prev]--; } delete u[postId]; setStored(STORAGE_REACTIONS, r); setStored(STORAGE_USER_REACTIONS, u); return Promise.resolve(getReactions(postId)); }
function getComments(postId){
var base = (comments[postId] || []).slice();
var extra = getStored(STORAGE_COMMENTS, {})[postId] || [];
return Promise.resolve(base.concat(extra));
}
function addComment(postId, body, author, authorId, parentId){
author = author || 'Гость';
var extra = getStored(STORAGE_COMMENTS, {});
if(!extra[postId]) extra[postId] = [];
var c = { id: 'u' + Date.now(), author: author, body: body, createdAt: new Date().toISOString(), authorId: authorId || null, parentId: parentId || null };
extra[postId].push(c);
setStored(STORAGE_COMMENTS, extra);
return Promise.resolve(c);
}
function updateComment(postId, commentId, body){
var extra = getStored(STORAGE_COMMENTS, {});
var arr = extra[postId] || [];
var c = arr.find(function(x){ return x.id === commentId; });
if(c){ c.body = body; c.updatedAt = new Date().toISOString(); setStored(STORAGE_COMMENTS, extra); return Promise.resolve(c); }
return Promise.resolve(null);
}
function deleteComment(postId, commentId){
var extra = getStored(STORAGE_COMMENTS, {});
var arr = extra[postId] || [];
var i = arr.findIndex(function(x){ return x.id === commentId; });
if(i >= 0){ arr.splice(i, 1); setStored(STORAGE_COMMENTS, extra); return Promise.resolve(true); }
return Promise.resolve(false);
}
function searchPosts(query){
query = (query || '').trim().toLowerCase();
if(!query) return getPosts({});
var allComments = getStored(STORAGE_COMMENTS, {});
var list = getAllPostsList();
var cats = {}; categories.forEach(function(c){ cats[c.id] = c.name; });
var scored = list.map(function(p){
var text = (p.title + ' ' + (p.excerpt || '') + ' ' + (p.body || '') + ' ' + (cats[p.categoryId] || '')).toLowerCase();
var commentText = (allComments[p.id] || []).map(function(c){ return c.body; }).join(' ').toLowerCase();
var full = text + ' ' + commentText;
var words = query.split(/\s+/).filter(Boolean);
var score = 0; words.forEach(function(w){ var idx = full.indexOf(w); while(idx !== -1){ score += 1; idx = full.indexOf(w, idx + 1); } });
return { post: p, score: score };
});
scored = scored.filter(function(x){ return x.score > 0; }).sort(function(a,b){ return b.score - a.score; });
return Promise.resolve(scored.map(function(x){ return x.post; }));
}
window.BizForum.data = {
getCategories: getCategories,
getPosts: getPosts,
getPost: getPost,
updatePost: updatePost,
getComments: getComments,
getCategory: getCategory,
getViews: getViews,
incrementView: incrementView,
getReactions: getReactions,
getUserReaction: getUserReaction,
setReaction: setReaction,
unsetReaction: unsetReaction,
addComment: addComment,
updateComment: updateComment,
deleteComment: deleteComment,
searchPosts: searchPosts,
createPost: createPost,
getMyDrafts: getMyDrafts,
publishPost: publishPost,
getFavorites: getFavorites,
toggleFavorite: toggleFavorite,
isFavorite: isFavorite
};
})();
