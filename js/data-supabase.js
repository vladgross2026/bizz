(function(){
var cfg = window.BIZFORUM_CONFIG;
if(!cfg || !cfg.useSupabase || !window.supabase){ window.BizForum = window.BizForum || {}; window.BizForum.data = window.BizForum.data || {}; return; }
var sb = window.supabase.createClient(cfg.SUPABASE_URL, cfg.SUPABASE_ANON_KEY);
var STORAGE_REACTIONS = 'bizforum_reactions';
var STORAGE_USER_REACTIONS = 'bizforum_user_reactions';
var STORAGE_FAVORITES = 'bizforum_favorites';
function getStored(key, def){ try { var v = localStorage.getItem(key); return v ? JSON.parse(v) : (def || {}); } catch(e){ return def || {}; } }
function setStored(key, val){ try { localStorage.setItem(key, JSON.stringify(val)); } catch(e){} }
function getUid(){ return sb.auth.getUser().then(function(r){ return r.data && r.data.user ? r.data.user.id : null; }); }
function getCategories(){ return sb.from('categories').select('id,name,slug').then(function(r){ if(r.error) return []; return r.data || []; }).then(function(arr){ return arr.map(function(c){ return { id: c.id, name: c.name, slug: c.slug }; }); }); }
function getSubscribedAuthorIds(){ return getUid().then(function(uid){ if(!uid) return []; return sb.from('subscriptions').select('author_id').eq('user_id', uid).then(function(r){ return (r.data || []).map(function(x){ return x.author_id; }); }).catch(function(){ return []; }); }); }
function subscribeToAuthor(authorId){ return getUid().then(function(uid){ if(!uid) return Promise.reject(new Error('Не авторизован')); if(uid === authorId) return Promise.resolve(); return sb.from('subscriptions').upsert({ user_id: uid, author_id: authorId },{ onConflict: 'user_id,author_id' }).then(function(){ return true; }); }); }
function unsubscribeFromAuthor(authorId){ return getUid().then(function(uid){ if(!uid) return Promise.resolve(); return sb.from('subscriptions').delete().eq('user_id', uid).eq('author_id', authorId).then(function(){ return true; }); }); }
function getPosts(opts){
opts = opts || {};
var rangeSize = opts.sort === 'recommended' ? 200 : 1000;
var q = sb.from('posts').select('id,category_id,title,excerpt,body,author_id,author_name,created_at,status,media_urls,price,is_anonymous').order('created_at',{ ascending: false }).range(0, rangeSize - 1);
if(opts.categoryId) q = q.eq('category_id', opts.categoryId);
if(opts.authorId){ q = q.eq('author_id', opts.authorId); q = q.eq('is_anonymous', false); }
if(opts.authorIds && opts.authorIds.length) q = q.in('author_id', opts.authorIds);
q = q.eq('status', 'published');
if(opts.followingOnly){
return getUid().then(function(uid){
if(!uid) return [];
return Promise.all([
sb.from('friend_requests').select('from_user_id,to_user_id').eq('status', 'accepted').or('from_user_id.eq.' + uid + ',to_user_id.eq.' + uid).then(function(r){ var data = r.data || []; return data.map(function(x){ return x.from_user_id === uid ? x.to_user_id : x.from_user_id; }); }),
getSubscribedAuthorIds()
]).then(function(arr){ var friends = arr[0] || []; var subs = arr[1] || []; var ids = []; var seen = {}; friends.forEach(function(id){ if(id && !seen[id]){ seen[id] = true; ids.push(id); } }); subs.forEach(function(id){ if(id && !seen[id]){ seen[id] = true; ids.push(id); } }); if(ids.length === 0) return []; return getPosts(Object.assign({}, opts, { authorIds: ids, followingOnly: undefined })); });
});
}
return q.then(function(r){
if(r.error) return []; var list = (r.data || []).map(function(p){ var anon = !!(p.is_anonymous); return { id: p.id, categoryId: p.category_id, title: p.title, excerpt: p.excerpt || '', body: p.body, createdAt: p.created_at, author: anon ? 'Аноним' : (p.author_name || 'Гость'), authorId: p.author_id, isAnonymous: anon, status: p.status || 'published', mediaUrls: (p.media_urls && Array.isArray(p.media_urls)) ? p.media_urls : [], price: (p.price != null && p.price > 0) ? p.price : null }; });
return getUid().then(function(uid){
list.forEach(function(p){ p._hasPurchased = false; });
return Promise.all(list.map(function(p){
return Promise.all([
sb.from('comments').select('id', { count: 'exact', head: true }).eq('post_id', p.id),
sb.from('post_views').select('view_count').eq('post_id', p.id).maybeSingle(),
sb.from('reactions').select('type').eq('post_id', p.id)
]).then(function(res){
var commentsCount = (res[0] && res[0].count) || 0;
var views = (res[1] && res[1].data && res[1].data.view_count) || 0;
var reacts = res[2].data || []; var rOut = emptyReactions(); reacts.forEach(function(x){ if(rOut[x.type] !== undefined) rOut[x.type]++; }); var scoreSum = 0; var positiveSum = 0; REACTION_TYPES.forEach(function(t){ var n = rOut[t] || 0; scoreSum += n; if(t !== 'fu') positiveSum += n; });
p.commentsCount = commentsCount; p.views = views; p.score = scoreSum; p._positiveReactions = positiveSum; p.reactions = rOut;
return p;
});
})).then(function(list){
if(opts.categoryId) list = list.filter(function(p){ return p.categoryId === opts.categoryId; });
var sort = opts.sort || 'new';
var sortPromise;
if(sort === 'recommended'){
var authorIds = []; var seen = {}; list.forEach(function(p){ if(p.authorId && !seen[p.authorId]){ seen[p.authorId] = true; authorIds.push(p.authorId); } });
var subPromise;
if(authorIds.length && sb.rpc){
subPromise = sb.rpc('get_subscriber_counts', { p_author_ids: authorIds }).then(function(r){ var m = {}; (r.data || []).forEach(function(row){ m[row.author_id] = parseInt(row.cnt, 10) || 0; }); return m; }).catch(function(){ return {}; });
} else {
subPromise = Promise.resolve({});
}
sortPromise = subPromise.then(function(subMap){
list.forEach(function(p){ p._subscribers = subMap[p.authorId] || 0; });
var now = Date.now(); var maxEng = 0;
list.forEach(function(p){ var pos = p._positiveReactions || 0; var e = Math.log(1 + pos + 2*(p.commentsCount||0) + 0.5*Math.log(1+(p.views||0)) + 0.3*(p._subscribers||0)); if(e > maxEng) maxEng = e; });
if(maxEng < 1) maxEng = 1;
list.forEach(function(p){ var ageHours = (now - new Date(p.createdAt).getTime()) / 3600000; var recency = 1 / (1 + ageHours / 24); var pos = p._positiveReactions || 0; var engagement = Math.log(1 + pos + 2*(p.commentsCount||0) + 0.5*Math.log(1+(p.views||0)) + 0.3*(p._subscribers||0)) / maxEng; p._feedScore = 0.6 * recency + 0.4 * engagement; });
list.sort(function(a,b){ return (b._feedScore || 0) - (a._feedScore || 0); });
return list;
});
} else {
if(sort === 'new') list.sort(function(a,b){ return new Date(b.createdAt) - new Date(a.createdAt); });
if(sort === 'hot') list.sort(function(a,b){ return ((b._positiveReactions !== undefined ? b._positiveReactions : b.score) || 0) - ((a._positiveReactions !== undefined ? a._positiveReactions : a.score) || 0); });
if(sort === 'comments') list.sort(function(a,b){ return (b.commentsCount || 0) - (a.commentsCount || 0); });
if(sort === 'views') list.sort(function(a,b){ return (b.views || 0) - (a.views || 0); });
sortPromise = Promise.resolve(list);
}
return sortPromise.then(function(list){
var limit = opts.limit || 0, offset = opts.offset || 0;
if(limit > 0) list = list.slice(offset, offset + limit); else if(offset > 0) list = list.slice(offset);
return getUid().then(function(uid){
if(!uid || list.length === 0) return list;
var ids = list.map(function(p){ return p.id; });
var paidIds = list.filter(function(p){ return p.price && p.price > 0; }).map(function(p){ return p.id; });
var reactPromise = sb.from('reactions').select('post_id, type').eq('user_id', uid).in('post_id', ids).then(function(r){
var map = {}; (r.data || []).forEach(function(x){ map[x.post_id] = x.type; });
list.forEach(function(p){ p.userReaction = map[p.id] || null; });
return list;
});
var purchPromise = (paidIds.length > 0) ? sb.from('post_purchases').select('post_id').eq('user_id', uid).in('post_id', paidIds).then(function(r){
var purchSet = {}; (r.data || []).forEach(function(x){ purchSet[x.post_id] = true; });
list.forEach(function(p){ if(purchSet[p.id]) p._hasPurchased = true; });
return list;
}) : Promise.resolve(list);
return Promise.all([reactPromise, purchPromise]).then(function(){ return list; });
}).then(function(list){
if(list.length === 0) return list;
var subPromise = getSubscriptionStatus ? getSubscriptionStatus() : Promise.resolve({ hasSubscription: true, opensRemaining: 2 });
var openedPromise = getOpenedPostIds ? getOpenedPostIds() : Promise.resolve([]);
return Promise.all([subPromise, openedPromise]).then(function(arr){
var status = arr[0] || { hasSubscription: true, opensRemaining: 2 };
var openedIds = arr[1] || [];
list.forEach(function(p){
var paidPost = !!(p.price && p.price > 0);
var isAuthor = p.authorId && p.authorId === (window.__bizforum_user_id || null);
if(paidPost){ p._canSeeContent = p._hasPurchased || isAuthor; p._subscriptionBlur = false; }
else { p._canSeeContent = status.hasSubscription || (openedIds.indexOf(p.id) >= 0); p._subscriptionBlur = !p._canSeeContent; p._opensRemaining = status.opensRemaining || 0; }
});
return list;
}).catch(function(){ return list; });
});
});
});
});
});
}
function getPost(id){
return sb.from('posts').select('id,category_id,title,excerpt,body,author_id,author_name,created_at,status,media_urls,price,is_anonymous').eq('id', id).single().then(function(r){
if(r.error || !r.data) return null;
var p = r.data; var anon = !!(p.is_anonymous); return { id: p.id, categoryId: p.category_id, title: p.title, excerpt: p.excerpt || '', body: p.body, createdAt: p.created_at, author: anon ? 'Аноним' : (p.author_name || 'Гость'), authorId: p.author_id, isAnonymous: anon, bestAnswerCommentId: (p.best_answer_comment_id !== undefined ? p.best_answer_comment_id : null) || null, status: p.status || 'published', mediaUrls: (p.media_urls && Array.isArray(p.media_urls)) ? p.media_urls : [], price: (p.price != null && p.price > 0) ? p.price : null };
}).then(function(p){
if(!p) return null;
return getUid().then(function(uid){
var hasPurchasedPromise = (uid && p.price) ? sb.from('post_purchases').select('post_id').eq('post_id', p.id).eq('user_id', uid).maybeSingle().then(function(r){ return !!(r.data && r.data.post_id); }) : Promise.resolve(false);
return hasPurchasedPromise.then(function(hasPurchased){
p._hasPurchased = hasPurchased;
return Promise.all([
sb.from('comments').select('id', { count: 'exact', head: true }).eq('post_id', p.id),
sb.from('post_views').select('view_count').eq('post_id', p.id).maybeSingle(),
sb.from('reactions').select('type').eq('post_id', p.id),
uid ? sb.from('reactions').select('type').eq('post_id', p.id).eq('user_id', uid).maybeSingle() : Promise.resolve({ data: null }),
getSubscriptionStatus ? getSubscriptionStatus() : Promise.resolve({ hasSubscription: true, opensRemaining: 2 }),
hasOpenedPost ? hasOpenedPost(p.id) : Promise.resolve(false)
]).then(function(res){
p.commentsCount = (res[0] && res[0].count) || 0;
var views = (res[1] && res[1].data && res[1].data.view_count) || 0;
var reacts = res[2].data || []; var rOut = emptyReactions(); reacts.forEach(function(x){ if(rOut[x.type] !== undefined) rOut[x.type]++; }); var scoreSum = 0; REACTION_TYPES.forEach(function(t){ scoreSum += rOut[t] || 0; });
p.views = views; p.score = scoreSum; p.reactions = rOut;
p.userReaction = (res[3] && res[3].data && res[3].data.type) || null;
var subStatus = res[4] || { hasSubscription: true, opensRemaining: 2 };
var hasOpened = res[5] === true;
var paidPost = !!(p.price && p.price > 0);
var isAuthor = uid && p.author_id === uid;
p._canSeeContent = paidPost ? (hasPurchased || isAuthor) : (subStatus.hasSubscription || hasOpened);
p._subscriptionBlur = !paidPost && !p._canSeeContent;
p._opensRemaining = subStatus.opensRemaining || 0;
return p;
});
});
});
});
}
function getCategory(id){ return sb.from('categories').select('id,name,slug').eq('id', id).single().then(function(r){ if(r.error || !r.data) return null; var c = r.data; return { id: c.id, name: c.name, slug: c.slug }; }); }
function getViews(postId){
return sb.from('post_views').select('view_count').eq('post_id', postId).maybeSingle().then(function(r){ if(r.error || !r.data) return 0; return Number(r.data.view_count) || 0; });
}
function incrementView(postId){ return sb.rpc('increment_post_view', { p_post_id: postId }).then(function(){ return getViews(postId); }); }
var REACTION_TYPES = ['muzhik','koroleva','rzhaka','fire','fu','grustno','babki','hahaha','useful'];
function emptyReactions(){ var o = {}; REACTION_TYPES.forEach(function(t){ o[t] = 0; }); return o; }
function getReactions(postId){
return getUid().then(function(uid){
if(uid) return sb.from('reactions').select('type').eq('post_id', postId).then(function(r){ var d = r.data || []; var out = emptyReactions(); d.forEach(function(x){ if(out[x.type] !== undefined) out[x.type]++; }); return out; });
return Promise.resolve(getStored(STORAGE_REACTIONS, {})[postId] || emptyReactions());
});
}
function getUserReaction(postId){
return getUid().then(function(uid){
if(uid) return sb.from('reactions').select('type').eq('post_id', postId).eq('user_id', uid).maybeSingle().then(function(r){ return r.data && r.data.type ? r.data.type : null; });
return Promise.resolve(getStored(STORAGE_USER_REACTIONS, {})[postId] || null);
});
}
function setReaction(postId, type){
return getUid().then(function(uid){
if(uid) return sb.from('reactions').upsert({ post_id: postId, user_id: uid, type: type },{ onConflict: 'post_id,user_id' }).then(function(){ return getReactions(postId); });
var r = getStored(STORAGE_REACTIONS, {}); var u = getStored(STORAGE_USER_REACTIONS, {}); var prev = u[postId]; if(!r[postId]) r[postId] = emptyReactions(); if(prev && r[postId][prev] > 0) r[postId][prev]--; r[postId][type] = (r[postId][type] || 0) + 1; u[postId] = type; setStored(STORAGE_REACTIONS, r); setStored(STORAGE_USER_REACTIONS, u); return Promise.resolve(r[postId]);
});
}
function unsetReaction(postId){
return getUid().then(function(uid){
if(!uid){ var r = getStored(STORAGE_REACTIONS, {}); var u = getStored(STORAGE_USER_REACTIONS, {}); var prev = u[postId]; if(prev && r[postId] && r[postId][prev] > 0){ r[postId][prev]--; } delete u[postId]; setStored(STORAGE_REACTIONS, r); setStored(STORAGE_USER_REACTIONS, u); return Promise.resolve(getReactions(postId)); }
return sb.from('reactions').delete().eq('post_id', postId).eq('user_id', uid).then(function(){ return getReactions(postId); });
});
}
function getComments(postId){
return sb.from('comments').select('id,body,author_id,author_name,author_device_id,parent_id,created_at,updated_at').eq('post_id', postId).order('created_at',{ ascending: true }).then(function(r){
if(r.error) return []; return (r.data || []).map(function(c){ return { id: c.id, author: c.author_name || 'Гость', body: c.body, createdAt: c.created_at, updatedAt: c.updated_at || null, authorId: c.author_id ? c.author_id : (c.author_device_id || null), parentId: (c.parent_id !== undefined && c.parent_id !== null) ? c.parent_id : null }; });
});
}
function getCommentReactions(commentIds){
if(!commentIds || commentIds.length === 0) return Promise.resolve({});
return getUid().then(function(uid){
return Promise.all([
sb.from('comment_reactions').select('comment_id, type').in('comment_id', commentIds),
uid ? sb.from('comment_reactions').select('comment_id, type').eq('user_id', uid).in('comment_id', commentIds) : Promise.resolve({ data: [] })
]).then(function(res){
var out = {}; commentIds.forEach(function(id){ out[id] = { reactions: emptyReactions(), userReaction: null }; });
(res[0].data || []).forEach(function(x){ if(out[x.comment_id] && out[x.comment_id].reactions[x.type] !== undefined) out[x.comment_id].reactions[x.type]++; });
(res[1].data || []).forEach(function(x){ if(out[x.comment_id]) out[x.comment_id].userReaction = x.type; });
return out;
});
});
}
function setCommentReaction(commentId, type){
return getUid().then(function(uid){ if(!uid) return Promise.reject(new Error('Не авторизован')); return sb.from('comment_reactions').upsert({ comment_id: commentId, user_id: uid, type: type },{ onConflict: 'comment_id,user_id' }).then(function(){ return getCommentReactions([commentId]); }); });
}
function unsetCommentReaction(commentId){
return getUid().then(function(uid){ if(!uid) return Promise.reject(new Error('Не авторизован')); return sb.from('comment_reactions').delete().eq('comment_id', commentId).eq('user_id', uid).then(function(){ return getCommentReactions([commentId]); }); });
}
function setBestAnswer(postId, commentId){
return getUid().then(function(uid){ if(!uid) return Promise.reject(new Error('Не авторизован')); return sb.from('posts').update({ best_answer_comment_id: commentId }).eq('id', postId).eq('author_id', uid).select().then(function(r){ if(r.error) return Promise.reject(r.error); return r.data && r.data[0]; }); });
}
function adminSetBestAnswer(postId, commentId){
return sb.rpc('admin_set_best_answer', { p_post_id: postId, p_comment_id: commentId }).then(function(r){ if(r.error) return Promise.reject(r.error); return true; });
}
function unsetBestAnswer(postId){
return getUid().then(function(uid){ if(!uid) return Promise.reject(new Error('Не авторизован')); return sb.from('posts').update({ best_answer_comment_id: null }).eq('id', postId).eq('author_id', uid).select().then(function(r){ if(r.error) return Promise.reject(r.error); return true; }); });
}
function adminUnsetBestAnswer(postId){
return sb.rpc('admin_set_best_answer', { p_post_id: postId, p_comment_id: null }).then(function(r){ if(r.error) return Promise.reject(r.error); return true; });
}
function getUserBadges(userId){
return sb.rpc('get_user_badges', { p_user_id: userId }).then(function(r){ if(r.error) return []; return r.data || []; });
}
function addComment(postId, body, author, authorId, parentId){
return getUid().then(function(uid){
var row = { post_id: postId, body: body, author_name: author || 'Гость', author_device_id: uid ? null : (authorId || null) };
if(uid) row.author_id = uid;
if(parentId) row.parent_id = parentId;
return sb.from('comments').insert(row).select('id,created_at').single().then(function(r){ if(r.error) return Promise.reject(r.error); return { id: r.data.id, author: author || 'Гость', body: body, createdAt: r.data.created_at, authorId: uid || authorId, parentId: parentId || null }; });
});
}
function createNotification(userId, type, payload){
return sb.from('notifications').insert({ user_id: userId, type: type, payload: payload || {} }).then(function(r){ if(r.error) return Promise.reject(r.error); return r.data; });
}
function getNotifications(limit){
limit = limit || 50;
return getUid().then(function(uid){ if(!uid) return []; return sb.from('notifications').select('id,type,payload,read,created_at').eq('user_id', uid).order('created_at',{ ascending: false }).limit(limit).then(function(r){ if(r.error) return []; return r.data || []; }); });
}
function markNotificationRead(id){
return getUid().then(function(uid){ if(!uid) return false; return sb.from('notifications').update({ read: true }).eq('id', id).eq('user_id', uid).then(function(r){ return !r.error; }); });
}
var _notificationsChannel = null;
function subscribeToNotifications(uid, onNew){
if(!uid || !onNew) return function(){};
if(_notificationsChannel) sb.removeChannel(_notificationsChannel);
_notificationsChannel = sb.channel('notifications-' + uid).on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'notifications', filter: 'user_id=eq.' + uid }, function(){ onNew(); }).subscribe();
return function(){ if(_notificationsChannel){ sb.removeChannel(_notificationsChannel); _notificationsChannel = null; } };
}
function getConversations(){
return getUid().then(function(uid){ if(!uid) return []; return sb.from('conversation_participants').select('conversation_id,conversations(type)').eq('user_id', uid).then(function(r){ if(r.error) return []; return (r.data || []).map(function(x){ return { id: x.conversation_id, type: x.conversations && x.conversations.type }; }); }); });
}
function getOrCreateDmConversation(otherUserId){
return getUid().then(function(uid){ if(!uid) return Promise.reject(new Error('Не авторизован')); return createNewDm(uid, otherUserId); });
}
function createNewDm(u1, u2){ return sb.rpc('create_dm_conversation', { p_other_user_id: u2 }).then(function(r){ if(r.error) return Promise.reject(r.error); return r.data; }); }
function getMessages(conversationId, limit){
limit = limit || 100;
return sb.from('messages').select('id,sender_id,body,created_at').eq('conversation_id', conversationId).order('created_at',{ ascending: false }).limit(limit).then(function(r){ if(r.error) return []; var arr = (r.data || []).map(function(m){ return { id: m.id, senderId: m.sender_id, body: m.body, createdAt: m.created_at }; }); arr.reverse(); return arr; });
}
function sendMessage(conversationId, body){
return getUid().then(function(uid){ if(!uid) return Promise.reject(new Error('Не авторизован')); return sb.from('messages').insert({ conversation_id: conversationId, sender_id: uid, body: body }).select('id,created_at').single().then(function(r){ if(r.error) return Promise.reject(r.error); return sb.from('conversation_participants').select('user_id').eq('conversation_id', conversationId).neq('user_id', uid).then(function(participants){ var other = (participants.data && participants.data[0]) ? participants.data[0].user_id : null; if(other && window.BizForum.createNotification) window.BizForum.createNotification(other, 'message_reply', { conversation_id: conversationId, from_user_id: uid, message_id: r.data.id }).catch(function(){}); return { id: r.data.id, senderId: uid, body: body, createdAt: r.data.created_at }; }); }); });
}
function getDmConversationsWithPreview(){ return getUid().then(function(uid){ if(!uid) return []; return sb.rpc('get_dm_conversations_with_preview').then(function(r){ if(r.error) return []; return (r.data || []).map(function(x){ return { conversationId: x.conversation_id, otherUserId: x.other_user_id, otherName: x.other_name || '—', lastBody: x.last_body || '', lastCreatedAt: x.last_created_at, unreadCount: (x.unread_count !== undefined && x.unread_count !== null) ? parseInt(x.unread_count, 10) : 0 }; }); }); }); }
var _messagesChannel = null;
function subscribeToMessages(conversationId, onNewMessage){ if(_messagesChannel) sb.removeChannel(_messagesChannel); if(!conversationId || !onNewMessage) return function(){}; _messagesChannel = sb.channel('messages-' + conversationId).on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'messages', filter: 'conversation_id=eq.' + conversationId }, function(){ onNewMessage(); }).subscribe(); return function(){ if(_messagesChannel) sb.removeChannel(_messagesChannel); _messagesChannel = null; }; }
function markConversationRead(conversationId){ if(!conversationId) return Promise.resolve(); return getUid().then(function(uid){ if(!uid) return; return sb.rpc('mark_conversation_read', { p_conversation_id: conversationId }).then(function(){}); }); }
function getTotalUnreadChatCount(){ return getUid().then(function(uid){ if(!uid) return 0; return sb.rpc('get_total_unread_chat_count').then(function(r){ if(r.error) return 0; return parseInt(r.data, 10) || 0; }).catch(function(){ return 0; }); }); }
function updateComment(postId, commentId, body){ return sb.from('comments').update({ body: body, updated_at: new Date().toISOString() }).eq('id', commentId).eq('post_id', postId).select().single().then(function(r){ return r.data; }); }
function deleteComment(postId, commentId){ return sb.from('comments').delete().eq('id', commentId).eq('post_id', postId).then(function(r){ return !r.error; }); }
function searchPosts(query, opts){
opts = opts || {};
var q = (query || '').trim().replace(/'/g, "''");
if(!q) return getPosts({});
var baseSelect = 'id,category_id,title,excerpt,body,author_id,author_name,created_at,media_urls,price,is_anonymous';
var promise = sb.from('posts').select(baseSelect).eq('status', 'published').or('title.ilike.%' + q + '%,body.ilike.%' + q + '%').order('created_at', { ascending: false }).limit(100);
if(opts.categoryId) promise = promise.eq('category_id', opts.categoryId);
if(opts.dateFrom) promise = promise.gte('created_at', opts.dateFrom);
if(opts.dateTo) promise = promise.lte('created_at', opts.dateTo);
return promise.then(function(r){
if(r.error) return []; var list = (r.data || []).map(function(p){ var anon = !!(p.is_anonymous); return { id: p.id, categoryId: p.category_id, title: p.title, excerpt: p.excerpt || '', body: p.body, author: anon ? 'Аноним' : (p.author_name || 'Гость'), authorId: p.author_id || null, isAnonymous: anon, createdAt: p.created_at, mediaUrls: (p.media_urls && Array.isArray(p.media_urls)) ? p.media_urls : [], price: (p.price != null && p.price > 0) ? p.price : null }; });
list.forEach(function(p){ p._hasPurchased = false; });
return Promise.all(list.map(function(p){
return Promise.all([
sb.from('comments').select('id', { count: 'exact', head: true }).eq('post_id', p.id),
sb.from('post_views').select('view_count').eq('post_id', p.id).maybeSingle(),
sb.from('reactions').select('type').eq('post_id', p.id)
]).then(function(res){
var commentsCount = (res[0] && res[0].count) || 0;
var views = (res[1] && res[1].data && res[1].data.view_count) || 0;
var reacts = res[2].data || []; var rOut = emptyReactions(); reacts.forEach(function(x){ if(rOut[x.type] !== undefined) rOut[x.type]++; }); var scoreSum = 0; REACTION_TYPES.forEach(function(t){ scoreSum += rOut[t] || 0; });
p.commentsCount = commentsCount; p.views = views; p.score = scoreSum; p.reactions = rOut;
return p;
});
})).then(function(list){
return getUid().then(function(uid){
if(!uid || list.length === 0) return list;
var ids = list.map(function(p){ return p.id; });
return sb.from('reactions').select('post_id, type').eq('user_id', uid).in('post_id', ids).then(function(r){
var map = {}; (r.data || []).forEach(function(x){ map[x.post_id] = x.type; });
list.forEach(function(p){ p.userReaction = map[p.id] || null; });
return list;
});
});
});
});
}
function updatePost(postId, data){
var mod = window.BizForum.moderation && window.BizForum.moderation.checkPostModeration;
if(mod){ var r = mod(data.title, data.body); if(!r.ok) return Promise.reject(new Error('moderation:' + (r.words || []).join(','))); }
var upd = { title: data.title, body: data.body || '', excerpt: (data.body || '').slice(0, 200), updated_at: new Date().toISOString() };
if(data.categoryId != null) upd.category_id = data.categoryId;
if(data.mediaUrls && Array.isArray(data.mediaUrls)) upd.media_urls = data.mediaUrls;
if(data.price != null) upd.price = data.categoryId === 'useful' ? Math.floor(data.price) : 0;
return sb.from('posts').update(upd).eq('id', postId).select().single().then(function(r){ if(r.error) return Promise.reject(r.error); var d = r.data; return { id: d.id, categoryId: d.category_id, title: d.title, body: d.body, excerpt: d.excerpt || '', author: d.author_name, createdAt: d.created_at, updated_at: d.updated_at }; });
}
function createPost(data){
return getUid().then(function(uid){
var isPublish = !data.draft;
var mod = window.BizForum.moderation && window.BizForum.moderation.checkPostModeration;
var modReject = null;
if(mod && isPublish){ var r = mod(data.title, data.body); if(!r.ok){ modReject = r; isPublish = false; } }
var isAnon = !!(data.anonymous);
var row = { category_id: data.categoryId, title: data.title, body: data.body || '', excerpt: (data.body || '').slice(0, 200), author_name: isAnon ? 'Аноним' : (data.author || 'Гость'), status: isPublish ? 'published' : 'draft', is_anonymous: isAnon };
if(uid) row.author_id = uid;
if(data.mediaUrls && Array.isArray(data.mediaUrls) && data.mediaUrls.length) row.media_urls = data.mediaUrls;
if(data.categoryId === 'useful' && data.price != null && data.price > 0) row.price = Math.floor(data.price);
return sb.from('posts').insert(row).select('id,created_at').single().then(function(r){ if(r.error) return null; var out = { id: r.data.id, categoryId: data.categoryId, title: data.title, body: data.body, excerpt: row.excerpt, author: row.author_name, createdAt: r.data.created_at, status: row.status, mediaUrls: row.media_urls || [], price: row.price || null }; if(modReject && uid && window.BizForum.createNotification){ var wordsStr = (modReject.words || []).slice(0, 5).join(', '); window.BizForum.createNotification(uid, 'moderation_post', { post_id: r.data.id, words: modReject.words || [], message: 'Исправьте пост: обнаружены недопустимые слова: ' + wordsStr }).catch(function(){}); out._moderationReject = true; out._violationWords = modReject.words || []; } return out; });
});
}
function getMyDrafts(){
return getUid().then(function(uid){ if(!uid) return []; return sb.from('posts').select('id,category_id,title,excerpt,body,author_id,author_name,created_at,status').eq('author_id', uid).eq('status', 'draft').order('created_at', { ascending: false }).then(function(r){ if(r.error) return []; return (r.data || []).map(function(p){ return { id: p.id, categoryId: p.category_id, title: p.title, excerpt: p.excerpt || '', body: p.body, createdAt: p.created_at, author: p.author_name || 'Гость', authorId: p.author_id, status: p.status }; }); }); });
}
function publishPost(postId){
return getUid().then(function(uid){ if(!uid) return Promise.reject(new Error('Не авторизован')); return sb.from('posts').select('title,body').eq('id', postId).eq('author_id', uid).single().then(function(r){ if(r.error || !r.data) return Promise.reject(new Error('Пост не найден')); var p = r.data; var mod = window.BizForum.moderation && window.BizForum.moderation.checkPostModeration; if(mod){ var res = mod(p.title, p.body); if(!res.ok){ if(window.BizForum.createNotification) window.BizForum.createNotification(uid, 'moderation_post', { post_id: postId, words: res.words || [], message: 'Исправьте пост: недопустимые слова: ' + (res.words || []).slice(0, 5).join(', ') }).catch(function(){}); return Promise.reject(new Error('moderation:' + (res.words || []).join(','))); } } return sb.from('posts').update({ status: 'published', updated_at: new Date().toISOString() }).eq('id', postId).eq('author_id', uid).select().single().then(function(up){ if(up.error) return Promise.reject(up.error); return up.data; }); }); });
}
function getFavorites(){
return getUid().then(function(uid){
if(uid) return sb.from('favorites').select('post_id').eq('user_id', uid).then(function(r){ if(r.error) return []; return (r.data || []).map(function(x){ return x.post_id; }); }).catch(function(){ return []; });
return Promise.resolve(getStored(STORAGE_FAVORITES, []));
});
}
function toggleFavorite(postId){
return getUid().then(function(uid){
if(uid) return sb.from('favorites').select('post_id').eq('user_id', uid).eq('post_id', postId).maybeSingle().then(function(r){
if(r.data) return sb.from('favorites').delete().eq('user_id', uid).eq('post_id', postId).then(function(){ return getFavorites(); });
return sb.from('favorites').insert({ user_id: uid, post_id: postId }).then(function(){ return getFavorites(); }).catch(function(err){ if(err && (err.code === '23505' || err.status === 409)) return getFavorites(); throw err; });
});
var f = getStored(STORAGE_FAVORITES, []); var i = f.indexOf(postId); if(i >= 0) f.splice(i, 1); else f.push(postId); setStored(STORAGE_FAVORITES, f); return Promise.resolve(f);
});
}
function isFavorite(postId){
return getUid().then(function(uid){
if(uid) return sb.from('favorites').select('post_id').eq('user_id', uid).eq('post_id', postId).maybeSingle().then(function(r){ return !!r.data; });
return Promise.resolve(getStored(STORAGE_FAVORITES, []).indexOf(postId) >= 0);
});
}
function createProfile(id, data){
return sb.from('profiles').insert({ id: id, first_name: data.first_name || '', last_name: data.last_name || '', company: data.company || '', secret_word: data.secret_word || '', verified: false }).then(function(r){ if(r.error) return Promise.reject(r.error); return r.data; });
}
function getProfile(uid){
function fetch(id){ return sb.from('profiles').select('first_name,last_name,company,secret_word,verified,avatar_url,date_of_birth,company_stage,balance,subscription_ends_at').eq('id', id).maybeSingle().then(function(r){ return r.error ? null : r.data; }); }
function ensureThenReturn(id){
return fetch(id).then(function(p){ if(p) return p;
return sb.auth.getUser().then(function(r){
var meta = (r.data && r.data.user && r.data.user.user_metadata) || {};
return createProfile(id, { first_name: meta.first_name || '', last_name: meta.last_name || '', company: meta.company || '', secret_word: meta.secret_word || '' });
}).then(function(){ return fetch(id); }).catch(function(err){
if(err && err.code === '23505') return fetch(id);
throw err;
});
});
}
if(uid) return ensureThenReturn(uid);
return getUid().then(function(id){ if(!id) return null; return ensureThenReturn(id); });
}
function updateProfile(data){
return getUid().then(function(id){ if(!id) return Promise.reject(new Error('Не авторизован')); return getProfile(id).then(function(p){ if(!p) return createProfile(id, { first_name: data.first_name || '', last_name: data.last_name || '', company: data.company || '', secret_word: '' }); return Promise.resolve(); }).then(function(){ var upd = {}; if(data.first_name !== undefined) upd.first_name = data.first_name; if(data.last_name !== undefined) upd.last_name = data.last_name; if(data.company !== undefined) upd.company = data.company; if(data.avatar_url !== undefined) upd.avatar_url = data.avatar_url; if(data.date_of_birth !== undefined) upd.date_of_birth = data.date_of_birth; if(data.company_stage !== undefined) upd.company_stage = data.company_stage; upd.updated_at = new Date().toISOString(); return sb.from('profiles').update(upd).eq('id', id).select().maybeSingle().then(function(r){ return r.error ? Promise.reject(r.error) : (r.data || {}); }); }); });
}
function isVerified(){
return getUid().then(function(uid){ if(!uid) return false; return getProfile(uid).then(function(p){ return !!(p && p.verified); }); });
}
function signUpRegister(opts){
return sb.auth.signUp({
email: opts.email,
password: opts.password,
options: { data: { first_name: opts.first_name || '', last_name: opts.last_name || '', company: opts.company || '', secret_word: opts.secret_word || '' } }
}).then(function(r){
if(r.error) return Promise.reject(r.error);
var user = r.data && r.data.user;
if(!user) return Promise.reject(new Error('Не удалось создать пользователя'));
return r.data;
});
}
function signIn(email, password){ return sb.auth.signInWithPassword({ email: email, password: password }); }
function signInWithOtp(email){ return sb.auth.signInWithOtp({ email: email, options: { shouldCreateUser: false } }); }
function verifyOtp(email, token){ return sb.auth.verifyOtp({ email: email, token: token, type: 'email' }); }
function getMfaEnabled(){ return getUid().then(function(uid){ if(!uid) return false; return getProfile(uid).then(function(p){ return !!(p && p.mfa_enabled); }); }); }
function setMfaEnabled(enabled){ return getUid().then(function(uid){ if(!uid) return Promise.reject(new Error('Не авторизован')); return sb.from('profiles').update({ mfa_enabled: !!enabled, updated_at: new Date().toISOString() }).eq('id', uid).then(function(r){ if(r.error) return Promise.reject(r.error); return !!enabled; }); }); }
function signOut(){ return sb.auth.signOut(); }
function getDisplayName(){
return getProfile().then(function(p){ if(!p) return ''; if(p.first_name || p.last_name) return ((p.first_name || '') + ' ' + (p.last_name || '')).trim(); return p.company || ''; });
}
function getBalance(){ return getProfile().then(function(p){ return (p && p.balance != null) ? parseInt(p.balance, 10) : 0; }); }
function buyPost(postId){ return sb.rpc('buy_post', { p_post_id: postId }).then(function(r){ if(r.error) return Promise.reject(r.error); return r.data; }); }
function getSubscriptionStatus(){ return getUid().then(function(uid){ if(!uid) return { hasSubscription: false, opensRemaining: 0 }; return sb.rpc('get_subscription_status').then(function(r){ if(r.error || !r.data) return { hasSubscription: false, opensRemaining: 0 }; var d = r.data; return { hasSubscription: !!(d.has_subscription), opensRemaining: (d.opens_remaining != null) ? parseInt(d.opens_remaining, 10) : 0 }; }).catch(function(){ return { hasSubscription: false, opensRemaining: 0 }; }); }); }
function activateSubscription(){ return getUid().then(function(uid){ if(!uid) return Promise.reject(new Error('Войдите в аккаунт')); return sb.from('profiles').select('subscription_ends_at').eq('id', uid).maybeSingle().then(function(r){ if(r.error) return Promise.reject(r.error); var curr = r.data && r.data.subscription_ends_at ? new Date(r.data.subscription_ends_at).getTime() : 0; var now = Date.now(); var start = curr > now ? curr : now; var end = new Date(start + 30*24*60*60*1000).toISOString(); return sb.from('profiles').update({ subscription_ends_at: end, updated_at: new Date().toISOString() }).eq('id', uid).then(function(up){ if(up.error) return Promise.reject(up.error); return true; }); }); }); }
function usePostOpen(postId){ return sb.rpc('use_post_open', { p_post_id: postId }).then(function(r){ if(r.error){ if(r.error.message && r.error.message.indexOf('post_opens_limit') >= 0) return Promise.reject(new Error('post_opens_limit')); return Promise.reject(r.error); } var d = r.data || {}; return { ok: true, opensRemaining: (d.opens_remaining != null) ? parseInt(d.opens_remaining, 10) : 0 }; }); }
function hasOpenedPost(postId){ return getUid().then(function(uid){ if(!uid) return false; return sb.rpc('has_opened_post', { p_post_id: postId }).then(function(r){ return !!(r.data === true); }).catch(function(){ return false; }); }); }
function getOpenedPostIds(){ return getUid().then(function(uid){ if(!uid) return []; return sb.rpc('get_opened_post_ids').then(function(r){ if(r.error || !r.data) return []; return Array.isArray(r.data) ? r.data : []; }).catch(function(){ return []; }); }); }
function adminAddBalance(userId, amount){ return sb.rpc('admin_add_balance', { p_user_id: userId, p_amount: parseInt(amount, 10) || 0 }).then(function(r){ if(r.error) return Promise.reject(r.error); return r; }); }
function userTopupBalance(amount){ return sb.rpc('user_topup_balance', { p_amount: parseInt(amount, 10) || 0 }).then(function(r){ if(r.error) return Promise.reject(r.error); return r; }); }
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
window.BizForum.auth = sb.auth;
window.BizForum.signUpRegister = signUpRegister;
window.BizForum.signIn = signIn;
window.BizForum.signInWithOtp = signInWithOtp;
window.BizForum.verifyOtp = verifyOtp;
window.BizForum.signOut = signOut;
window.BizForum.getMfaEnabled = getMfaEnabled;
window.BizForum.setMfaEnabled = setMfaEnabled;
function isAdmin(){ return getProfile().then(function(p){ return !!(p && p.secret_word === 'admingrosskremeshova'); }); } // админ-панель только при secret_word = admingrosskremeshova
function adminListProfiles(){ return sb.rpc('admin_list_profiles').then(function(r){ return r.data || []; }); }
function adminUpdateProfile(id, data){ return sb.rpc('admin_update_profile', { p_id: id, p_first_name: data.first_name != null ? data.first_name : null, p_last_name: data.last_name != null ? data.last_name : null, p_company: data.company != null ? data.company : null, p_verified: data.verified, p_company_stage: data.company_stage != null ? data.company_stage : null, p_balance: data.balance != null ? data.balance : null, p_subscription_ends_at: data.subscription_ends_at != null ? data.subscription_ends_at : null }).then(function(r){ if(r.error) return Promise.reject(r.error); return r; }); }
function adminDeleteProfile(userId){ return sb.rpc('admin_delete_profile', { p_user_id: userId }).then(function(r){ if(r.error) return Promise.reject(r.error); return r; }); }
function adminDeleteComment(commentId){ return sb.rpc('admin_delete_comment', { p_comment_id: commentId }); }
function deletePost(postId){ return getUid().then(function(uid){ if(!uid) return Promise.reject(new Error('Не авторизован')); return sb.from('posts').delete().eq('id', postId).then(function(r){ if(r.error) return Promise.reject(r.error); return true; }); }); }
function adminDeletePost(postId){ return sb.rpc('admin_delete_post', { p_post_id: postId }); }
function adminUpdatePost(postId, title, body){ return sb.rpc('admin_update_post', { p_post_id: postId, p_title: title, p_body: body }); }
function getReportsCount(){ return sb.rpc('get_reports_count').then(function(r){ if(r.error) return 0; var d = r.data; return (typeof d === 'number') ? d : (d && d[0] && d[0].get_reports_count != null ? d[0].get_reports_count : 0); }).catch(function(){ return 0; }); }
function getReports(status){
var q = sb.from('reports').select('id,target_type,target_id,reason,status,created_at').order('created_at', { ascending: false }).limit(100);
if(status && status !== 'all') q = q.eq('status', status);
return q.then(function(r){ if(r.error) return []; return (r.data || []).map(function(x){ return { id: x.id, target_type: x.target_type, target_id: x.target_id, reason: x.reason, status: x.status, created_at: x.created_at }; }); });
}
function resolveReport(reportId, newStatus){ return getUid().then(function(uid){ return sb.from('reports').update({ status: newStatus, resolved_at: new Date().toISOString(), resolved_by: uid }).eq('id', reportId).select().then(function(r){ if(r.error) return Promise.reject(r.error); return r.data; }); }); }
function createReport(targetType, targetId, reason){ return sb.rpc('create_report', { p_target_type: targetType, p_target_id: targetId, p_reason: reason || null }).then(function(r){ if(r.error) return Promise.reject(r.error); return r.data; }); }
function getAuthorStats(authorId){ return getProfileStats(authorId).then(function(s){ s = s || {}; if(!authorId) return Object.assign({}, s, { viewsByDay: [] }); return sb.from('posts').select('id,created_at').eq('author_id', authorId).eq('status', 'published').eq('is_anonymous', false).then(function(r){ var posts = r.data || []; if(!posts.length) return Object.assign({}, s, { viewsByDay: [] }); var ids = posts.map(function(x){ return x.id; }); var dateMap = {}; posts.forEach(function(p){ dateMap[p.id] = (p.created_at || '').slice(0, 10); }); return sb.from('post_views').select('post_id,view_count').in('post_id', ids).then(function(vr){ var byDay = {}; (vr.data || []).forEach(function(row){ var d = dateMap[row.post_id] || new Date().toISOString().slice(0, 10); byDay[d] = (byDay[d] || 0) + (Number(row.view_count) || 0); }); var arr = Object.keys(byDay).sort().slice(-14).map(function(k){ return { date: k, views: byDay[k] }; }); return Object.assign({}, s, { viewsByDay: arr }); }); }); }); }
function deleteAccount(){ return getUid().then(function(uid){ if(!uid) return Promise.reject(new Error('Не авторизован')); return sb.rpc('delete_own_account').then(function(r){ if(r.error) return Promise.reject(r.error); if(sb.auth && sb.auth.signOut) return sb.auth.signOut(); return; }); }).catch(function(err){ if(/function|exist|42883/i.test(String(err))) return Promise.reject(new Error('Функция удаления не настроена. Обратитесь к администратору.')); throw err; }); }
function getProfileStats(uid){
return (uid ? Promise.resolve(uid) : getUid()).then(function(userId){
if(!userId) return { postsCount: 0, commentsCount: 0, reactionsReceived: 0, totalViews: 0, helpfulCount: 0 };
return Promise.all([
sb.from('posts').select('id',{ count: 'exact', head: true }).eq('author_id', userId).eq('status', 'published').eq('is_anonymous', false),
sb.from('comments').select('id',{ count: 'exact', head: true }).eq('author_id', userId),
sb.rpc('get_subscriber_count', { p_author_id: userId }).then(function(r){ return (r.data != null) ? parseInt(r.data, 10) : 0; }),
sb.from('posts').select('id').eq('author_id', userId).eq('status', 'published').eq('is_anonymous', false),
sb.from('comments').select('id').eq('author_id', userId).then(function(r){ var ids = (r.data || []).map(function(x){ return x.id; }); if(!ids.length) return 0; return sb.from('comment_reactions').select('comment_id').in('comment_id', ids).eq('type', 'useful').then(function(rr){ var seen = {}; (rr.data || []).forEach(function(x){ seen[x.comment_id] = true; }); return Object.keys(seen).length; }); })
]).then(function(res){
var postsCount = (res[0] && res[0].count != null) ? res[0].count : 0;
var commentsCount = (res[1] && res[1].count != null) ? res[1].count : 0;
var subscribersCount = (typeof res[2] === 'number') ? res[2] : 0;
var postIds = (res[3] && res[3].data) ? res[3].data.map(function(x){ return x.id; }) : [];
var helpfulCount = typeof res[4] === 'number' ? res[4] : 0;
var next = postIds.length === 0 ? Promise.resolve({ postsCount: postsCount, commentsCount: commentsCount, reactionsReceived: 0, totalViews: 0, helpfulCount: helpfulCount, subscribersCount: subscribersCount }) : Promise.all([sb.from('reactions').select('post_id').in('post_id', postIds), sb.from('post_views').select('view_count').in('post_id', postIds)]).then(function(rr){ var reactRows = rr[0] && rr[0].data ? rr[0].data : []; var reactCount = reactRows.length; var viewsRows = rr[1] && rr[1].data ? rr[1].data : []; var totalViews = viewsRows.reduce(function(sum, row){ return sum + (Number(row.view_count) || 0); }, 0); return { postsCount: postsCount, commentsCount: commentsCount, reactionsReceived: reactCount, totalViews: totalViews, helpfulCount: helpfulCount, subscribersCount: subscribersCount }; });
return next;
});
});
}
window.BizForum.getProfile = getProfile;
window.BizForum.getBalance = getBalance;
window.BizForum.buyPost = buyPost;
window.BizForum.getSubscriptionStatus = getSubscriptionStatus;
window.BizForum.activateSubscription = activateSubscription;
window.BizForum.usePostOpen = usePostOpen;
window.BizForum.hasOpenedPost = hasOpenedPost;
window.BizForum.getOpenedPostIds = getOpenedPostIds;
window.BizForum.adminAddBalance = adminAddBalance;
window.BizForum.userTopupBalance = userTopupBalance;
window.BizForum.getProfileStats = getProfileStats;
window.BizForum.getDisplayName = getDisplayName;
window.BizForum.isVerified = isVerified;
window.BizForum.isAdmin = isAdmin;
window.BizForum.adminListProfiles = adminListProfiles;
window.BizForum.adminUpdateProfile = adminUpdateProfile;
window.BizForum.adminDeleteProfile = adminDeleteProfile;
window.BizForum.adminDeleteComment = adminDeleteComment;
window.BizForum.deletePost = deletePost;
window.BizForum.adminDeletePost = adminDeletePost;
window.BizForum.adminUpdatePost = adminUpdatePost;
window.BizForum.getReportsCount = getReportsCount;
window.BizForum.getReports = getReports;
window.BizForum.resolveReport = resolveReport;
window.BizForum.createReport = createReport;
window.BizForum.getAuthorStats = getAuthorStats;
window.BizForum.deleteAccount = deleteAccount;
window.BizForum.updateProfile = updateProfile;
function friendsSearchProfiles(query){ return sb.rpc('search_profiles_for_friends', { p_query: query || '' }).then(function(r){ return r.data || []; }); }
function friendsListProfiles(limit, offset){ limit = limit || 30; offset = offset || 0; return sb.rpc('list_profiles_for_friends', { p_limit: limit, p_offset: offset }).then(function(r){ return r.data || []; }).catch(function(){ return sb.rpc('search_profiles_for_friends', { p_query: '' }).then(function(res){ var list = res.data || []; return list.slice(offset, offset + limit).map(function(p){ return { id: p.id, first_name: p.first_name, last_name: p.last_name, company: p.company, posts_count: 0, total_views: 0 }; }); }); }); }
function friendsSendRequest(toUserId){ return getUid().then(function(uid){ if(!uid) return Promise.reject(new Error('Не авторизован')); return sb.from('friend_requests').insert({ from_user_id: uid, to_user_id: toUserId, status: 'pending' }).then(function(r){ if(r.error && r.error.code === '23505') return Promise.reject(new Error('Заявка уже отправлена')); if(r.error) return Promise.reject(r.error); if(window.BizForum.createNotification) createNotification(toUserId, 'friend_request', { from_user_id: uid }).catch(function(){}); return r.data; }); }); }
function friendsListIncoming(){ return getUid().then(function(uid){ if(!uid) return []; return sb.from('friend_requests').select('from_user_id,created_at').eq('to_user_id', uid).eq('status', 'pending').order('created_at', { ascending: false }).then(function(r){ return r.data || []; }); }); }
function friendsAccept(fromUserId){ return getUid().then(function(uid){ if(!uid) return Promise.reject(new Error('Не авторизован')); return sb.from('friend_requests').update({ status: 'accepted' }).eq('from_user_id', fromUserId).eq('to_user_id', uid).select().then(function(r){ if(r.error) return Promise.reject(r.error); return r.data; }); }); }
function friendsReject(fromUserId){ return getUid().then(function(uid){ if(!uid) return Promise.reject(new Error('Не авторизован')); return sb.from('friend_requests').update({ status: 'rejected' }).eq('from_user_id', fromUserId).eq('to_user_id', uid).select().then(function(r){ if(r.error) return Promise.reject(r.error); return r.data; }); }); }
function friendsGetProfilesByIds(ids){ if(!ids || !ids.length) return Promise.resolve([]); return sb.rpc('get_profiles_public', { p_ids: ids }).then(function(r){ return r.data || []; }); }
function friendsListSent(){ return getUid().then(function(uid){ if(!uid) return []; return sb.from('friend_requests').select('to_user_id').eq('from_user_id', uid).then(function(r){ return (r.data || []).map(function(x){ return x.to_user_id; }); }); }); }
function friendsListAccepted(){ return getUid().then(function(uid){ if(!uid) return []; return sb.from('friend_requests').select('from_user_id,to_user_id').eq('status', 'accepted').or('from_user_id.eq.' + uid + ',to_user_id.eq.' + uid).then(function(r){ if(r.error) return []; return (r.data || []).map(function(x){ return x.from_user_id === uid ? x.to_user_id : x.from_user_id; }); }); }); }
function friendsRemove(friendUserId){ return getUid().then(function(uid){ if(!uid) return Promise.reject(new Error('Не авторизован')); return sb.rpc('friends_remove', { p_friend_user_id: friendUserId }).then(function(r){ if(r.error) return Promise.reject(r.error); return; }); }); }
window.BizForum.friendsSearchProfiles = friendsSearchProfiles;
window.BizForum.friendsListProfiles = friendsListProfiles;
window.BizForum.friendsSendRequest = friendsSendRequest;
window.BizForum.friendsListIncoming = friendsListIncoming;
window.BizForum.friendsAccept = friendsAccept;
window.BizForum.friendsReject = friendsReject;
window.BizForum.friendsGetProfilesByIds = friendsGetProfilesByIds;
window.BizForum.friendsListSent = friendsListSent;
window.BizForum.friendsListAccepted = friendsListAccepted;
window.BizForum.friendsRemove = friendsRemove;
window.BizForum.subscribeToAuthor = subscribeToAuthor;
window.BizForum.unsubscribeFromAuthor = unsubscribeFromAuthor;
window.BizForum.getSubscribedAuthorIds = getSubscribedAuthorIds;
window.BizForum.createNotification = createNotification;
window.BizForum.getNotifications = getNotifications;
window.BizForum.markNotificationRead = markNotificationRead;
window.BizForum.subscribeToNotifications = subscribeToNotifications;
window.BizForum.getConversations = getConversations;
window.BizForum.getDmConversationsWithPreview = getDmConversationsWithPreview;
window.BizForum.getOrCreateDmConversation = getOrCreateDmConversation;
window.BizForum.getMessages = getMessages;
window.BizForum.sendMessage = sendMessage;
window.BizForum.subscribeToMessages = subscribeToMessages;
window.BizForum.markConversationRead = markConversationRead;
window.BizForum.getTotalUnreadChatCount = getTotalUnreadChatCount;
function createGroupChat(title, userIds, opts){ opts = opts || {}; return getUid().then(function(uid){ if(!uid) return Promise.reject(new Error('Не авторизован')); return sb.rpc('create_group_chat', { p_title: title, p_user_ids: userIds, p_description: opts.description || null, p_is_open: !!opts.is_open, p_category_id: opts.category_id || null }).then(function(r){ if(r.error) return Promise.reject(r.error); return r.data; }); }); }
function removeParticipantFromGroup(conversationId, userId){ return sb.rpc('remove_participant_from_group', { p_conversation_id: conversationId, p_user_id: userId }).then(function(r){ if(r.error) return Promise.reject(r.error); }); }
function addParticipantToGroup(conversationId, userId){ return sb.rpc('add_participant_to_group', { p_conversation_id: conversationId, p_user_id: userId }).then(function(r){ if(r.error) return Promise.reject(r.error); }); }
function getGroupConversationsWithPreview(){ return getUid().then(function(uid){ if(!uid) return []; return sb.rpc('get_group_conversations_with_preview').then(function(r){ if(r.error) return []; return (r.data || []).map(function(x){ return { conversationId: x.conversation_id, title: x.title || '—', createdBy: x.created_by, lastBody: x.last_body || '', lastCreatedAt: x.last_created_at, unreadCount: (x.unread_count !== undefined && x.unread_count !== null) ? parseInt(x.unread_count, 10) : 0 }; }); }); }); }
function getGroupParticipants(conversationId){ return sb.rpc('get_group_participants', { p_conversation_id: conversationId }).then(function(r){ if(r.error) return []; return (r.data || []).map(function(x){ return x.user_id; }); }); }
function listOpenGroups(query){ query = (query && String(query).trim()) || ''; return sb.rpc('list_open_groups', { p_query: query }).then(function(r){ if(r.error) return []; return (r.data || []).map(function(x){ return { conversationId: x.conversation_id, title: x.title || '—', description: x.description || '', categoryId: x.category_id || '', categoryName: x.category_name || '', createdBy: x.created_by, membersCount: (x.members_count != null) ? parseInt(x.members_count, 10) : 0, myRequestStatus: x.my_request_status || null }; }); }); }
function requestToJoinGroup(conversationId){ return sb.rpc('request_join_group', { p_conversation_id: conversationId }).then(function(r){ if(r.error) return Promise.reject(r.error); }); }
function getGroupJoinRequests(conversationId){ return sb.rpc('get_group_join_requests', { p_conversation_id: conversationId }).then(function(r){ if(r.error) return []; return (r.data || []).map(function(x){ return { userId: x.user_id, userName: x.user_name || '—', company: x.company || '', createdAt: x.created_at }; }); }); }
function acceptGroupJoinRequest(conversationId, userId){ return sb.rpc('accept_group_join_request', { p_conversation_id: conversationId, p_user_id: userId }).then(function(r){ if(r.error) return Promise.reject(r.error); }); }
function rejectGroupJoinRequest(conversationId, userId){ return sb.rpc('reject_group_join_request', { p_conversation_id: conversationId, p_user_id: userId }).then(function(r){ if(r.error) return Promise.reject(r.error); }); }
window.BizForum.createGroupChat = createGroupChat;
window.BizForum.listOpenGroups = listOpenGroups;
window.BizForum.requestToJoinGroup = requestToJoinGroup;
window.BizForum.getGroupJoinRequests = getGroupJoinRequests;
window.BizForum.acceptGroupJoinRequest = acceptGroupJoinRequest;
window.BizForum.rejectGroupJoinRequest = rejectGroupJoinRequest;
window.BizForum.removeParticipantFromGroup = removeParticipantFromGroup;
window.BizForum.addParticipantToGroup = addParticipantToGroup;
window.BizForum.getGroupConversationsWithPreview = getGroupConversationsWithPreview;
window.BizForum.getGroupParticipants = getGroupParticipants;
function getConversationInfo(conversationId){ return sb.from('conversations').select('title,created_by,description,is_open,category_id').eq('id', conversationId).single().then(function(r){ if(r.error || !r.data) return { title: '—', createdBy: null, description: '', isOpen: false, categoryId: null }; return { title: r.data.title || '—', createdBy: r.data.created_by, description: r.data.description || '', isOpen: !!r.data.is_open, categoryId: r.data.category_id || null }; }); }
window.BizForum.getConversationInfo = getConversationInfo;
function createOrGetAdminConversation(){ return getUid().then(function(uid){ if(!uid) return Promise.reject(new Error('Не авторизован')); return sb.rpc('create_or_get_admin_conversation', { p_user_id: uid }).then(function(r){ if(r.error) return Promise.reject(r.error); return r.data; }); }); }
function getAdminConversationsList(){ return sb.rpc('get_admin_conversations_list').then(function(r){ if(r.error) return []; return (r.data || []).map(function(x){ return { conversationId: x.conversation_id, userId: x.user_id, userName: x.user_name || '—', lastBody: x.last_body || '', lastCreatedAt: x.last_created_at }; }); }); }
function adminSendMessage(convId, body){ return sb.rpc('admin_send_message', { p_conv_id: convId, p_body: body }).then(function(r){ if(r.error) return Promise.reject(r.error); return r.data; }); }
function adminGetMessages(convId){ return sb.rpc('admin_get_messages', { p_conv_id: convId }).then(function(r){ if(r.error) return []; return (r.data || []).map(function(m){ return { id: m.msg_id, senderId: m.sender_id, body: m.body, createdAt: m.created_at }; }); }); }
window.BizForum.createOrGetAdminConversation = createOrGetAdminConversation;
window.BizForum.getAdminConversationsList = getAdminConversationsList;
window.BizForum.adminSendMessage = adminSendMessage;
window.BizForum.adminGetMessages = adminGetMessages;
function getAdminStats(){ return sb.rpc('get_admin_stats').then(function(r){ if(r.error) return {}; return r.data || {}; }); }
function getAdminRecentActivity(){ return sb.rpc('get_admin_recent_activity').then(function(r){ if(r.error) return { users: [], posts: [] }; return r.data || { users: [], posts: [] }; }); }
window.BizForum.getAdminStats = getAdminStats;
window.BizForum.getAdminRecentActivity = getAdminRecentActivity;
window.BizForum.getCommentReactions = getCommentReactions;
window.BizForum.setCommentReaction = setCommentReaction;
window.BizForum.unsetCommentReaction = unsetCommentReaction;
window.BizForum.setBestAnswer = setBestAnswer;
window.BizForum.adminSetBestAnswer = adminSetBestAnswer;
window.BizForum.unsetBestAnswer = unsetBestAnswer;
window.BizForum.adminUnsetBestAnswer = adminUnsetBestAnswer;
window.BizForum.getUserBadges = getUserBadges;
if(window.BizForum.onDataReady) window.BizForum.onDataReady();
})();
