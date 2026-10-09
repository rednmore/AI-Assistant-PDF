<#
.SYNOPSIS
    Prépare le site SharePoint Legal Department pour l'EFC Procurement Assistant.

.DESCRIPTION
    Script idempotent : il peut être relancé sans dupliquer les listes, les colonnes ou les paramètres.
    - Vérifie la présence des colonnes de l'annexe A dans Procurement Records (rapport seulement, aucune modification).
    - Ajoute à Procurement Records les colonnes techniques nécessaires à la reprise, au versioning et aux flux.
    - Crée Procurement Approvals, Procurement History, Procurement Config, Procurement Settings,
      Procurement Policy Links et la bibliothèque Procurement Documents.
    - Active le versioning, désactive l'approbation de contenu, crée les index.
    - Initialise les seuils (cahier §8.2) et les paramètres. Les valeurs existantes ne sont pas écrasées.

.PREREQUIS
    PnP.PowerShell 2.x ou supérieur (Install-Module PnP.PowerShell -Scope CurrentUser).
    Une inscription d'application Entra ID pour PnP (obligatoire depuis septembre 2024), passée en -ClientId.
    Droits de propriétaire sur le site.

.EXEMPLE
    ./Provision-EFC-Procurement.ps1 -SiteUrl "https://efc.sharepoint.com/sites/LegalDepartment" -ClientId "00000000-0000-0000-0000-000000000000"
#>
param(
    [Parameter(Mandatory = $true)] [string] $SiteUrl,
    [Parameter(Mandatory = $true)] [string] $ClientId,
    [string] $RecordsListTitle = "Procurement Records"
)

$ErrorActionPreference = "Stop"
Connect-PnPOnline -Url $SiteUrl -Interactive -ClientId $ClientId

# ---------------------------------------------------------------------------
# Fonctions utilitaires
# ---------------------------------------------------------------------------

function Ensure-List {
    param([string] $Title, [string] $Template = "GenericList")
    $list = Get-PnPList -Identity $Title -ErrorAction SilentlyContinue
    if (-not $list) {
        Write-Host "Création de la liste $Title" -ForegroundColor Cyan
        $list = New-PnPList -Title $Title -Template $Template -OnQuickLaunch:$false
    }
    Set-PnPList -Identity $Title -EnableVersioning $true -EnableModeration $false | Out-Null
    return Get-PnPList -Identity $Title
}

function Test-Field {
    param([string] $List, [string] $Name)
    $fields = Get-PnPField -List $List
    return [bool]($fields | Where-Object { $_.InternalName -eq $Name -or $_.Title -eq $Name })
}

function Ensure-Field {
    param(
        [string] $List,
        [string] $Name,
        [ValidateSet("Text", "Note", "Number", "Currency", "Boolean", "Choice", "URL")] [string] $Type,
        [string[]] $Choices
    )
    if (Test-Field -List $List -Name $Name) { return }
    Write-Host "  + $List.$Name ($Type)"
    if ($Type -eq "Choice") {
        Add-PnPField -List $List -DisplayName $Name -InternalName $Name -Type Choice -Choices $Choices -AddToDefaultView | Out-Null
    }
    else {
        Add-PnPField -List $List -DisplayName $Name -InternalName $Name -Type $Type -AddToDefaultView | Out-Null
    }
}

function Ensure-DateTimeField {
    param([string] $List, [string] $Name)
    if (Test-Field -List $List -Name $Name) { return }
    Write-Host "  + $List.$Name (DateTime)"
    $xml = "<Field Type='DateTime' Format='DateTime' DisplayName='$Name' Name='$Name' StaticName='$Name' ID='{$([guid]::NewGuid())}' />"
    Add-PnPFieldFromXml -List $List -FieldXml $xml | Out-Null
}

function Ensure-PersonField {
    param([string] $List, [string] $Name)
    if (Test-Field -List $List -Name $Name) { return }
    Write-Host "  + $List.$Name (Person)"
    $xml = "<Field Type='User' UserSelectionMode='PeopleOnly' UserSelectionScope='0' DisplayName='$Name' Name='$Name' StaticName='$Name' ID='{$([guid]::NewGuid())}' />"
    Add-PnPFieldFromXml -List $List -FieldXml $xml | Out-Null
}

