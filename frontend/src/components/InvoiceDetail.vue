<script setup>
import { onMounted, reactive, ref, watch } from "vue";
import { cancelInvoice, clearCategoryOverride, editFields, openFile, retryExtraction, review, reviewEvidence, ruleCheck, saveItems, setCategoryOverride, uploadEvidence } from "../api";
import StatusBadge from "./StatusBadge.vue";

const props = defineProps({ data: { type: Object, required: true }, editor: { type: String, default: "admin" } });
const emit = defineEmits(["changed", "close"]);
const dialog = ref(null);
const tab = ref("overview");
const busy = ref(false);
const error = ref("");
const comment = ref("");
const orders = ref([]);
const payments = ref([]);
const fields = reactive({});
const items = ref([]);
const categoryDraft = ref({});
const invoice = () => props.data.invoice;
watch(() => props.data, (data) => {
  const row = data.invoice;
  for (const key of ["invoiceNumber","invoiceDate","sellerName","sellerTaxNo","buyerName","buyerTaxNo","amountExclTax","totalTax","totalAmount"])
    fields[key] = row[key] ?? "";
  items.value = data.items.map((item) => ({
    itemName: item.itemName || "", specModel: item.specModel || "", unit: item.unit || "",
    quantity: item.quantity ?? 1, unitPrice: item.unitPrice ?? "", amount: item.amount ?? "",
    taxRate: item.taxRate || "", taxAmount: item.taxAmount ?? "",
  }));
  if (!items.value.length) addItem();
  categoryDraft.value = Object.fromEntries(data.items.map((item) => {
    const override = data.categoryOverrides?.find((row) => row.itemId === item.id);
    const verdict = data.classifications?.find((row) => row.itemId === item.id)?.verdict || "存疑";
    return [item.id, { verdict: override?.verdict || verdict, reason: override?.reason || "" }];
  }));
}, { immediate: true });
onMounted(() => dialog.value?.showModal());
function addItem() { items.value.push({ itemName:"", specModel:"", unit:"", quantity:1, unitPrice:"", amount:"", taxRate:"", taxAmount:"" }); }
function money(value) { return value == null || value === "" ? "—" : `¥${Number(value).toFixed(2)}`; }
function date(value) { return value ? String(value).replace("T"," ").slice(0,16) : "—"; }
async function run(action) {
  busy.value = true; error.value = "";
  try { await action(); emit("changed", invoice().id); }
  catch (e) { error.value = e.message; }
  finally { busy.value = false; }
}
function save() {
  const payload = { ...fields };
  for (const key of ["amountExclTax","totalTax","totalAmount"]) payload[key] = fields[key] === "" ? null : Number(fields[key]);
  payload.invoiceDate ||= null;
  const lines = items.value.filter((item) => item.itemName.trim()).map((item) => ({
    ...item, quantity: Number(item.quantity), unitPrice: Number(item.unitPrice),
    amount: item.amount === "" ? null : Number(item.amount), taxAmount: item.taxAmount === "" ? null : Number(item.taxAmount),
  }));
  if (!lines.length) { error.value = "请至少填写一条商品明细"; return; }
  if (lines.some((item) => !Number.isFinite(item.unitPrice) || item.unitPrice < 0 || !Number.isFinite(item.quantity) || item.quantity <= 0)) {
    error.value = "请检查商品数量和单价"; return;
  }
  run(async () => { await editFields(invoice().id, payload, props.editor); await saveItems(invoice().id, lines); });
}
function submitEvidence() {
  if (!orders.value.length && !payments.value.length) { error.value = "请先选择订单截图或支付记录"; return; }
  run(async () => { await uploadEvidence(invoice().id, orders.value, payments.value); orders.value = []; payments.value = []; });
}
function doReview(stage, result) {
  if ((result === "reject" || stage === "reimbursement") && !comment.value.trim()) { error.value = "请填写审核说明"; return; }
  run(() => review(invoice().id, stage, result, comment.value.trim()));
}
function doEvidenceReview(group, result) {
  if (result === "reject" && !comment.value.trim()) { error.value = "退回凭证时请填写审核说明"; return; }
  run(() => reviewEvidence(invoice().id, group.id, result, comment.value.trim()));
}
function abandon() {
  if (!comment.value.trim()) { error.value = "请先填写放弃原因"; return; }
  if (!confirm("确定放弃这张发票？放弃后不能继续审核。")) return;
  run(() => cancelInvoice(invoice().id, comment.value.trim()));
}
function saveCategory(item) {
  const draft = categoryDraft.value[item.id];
  if (!draft?.reason?.trim()) { error.value = "请填写商品品类判断依据"; return; }
  run(() => setCategoryOverride(invoice().id, item.id, draft.verdict, draft.reason.trim()));
}
function clearCategory(item) { run(() => clearCategoryOverride(invoice().id, item.id)); }
async function preview(path) { error.value = ""; try { await openFile(path); } catch (e) { error.value = e.message; } }
</script>

