ObjC.import('AppKit');ObjC.import('Foundation');
function read(path){var e=Ref(),s=$.NSString.stringWithContentsOfFileEncodingError($(path),$.NSUTF8StringEncoding,e);if(s.isNil())throw new Error('Missing GUI ownership');return JSON.parse(ObjC.unwrap(s));}
function write(path,value){var e=Ref();if(!$(JSON.stringify(value)).writeToFileAtomicallyEncodingError($(path),true,$.NSUTF8StringEncoding,e))throw new Error('Unable to record GUI cleanup');}
function instance(){var all=$.NSRunningApplication.runningApplicationsWithBundleIdentifier($('com.apple.Terminal'));if(Number(all.count)!==1)throw new Error('Terminal instance unavailable');var p=all.firstObject;return {pid:Number(p.processIdentifier),started:Number(p.launchDate.timeIntervalSince1970)};}
function targetWindows(app,id){var w=app.windows.byId(id);try{return w.exists()?[w]:[];}catch(e){if(missing(e))return [];throw e;}}
function missing(e){return e.errorNumber===-1728 || /Can't get object|not found/i.test(String(e.message));}
function isClosed(app,id){try{var values=targetWindows(app,id);if(values.length===0)return true;var tabs=values[0].tabs();return !tabs || tabs.length===0;}catch(e){if(missing(e))return true;throw e;}}
function run(argv){
  var app=Application('com.apple.Terminal');
  if(argv[0]==='claim'){
    var request=read(argv[1]),tty=argv[2],matches=[];
    if($.NSFileManager.defaultManager.fileExistsAtPath($(request.owner)))throw new Error('GUI job already claimed');
    var all=app.windows(),candidates=all.length?[all[0]]:[];
    function match(w){var stable=app.windows.byId(w.id()),tabs=stable.tabs()||[];tabs.forEach(function(t){if(t.busy() && t.tty()===tty)matches.push({w:stable,t:t,count:tabs.length});});}
    candidates.forEach(match);
    if(matches.length===0)all.slice(1).forEach(match);
    if(matches.length!==1 || matches[0].count!==1)throw new Error('GUI runner requires its own single-tab window');
    var picked=matches[0],identity=instance();picked.t.customTitle='EXMC-GUI-'+request.token;
    write(request.owner,{token:request.token,window_id:picked.w.id(),tty:tty,title:'EXMC-GUI-'+request.token,pid:identity.pid,started:identity.started});
    return;
  }
  var request=read(argv[1]),owner=read(request.owner),result={token:request.token,ok:false};
  try{
    if(owner.token!==request.token)throw new Error('GUI ownership token changed');
    var actual=instance();
    if(actual.pid!==owner.pid || actual.started!==owner.started)throw new Error('Terminal instance changed');
    var windows=targetWindows(app,owner.window_id);
    if(windows.length===0){result.ok=true;result.status='already_closed';}
    else{
      if(windows.length!==1)throw new Error('Ambiguous Terminal window');
      var w=windows[0],tabs=w.tabs()||[];
      if(tabs.length!==1 || tabs[0].tty()!==owner.tty || tabs[0].customTitle()!==owner.title)throw new Error('Terminal window ownership changed');
      for(var i=0;i<100 && tabs[0].busy();i++)delay(0.05);
      if(tabs[0].busy())throw new Error('Terminal remains busy; preserving it');
      if(request.keep_window){result.ok=true;result.status='retained';}
      else{app.close(w,{saving:'no'});delay(0.1);if(!isClosed(app,owner.window_id))throw new Error('Terminal window did not close');result.ok=true;result.status='closed';}
    }
  }catch(error){result.error=String(error.message||error);}
  if(!request.keep_window && request.previous_focus){
    try{var current=$.NSWorkspace.sharedWorkspace.frontmostApplication;
      if(!current.isNil() && ObjC.unwrap(current.bundleIdentifier)==='com.apple.Terminal'){
        var previous=$.NSRunningApplication.runningApplicationWithProcessIdentifier(request.previous_focus.pid);
        if(!previous.isNil() && Number(previous.launchDate.timeIntervalSince1970)===request.previous_focus.started)previous.activateWithOptions($.NSApplicationActivateIgnoringOtherApps);
      }
    }catch(e){result.ok=false;result.error='GUI focus restoration failed';}
  }
  write(request.cleanup,result);
}
