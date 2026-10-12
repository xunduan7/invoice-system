import axios from "axios";

// All backend paths are kept here so the Vue views only handle interaction.
const client = axios.create({ baseURL: "/api", timeout: 120000 });
client.interceptors.request.use((config) => {
  const token = localStorage.getItem("teammate_invoice_token");
  if (token) config.headers.Authorization = `Bearer ${token}`;
  return config;
});
client.interceptors.response.use(
  (response) => response.data,
  (error) => {
    if (error.response?.status === 401 && !error.config?.url?.includes("/auth/")) {
      localStorage.removeItem("teammate_invoice_token");
      window.dispatchEvent(new Event("invoice-auth-expired"));
    }
    return Promise.reject(new Error(error.response?.data?.message || error.message || "请求失败"));
  },
);

export async function register(username, password) {
  const result = await client.post("/auth/register", { username, password });
  if (!result.success) throw new Error(result.message);
  return result;
}
export const login = (username, password) => client.post("/auth/login", { username, password });
export const listInvoices = () => client.get("/invoices");
export const details = (id) => client.get(`/invoices/${id}/details`);
export const listRules = () => client.get("/rules");
export const addRule = (rule) => client.post("/rules", rule);
export const deleteRule = (id) => client.delete(`/rules/${id}`);
export const setCategoryOverride = (id, itemId, verdict, reason) =>
  client.put(`/invoices/${id}/items/${itemId}/category`, { verdict, reason });
export const clearCategoryOverride = (id, itemId) => client.delete(`/invoices/${id}/items/${itemId}/category`);
export const editFields = (id, fields, editor) =>
  client.put(`/invoices/${id}/fields`, fields, { headers: { "X-Edited-By": editor } });
export const saveItems = (id, items) => client.post(`/invoices/${id}/manual-items`, items);
export const ruleCheck = (id) => client.post(`/invoices/${id}/rule-check`);
export const retryExtraction = (id) => client.post(`/invoices/${id}/retry-extraction`);
export const reviewEvidence = (id, evidenceId, result, comment) =>
  client.post(`/invoices/${id}/payment-evidence/${evidenceId}/review`, { result, comment });
export const review = (id, stage, result, comment) =>
  client.post(`/invoices/${id}/review`, { stage, result, comment });
export const cancelInvoice = (id, reason) => client.post(`/invoices/${id}/cancel`, { reason });
export function uploadEvidence(id, orders, payments) {
  const data = new FormData();
  orders.forEach((file) => data.append("orderScreenshots", file));
  payments.forEach((file) => data.append("paymentRecords", file));
  return client.post(`/invoices/${id}/payment-evidence`, data);
}
export async function uploadFiles(files) {
  const results = [];
  for (const file of files) {
    const data = new FormData();
    data.append("file", file);
    try {
      results.push({ file: file.name, result: await client.post("/upload", data) });
    } catch (error) {
      results.push({ file: file.name, error: error.message });
    }
  }
  return results;
}
export async function openFile(path) {
  const blob = await client.get(path, { responseType: "blob" });
  const url = URL.createObjectURL(blob);
  const opened = window.open(url, "_blank", "noopener");
  if (!opened) {
    const link = document.createElement("a");
    link.href = url;
    link.download = "附件";
    link.click();
  }
  setTimeout(() => URL.revokeObjectURL(url), 120000);
}
