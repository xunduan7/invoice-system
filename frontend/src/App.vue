<script setup>
import { computed, onMounted, ref } from "vue";
import { addRule, deleteRule, details, listInvoices, listRules, login, register, uploadFiles } from "./api";
import InvoiceDetail from "./components/InvoiceDetail.vue";
import StatusBadge from "./components/StatusBadge.vue";

const username = ref(localStorage.getItem("teammate_invoice_user") || "");
const password = ref("");
const authMode = ref("login");
const loggedIn = ref(false);
const page = ref("dashboard");
const busy = ref(false);
const error = ref("");
const notice = ref("");
const invoices = ref([]);
const rules = ref([]);
const ruleForm = ref({ verdict: "可以", category: "", keywords: "" });
const selected = ref(null);
const files = ref([]);
const fileInput = ref(null);
const dragActive = ref(false);
const uploadResults = ref([]);
const search = ref("");
const statusFilter = ref("");
const pending = computed(() => invoices.value.filter((row) =>
  row.qualificationStatus === "待审核" || row.status === "需OCR" ||
  row.status === "识别失败" || row.status === "已提取文本" || row.status === "已OCR文本" || row.status === "待人工补全" ||
  row.status?.includes("补凭证") || row.status?.includes("待人工处理") || row.status === "待补全"));
const approved = computed(() => invoices.value.filter((row) => row.qualificationStatus === "通过"));
const finished = computed(() => invoices.value.filter((row) => row.reimbursementStatus === "已报销"));
const visible = computed(() => {
  let rows = invoices.value;
  if (page.value === "pending") rows = pending.value;
  if (page.value === "history") rows = rows.filter((row) => row.reimbursementStatus !== "待报销");
  if (statusFilter.value) rows = rows.filter((row) => row.status === statusFilter.value || row.qualificationStatus === statusFilter.value);
  const query = search.value.trim().toLowerCase();
  if (query) rows = rows.filter((row) => [row.fileName, row.invoiceNumber, row.sellerName, row.sellerTaxNo]
    .some((value) => String(value || "").toLowerCase().includes(query)));
  return rows;
});
const statuses = computed(() => [...new Set(invoices.value.map((row) => row.status).filter(Boolean))]);
const uploadCount = computed(() => uploadResults.value.reduce((sum, item) => sum + (item.result?.successCount || 0), 0));
const uploadErrors = computed(() => uploadResults.value.reduce((sum, item) => sum + (item.result?.failedCount || (item.error ? 1 : 0)), 0));

async function refresh() { [invoices.value, rules.value] = await Promise.all([listInvoices(), listRules()]); }
async function saveRule() {
  error.value = "";
  try { await addRule(ruleForm.value); rules.value = await listRules(); ruleForm.value = { verdict: "可以", category: "", keywords: "" }; notice.value = "规则已添加"; }
  catch (e) { error.value = e.message; }
}
async function removeRule(id) {
  if (!confirm("确定删除这条品类规则吗？")) return;
  error.value = "";
  try { await deleteRule(id); rules.value = await listRules(); notice.value = "规则已删除"; }
  catch (e) { error.value = e.message; }
}
async function signIn() {
  busy.value = true; error.value = "";
  try {
    if (authMode.value === "register") await register(username.value.trim(), password.value);
    const result = await login(username.value.trim(), password.value);
    localStorage.setItem("teammate_invoice_token", result.token);
    localStorage.setItem("teammate_invoice_user", username.value.trim());
    await refresh();
    loggedIn.value = true;
    password.value = "";
  } catch (e) { error.value = e.message; }
  finally { busy.value = false; }
}
function signOut() {
  localStorage.removeItem("teammate_invoice_token");
  loggedIn.value = false; selected.value = null; invoices.value = []; password.value = "";
}
async function chooseInvoice(id) {
  error.value = "";
  try { selected.value = await details(id); }
  catch (e) { error.value = e.message; }
}
async function changed(id) {
  try { await refresh(); selected.value = await details(id); notice.value = "已保存"; }
  catch (e) { error.value = e.message; }
}
function selectFiles(event) { files.value = [...event.target.files]; uploadResults.value = []; }
function dropFiles(event) { dragActive.value = false; files.value = [...event.dataTransfer.files]; uploadResults.value = []; }
function clearFiles() { files.value = []; if (fileInput.value) fileInput.value.value = ""; }
async function upload() {
  if (!files.value.length) return;
  busy.value = true; error.value = ""; notice.value = "";
  try { uploadResults.value = await uploadFiles(files.value); await refresh(); notice.value = "批次处理完成"; }
  catch (e) { error.value = e.message; }
  finally { busy.value = false; }
}
function money(value) { return value == null ? "—" : `¥${Number(value).toFixed(2)}`; }
function date(value) { return value ? String(value).replace("T", " ").slice(0, 16) : "—"; }
onMounted(async () => {
  window.addEventListener("invoice-auth-expired", signOut);
  if (!localStorage.getItem("teammate_invoice_token")) return;
  try { await refresh(); loggedIn.value = true; }
  catch (e) { error.value = e.message; signOut(); }
});
</script>

