<script setup>
import { computed } from "vue";

const props = defineProps({
  status: { type: String, default: "" },
});

const tone = computed(() => {
  const status = props.status || "";
  if (["审核通过", "已报销", "已审核", "已提交", "通过", "已通过", "可以"].includes(status)) {
    return "positive";
  }
  if (status.startsWith("审核不通过") || ["已退回", "不通过", "不可以", "识别失败"].includes(status)) {
    return "negative";
  }
  if (
    status.includes("补凭证") ||
    status.startsWith("待人工处理") ||
    ["待审核", "待补全", "待人工补全", "待核验", "已提取文本", "已OCR文本", "需OCR", "待人工确认", "存疑"].includes(status)
  ) {
    return "attention";
  }
  return "neutral";
});
</script>

<template>
  <span class="status-badge" :class="`status-badge--${tone}`">
    <span class="status-badge__dot" aria-hidden="true"></span>
    {{ status || "未设置" }}
  </span>
</template>
