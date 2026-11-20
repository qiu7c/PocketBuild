"use strict";
const element = id => document.getElementById(id);
let token = sessionStorage.getItem("buildCode") || "";
let project = "";
let filename = "";
let dirty = false;
let running = false;
let polling = false;
let uploading = false;
let generation = 0;
let currentJob = "";
let selectedJob = "";
let projectRows = [];
let currentIssue = null;
let outputKey = "";
let artifactKey = "";
let outputTab = "log";
let lineCount = 0;
let folders = new Map();
const sourceButtons = new Map();
const outputTabs = ["problems", "log", "artifacts"];
const buildStates = {
    idle: "无构建任务", running: "正在编译", succeeded: "编译成功",
    failed: "编译失败", cancelled: "已取消", interrupted: "已中断"
};

function message(text) {
    const pairing = !element("login").hidden;
    element("message").textContent = pairing ? "" : text;
    element("pairing-message").textContent = pairing ? text : "";
}
function showOutput(name) {
    outputTab = name;
    element("workspace").setAttribute("data-output", name);
    for (const tab of outputTabs) {
        const selected = tab === name;
        element("tab-" + tab).setAttribute("aria-selected", String(selected));
        element("tab-" + tab).tabIndex = selected ? 0 : -1;
        element("panel-" + tab).hidden = !selected;
    }
}
function showSidebar(open) {
    element("sidebar").setAttribute("data-open", String(open));
    element("sidebar-toggle").setAttribute("aria-expanded", String(open));
    if (!open) element("project-menu").open = false;
}
function refreshEditor() {
    const editor = element("content");
    element("unsaved").hidden = !dirty;
    element("save").disabled = !dirty;
    element("editor-empty").hidden = Boolean(filename);
    editor.hidden = element("line-numbers").hidden = !filename;
    const count = filename ? editor.value.split("\n").length : 0;
    if (lineCount !== count) {
        lineCount = count;
        element("line-numbers").textContent = Array.from({length: count}, (_, index) => index + 1).join("\n");
    }
    element("line-numbers").scrollTop = editor.scrollTop;
}
async function api(action, data = {}) {
    const response = await fetch("/api/v1/workspace", {
        method: "POST", headers: {"Content-Type":"application/json", Authorization:"Bearer " + token},
        body: JSON.stringify({action, ...data})
    });
    let result;
    try { result = await response.json(); }
    catch { throw new Error("请求失败，HTTP " + response.status); }
    if (!response.ok) {
        const error = new Error(typeof result.error === "string" ? result.error : "HTTP " + response.status);
        error.status = response.status;
        throw error;
    }
    return result;
}
function handle(action) {
    return async event => {
        if (event) event.preventDefault();
        try { await action(); }
        catch (error) { message(error.message); }
    };
}
async function save() {
    if (!filename) return;
    await uploadBlob(project, filename, new Blob([element("content").value], {type:"text/plain;charset=utf-8"}));
    dirty = false;
    refreshEditor();
    if (filename === "MobileCompiler.json") await listFiles();
    message("已保存 " + filename);
}
async function leaveFile() {
    if (!dirty) return;
    if (!confirm("当前文件有修改，保存后继续？")) throw new Error("操作已取消，修改仍在编辑器中");
    await save();
}
async function listFiles() {
    const result = await api("files", {project});
    const summary = result.summary;
    element("project-details").hidden = !summary;
    if (summary) {
        const product = (summary.productType || projectRows.find(item => item.id === project)?.productType) === "app" ? "UIKit App" : "插件";
        element("project-target").textContent = summary.sdk ? product + " · " + summary.sdk + " SDK · " + summary.cpu : product;
        element("project-outputs").textContent = summary.outputs?.join(" / ") || "";
        element("project-readiness").textContent = summary.issue?.message || "所需组件已就绪";
        element("project-readiness").setAttribute("data-state", summary.issue ? "failed" : "idle");
    }
    element("files").replaceChildren();
    const previousFolders = folders;
    folders = new Map();
    sourceButtons.clear();
    element("files-empty").hidden = result.files.length > 0;
    element("files-empty").textContent = "此项目还没有文件，可新建或上传源码。";
    for (const path of result.files) {
        const parts = path.split("/");
        const name = parts.pop();
        let parent = element("files");
        let directory = "";
        for (const part of parts) {
            directory += part + "/";
            if (!folders.has(directory)) {
                const row = document.createElement("li");
                const detail = document.createElement("details");
                const title = document.createElement("summary");
                title.textContent = part;
                title.title = directory;
                detail.open = previousFolders.get(directory)?.detail.open ?? true;
                const list = document.createElement("ul");
                detail.append(title, list);
                row.append(detail);
                parent.append(row);
                folders.set(directory, {detail, list});
            }
            parent = folders.get(directory).list;
        }
        const item = document.createElement("li");
        const button = document.createElement("button");
        button.textContent = name;
        button.title = path;
        button.setAttribute("aria-current", String(path === filename));
        button.onclick = handle(async () => {
            await openSource(path);
        });
        item.append(button);
        parent.append(item);
        sourceButtons.set(path, button);
    }
    element("options-fields").disabled = true;
    let config = {};
    if (result.files.includes("MobileCompiler.json")) {
        const manifest = await api("read", {project, path:"MobileCompiler.json"});
        try { config = JSON.parse(manifest.content); }
        catch { message("MobileCompiler.json 格式有误，请在编辑器修正后重新选择项目"); return; }
        if (!config || Array.isArray(config) || typeof config !== "object") {
            message("MobileCompiler.json 应为 JSON 对象"); return;
        }
    }
    const defaults = result.buildDefaults || {};
    const type = config.productType || summary?.productType || projectRows.find(item => item.id === project)?.productType || "tweak";
    element("option-product").value = type;
    element("tweak-options").hidden = type === "app";
    element("option-dylib").checked = (config.exportDylib ?? defaults.exportDylib) !== false;
    element("option-package").checked = result.files.includes("MobileCompiler.json") && (config.package ?? defaults.package) !== false;
    const schemes = config.packageSchemes ?? (config.packageScheme ? [config.packageScheme] : (defaults.packageSchemes || ["rootless"]));
    const selectedSchemes = Array.isArray(schemes) ? schemes : ["rootless"];
    for (const scheme of ["rootless", "rootful", "roothide"]) element("option-" + scheme).checked = selectedSchemes.includes(scheme);
    element("option-cpu").value = config.cpuArchitecture || "arm64";
    const sdk = config.sdkVersion || defaults.sdkVersion || "16.4";
    const minimum = defaults.deploymentTarget || "15.0";
    element("option-sdk").value = sdk;
    element("option-minimum").value = config.deploymentTarget || (parseFloat(minimum) > parseFloat(sdk) ? "15.0" : minimum);
    element("options-fields").disabled = false;
}
async function openSource(path) {
    await leaveFile();
    const file = await api("read", {project, path});
    displaySource(path, file.content);
}
function displaySource(path, content, {line, column, snapshot, currentAvailable} = {}) {
    sourceButtons.get(filename)?.setAttribute("aria-current", "false");
    filename = path;
    if (!snapshot) sourceButtons.get(path)?.setAttribute("aria-current", "true");
    element("filename").textContent = path;
    element("filename").title = path;
    element("source-context").hidden = !snapshot;
    element("edit-current").hidden = !snapshot || !currentAvailable;
    const editor = element("content");
    editor.value = content;
    editor.readOnly = Boolean(snapshot);
    editor.disabled = false;
    editor.setSelectionRange(0, 0);
    editor.scrollTop = editor.scrollLeft = 0;
    showSidebar(false);
    refreshEditor();
    editor.focus({preventScroll:true});
    if (line) {
        const lines = editor.value.split("\n");
        const row = Math.min(lines.length, Math.max(1, line)) - 1;
        const start = lines.slice(0, row).reduce((offset, value) => offset + value.length + 1, 0);
        let offset = start;
        let end = start + lines[row].length;
        if (column) {
            const encoder = new TextEncoder();
            let bytes = 0;
            for (const character of lines[row]) {
                bytes += encoder.encode(character).length;
                if (bytes >= column) { end = offset + character.length; break; }
                offset += character.length;
            }
        }
        editor.setSelectionRange(offset, end);
        const lineHeight = parseFloat(getComputedStyle(editor).lineHeight) || 20;
        editor.scrollTop = Math.max(0, row * lineHeight - (editor.clientHeight / 2));
        element("line-numbers").scrollTop = editor.scrollTop;
        message(snapshot ? "" : "当前源码与该次构建快照一致");
    }
}
async function listProjects(selected = project) {
    const result = await api("projects");
    projectRows = result.projects;
    const select = element("project");
    select.replaceChildren();
    for (const item of result.projects) {
        const type = item.productType === "app" ? "App" : "插件";
        select.add(new Option(item.name + " · " + type + " · " + item.id.slice(-6), item.id));
    }
    if (result.projects.some(item => item.id === selected)) select.value = selected;
    if (project !== select.value) folders.clear();
    project = select.value;
    element("project-menu").open = false;
    selectedJob = "";
    element("job-history").hidden = true;
    outputKey = "";
    showOutput("log");
    renderOutput({state:"idle"});
    filename = "";
    dirty = false;
    element("source-context").hidden = true;
    element("project-details").hidden = true;
    element("filename").textContent = "选择文件";
    element("filename").title = "选择文件";
    element("content").value = "";
    element("content").disabled = true;
    refreshEditor();
    for (const id of ["rename-project", "upload", "folder", "new-file", "load-history"]) element(id).disabled = !project;
    element("build").disabled = !project || running || uploading;
    if (project) {
        await listFiles();
    } else {
        element("files").replaceChildren();
        element("files-empty").hidden = false;
        element("files-empty").textContent = "在项目菜单中新建项目或导入源码。";
        element("options-fields").disabled = true;
    }
}
async function download(file, jobID) {
    const response = await fetch("/download?file=" + encodeURIComponent(file) + "&job=" + encodeURIComponent(jobID), {headers:{Authorization:"Bearer " + token}});
    if (!response.ok) throw new Error("下载失败，HTTP " + response.status);
    const url = URL.createObjectURL(await response.blob());
    const link = document.createElement("a");
    link.href = url;
    link.download = file;
    link.click();
    setTimeout(() => URL.revokeObjectURL(url), 60000);
}
function renderOutput(job) {
    element("job-state").textContent = (buildStates[job.state] || job.state) +
        (job.state === "running" && job.stage ? " · " + job.stage : "");
    element("job-state").setAttribute("data-state", job.state);
    element("cancel").hidden = element("cancel").disabled = job.state !== "running";
    currentIssue = job.issue || null;
    element("build-issue").hidden = element("problem-count").hidden = !currentIssue;
    element("issues-empty").hidden = Boolean(currentIssue);
    element("jump-to-error").hidden = !currentIssue?.file;
    if (currentIssue) {
        const location = currentIssue.file ? [currentIssue.file,currentIssue.line,currentIssue.column].filter(Boolean).join(":") + " — " : "";
        const instruction = currentIssue.kind === "components" ? "。在手机「构建」打开此记录，安装缺项后可直接重试。" : "";
        element("issue-message").textContent = location + currentIssue.message + instruction;
    }
    const log = job.log || "";
    const logView = element("log");
    logView.hidden = !log;
    element("log-empty").hidden = Boolean(log);
    if (logView.textContent !== log) {
        const panel = element("panel-log");
        const follow = outputTab === "log" && panel.scrollHeight - panel.clientHeight - panel.scrollTop < 12;
        logView.textContent = log;
        if (follow) panel.scrollTop = panel.scrollHeight;
    }
    const recorded = job.artifacts || [];
    element("download-log").hidden = !recorded.includes("build.log");
    element("download-report").hidden = !recorded.includes("report.json");
    element("log-downloads").hidden = element("download-log").hidden && element("download-report").hidden;
    const artifacts = job.products || recorded.filter(file => /\.(ipa|deb|dylib)$/i.test(file));
    element("artifact-count").textContent = artifacts.length;
    element("artifact-count").hidden = artifacts.length === 0;
    element("artifacts-empty").hidden = artifacts.length > 0;
    const key = JSON.stringify([job.id, artifacts]);
    if (artifactKey !== key) {
        artifactKey = key;
        element("artifacts").replaceChildren();
        for (const file of artifacts) {
            const button = document.createElement("button");
            const name = document.createElement("span");
            name.className = "artifact-name";
            name.textContent = file;
            const label = document.createElement("span");
            label.className = "download-label";
            label.textContent = "下载";
            button.append(name, label);
            button.onclick = handle(() => download(file, job.id));
            element("artifacts").append(button);
        }
    }
    const stateKey = JSON.stringify([job.id, job.state]);
    if (outputKey !== stateKey) {
        outputKey = stateKey;
        if (currentIssue) showOutput("problems");
        else if (artifacts.length && job.state === "succeeded") showOutput("artifacts");
        else showOutput("log");
    }
}
async function poll() {
    if (!token || polling) return;
    const current = generation;
    const selectedProject = project;
    const selectedBuild = selectedJob;
    polling = true;
    try {
        const job = await api("job", selectedBuild ? {job_id:selectedBuild} : selectedProject ? {project:selectedProject} : {});
        if (current !== generation || selectedProject !== project || selectedBuild !== selectedJob) return;
        currentJob = job.id || "";
        running = Boolean(job.activeJobId || job.state === "running");
        element("build").disabled = !project || running || uploading;
        renderOutput(job);
    } catch (error) {
        if (current === generation && selectedProject === project && selectedBuild === selectedJob) {
            if (error.status === 404 && selectedBuild) {
                selectedJob = "";
                element("job-history").hidden = true;
            }
            message(error.message);
        }
    }
    finally { polling = false; }
}
function fileData(file) {
    return new Promise((resolve,reject) => {
        const reader = new FileReader();
        reader.onload = () => resolve(reader.result.split(",")[1]);
        reader.onerror = () => reject(new Error("读取文件失败"));
        reader.readAsDataURL(file);
    });
}
async function uploadBlob(targetProject, path, file) {
    const task = await api("upload_begin", {project:targetProject, path});
    try {
        const chunkSize = 512 * 1024;
        for (let offset = 0; offset < file.size; offset += chunkSize) {
            const data = await fileData(file.slice(offset, offset + chunkSize));
            await api("upload_chunk", {upload:task.upload, offset, data});
        }
        await api("upload_finish", {upload:task.upload, size:file.size});
    } catch (error) {
        await api("upload_abort", {upload:task.upload}).catch(() => {});
        throw error;
    }
}
async function upload(files, directory) {
    if (!project) throw new Error("请先新建项目");
    await leaveFile();
    const targetProject = project;
    uploading = true;
    element("build").disabled = true;
    element("project").disabled = true;
    element("upload").disabled = true;
    element("folder").disabled = true;
    element("import-project").disabled = true;
    element("rename-project").disabled = true;
    element("create").disabled = true;
    try {
        for (const file of files) {
            const parts = file.webkitRelativePath ? file.webkitRelativePath.split("/") : [file.name];
            if (parts.some(part => [".git",".theos","DerivedData","__pycache__"].includes(part))) continue;
            const path = directory ? parts.slice(1).join("/") : file.name;
            message("正在上传 " + path);
            await uploadBlob(targetProject, path, file);
        }
        await listFiles();
        message("上传完成");
    } finally {
        uploading = false;
        element("build").disabled = running;
        element("project").disabled = false;
        element("upload").disabled = false;
        element("folder").disabled = false;
        element("import-project").disabled = false;
        element("rename-project").disabled = false;
        element("create").disabled = false;
    }
}