<template>
  <dialog ref="dialog" class="detail-dialog" aria-label="发票详情" @close="emit('close')">
    <header class="detail-header"><div><p class="eyebrow">发票档案 <span class="detail-number">#{{ invoice().id }}</span></p><h2>发票详情</h2><p class="detail-filename">{{ invoice().fileName }}</p></div><button type="button" class="detail-close" aria-label="关闭详情" @click="dialog.close()">×</button></header>
    <div class="detail-scroll">
      <div class="detail-meta"><div><small>上传时间</small><strong>{{ date(invoice().uploadTime) }}</strong></div><div><small>自动预审</small><StatusBadge :status="invoice().status" /></div><div><small>资质审核</small><StatusBadge :status="invoice().qualificationStatus" /></div><div><small>财务状态</small><StatusBadge :status="invoice().financialStatus" /></div><div><small>最终报销</small><StatusBadge :status="invoice().reimbursementStatus" /></div></div>
      <p v-if="error" class="error" role="alert">{{ error }}</p>
      <nav class="tabs" aria-label="发票详情"><button v-for="entry in [['overview','概览'],['edit','人工修正'],['evidence','支付凭证'],['review','审核与财务'],['events','修改记录']]" :key="entry[0]" type="button" :class="{active:tab===entry[0]}" @click="tab=entry[0]">{{ entry[1] }}</button></nav>
      <div class="detail-content">
        <div v-if="tab==='overview'">
          <p class="notice" :class="{'notice-good':invoice().status==='审核通过'}">{{ invoice().errorMessage || invoice().reviewComment || invoice().status }}</p>
          <div v-if="data.validation?.missing?.length || data.validation?.mismatches?.length || data.validation?.duplicateOf" class="subcard"><strong>核对提醒</strong><p v-if="data.validation.missing.length">待补全：{{ data.validation.missing.join('、') }}</p><p v-if="data.validation.mismatches.length">金额或日期异常：{{ data.validation.mismatches.join('；') }}</p><p v-if="data.validation.duplicateOf">疑似重复：发票 #{{ data.validation.duplicateOf }}</p></div>
          <div class="facts"><div><small>发票号码（可选）</small><strong>{{ invoice().invoiceNumber || '未提取' }}</strong></div><div><small>开票日期</small><strong>{{ invoice().invoiceDate || '待补全' }}</strong></div><div><small>销售方</small><strong>{{ invoice().sellerName || '待补全' }}</strong></div><div><small>销售方税号</small><strong>{{ invoice().sellerTaxNo || '待补全' }}</strong></div><div><small>购买方（可选）</small><strong>{{ invoice().buyerName || '未提取' }}</strong></div><div><small>价税合计</small><strong>{{ money(invoice().totalAmount) }}</strong></div></div>
          <h3>商品明细</h3><div class="table-scroll"><table><thead><tr><th>名称</th><th>品类判断</th><th>数量</th><th>单价</th><th>金额</th><th>税额</th></tr></thead><tbody><tr v-for="item in data.items" :key="item.id"><td>{{ item.itemName }}</td><td><StatusBadge :status="data.classifications?.find(row => row.itemId === item.id)?.verdict" /><small>{{ data.classifications?.find(row => row.itemId === item.id)?.category }}</small></td><td>{{ item.quantity }}</td><td>{{ money(item.unitPrice) }}</td><td>{{ money(item.amount) }}</td><td>{{ money(item.taxAmount) }}</td></tr><tr v-if="!data.items.length"><td colspan="6">暂无明细，请核对原件后人工补全</td></tr></tbody></table></div>
          <details v-if="data.items.length"><summary>人工调整商品品类判断</summary><p class="muted">人工结论会覆盖自动品类判断，保存后需重新运行预审；单价和周累计规则仍由程序执行。</p><article v-for="item in data.items" :key="`category-${item.id}`" class="subcard"><strong>{{ item.itemName }}</strong><div class="form-grid"><label>最终结论<select v-model="categoryDraft[item.id].verdict"><option>可以</option><option>存疑</option><option>不可以</option></select></label><label>判断依据<input v-model="categoryDraft[item.id].reason" maxlength="1000" placeholder="说明为什么这样判断" /></label></div><div class="button-row"><button type="button" :disabled="busy || invoice().qualificationStatus==='已取消' || invoice().reimbursementStatus==='已报销'" @click="saveCategory(item)">保存人工结论</button><button v-if="data.categoryOverrides?.some(row => row.itemId === item.id)" type="button" :disabled="busy" @click="clearCategory(item)">撤销人工结论</button></div></article></details>
          <div class="button-row"><button type="button" @click="preview(`/invoices/${invoice().id}/file`)">预览原始 PDF</button><button v-if="['需OCR','识别失败','待人工补全','已提取文本','已OCR文本'].includes(invoice().status)" type="button" :disabled="busy" @click="run(() => retryExtraction(invoice().id))">重新识别</button><button type="button" class="primary" :disabled="busy || invoice().qualificationStatus!=='待审核'" @click="run(() => ruleCheck(invoice().id))">{{ busy ? '处理中…' : '运行自动预审' }}</button></div>
          <details><summary>查看提取文本与 AI 原始结果</summary><pre>{{ invoice().aiRawJson || invoice().rawText || '暂无识别结果' }}</pre></details>
        </div>
        <form v-else-if="tab==='edit'" @submit.prevent="save">
          <p class="notice">请对照原始 PDF 核对。保存后可重新运行自动预审。</p>
          <div class="form-grid"><label>发票号码<input v-model="fields.invoiceNumber" /></label><label>开票日期<input v-model="fields.invoiceDate" type="date" /></label><label>销售方名称<input v-model="fields.sellerName" required /></label><label>销售方税号<input v-model="fields.sellerTaxNo" /></label><label>购买方名称<input v-model="fields.buyerName" /></label><label>购买方税号<input v-model="fields.buyerTaxNo" /></label><label>不含税金额<input v-model="fields.amountExclTax" type="number" step="0.01" /></label><label>税额合计<input v-model="fields.totalTax" type="number" step="0.01" /></label><label>价税合计<input v-model="fields.totalAmount" type="number" min="0.01" step="0.01" required /></label></div>
          <h3>商品明细</h3><div v-for="(item,index) in items" :key="index" class="item-form"><input v-model="item.itemName" placeholder="商品名称" aria-label="商品名称" /><input v-model="item.quantity" type="number" min="0.0001" step="any" placeholder="数量" aria-label="数量" /><input v-model="item.unitPrice" type="number" min="0" step="0.01" placeholder="单价" aria-label="单价" /><input v-model="item.amount" type="number" min="0" step="0.01" placeholder="金额" aria-label="金额" /><input v-model="item.taxAmount" type="number" min="0" step="0.01" placeholder="税额" aria-label="税额" /><button type="button" @click="items.splice(index,1)">移除</button></div>
          <div class="button-row"><button type="button" @click="addItem">添加商品</button><button class="primary" type="submit" :disabled="busy || invoice().qualificationStatus==='已取消' || invoice().reimbursementStatus==='已报销'">保存修正</button></div>
        </form>
        <div v-else-if="tab==='evidence'">
          <p class="notice">同一凭证组要同时包含订单截图与支付记录。人工核验通过后，重新运行自动预审。</p>
          <div class="form-grid"><label>订单截图<input type="file" multiple accept="image/*,.pdf" @change="orders=[...$event.target.files]" /></label><label>支付记录<input type="file" multiple accept="image/*,.pdf" @change="payments=[...$event.target.files]" /></label></div>
          <div class="button-row"><button class="primary" type="button" :disabled="busy" @click="submitEvidence">上传凭证</button></div>
          <label>凭证核验意见<textarea v-model="comment" rows="2" placeholder="记录核验依据或退回原因" /></label>
          <article v-for="group in data.evidenceGroups" :key="group.id" class="subcard"><h3>凭证组 #{{ group.id }} · {{ date(group.createdAt) }} <StatusBadge :status="group.status" /></h3><p v-if="group.reviewComment">核验意见：{{ group.reviewComment }}</p><div class="button-row"><button v-for="file in group.orderScreenshots" :key="`o-${file.id}`" type="button" @click="preview(`/invoices/${invoice().id}/evidence-files/order/${file.id}`)">订单：{{ file.fileName }}</button><button v-for="file in group.paymentRecords" :key="`p-${file.id}`" type="button" @click="preview(`/invoices/${invoice().id}/evidence-files/payment/${file.id}`)">支付：{{ file.fileName }}</button></div><div class="button-row"><button type="button" :disabled="busy || ['通过','已通过'].includes(group.status)" @click="doEvidenceReview(group,'approve')">核验通过</button><button type="button" :disabled="busy" @click="doEvidenceReview(group,'reject')">退回凭证</button></div></article>
          <p v-if="!data.evidenceGroups.length">暂无凭证</p>
        </div>
        <div v-else-if="tab==='review'">
          <label>审核说明<textarea v-model="comment" rows="3" placeholder="记录人工核验依据与处理意见" /></label>
          <h3>资质审核</h3><div class="button-row"><button type="button" :disabled="busy || !['审核通过','待人工处理（品类）'].includes(invoice().status) || invoice().reimbursementStatus==='已报销'" @click="doReview('qualification','approve')">通过</button><button type="button" :disabled="busy || invoice().reimbursementStatus==='已报销'" @click="doReview('qualification','reject')">不通过</button></div>
          <h3>财务提交</h3><div class="button-row"><button type="button" :disabled="busy || invoice().qualificationStatus!=='通过' || invoice().financialStatus!=='待提交'" @click="doReview('financial','submit')">标记已提交</button><button type="button" :disabled="busy || invoice().financialStatus!=='已提交'" @click="doReview('financial','approve')">财务已审核</button><button type="button" :disabled="busy || invoice().financialStatus!=='已提交'" @click="doReview('financial','reject')">财务退回</button></div>
          <h3>最终报销</h3><div class="button-row"><button type="button" :disabled="busy || invoice().financialStatus!=='已审核' || invoice().reimbursementStatus==='已报销'" @click="doReview('reimbursement','approve')">标记已报销</button><button type="button" :disabled="busy || invoice().financialStatus!=='已审核'" @click="doReview('reimbursement','reject')">报销退回</button></div>
          <h3>放弃当前发票</h3><p class="muted">若同周累计超过 1000 元，可选择补齐相关凭证保留当前发票，或填写原因后放弃。已进入财务流程的发票不能放弃。</p><div class="button-row"><button type="button" :disabled="busy || invoice().financialStatus!=='待提交' || invoice().qualificationStatus==='已取消'" @click="abandon">放弃当前发票</button></div>
          <p class="muted">当前审核意见：{{ invoice().reviewComment || '暂无' }}</p>
        </div>
        <div v-else><article v-for="entry in data.editLogs" :key="entry.id" class="subcard"><strong>{{ entry.fieldName }}</strong><small> {{ date(entry.editedAt) }} · {{ entry.editedBy }}</small><p>{{ entry.oldValue || '空' }} → {{ entry.newValue || '空' }}</p></article><p v-if="!data.editLogs.length">暂无字段修改记录</p></div>
      </div>
    </div>
  </dialog>
</template>
