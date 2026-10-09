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

# Seuils du cahier §8.2. ApprovalAuthority reste à compléter selon l'Annex 2 (Delegation of Authority) :
# une fonction ou un organe, jamais le nom d'une personne (§8.2).
Ensure-Item -List "Procurement Config" -Title "Level 1" -Values @{
    Level = 1; LevelName = "Standard"; MaxValueIncl = 25000; Route = "Direct appointment"
    CompetitionRequirement = "Preuve proportionnée du caractère raisonnable du prix."
    ApprovalAuthority = "A CONFIRMER - Annex 2 DoA"
    RequiredRouteEvidence = "Justification du prix (devis, comparaison, historique)."
}
Ensure-Item -List "Procurement Config" -Title "Level 2" -Values @{
    Level = 2; LevelName = "Controlled"; MinValueExcl = 25000; MaxValueIncl = 50000; Route = "Market assessment"
    CompetitionRequirement = "Au moins deux fournisseurs identifiés et éléments de prix indicatifs."
    ApprovalAuthority = "A CONFIRMER - Annex 2 DoA"
    RequiredRouteEvidence = "Note de market assessment avec au moins deux fournisseurs et prix indicatifs."
}
Ensure-Item -List "Procurement Config" -Title "Level 3" -Values @{
    Level = 3; LevelName = "Enhanced"; MinValueExcl = 50000; MaxValueIncl = 250000; Route = "Competitive RFP"
    CompetitionRequirement = "Normalement au moins trois offres écrites et évaluation documentée."
    ApprovalAuthority = "A CONFIRMER - Annex 2 DoA"
    RequiredRouteEvidence = "Dossier RFP, trois offres écrites, grille d'évaluation signée."
}
Ensure-Item -List "Procurement Config" -Title "Level 4" -Values @{
    Level = 4; LevelName = "Strategic"; MinValueExcl = 250000; Route = "RFI (si utile) puis competitive RFP"
    CompetitionRequirement = "Market discovery, compétition formelle et évaluation complète."
    ApprovalAuthority = "A CONFIRMER - Annex 2 DoA"
    RequiredRouteEvidence = "RFI éventuelle, dossier RFP, offres, évaluation complète, recommandation d'attribution."
}

Ensure-List -Title "Procurement Settings" | Out-Null
Ensure-Field -List "Procurement Settings" -Name "SettingValue" -Type Text
Ensure-Field -List "Procurement Settings" -Name "SettingDescription" -Type Note

$settings = [ordered]@{
    "NearThresholdPercent"     = @("10", "Alerte si le total atteint (100 - X) % du plafond du niveau courant.")
    "LegalMandatory.MinLevel"  = @("3", "Niveau à partir duquel la revue Legal est obligatoire. HYPOTHESE à valider.")
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

$policies = @(
    "Procurement Policy V3.2", "Annex 1 - Procedure V3.2", "Annex 2 - Delegation of Authority V3.2",
    "Annex 3 - Contracting Guidelines V3.2", "Annex 4 - Signature Authority Matrix V3.2",
    "Annex 5 - Supplier Due Diligence Procedure V3.2"
)
$order = 1
foreach ($p in $policies) {
    Ensure-Item -List "Procurement Policy Links" -Title $p -Values @{ SortOrder = $order; IsActive = $true; Summary = "A RÉDIGER : résumé opérationnel validé par Legal." }
    $order++
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