element("connect-form").onsubmit = handle(async () => {
    const button = element("connect");
    token = element("code").value.trim();
    button.disabled = true;
    button.textContent = "正在连接…";
    message("");
    try { await listProjects(); }
    finally {
        button.disabled = false;
        button.textContent = "连接";
    }
    sessionStorage.setItem("buildCode", token);
    element("login").hidden = true;
    element("workspace").hidden = false;
    element("disconnect").hidden = false;
    element("connection").textContent = "已连接";
    element("connection").setAttribute("data-state", "connected");
    const tools = await api("tools");
    message(tools.compilerBundled || tools.compilerLoaded ? "" :
        "已连接。请在手机工具链管理中检查组件安装状态。");
    await poll();
});
element("disconnect").onclick = handle(async () => {
    await leaveFile();
    generation++;
    token = "";
    sessionStorage.removeItem("buildCode");
    element("workspace").hidden = true;
    element("login").hidden = false;
    element("disconnect").hidden = true;
    element("connection").textContent = "未连接";
    element("connection").setAttribute("data-state", "disconnected");
    showSidebar(false);
    message("");
    element("code").focus();
});
element("project").onchange = handle(async () => {
    const selected = element("project").value;
    try { await leaveFile(); }
    catch (error) { element("project").value = project; throw error; }
    await listProjects(selected);
});
element("create").onclick = handle(async () => {
    element("project-menu").open = false;
    const name = prompt("项目名称");
    if (!name) return;
    await leaveFile();
    const result = await api("create", {name, productType:element("product-type").value});
    await listProjects(result.id);
});
element("rename-project").onclick = handle(async () => {
    element("project-menu").open = false;
    const selected = projectRows.find(item => item.id === project);
    if (!selected) throw new Error("请选择项目");
    const name = prompt("新的项目名称", selected.name)?.trim();
    if (!name) return;
    await leaveFile();
    await api("rename_project", {project, name});
    await listProjects(project);
});
element("content").oninput = () => {
    dirty = true;
    refreshEditor();
};
element("content").onscroll = () => { element("line-numbers").scrollTop = element("content").scrollTop; };
element("option-product").onchange = () => {element("tweak-options").hidden=element("option-product").value==="app";};
element("options-form").onsubmit = handle(async () => {
    if (!project) throw new Error("请选择项目");
    await leaveFile();
    const list = await api("files", {project});
    const config = list.files.includes("MobileCompiler.json") ?
        JSON.parse((await api("read", {project, path:"MobileCompiler.json"})).content) : {};
    if (!config || Array.isArray(config) || typeof config !== "object") throw new Error("MobileCompiler.json 应为 JSON 对象");
    const type = element("option-product").value;
    const schemes = ["rootless", "rootful", "roothide"].filter(scheme=>element("option-"+scheme).checked);
    const dylib = element("option-dylib").checked, deb = element("option-package").checked;
    if (type === "tweak" && !dylib && !deb) throw new Error("请选择独立 dylib 或 DEB");
    if (type === "tweak" && deb && !schemes.length) throw new Error("请选择至少一种 DEB 类型");
    Object.assign(config, {productType:type, exportDylib:dylib, package:type==="tweak"&&deb,
        cpuArchitecture:element("option-cpu").value, sdkVersion:element("option-sdk").value,
        deploymentTarget:element("option-minimum").value.trim()});
    if (schemes.length) {config.packageSchemes=schemes;config.packageScheme=schemes[0];}
    const content = JSON.stringify(config, null, 2) + "\n";
    await uploadBlob(project, "MobileCompiler.json", new Blob([content]));
    if (filename === "MobileCompiler.json") {
        element("content").value = content;
        refreshEditor();
    }
    await listFiles();
    message("构建设置已保存，下一次构建生效");
});
element("save").onclick = handle(save);
element("new-file").onclick = handle(async () => {
    if (!project) throw new Error("请先新建项目");
    const path = prompt("相对路径，例如 Tweak.xm 或 MobileCompiler.json");
    if (!path) return;
    await leaveFile();
    const files = await api("files", {project});
    if (files.files.includes(path)) throw new Error("文件已存在，请在左侧打开");
    await api("write", {project, path, content:""});
    await listFiles();
    await openSource(path);
});
element("build").onclick = handle(async () => {
    if (!project) throw new Error("请选择项目");
    await leaveFile();
    const result = await api("build", {project});
    selectedJob = "";
    element("job-history").hidden = true;
    message(result.issue?.message || "");
    await poll();
});
element("cancel").onclick = handle(async () => {
    await api("cancel", {job_id:currentJob});
    message("已请求取消，当前编译步骤结束后生效");
});
for (const [button, input] of [["upload", "files-input"], ["folder", "folder-input"], ["import-project", "import-input"]]) {
    element(button).onclick = () => {
        element("project-menu").open = false;
        element(input).click();
    };
}
for (const [id, directory] of [["files-input",false],["folder-input",true]]) {
    const input = element(id);
    input.onchange = handle(async () => {
        const files = [...input.files];
        input.value = "";
        if (files.length) await upload(files, directory);
    });
}
element("import-input").onchange = handle(async () => {
    const input = element("import-input");
    const files = [...input.files];
    input.value = "";
    if (!files.length) return;
    const folder = files[0].webkitRelativePath.split("/")[0];
    const name = prompt("新项目名称", folder)?.trim();
    if (!name) return;
    await leaveFile();
    const newProject = await api("create", {name, productType:element("product-type").value, empty:true});
    await listProjects(newProject.id);
    await upload(files, true);
});
element("jump-to-error").onclick = handle(async () => {
    if (!currentIssue?.file) return;
    await leaveFile();
    const file = currentIssue.file;
    let source;
    try { source = await api("diagnostic_source", {job_id: currentJob}); }
    catch (error) {
        if (error.status !== 404) throw error;
        await openSource(file);
        message("该次构建的源码快照不可用。已打开当前源码。");
        return;
    }
    displaySource(source.path, source.text, source);
});
element("edit-current").onclick = handle(() => openSource(filename));
element("refresh-project").onclick = handle(listFiles);
element("download-log").onclick = handle(() => download("build.log", currentJob));
element("download-report").onclick = handle(() => download("report.json", currentJob));
element("load-history").onclick = handle(async () => {
    if (!project) throw new Error("请选择项目");
    const selected = project;
    const response = await api("history", {project:selected});
    if (project !== selected) return;
    const select = element("job-history");
    select.replaceChildren(new Option("最近一次构建", ""));
    for (const job of response.builds) {
        const time = new Date((job.finishedAt || job.startedAt) * 1000).toLocaleString();
        select.add(new Option((buildStates[job.state] || job.state) + " · " + time, job.id));
    }
    select.value = selectedJob;
    select.hidden = false;
});
element("job-history").onchange = handle(async () => {
    selectedJob = element("job-history").value;
    await poll();
});
for (const [index, tab] of outputTabs.entries()) {
    const button = element("tab-" + tab);
    button.onclick = () => showOutput(tab);
    button.onkeydown = event => {
        const next = {
            ArrowLeft: (index + outputTabs.length - 1) % outputTabs.length,
            ArrowRight: (index + 1) % outputTabs.length,
            Home: 0,
            End: outputTabs.length - 1
        }[event.key];
        if (next === undefined) return;
        event.preventDefault();
        showOutput(outputTabs[next]);
        element("tab-" + outputTabs[next]).focus();
    };
}
element("sidebar-toggle").onclick = () => {
    showSidebar(true);
    element("sidebar-close").focus();
};
element("sidebar-close").onclick = () => {
    showSidebar(false);
    element("sidebar-toggle").focus();
};
element("sidebar-backdrop").onclick = element("sidebar-close").onclick;
window.addEventListener("keydown", event => {
    if (element("workspace").hidden || event.defaultPrevented || event.repeat) return;
    if (event.key === "Escape") {
        if (element("project-menu").open) {
            element("project-menu").open = false;
            element("project-menu").firstElementChild.focus();
        } else if (element("sidebar-toggle").getAttribute("aria-expanded") === "true") {
            element("sidebar-close").click();
        }
    }
    if (!(event.ctrlKey || event.metaKey) || event.altKey) return;
    const key = event.key.toLowerCase();
    if (key !== "s" && key !== "enter") return;
    event.preventDefault();
    (key === "s" ? element("save") : element("build")).click();
});
window.addEventListener("beforeunload", event => {
    if (dirty) { event.preventDefault(); event.returnValue = ""; }
});
element("code").value = token;
setInterval(() => { if (!element("workspace").hidden) poll(); }, 1200);