function Ensure-LookupField {
    param([string] $List, [string] $Name, [string] $TargetList)
    if (Test-Field -List $List -Name $Name) { return }
    Write-Host "  + $List.$Name (Lookup -> $TargetList)"
    $target = Get-PnPList -Identity $TargetList
    $xml = "<Field Type='Lookup' DisplayName='$Name' Name='$Name' StaticName='$Name' ID='{$([guid]::NewGuid())}' List='{$($target.Id)}' ShowField='Title' Indexed='TRUE' />"
    Add-PnPFieldFromXml -List $List -FieldXml $xml | Out-Null
}

function Ensure-Index {
    param([string] $List, [string] $Name)
    $field = Get-PnPField -List $List | Where-Object { $_.InternalName -eq $Name -or $_.Title -eq $Name } | Select-Object -First 1
    if (-not $field) { Write-Warning "Index impossible : colonne $Name absente de $List"; return }
    if (-not $field.Indexed) {
        Set-PnPField -List $List -Identity $field.InternalName -Values @{ Indexed = $true } | Out-Null
        Write-Host "  index $List.$($field.InternalName)"
    }
}

function Ensure-Item {
    param([string] $List, [string] $Title, [hashtable] $Values)
    $existing = Get-PnPListItem -List $List -PageSize 500 | Where-Object { $_["Title"] -eq $Title }
    if ($existing) { return }
    $Values["Title"] = $Title
    Add-PnPListItem -List $List -Values $Values | Out-Null
    Write-Host "  item $List : $Title"
}

# ---------------------------------------------------------------------------
# 1. Procurement Records : contrôle du schéma existant
# ---------------------------------------------------------------------------

Write-Host "`n1. Contrôle de $RecordsListTitle" -ForegroundColor Yellow
if (-not (Get-PnPList -Identity $RecordsListTitle -ErrorAction SilentlyContinue)) {
    throw "La liste $RecordsListTitle est introuvable. Le cahier (§9) indique qu'elle existe déjà ; vérifiez le site."
}

$expected = @(
    "Title", "RecordID", "Status", "Department", "Project Owner", "Business Owner",
    "BusinessNeed", "PurchaseType", "RequiredDate", "FundingSource", "SupplierName", "ProcurementContext",
    "RelatedPartyFlag", "InitialRisks", "MainPrice", "CurrencyTreatment", "OptionsValue", "RenewalsValue",
    "RecurringAnnualValue", "RecurringYears", "ImplementationValue", "FeesExpensesValue",
    "RelatedPurchasesValue", "RelatedPurchasesReference", "TotalExpectedCommitment", "BudgetReference",
    "ValueCalculationBasis", "ProcurementLevel", "ProcurementLevelName", "ProcurementRoute",
    "CompetitionRequirement", "ApprovalAuthority", "LegalMandatory", "DueDiligenceTier", "RiskProfile",
    "RiskData", "RiskIT", "RiskIP", "RiskPricing", "RiskLiability", "RiskLaw", "RiskConflict", "RiskCritical",
    "Legal Reviewer", "Finance Reviewer", "Business Approver", "Signature Authority",
    "SubmittedOn", "ApprovedOn", "ContractSignedOn", "ClosedOn", "LatestPDFUrl", "Comments"
)
$missing = $expected | Where-Object { -not (Test-Field -List $RecordsListTitle -Name $_) }
if ($missing) {
    Write-Warning ("Colonnes de l'annexe A absentes (à créer ou à documenter par IT) : " + ($missing -join ", "))
}
else {
    Write-Host "  Toutes les colonnes de l'annexe A sont présentes."
}

# Un brouillon est enregistré incomplet : aucune colonne métier ne doit être obligatoire au niveau SharePoint,
# sinon Patch échoue dès le premier enregistrement. L'obligation est contrôlée par l'application (nfMissing)
# et par le flux de soumission. Rapport uniquement.
$required = Get-PnPField -List $RecordsListTitle | Where-Object { $_.Required -and -not $_.Hidden -and $_.InternalName -ne "Title" }
if ($required) {
    Write-Warning ("Colonnes obligatoires dans SharePoint, à passer en facultatif pour permettre les brouillons : " + (($required | ForEach-Object { $_.InternalName }) -join ", "))
}
$titleField = Get-PnPField -List $RecordsListTitle -Identity "Title"
if ($titleField.Required) {
    Write-Host "  Title est obligatoire : l'application le pré-remplit à la création, aucun changement requis."
}