<template>
  <main v-if="!loggedIn" class="auth-layout">
    <form class="card auth-card" @submit.prevent="signIn">
      <p class="eyebrow">材料费发票智能预审</p>
      <h1>{{ authMode === 'register' ? '创建管理员账号' : '管理员登录' }}</h1>
      <p class="muted">上传发票、核对信息、完成审核与报销记录。</p>
      <label>用户名<input v-model="username" autocomplete="username" required /></label>
      <label>密码<input v-model="password" type="password" minlength="6" :autocomplete="authMode === 'register' ? 'new-password' : 'current-password'" required /></label>
      <p v-if="error" class="error" role="alert">{{ error }}</p>
      <button class="primary" type="submit" :disabled="busy">{{ busy ? '处理中…' : authMode === 'register' ? '注册并登录' : '登录' }}</button>
      <button class="link-button" type="button" @click="authMode = authMode === 'login' ? 'register' : 'login'">{{ authMode === 'login' ? '创建账号' : '返回登录' }}</button>
    </form>
  </main>
  <div v-else class="app-layout">
    <aside class="sidebar">
      <div class="brand"><span>材</span><div><strong>材审</strong><small>INVOICE DESK</small></div></div>
      <p class="sidebar-caption">工作区</p>
      <nav aria-label="主导航">
        <button v-for="entry in [['dashboard','总览','▦'],['invoices','发票管理','▤'],['pending','待办审核','◇'],['history','报销历史','◷'],['rules','品类规则','⚙']]" :key="entry[0]" type="button" :class="{active:page===entry[0]}" @click="page=entry[0];selected=null">
          <span class="nav-icon" aria-hidden="true">{{ entry[2] }}</span><span>{{ entry[1] }}</span><span v-if="entry[0]==='pending' && pending.length" class="nav-count">{{ pending.length }}</span>
        </button>
      </nav>
      <p class="sidebar-user">{{ username }} <button type="button" @click="signOut">退出登录</button></p>
    </aside>
    <main class="workspace">
      <header class="page-header">
        <div><p class="eyebrow">{{ page === 'rules' ? 'REVIEW POLICY' : '材料费发票管理平台' }}</p>
          <h1>{{ { dashboard:'工作台总览', invoices:'发票管理', pending:'待办审核', history:'报销历史', rules:'品类规则' }[page] }}</h1>
          <p class="page-description">{{ { dashboard:'掌握发票进度，优先处理需要人工确认的记录。', invoices:'查看发票信息和每张发票的审核进度。', pending:'集中处理待补全、待补凭证和待审核的发票。', history:'查看已完成的财务与报销记录。', rules:'长期规则优先于自动判断；新增规则对后续预审生效。' }[page] }}</p></div>
        <button type="button" @click="refresh">刷新数据</button>
      </header>
      <p v-if="error" class="error" role="alert">{{ error }}</p>
      <p v-if="notice" class="notice" role="status">{{ notice }}</p>
      <template v-if="page==='dashboard'">
        <div class="stats-grid">
          <article v-for="card in [['发票总数',invoices.length,'▤','已独立建档'],['待办审核',pending.length,'◇','需要人工处理'],['资质通过',approved.length,'✓','可进入财务流程'],['报销办结',finished.length,'◷','已有最终结果']]" :key="card[0]" class="card stat">
            <div class="stat-heading"><small>{{ card[0] }}</small><span class="stat-icon">{{ card[2] }}</span></div><strong>{{ card[1] }}</strong><small>{{ card[3] }}</small>
          </article>
        </div>
        <div class="dashboard-grid">
          <section class="card upload-card">
            <h2>上传 PDF / ZIP</h2><p class="muted">可一次选择多份文件，每份文件单独处理。</p>
            <label class="upload-dropzone" :class="{'is-dragging':dragActive}" @dragenter.prevent="dragActive=true" @dragover.prevent="dragActive=true" @dragleave.prevent="dragActive=false" @drop.prevent="dropFiles">
              <span class="upload-symbol">↑</span><strong>拖入文件，或点击选择</strong><small>支持 PDF、ZIP · 单文件不超过 50 MB</small>
              <input ref="fileInput" type="file" multiple accept=".pdf,.zip" @change="selectFiles" />
            </label>
            <div v-if="files.length" class="selected-files"><span v-for="(file,index) in files" :key="index">{{ file.name }}</span><button type="button" class="link-button" @click="clearFiles">清空</button></div>
            <button class="primary" type="button" :disabled="busy||!files.length" @click="upload">{{ busy ? '正在处理…' : '开始上传 →' }}</button>
            <div v-if="uploadResults.length" class="upload-result"><p>建档 {{ uploadCount }} 张，失败 {{ uploadErrors }} 份。</p>
              <div v-for="item in uploadResults" :key="item.file"><strong>{{ item.file }}</strong><span v-if="item.error" class="error">：{{ item.error }}</span><template v-else>：建档 {{ item.result.successCount }} 张；重复 {{ item.result.duplicates?.length || 0 }} 张
                <p v-for="entry in item.result.errors" :key="entry.fileName" class="error">{{ entry.fileName }}：{{ entry.reason }}</p>
                <p v-for="entry in item.result.duplicates" :key="entry.fileName">{{ entry.fileName }} 已存在于 #{{ entry.existingInvoiceId }}</p></template></div>
              <button v-if="uploadResults[0]?.result?.savedInvoices?.length" type="button" @click="chooseInvoice(uploadResults[0].result.savedInvoices[0].id)">查看首张发票</button>
            </div>
          </section>
          <section class="card priority-card"><div class="section-heading"><h2>优先处理</h2><button type="button" class="link-button" @click="page='pending'">查看全部 →</button></div>
            <p v-if="!pending.length">暂无待办</p>
            <div v-for="row in pending.slice(0,5)" :key="row.id" class="list-row"><span class="priority-mark">!</span><div class="priority-copy"><strong>#{{ row.id }} {{ row.fileName }}</strong><p>{{ row.errorMessage || row.status }}</p></div><StatusBadge :status="row.status" /><button type="button" class="link-button" @click="chooseInvoice(row.id)">查看</button></div>
          </section>
        </div>
      </template>
      <section v-else-if="page==='rules'" class="card rule-panel">
        <div class="rule-panel-head"><h2>品类长期规则</h2><span>{{ rules.length }} 条规则</span></div>
        <form class="rule-form" @submit.prevent="saveRule"><label>结论<select v-model="ruleForm.verdict"><option>可以</option><option>存疑</option><option>不可以</option></select></label><label>品类<input v-model="ruleForm.category" required maxlength="100" placeholder="例如：电子元器件" /></label><label>关键词（逗号分隔）<input v-model="ruleForm.keywords" required maxlength="2000" placeholder="例如：开发板,传感器" /></label><button class="primary" type="submit">添加规则</button></form>
        <div class="table-scroll"><table class="rules-table"><thead><tr><th>结论</th><th>品类</th><th>关键词</th><th>操作</th></tr></thead><tbody>
          <tr v-for="rule in rules" :key="rule.id"><td><StatusBadge :status="rule.verdict" /></td><td><strong>{{ rule.category }}</strong></td><td class="rule-keywords">{{ rule.keywords }}</td><td><button type="button" class="link-button" @click="removeRule(rule.id)">删除</button></td></tr>
        </tbody></table></div>
        <div class="rule-panel-head"><h2>金额规则</h2><span>自动预审执行</span></div>
        <p class="muted" style="padding:0 22px 22px">单价 ≥ ¥1,000：资产不通过；¥500–999.99：需核验订单和支付凭证；同周同商家累计 &gt; ¥1,000：需核验相关发票凭证；累计 &gt; ¥3,000：不通过。</p>
      </section>
      <section v-else class="card"><div class="section-heading"><h2>{{ page==='history'?'报销记录':page==='pending'?'待处理发票':'全部发票' }}</h2><span>{{ visible.length }} 张</span></div>
        <div class="filters"><input v-model="search" placeholder="搜索文件名、发票号或销售方" /><select v-model="statusFilter"><option value="">全部处理状态</option><option v-for="status in statuses" :key="status">{{ status }}</option><option>待审核</option><option>通过</option><option>不通过</option></select></div>
        <div class="table-scroll"><table><thead><tr><th>发票</th><th>销售方</th><th>价税合计</th><th>预审</th><th>资质</th><th>财务</th><th>报销</th><th>操作</th></tr></thead><tbody>
          <tr v-for="row in visible" :key="row.id"><td><strong>#{{ row.id }} {{ row.fileName }}</strong><small>{{ row.invoiceNumber || '暂无发票号' }} · {{ date(row.uploadTime) }}</small></td><td>{{ row.sellerName || '待补全' }}</td><td>{{ money(row.totalAmount) }}</td><td><StatusBadge :status="row.status" /></td><td><StatusBadge :status="row.qualificationStatus" /></td><td><StatusBadge :status="row.financialStatus" /></td><td><StatusBadge :status="row.reimbursementStatus" /></td><td><button type="button" @click="chooseInvoice(row.id)">查看详情</button></td></tr>
          <tr v-if="!visible.length"><td colspan="8">暂无符合条件的发票</td></tr>
        </tbody></table></div>
      </section>
      <InvoiceDetail v-if="selected" :key="selected.invoice.id" :data="selected" :editor="username" @close="selected=null" @changed="changed" />
    </main>
  </div>
</template>
