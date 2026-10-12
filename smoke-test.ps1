param([string]$BaseUrl = 'http://127.0.0.1:18080')

$ErrorActionPreference = 'Stop'
$sample = Join-Path $PSScriptRoot 'sample-data'
$username = 'smoke_' + (Get-Date -Format 'yyyyMMddHHmmss')
$password = 'test123456'

function Send-Json($method, $path, $body, $headers) {
    $params = @{
        Method = $method
        Uri = "$BaseUrl/api$path"
        ContentType = 'application/json'
        Body = (ConvertTo-Json -InputObject $body -Depth 10 -Compress)
    }
    if ($headers) { $params.Headers = $headers }
    Invoke-RestMethod @params
}

$registered = Send-Json Post '/auth/register' @{ username = $username; password = $password } $null
if (-not $registered.success) { throw "注册失败: $($registered.message)" }
$login = Send-Json Post '/auth/login' @{ username = $username; password = $password } $null
$headers = @{ Authorization = "Bearer $($login.token)" }
$rules = Invoke-RestMethod -Method Get -Uri "$BaseUrl/api/rules" -Headers $headers
if ($rules.Count -lt 19) { throw '品类规则未初始化' }

$upload = Invoke-RestMethod -Method Post -Uri "$BaseUrl/api/upload" -Headers $headers -Form @{
    file = Get-Item -LiteralPath (Join-Path $sample '01_普通材料_320.pdf')
}
if ($upload.successCount -ne 1) { throw "上传失败: $($upload | ConvertTo-Json -Depth 4)" }
$id = $upload.savedInvoices[0].id

$fields = @{
    invoiceNumber = "SAMPLE-$id"
    invoiceDate = (Get-Date -Format 'yyyy-MM-dd')
    sellerName = "模拟材料商-$id"
    sellerTaxNo = "TESTTAX$id"
    buyerName = '测试工作室'
    amountExclTax = 320
    totalTax = 0
    totalAmount = 320
}
$null = Send-Json Put "/invoices/$id/fields" $fields $headers
$null = Send-Json Post "/invoices/$id/manual-items" @(@{
    itemName = '模拟电子材料'
    quantity = 1
    unitPrice = 320
    amount = 320
    taxAmount = 0
}) $headers
$checked = Invoke-RestMethod -Method Post -Uri "$BaseUrl/api/invoices/$id/rule-check" -Headers $headers
if ($checked.status -ne '审核通过') { throw "预审结果异常: $($checked.status)" }

$details = Invoke-RestMethod -Method Get -Uri "$BaseUrl/api/invoices/$id/details" -Headers $headers
if ($details.items.Count -ne 1 -or $details.editLogs.Count -lt 1) { throw '详情缺少商品或修改记录' }
$itemId = $details.items[0].id
$override = Send-Json Put "/invoices/$id/items/$itemId/category" @{ verdict='可以'; reason='人工核对为电子材料' } $headers
if ($override.verdict -ne '可以') { throw '人工品类结论未保存' }
$checked = Invoke-RestMethod -Method Post -Uri "$BaseUrl/api/invoices/$id/rule-check" -Headers $headers
if ($checked.status -ne '审核通过') { throw '人工品类结论后预审失败' }

$evidence = Invoke-RestMethod -Method Post -Uri "$BaseUrl/api/invoices/$id/payment-evidence" -Headers $headers -Form @{
    orderScreenshots = Get-Item -LiteralPath (Join-Path $sample '订单截图_模拟.pdf')
    paymentRecords = Get-Item -LiteralPath (Join-Path $sample '支付记录_模拟.pdf')
}
if ($evidence.orderScreenshots.Count -ne 1 -or $evidence.paymentRecords.Count -ne 1) { throw '凭证上传不完整' }
$verified = Send-Json Post "/invoices/$id/payment-evidence/$($evidence.id)/review" @{ result='approve'; comment='订单和支付记录核对一致' } $headers
if ($verified.status -ne '通过') { throw '凭证核验失败' }

$preview = Join-Path $PSScriptRoot 'backend/target/smoke-preview.pdf'
Invoke-WebRequest -Method Get -Uri "$BaseUrl/api/invoices/$id/file" -Headers $headers -OutFile $preview
if ((Get-Item -LiteralPath $preview).Length -lt 100) { throw '原件预览失败' }

$qualified = Send-Json Post "/invoices/$id/review" @{ stage='qualification'; result='approve'; comment='模拟凭证已人工核验' } $headers
$submitted = Send-Json Post "/invoices/$id/review" @{ stage='financial'; result='submit'; comment='已提交财务' } $headers
$financial = Send-Json Post "/invoices/$id/review" @{ stage='financial'; result='approve'; comment='财务审核通过' } $headers
$reimbursed = Send-Json Post "/invoices/$id/review" @{ stage='reimbursement'; result='approve'; comment='模拟报销完成' } $headers
if ($qualified.qualificationStatus -ne '通过' -or $submitted.financialStatus -ne '已提交' -or $financial.financialStatus -ne '已审核' -or $reimbursed.reimbursementStatus -ne '已报销') {
    throw '审核状态流转失败'
}

$second = Invoke-RestMethod -Method Post -Uri "$BaseUrl/api/upload" -Headers $headers -Form @{
    file = Get-Item -LiteralPath (Join-Path $sample '02_低值品_650.pdf')
}
if ($second.successCount -ne 1) { throw '第二张发票上传失败' }
$secondId = $second.savedInvoices[0].id
$null = Send-Json Put "/invoices/$secondId/fields" @{
    invoiceNumber = "LOW-$secondId"; invoiceDate = (Get-Date -Format 'yyyy-MM-dd')
    sellerName = "低值品材料商-$secondId"; sellerTaxNo = "LOWTAX$secondId"
    totalAmount = 650; amountExclTax = 650; totalTax = 0
} $headers
$null = Send-Json Post "/invoices/$secondId/manual-items" @(@{
    itemName = '电烙铁'; quantity = 1; unitPrice = 650; amount = 650; taxAmount = 0
}) $headers
$low = Invoke-RestMethod -Method Post -Uri "$BaseUrl/api/invoices/$secondId/rule-check" -Headers $headers
if ($low.status -ne '需补凭证（低值品）') { throw "低值品规则错误: $($low.status)" }
$cancelled = Send-Json Post "/invoices/$secondId/cancel" @{ reason='选择放弃当前发票' } $headers
if ($cancelled.status -ne '已取消') { throw '放弃发票路径失败' }

Write-Output "PASS: invoices #$id/$secondId / upload / category override / rules / evidence / review / cancel"