# Statuts : le cahier (§6.2) ne prévoit pas Rejected. Rapport uniquement.
$status = Get-PnPField -List $RecordsListTitle -Identity "Status" -ErrorAction SilentlyContinue
if ($status -and $status.Choices -notcontains "Rejected") {
    Write-Warning "Le choix Status ne contient pas 'Rejected'. Voir README, décision recommandée."
}

# Colonnes techniques ajoutées (documentées dans README)
Write-Host "  Colonnes techniques"
Ensure-Field -List $RecordsListTitle -Name "RecordVersion" -Type Number
Ensure-Field -List $RecordsListTitle -Name "LastStep" -Type Number
Ensure-Field -List $RecordsListTitle -Name "AmendmentPending" -Type Boolean
Ensure-Field -List $RecordsListTitle -Name "AmendmentReason" -Type Note
Ensure-Field -List $RecordsListTitle -Name "PdfRequested" -Type Boolean
Ensure-Field -List $RecordsListTitle -Name "PdfReason" -Type Text

Set-PnPList -Identity $RecordsListTitle -EnableVersioning $true -EnableModeration $false | Out-Null
foreach ($idx in @("RecordID", "Status", "Project Owner", "Business Owner", "Department", "SupplierName")) {
    Ensure-Index -List $RecordsListTitle -Name $idx
}

# ---------------------------------------------------------------------------
# 2. Listes de paramétrage
# ---------------------------------------------------------------------------

Write-Host "`n2. Paramétrage" -ForegroundColor Yellow

Ensure-List -Title "Procurement Config" | Out-Null
Ensure-Field -List "Procurement Config" -Name "Level" -Type Number
Ensure-Field -List "Procurement Config" -Name "LevelName" -Type Text
Ensure-Field -List "Procurement Config" -Name "MinValueExcl" -Type Number
Ensure-Field -List "Procurement Config" -Name "MaxValueIncl" -Type Number
Ensure-Field -List "Procurement Config" -Name "Route" -Type Text
Ensure-Field -List "Procurement Config" -Name "CompetitionRequirement" -Type Note
Ensure-Field -List "Procurement Config" -Name "ApprovalAuthority" -Type Text
Ensure-Field -List "Procurement Config" -Name "RequiredRouteEvidence" -Type Note

# Seuils, routes, autorités et preuves : repris à l'identique du prototype V3.2 FINAL R4 (fonctions recalc,
# routes, approvers, competition, notes, actions). ApprovalAuthority désigne une fonction ou un organe,
# jamais une personne (§8.2). Level 1 commence strictement au-dessus de 0 : un total nul ne produit
# aucun niveau, comme dans le prototype.
Ensure-Item -List "Procurement Config" -Title "Level 1" -Values @{
    Level = 1; LevelName = "Standard"; MinValueExcl = 0; MaxValueIncl = 25000; Route = "Direct appointment"
    CompetitionRequirement = "Price-reasonableness evidence. Document the need, price reasonableness, approval and contractual basis."
    ApprovalAuthority = "Relevant budget owner with delegated authority"
    RequiredRouteEvidence = "Define the need and total value; Keep price-reasonableness evidence; Record approval and contractual basis"
}
Ensure-Item -List "Procurement Config" -Title "Level 2" -Values @{
    Level = 2; LevelName = "Controlled"; MinValueExcl = 25000; MaxValueIncl = 50000; Route = "Market assessment"
    CompetitionRequirement = "At least two identified suppliers and indicative prices. Record the market assessment and recommendation."
    ApprovalAuthority = "Relevant Director or approved equivalent"
    RequiredRouteEvidence = "Identify at least two suppliers; Record indicative pricing; Document the recommendation"
}
Ensure-Item -List "Procurement Config" -Title "Level 3" -Values @{
    Level = 3; LevelName = "Enhanced"; MinValueExcl = 50000; MaxValueIncl = 250000; Route = "Competitive request for proposals"
    CompetitionRequirement = "Normally at least three written offers and evaluation. Use a written specification and criteria fixed in advance."
    ApprovalAuthority = "Relevant senior approver under the EFC DoA"
    RequiredRouteEvidence = "Issue a written RFP; Seek normally at least three written offers; Retain the evaluation and award recommendation"
}
Ensure-Item -List "Procurement Config" -Title "Level 4" -Values @{
    Level = 4; LevelName = "Strategic"; MinValueExcl = 250000; Route = "Market information request followed by competitive RFP"
    CompetitionRequirement = "Market discovery where useful, normally at least three offers and full evaluation. Complete market discovery, formal competition and full evaluation."
    ApprovalAuthority = "Competent executive or governance body under the EFC DoA"
    RequiredRouteEvidence = "Run market discovery or an RFI where useful; Issue a competitive RFP; Retain the full evaluation and governance approval"
}

