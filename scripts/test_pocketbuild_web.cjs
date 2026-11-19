"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

class Element {
    constructor(id) { this.id=id; this.children=[]; this.value=""; this.hidden=false; this.disabled=false; this.textContent=""; }
    replaceChildren(...items) { this.children=items; if (this.id==="project") this.value=""; }
    append(item) { this.children.push(item); }
    add(option) { this.children.push(option); if (!this.value) this.value=option.value; }
    setAttribute(name,value) { this[name]=value; }
    click() { if (this.onclick) return this.onclick(); }
}
const elements = new Map();
const element = id => {
    if (!elements.has(id)) elements.set(id,new Element(id));
    return elements.get(id);
};
const files = new Map([["Tweak.m","#import <Foundation/Foundation.h>"], ["MobileCompiler.json", JSON.stringify({
    productName:"Demo", sources:["Tweak.m"], customOption:"preserved", package:false, exportDylib:true
})]]);
const uploads = new Map();
const requests = [];
let sequence=0;
let failChunk=false;
let job={state:"idle",artifacts:[]};
let downloadRoute="";
const context = {
    console, Blob, URL, setTimeout: callback => callback(), setInterval: () => {},
    window:{addEventListener:()=>{}}, sessionStorage:{getItem:()=>null,setItem:()=>{},removeItem:()=>{}},
    document:{getElementById:element,createElement:tag=>new Element(tag)},
    Option:class { constructor(text,value) { this.text=text;this.value=value; } },
    confirm:()=>true,prompt:()=>"NewProject",
    FileReader:class {
        readAsDataURL(blob) {
            blob.arrayBuffer().then(bytes => {
                this.result="data:application/octet-stream;base64,"+Buffer.from(bytes).toString("base64");
                this.onload();
            }).catch(error=>this.onerror(error));
        }
    },
    fetch:async (route,request) => {
        if (route.startsWith("/download")) {downloadRoute=route;return {ok:true,status:200,blob:async()=>new Blob(["artifact"])};}
        const body=JSON.parse(request.body);
        requests.push(body);
        let status=200, result={};
        switch(body.action) {
            case "projects": result={projects:[{id:"p1",name:"Demo"}]}; break;
            case "files": result={files:[...files.keys()]}; break;
            case "read": result={content:files.get(body.path)}; break;
            case "tools": result={compilerBundled:true}; break;
            case "create": result={id:"p1"};break;
            case "job": result=job; break;
            case "upload_begin":
                result={upload:String(++sequence)};
                uploads.set(result.upload,{path:body.path,bytes:Buffer.alloc(0)});
                break;
            case "upload_chunk": {
                if(failChunk && body.offset>0) {status=500;result={error:"disk full fixture"};break;}
                const upload=uploads.get(body.upload);
                assert.equal(body.offset,upload.bytes.length);
                upload.bytes=Buffer.concat([upload.bytes,Buffer.from(body.data,"base64")]);
                result={offset:upload.bytes.length};
                break;
            }
            case "upload_finish": {
                const upload=uploads.get(body.upload);
                assert.equal(body.size,upload.bytes.length);
                files.set(upload.path,upload.bytes.toString("utf8"));
                uploads.delete(body.upload);
                result={saved:true};
                break;
            }
            case "upload_abort": uploads.delete(body.upload);result={aborted:true};break;
            case "build": job={id:"build-active",state:"running",stage:"clang",artifacts:[],log:"compiling"};result={id:job.id,state:"running"};break;
            case "cancel": job={state:"cancelled",artifacts:[],log:"cancelled"};result={state:"cancelling"};break;
            default: throw new Error("Unexpected action "+body.action);
        }
        return {ok:status===200,status,json:async()=>result};
    },
};
vm.createContext(context);
vm.runInContext(fs.readFileSync(path.join(__dirname,"../Resources/BuildWeb/app.js"),"utf8"),context);
async function main() {
    element("code").value="pairing-code";
    await element("connect-form").onsubmit();
    assert.equal(element("workspace").hidden,false);
    assert.equal(element("project").value,"p1");
    element("product-type").value="app";
    await element("create").onclick();
    assert.equal(requests.find(item=>item.action==="create").productType,"app");
    await element("files").children[0].children[0].onclick();
    element("content").value="中文源码\nvoid test(void) {}";
    element("content").oninput();
    await element("save").onclick();
    assert.equal(files.get("Tweak.m"),element("content").value);
    assert.equal(uploads.size,0);
    element("option-product").value="tweak";
    element("option-dylib").checked=true;
    element("option-package").checked=true;
    for(const scheme of ["rootless","rootful","roothide"]) element("option-"+scheme).checked=true;
    element("option-cpu").value="arm64e";
    await element("options-form").onsubmit();
    const config=JSON.parse(files.get("MobileCompiler.json"));
    assert.deepEqual(config.packageSchemes,["rootless","rootful","roothide"]);
    assert.equal(config.exportDylib,true);
    assert.equal(config.package,true);
    assert.equal(config.cpuArchitecture,"arm64e");
    assert.deepEqual(config.sources,["Tweak.m"]);
    assert.equal(config.customOption,"preserved");
    element("option-dylib").checked=false;
    element("option-package").checked=false;
    await element("options-form").onsubmit();
    assert.match(element("message").textContent,/请选择独立 dylib 或 DEB/);
    assert.equal(files.get("MobileCompiler.json"),JSON.stringify(config,null,2)+"\n");
    const blob=new Blob(["x".repeat(1200000)]);
    blob.name="Large.mm";
    blob.webkitRelativePath="Demo/Large.mm";
    element("folder-input").files=[blob];
    const before=requests.length;
    await element("folder-input").onchange();
    const chunks=requests.slice(before).filter(item=>item.action==="upload_chunk");
    assert.equal(chunks.length,3);
    assert.deepEqual(chunks.map(item=>item.offset),[0,524288,1048576]);
    assert.equal(files.get("Large.mm").length,1200000);
    assert.equal(element("project").disabled,false);

    failChunk=true;
    element("folder-input").files=[blob];
    await element("folder-input").onchange();
    assert.equal(uploads.size,0);
    assert.equal(files.get("Large.mm").length,1200000);
    assert.equal(element("message").textContent,"disk full fixture");
    failChunk=false;
    await element("build").onclick();
    assert.equal(element("build").disabled,true);
    assert.equal(element("cancel").disabled,false);
    assert.match(element("job-state").textContent,/clang/);
    await element("cancel").onclick();
    assert.equal(requests.find(item=>item.action==="cancel").job_id,"build-active");
    await vm.runInContext("poll()",context);
    assert.equal(element("job-state").textContent,"已取消");
    job={id:"build-123",state:"succeeded",artifacts:["Demo-unsigned.ipa"],log:"done"};
    await vm.runInContext("poll()",context);
    assert.equal(element("artifacts").children.length,1);
    await element("artifacts").children[0].onclick();
    assert.equal(downloadRoute,"/download?file=Demo-unsigned.ipa&job=build-123");
    console.log("PASS: browser connection, UTF-8 save, multi-chunk folder upload, failed-upload abort, build/cancel, artifact download.");
}
main().catch(error=>{console.error(error);process.exitCode=1;});