Ensure-List -Title "Procurement Settings" | Out-Null
Ensure-Field -List "Procurement Settings" -Name "SettingValue" -Type Text
Ensure-Field -List "Procurement Settings" -Name "SettingDescription" -Type Note

$settings = [ordered]@{
    "NearThresholdPercent"     = @("5", "Alerte si le total dépasse (100 - X) % d'un seuil sans l'atteindre. Prototype V3.2 : 5 %.")
    "LegalMandatory.MinLevel"  = @("3", "Niveau à partir duquel la revue Legal est obligatoire. Prototype V3.2 : 3.")
    "ContractRequired.Above"   = @("10000", "Annex 3 : au-delà de ce montant, contrat écrit exécuté exigé ; en dessous, devis accepté suffisant.")
    "GroupId.Users"            = @("", "Object ID Entra de EFC-Procurement-Users")
    "GroupId.Legal"            = @("", "Object ID Entra de EFC-Procurement-Legal")
    "GroupId.Finance"          = @("", "Object ID Entra de EFC-Procurement-Finance")
    "GroupId.Approvers"        = @("", "Object ID Entra de EFC-Procurement-Approvers")
    "GroupId.Administrators"   = @("", "Object ID Entra de EFC-Procurement-Administrators")
    "GroupId.Auditors"         = @("", "Object ID Entra de EFC-Procurement-Auditors")
    "AdminEmail"               = @("", "Adresse (de préférence une boîte partagée) qui reçoit les erreurs de flux.")
    "AppUrl"                   = @("", "URL de lecture de l'application (https://apps.powerapps.com/play/e/.../a/...).")
    "DocumentsLibraryUrl"      = @("", "URL du site + chemin de la bibliothèque Procurement Documents.")
}
foreach ($key in $settings.Keys) {
    Ensure-Item -List "Procurement Settings" -Title $key -Values @{ SettingValue = $settings[$key][0]; SettingDescription = $settings[$key][1] }
}

Ensure-List -Title "Procurement Policy Links" | Out-Null
Ensure-Field -List "Procurement Policy Links" -Name "Summary" -Type Note
Ensure-Field -List "Procurement Policy Links" -Name "DocumentUrl" -Type URL
Ensure-Field -List "Procurement Policy Links" -Name "SortOrder" -Type Number
Ensure-Field -List "Procurement Policy Links" -Name "IsActive" -Type Boolean

# Résumés et liens repris du prototype. ATTENTION : les liens du prototype sont des recherches SharePoint
# (_layouts/15/search.aspx?q=...), pas des liens directs. Le cahier (§7.7) exige un lien vers la version
# publiée : remplacer chaque DocumentUrl par le lien direct dès que les documents sont publiés.
$search = "https://ecaeurope.sharepoint.com/_layouts/15/search.aspx?q="
$policies = @(
    @{ T = "Procurement Policy V3.2"; F = "EFC_Procurement_Policy_V3.2.docx"
       S = "Mandatory governance policy for procurement by EFC. Use it before EFC signs, orders, instructs work or approves payment. Core rules: calculate the full expected commitment (fees, expenses, options, renewals, extensions, related purchases); do not split requirements; use proportionate competition and documented criteria; complete risk-based due diligence before award; declare conflicts, related parties, gifts and hospitality; obtain approvals before commitment (budget availability is not approval); use a valid contractual basis and an authorised signatory; keep an auditable file. Mandatory law, the EFC Statutes and governing-body resolutions prevail; the Policy prevails over its Annexes." },
    @{ T = "Annex 1 - Procedure V3.2"; F = "EFC_Procurement_Annex_1_Procedure_V3.2.docx"
       S = "Operational sourcing and award workflow. Up to EUR 25,000: direct appointment. EUR 25,001-50,000: market assessment, at least two suppliers and indicative prices. EUR 50,001-250,000: competitive RFP, normally three written offers and evaluation. Above EUR 250,000: RFI where useful, then competitive RFP and full evaluation. Key rule: no signature, order, start of work or payment approval until the correct route and controls have been checked." },
    @{ T = "Annex 2 - Delegation of Authority V3.2"; F = "EFC_Procurement_Annex_2_Delegation_of_Authority_V3.2.docx"
       S = "Approval before commitment. No self-approval and no approval outside delegated limits. The highest applicable approval prevails. Budget approval does not approve the procurement. Related-party cases require recusal and independent approval. Escalate reserved matters, exceptions, conflicts, unclear authority, unbudgeted commitments and material risk. Procurement approval does not grant signature authority." },
    @{ T = "Annex 3 - Contracting Guidelines V3.2"; F = "EFC_Procurement_Annex_3_Contracting_Guidelines_V3.2.docx"
       S = "Up to EUR 10,000: signed or formally accepted quotation and expressly accepted terms, unless risk requires a contract. Above EUR 10,000: executed written contract before commencement or payment. Mandatory Legal involvement regardless of value: NDAs, personal data, privacy, security, IT, software, cloud; open-ended or uncapped pricing; employment or individual-consultant classification; IP, publications, research, collaboration or sponsorship; material liability, indemnity, sanctions, regulatory or reputational risk; non-approved governing law, forum or arbitration." },
    @{ T = "Annex 4 - Signature Authority Matrix V3.2"; F = "EFC_Procurement_Annex_4_Signature_Authority_Matrix_V3.2.docx"
       S = "Authority arises only from the applicable register authority or a valid power of attorney. Verify entity, value, subject, duration, territory and joint-signature limits. Complete Legal and business approvals before signature. Use only the Legal-approved execution copy. Do not infer authority from title, seniority, budget or past practice. Do not sign blank, incomplete or backdated documents. Report any unauthorised commitment to Legal immediately." },
    @{ T = "Annex 5 - Supplier Due Diligence Procedure V3.2"; F = "EFC_Procurement_Annex_5_Supplier_Due_Diligence_V3.2.docx"
       S = "Low: standard supply, no sensitive access, high-risk geography or dependency; identity, bank, conflict, sanctions and basic commercial checks. Medium: material value, data or premises access, subcontracting, event dependency or ESG exposure; add ownership, financial, privacy/security, insurance, references and sustainability checks. High: strategic dependency, public officials, sensitive data, critical systems, adverse information, complex ownership or marginal result; enhanced Legal/Compliance review and governance approval. Outcomes: Pass, Pass with conditions, Marginal (no award until enhanced review), Fail." }
)
$order = 1
foreach ($p in $policies) {
    Ensure-Item -List "Procurement Policy Links" -Title $p.T -Values @{
        SortOrder = $order; IsActive = $true; Summary = $p.S
        DocumentUrl = "$search$($p.F), $($p.F)"
    }
    $order++
}

# Valeurs de choix attendues par l'application et les flux (prototype V3.2). Rapport uniquement :
# une valeur différente dans SharePoint ne casse pas l'application, mais elle doit être reportée ici.
$expectedChoices = @{
    "Department"         = @("Corporate Services", "Finance", "Legal", "Communications", "Football Affairs", "Commercial", "Events", "IT", "HR", "Other")
    "PurchaseType"       = @("Goods", "Services", "IT, software or cloud", "Works", "Events, venue or travel", "Consultant or individual")
    "FundingSource"      = @("EFC budget", "Grant or donor funding", "Public or restricted funding")
    "ProcurementContext" = @("New procurement", "Existing supplier", "Renewal or extension", "Additional scope or change", "Related purchase")
    "CurrencyTreatment"  = @("EUR — no conversion required", "Finance-confirmed EUR equivalent", "Finance confirmation pending")
    "RiskProfile"        = @("Low", "Medium", "High")
    "DueDiligenceTier"   = @("Low", "Medium", "High")
}
foreach ($col in $expectedChoices.Keys) {
    $f = Get-PnPField -List $RecordsListTitle | Where-Object { $_.InternalName -eq $col -or $_.Title -eq $col } | Select-Object -First 1
    if (-not $f) { continue }
    $f = Get-PnPField -List $RecordsListTitle -Identity $f.InternalName
    $missingChoices = $expectedChoices[$col] | Where-Object { $f.Choices -notcontains $_ }
    if ($missingChoices) { Write-Warning "$col : valeurs absentes de la colonne Choice : $($missingChoices -join ' | ')" }
}

# ---------------------------------------------------------------------------
# 3. Procurement Approvals
# ---------------------------------------------------------------------------

Write-Host "`n3. Procurement Approvals" -ForegroundColor Yellow
Ensure-List -Title "Procurement Approvals" | Out-Null
Ensure-LookupField -List "Procurement Approvals" -Name "ProcurementRecord" -TargetList $RecordsListTitle
Ensure-Field -List "Procurement Approvals" -Name "RecordID" -Type Text
Ensure-Field -List "Procurement Approvals" -Name "ApprovalType" -Type Choice -Choices @("Finance", "Legal", "Business", "Signature")
Ensure-Field -List "Procurement Approvals" -Name "Sequence" -Type Number
Ensure-PersonField -List "Procurement Approvals" -Name "Approver"
Ensure-Field -List "Procurement Approvals" -Name "Decision" -Type Choice -Choices @("Not started", "Pending", "Approved", "Approved with conditions", "Returned", "Rejected", "Cancelled")
Ensure-DateTimeField -List "Procurement Approvals" -Name "DecisionDate"
Ensure-Field -List "Procurement Approvals" -Name "Comments" -Type Note
Ensure-Field -List "Procurement Approvals" -Name "Conditions" -Type Note
Ensure-DateTimeField -List "Procurement Approvals" -Name "RequestedOn"
Ensure-PersonField -List "Procurement Approvals" -Name "RequestedBy"
Ensure-Field -List "Procurement Approvals" -Name "ApprovalVersion" -Type Number
Ensure-Field -List "Procurement Approvals" -Name "Processed" -Type Boolean
foreach ($idx in @("RecordID", "Decision", "Approver", "ApprovalVersion")) { Ensure-Index -List "Procurement Approvals" -Name $idx }

# ---------------------------------------------------------------------------
# 4. Procurement History
# ---------------------------------------------------------------------------

Write-Host "`n4. Procurement History" -ForegroundColor Yellow
Ensure-List -Title "Procurement History" | Out-Null
Ensure-LookupField -List "Procurement History" -Name "ProcurementRecord" -TargetList $RecordsListTitle
Ensure-Field -List "Procurement History" -Name "RecordID" -Type Text
Ensure-Field -List "Procurement History" -Name "EventType" -Type Choice -Choices @(
    "Created", "Submitted", "SubmissionRefused", "ApprovalRequested", "Decision", "Returned", "Reopened",
    "Approved", "Rejected", "PDFGenerated", "DocumentUploaded", "ContractSigned", "Closed", "Cancelled", "FlowError")
Ensure-DateTimeField -List "Procurement History" -Name "EventDate"
Ensure-PersonField -List "Procurement History" -Name "PerformedBy"
Ensure-Field -List "Procurement History" -Name "PreviousStatus" -Type Text
Ensure-Field -List "Procurement History" -Name "NewStatus" -Type Text
Ensure-Field -List "Procurement History" -Name "VersionNumber" -Type Number
Ensure-Field -List "Procurement History" -Name "ChangeSummary" -Type Note
Ensure-Field -List "Procurement History" -Name "PDFUrl" -Type URL
foreach ($idx in @("RecordID", "EventType")) { Ensure-Index -List "Procurement History" -Name $idx }

# ---------------------------------------------------------------------------
# 5. Procurement Documents (bibliothèque)
# ---------------------------------------------------------------------------

Write-Host "`n5. Procurement Documents" -ForegroundColor Yellow
Ensure-List -Title "Procurement Documents" -Template DocumentLibrary | Out-Null
Ensure-LookupField -List "Procurement Documents" -Name "ProcurementRecord" -TargetList $RecordsListTitle
Ensure-Field -List "Procurement Documents" -Name "RecordID" -Type Text
Ensure-Field -List "Procurement Documents" -Name "DocumentType" -Type Choice -Choices @(
    "Generated PDF", "Quote or offer", "Sourcing evidence", "Evaluation", "Due diligence",
    "Contract", "Purchase order", "Approval evidence", "Other")
Ensure-Field -List "Procurement Documents" -Name "DocVersion" -Type Number
Ensure-Field -List "Procurement Documents" -Name "DocStatus" -Type Choice -Choices @("Current", "Superseded")
Ensure-PersonField -List "Procurement Documents" -Name "DocOwner"
foreach ($idx in @("RecordID", "DocumentType", "DocStatus")) { Ensure-Index -List "Procurement Documents" -Name $idx }

Write-Host "`nTerminé. Étape suivante : renseigner les GroupId.*, AdminEmail et les DocumentUrl de Procurement Policy Links." -ForegroundColor Green
