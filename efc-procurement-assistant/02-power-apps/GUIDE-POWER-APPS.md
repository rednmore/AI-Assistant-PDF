# Construction de la Canvas App

Ce guide suit l'ordre dans lequel il faut construire l'application. Les noms de contrôles indiqués sont ceux qu'utilisent les formules nommées (App.Formulas.fx) et les flux. Si vous en changez un, changez-le partout.

Principe retenu : un écran d'accueil (scrHome) et un écran dossier unique (scrRecord) qui contient les six étapes dans six conteneurs. Les étapes 1, 2, 4 et 5 sont des formulaires d'édition SharePoint, tous liés au même enregistrement varRec. Les étapes 3 et 6 sont en lecture seule. Ce choix présente trois avantages. Les formulaires gèrent nativement les colonnes Person et Choice, et se rechargent seuls lorsqu'on change de dossier. Un seul Patch enregistre l'ensemble des étapes. Les formules nommées voient en permanence la saisie de toutes les étapes, ce qui garde le total, la route et les risques cohérents.

## 1. Création et réglages

1. Dans make.powerapps.com, ouvrir la solution « EFC Procurement Assistant », puis Nouveau > Application > Application canevas, au format Tablette.
2. Dans Paramètres > Affichage, désactiver « Mettre à l'échelle pour s'adapter » et « Verrouiller les proportions ». L'application devient responsive (§12, §13).
3. Dans Paramètres > Mises à jour, vérifier que « Gestion des erreurs au niveau des formules » est activée. Elle est nécessaire pour vider une colonne Person avec Blank(). Activer aussi « Formules nommées » et « Fonctions définies par l'utilisateur » si elles apparaissent encore comme options.
4. Dans Paramètres > Général, régler la limite de lignes de données à 2000.
5. Ajouter les sources de données suivantes : Procurement Records, Procurement Approvals, Procurement History, Procurement Documents, Procurement Config, Procurement Settings, Procurement Policy Links, ainsi que les connecteurs Office 365 Utilisateurs et Office 365 Groupes.
6. Une fois les flux F0 et F7 créés, les ajouter depuis le volet Power Automate : RecordAction et UploadProcurementDocument.

## 2. Objet App

Formulas : coller le contenu de App.Formulas.fx. Tant que les contrôles qu'il cite n'existent pas, Power Apps affiche des erreurs, et c'est normal. Vous pouvez aussi ne coller que les blocs « paramètres » et « palette », puis ajouter les autres au fur et à mesure.

OnStart :

```
// Rôles : appartenance directe aux groupes Entra. Les groupes imbriqués ne sont pas résolus :
// gérer des membres directs uniquement, ou remplacer par un flux qui appelle checkMemberGroups.
With(
    {
        gLegal: LookUp('Procurement Settings', Title = "GroupId.Legal", SettingValue),
        gFinance: LookUp('Procurement Settings', Title = "GroupId.Finance", SettingValue),
        gApprovers: LookUp('Procurement Settings', Title = "GroupId.Approvers", SettingValue),
        gAdmins: LookUp('Procurement Settings', Title = "GroupId.Administrators", SettingValue),
        gAuditors: LookUp('Procurement Settings', Title = "GroupId.Auditors", SettingValue)
    },
    Concurrent(
        ClearCollect(colLegalMembers, Office365Groups.ListGroupMembers(gLegal, {'$top': 999}).value),
        ClearCollect(colFinanceMembers, Office365Groups.ListGroupMembers(gFinance, {'$top': 999}).value),
        ClearCollect(colApproverMembers, Office365Groups.ListGroupMembers(gApprovers, {'$top': 999}).value),
        ClearCollect(colAdminMembers, Office365Groups.ListGroupMembers(gAdmins, {'$top': 999}).value),
        ClearCollect(colAuditorMembers, Office365Groups.ListGroupMembers(gAuditors, {'$top': 999}).value)
    )
);
Set(varIsLegal, !IsBlank(LookUp(colLegalMembers, Lower(userPrincipalName) = nfUserEmail || Lower(mail) = nfUserEmail)));
Set(varIsFinance, !IsBlank(LookUp(colFinanceMembers, Lower(userPrincipalName) = nfUserEmail || Lower(mail) = nfUserEmail)));
Set(varIsAdmin, !IsBlank(LookUp(colAdminMembers, Lower(userPrincipalName) = nfUserEmail || Lower(mail) = nfUserEmail)));
Set(varIsAuditor, !IsBlank(LookUp(colAuditorMembers, Lower(userPrincipalName) = nfUserEmail || Lower(mail) = nfUserEmail)));
Set(varHomeTab, "Drafts");
Set(varStep, 1)
```

StartScreen :

```
If(IsBlank(Param("recordId")), scrHome, scrRecord)
```

Les flux envoient des liens de la forme AppUrl?recordId=123&view=decision. Le chargement du dossier se fait dans scrRecord.OnVisible, et non dans OnStart, pour rester correct même lorsque OnStart n'est pas bloquant.

## 3. Bandeau commun

Construire le bandeau une fois sur scrHome, puis le copier sur scrRecord.

1. Conteneur horizontal conHeader : Height 64, Fill nfNavy, PaddingLeft et PaddingRight 24, LayoutAlignItems Center.
2. Image imgLogo : logo EFC en blanc, Height 36.
3. Libellé lblAppTitle : Text "EFC Procurement Assistant", Color White, Size 18, FontWeight Semibold, FillPortions 1.
4. Bouton btnPolicy : Text "Policy & Annexes", Fill Transparent, BorderColor nfCyan, Color White, OnSelect `Set(varShowPolicy, true)`.
5. Libellé lblUser : Text `User().FullName`, Color White.

Panneau Policy & Annexes (§7.7), à copier sur les deux écrans, au-dessus de tous les autres contrôles :

1. Conteneur conPolicy : Visible varShowPolicy, X `Parent.Width - Self.Width`, Width `Min(480, Parent.Width)`, Height Parent.Height, Fill White, DropShadow Bold.
2. Galerie galPolicy, avec Items :

```
SortByColumns(Filter('Procurement Policy Links', IsActive = true), "SortOrder", SortOrder.Ascending)
```

3. Dans le modèle de la galerie : un libellé pour le titre (ThisItem.Title, en gras, couleur nfNavy), un libellé pour le résumé (ThisItem.Summary, AutoHeight true), et un bouton « Ouvrir le document » avec OnSelect `Launch(ThisItem.DocumentUrl)`.
4. Bouton btnClosePolicy : Text "Fermer", OnSelect `Set(varShowPolicy, false)`.

Les liens et les résumés sont administrés dans la liste SharePoint. Les modifier ne nécessite pas de republier l'application.

## 4. Écran d'accueil scrHome

Fill nfBackground.

1. Bouton btnNew : Text "New Procurement", Fill nfNavy. OnSelect :

```
IfError(
    Set(
        varRec,
        Patch(
            'Procurement Records',
            Defaults('Procurement Records'),
            {
                Title: "Nouveau dossier " & Text(Now(), "dd.mm.yyyy hh:mm"),
                Status: {Value: "Draft"},
                'Project Owner': {
                    Claims: "i:0#.f|membership|" & nfUserEmail,
                    DisplayName: User().FullName,
                    Email: nfUserEmail,
                    Department: "",
                    JobTitle: "",
                    Picture: ""
                },
                FundingSource: {Value: "EFC budget"},
                ProcurementContext: {Value: "New procurement"},
                CurrencyTreatment: {Value: "EUR — no conversion required"},
                RecordVersion: 1,
                LastStep: 1
            }
        )
    );
    Set(
        varRec,
        Patch('Procurement Records', varRec, {RecordID: "PR-" & Text(Year(Now())) & "-" & Text(varRec.ID, "0000")})
    );
    Set(varStep, 1);
    Navigate(scrRecord, ScreenTransition.None),
    Notify("Création impossible : " & FirstError.Message, NotificationType.Error)
)
```

2. Galerie horizontale galTabs, servant d'onglets. Items :

```
Table(
    {Key: "Drafts", Label: "My Drafts"},
    {Key: "Open", Label: "My Open Records"},
    {Key: "Approvals", Label: "Approvals Pending"},
    {Key: "Search", Label: "Search"}
)
```

Dans le modèle, un bouton avec Text ThisItem.Label, Fill `If(varHomeTab = ThisItem.Key, nfNavy, White)`, Color `If(varHomeTab = ThisItem.Key, White, nfNavy)`, et OnSelect `Set(varHomeTab, ThisItem.Key)`.

3. Conteneur conSearch, Visible `varHomeTab = "Search"`, contenant :
    1. Une zone de texte txtSearch, avec HintText "RecordID, titre ou fournisseur (début du texte)".
    2. Une liste déroulante cmbSearchStatus, avec Items `Choices([@'Procurement Records'].Status)`.
    3. Une liste déroulante cmbSearchDepartment, avec Items `Choices([@'Procurement Records'].Department)`.
    4. Une liste déroulante cmbSearchOwner, avec Items `Choices([@'Procurement Records'].'Project Owner')`.

    Les trois listes déroulantes sont des ComboBox classiques avec SelectMultiple false.

4. Galerie galRecords (verticale), avec Items :

```
Switch(
    varHomeTab,
    "Drafts",
        SortByColumns(
            Filter(
                'Procurement Records',
                Status.Value = "Draft" &&
                ('Project Owner'.Email = User().Email || 'Business Owner'.Email = User().Email)
            ),
            "Modified", SortOrder.Descending
        ),
    "Open",
        SortByColumns(
            Filter(
                'Procurement Records',
                (Status.Value = "Draft" || Status.Value = "Ready for Submission" || Status.Value = "Under Review" ||
                 Status.Value = "Returned for Amendment" || Status.Value = "Approved" || Status.Value = "Contract Signed") &&
                ('Project Owner'.Email = User().Email || 'Business Owner'.Email = User().Email ||
                 'Legal Reviewer'.Email = User().Email || 'Finance Reviewer'.Email = User().Email ||
                 'Business Approver'.Email = User().Email || 'Signature Authority'.Email = User().Email)
            ),
            "Modified", SortOrder.Descending
        ),
    "Search",
        SortByColumns(
            Filter(
                'Procurement Records',
                IsBlank(txtSearch.Text) || StartsWith(RecordID, txtSearch.Text) ||
                    StartsWith(Title, txtSearch.Text) || StartsWith(SupplierName, txtSearch.Text),
                IsBlank(cmbSearchStatus.Selected) || Status.Value = cmbSearchStatus.Selected.Value,
                IsBlank(cmbSearchDepartment.Selected) || Department.Value = cmbSearchDepartment.Selected.Value,
                IsBlank(cmbSearchOwner.Selected) || 'Project Owner'.Email = cmbSearchOwner.Selected.Email
            ),
            "Modified", SortOrder.Descending
        )
)
```

Visible `varHomeTab <> "Approvals"`. Dans le modèle : un libellé ThisItem.RecordID (couleur nfMuted), un libellé ThisItem.Title (en gras), un libellé `ThisItem.Status.Value & " · " & ThisItem.SupplierName & " · " & Text(ThisItem.TotalExpectedCommitment, "€ #,##0")`, et une pastille de niveau dont le Text vaut `"L" & ThisItem.ProcurementLevel`. OnSelect du modèle :

```
Set(varRec, ThisItem);
Set(varStep, Coalesce(ThisItem.LastStep, 1));
Navigate(scrRecord, ScreenTransition.None)
```

Les galeries n'utilisent que des opérateurs délégables à SharePoint (égalité sur Choice et Person, StartsWith, Or). La recherche porte sur le début du texte et non sur une partie quelconque du titre : c'est une limite de SharePoint, pas un choix. Pour une recherche plein texte, il faudrait Dataverse ou la recherche SharePoint, ce qui dépasse le périmètre.

5. Galerie galApprovals, avec Visible `varHomeTab = "Approvals"` et Items :

```
SortByColumns(
    Filter('Procurement Approvals', Decision.Value = "Pending" && Approver.Email = User().Email),
    "RequestedOn", SortOrder.Ascending
)
```

Modèle : ThisItem.RecordID, ThisItem.ProcurementRecord.Value (titre du dossier), ThisItem.ApprovalType.Value, et `"Demandé le " & Text(ThisItem.RequestedOn, "dd.mm.yyyy")`. OnSelect :

```
Set(varRec, LookUp('Procurement Records', ID = ThisItem.ProcurementRecord.Id));
Set(varStep, 6);
Navigate(scrRecord, ScreenTransition.None)
```

6. Libellé lblEmpty : Text "Aucun dossier", Visible `IsEmpty(galRecords.AllItems) && varHomeTab <> "Approvals"`.

## 5. Écran dossier scrRecord

### 5.1 OnVisible

```
// Chargement depuis un lien de notification
If(
    !IsBlank(Param("recordId")) && IsBlank(varRec),
    Set(varRec, LookUp('Procurement Records', ID = Value(Param("recordId"))));
    Set(varStep, If(Param("view") = "decision", 6, Coalesce(varRec.LastStep, 1)))
);
// Rafraîchit le dossier (un flux a pu le modifier entre-temps)
Set(varRec, LookUp('Procurement Records', ID = varRec.ID));
Set(
    varCanEdit,
    varRec.Status.Value in ["Draft", "Returned for Amendment"] &&
    (Lower(varRec.'Project Owner'.Email) = nfUserEmail || Lower(varRec.'Business Owner'.Email) = nfUserEmail || varIsAdmin)
);
Set(
    varMyApproval,
    LookUp(
        'Procurement Approvals',
        RecordID = varRec.RecordID && Decision.Value = "Pending" && Approver.Email = User().Email
    )
);
Set(varShowPolicy, false)
```

Si varRec est vide (dossier introuvable ou non autorisé), afficher un libellé « Dossier introuvable ou accès refusé » et masquer le reste. Visible du conteneur principal : `!IsBlank(varRec)`.

### 5.2 Structure

1. conHeader (copié depuis l'accueil). Ajouter un bouton btnBack "← Accueil", avec OnSelect `Set(varRec, Blank()); Navigate(scrHome, ScreenTransition.None)`. Pour avertir des modifications non enregistrées, utiliser plutôt :

```
If(
    frmWhat.Unsaved || frmHowMuch.Unsaved || frmChecks.Unsaved || frmApprovals.Unsaved,
    Set(varConfirmLeave, true),
    Set(varRec, Blank()); Navigate(scrHome, ScreenTransition.None)
)
```

   Ajouter alors un petit conteneur de confirmation (Visible varConfirmLeave) avec deux boutons : « Enregistrer et quitter » (`Select(btnSave); Set(varConfirmLeave, false)`) et « Quitter sans enregistrer » (`Set(varConfirmLeave, false); Set(varRec, Blank()); Navigate(scrHome)`).

2. Bandeau dossier lblRecordHeader : Text `varRec.RecordID & " · " & varRec.Title & " · " & varRec.Status.Value & " · v" & varRec.RecordVersion`.

3. Indicateur d'étapes galSteps (galerie horizontale), avec Items :

```
Table(
    {n: 1, Label: "What"}, {n: 2, Label: "How much"}, {n: 3, Label: "Route"},
    {n: 4, Label: "Checks"}, {n: 5, Label: "Approvals"}, {n: 6, Label: "Sign off"}
)
```

   Dans le modèle, un cercle avec Fill :

```
If(
    ThisItem.n = varStep, nfNavy,
    !(ThisItem.n in nfStepsWithMissing.Value) && ThisItem.n <= Coalesce(varRec.LastStep, 1), nfCyan,
    White
)
```

   Un libellé dans le cercle, avec Text `If(ThisItem.n < varStep && !(ThisItem.n in nfStepsWithMissing.Value), "✓", Text(ThisItem.n))`. Un libellé ThisItem.Label sous le cercle. OnSelect : `Set(varStep, ThisItem.n)`.

4. Six conteneurs conStep1 à conStep6 : Visible `varStep = 1` (et ainsi de suite jusqu'à 6), Fill White, BorderColor nfBorder, BorderThickness 1, RadiusTopLeft et les trois autres rayons à 8. Pas de contour cyan (§12).

5. Pied de page conFooter :
    1. btnPrev "Précédent" : OnSelect `Set(varStep, Max(1, varStep - 1))`.
    2. btnSave "Enregistrer le brouillon" : Visible varCanEdit (formule au point 5.9).
    3. btnNext "Suivant" : OnSelect `If(varCanEdit, Select(btnSave)); Set(varStep, Min(6, varStep + 1))`.

### 5.3 Step 1 – What (conStep1)

Insérer un formulaire d'édition frmWhat : DataSource 'Procurement Records', Item varRec, DefaultMode FormMode.Edit, DisplayMode `If(varCanEdit, DisplayMode.Edit, DisplayMode.View)`, Columns 2.

Champs, dans l'ordre : Title, Department, BusinessNeed, PurchaseType, Project Owner, Business Owner, RequiredDate, FundingSource, SupplierName, ProcurementContext, RelatedPartyFlag, InitialRisks.

Renommer le contrôle de saisie de chaque carte, c'est-à-dire le DataCardValue :

```
Title              -> txtTitle
Department         -> cmbDepartment
BusinessNeed       -> txtBusinessNeed       (Mode multiligne)
PurchaseType       -> cmbPurchaseType
Project Owner      -> cmbProjectOwner
Business Owner     -> cmbBusinessOwner
RequiredDate       -> dteRequiredDate
FundingSource      -> cmbFundingSource
SupplierName       -> txtSupplierName
ProcurementContext -> cmbProcurementContext
RelatedPartyFlag   -> tglRelatedParty
InitialRisks       -> txtInitialRisks
```

Dans chaque carte, mettre la propriété Required de la carte à false : l'obligation est contrôlée au moment de la soumission, pas de l'enregistrement d'un brouillon. Pour marquer visuellement les champs obligatoires, ajouter " *" au libellé de la carte (Title, Department, BusinessNeed, PurchaseType, Project Owner, Business Owner, FundingSource, ProcurementContext).

Valeurs de choix : les colonnes Choice de SharePoint doivent contenir exactement les valeurs du prototype, que le script contrôle. Department : Corporate Services, Finance, Legal, Communications, Football Affairs, Commercial, Events, IT, HR, Other. PurchaseType : Goods, Services, IT, software or cloud, Works, Events, venue or travel, Consultant or individual. FundingSource : EFC budget, Grant or donor funding, Public or restricted funding. ProcurementContext : New procurement, Existing supplier, Renewal or extension, Additional scope or change, Related purchase. Les formules comparent ces libellés au caractère près, par exemple "Consultant or individual" pour le déclencheur Legal.

Libellés à reprendre du prototype : « Business Owner / Project Leader * » pour Business Owner, « Required delivery / start date » pour RequiredDate, « Proposed supplier, if known » pour SupplierName et « Assumptions, dependencies or initial risks » pour InitialRisks. Pour RelatedPartyFlag : « The supplier may be connected to an EFC governing-body member, employee, member organisation or related person ».

Le Project Owner est prérempli à la création (btnNew). Il reste modifiable tant que le dossier est en Draft, ce qui correspond au « contrôle » demandé au §7.1.

### 5.4 Step 2 – How much (conStep2)

Formulaire frmHowMuch, avec les mêmes réglages que frmWhat. Champs : MainPrice, CurrencyTreatment, OptionsValue, RenewalsValue, RecurringAnnualValue, RecurringYears, ImplementationValue, FeesExpensesValue, RelatedPurchasesValue, RelatedPurchasesReference, BudgetReference, ValueCalculationBasis.

Renommer les contrôles :

```
MainPrice                 -> txtMainPrice
CurrencyTreatment         -> cmbCurrencyTreatment
OptionsValue              -> txtOptionsValue
RenewalsValue             -> txtRenewalsValue
RecurringAnnualValue      -> txtRecurringAnnualValue
RecurringYears            -> txtRecurringYears
ImplementationValue       -> txtImplementationValue
FeesExpensesValue         -> txtFeesExpensesValue
RelatedPurchasesValue     -> txtRelatedPurchasesValue
RelatedPurchasesReference -> txtRelatedPurchasesReference
BudgetReference           -> txtBudgetReference
ValueCalculationBasis     -> txtValueCalculationBasis
```

Pour toutes les zones de montant, et pour txtRecurringYears, Format TextFormat.Number. Le prototype n'additionne une composante que si sa case est cochée. Ici, il n'y a pas de case : une composante vide ou à zéro n'est simplement pas prise en compte, et le résultat est identique. Le prototype limite Recurring Years à 1 à 5 ans. Si cette limite est voulue, remplacer txtRecurringYears par une liste déroulante avec les Items [1, 2, 3, 4, 5], et adapter nfTotal pour lire Value(cmbRecurringYears.Selected.Value). Pour RenewalsValue et RecurringAnnualValue, ajouter un texte d'aide sous la carte : les renouvellements valorisés globalement vont dans Renewals, les coûts annuels dans Recurring Annual Value. Saisir les deux pour le même coût le compterait deux fois.

À droite du formulaire, ajouter une carte de synthèse :

1. Libellé lblTotalCaption "Total Expected Commitment (hors TVA)".
2. Libellé lblTotal : Text `Text(nfTotal, "€ #,##0.00")`, Size 28, Color nfNavy.
3. Libellé lblLevelPreview : Text `"Niveau " & nfLevel.Level & " – " & nfLevel.LevelName & " · " & nfLevel.Route`.
4. Libellé lblNearThreshold : Visible nfNearThreshold, Color nfMagenta. Text :

```
"The value is within " & Text(nfNearPct * 100) & "% of a threshold (EUR " & Text(nfLevel.MaxValueIncl, "#,##0") &
"). The higher route (" & nfNextLevel.Route & ") should be considered unless Finance and Legal approve a documented alternative."
```

5. Libellé lblAmountErrors : Visible `nfHasNegative || nfYearsNotInteger`, Color nfMagenta. Text :

```
Concat(
    Filter(
        Table(
            {On: nfHasNegative, Msg: "Les montants ne peuvent pas être négatifs."},
            {On: nfYearsNotInteger, Msg: "Recurring Years doit être un nombre entier d'années."}
        ),
        On
    ),
    Msg, Char(10)
)
```

### 5.5 Step 3 – Automatic Route (conStep3)

Aucun formulaire : tout est calculé, et donc en lecture seule (§7.3). Créer six tuiles, chacune composée d'un conteneur blanc avec une barre supérieure de 4 px de couleur nfCyan, un libellé de légende (nfMuted) et un libellé de valeur (Size 20, nfNavy) :

```
Level                 : nfLevel.Level & " – " & nfLevel.LevelName
Route                 : nfLevel.Route
Approval Authority    : nfLevel.ApprovalAuthority
Competition           : nfLevel.CompetitionRequirement
Legal                 : If(nfLegalMandatory, "Mandatory", "Required only if a Legal trigger applies")
Due Diligence         : nfDueDiligenceTier
```

La tuile Legal prend un Fill nfMagenta quand nfLegalMandatory est vrai, et la tuile Due Diligence un Fill nfPurple lorsque nfDueDiligenceTier vaut High. Sous la valeur de la tuile Legal, un libellé affiche `If(nfLegalMandatory, "Motif : " & nfLegalReasons, "Value and Step 4 risk triggers apply.")`. Sous la tuile Approval Authority, reprendre le texte du prototype : "Award approval remains separate from signature authority."

Sous les tuiles, un libellé lblRouteEvidence affiche `"Required route evidence : " & Substitute(nfLevel.RequiredRouteEvidence, "; ", Char(10) & "• ")`, précédé d'une puce "• ". Les preuves sont stockées dans Procurement Config, séparées par « ; ».

Un libellé lblRouteBasis reprend la phrase du prototype :

```
If(
    IsBlank(nfLevel),
    "Complete the value calculation to generate the applicable route.",
    "EUR " & Text(nfTotal, "#,##0") & " produces Level " & nfLevel.Level & " under the V3.2 thresholds."
)
```

Ces valeurs reflètent la saisie en cours. Elles ne sont écrites dans SharePoint qu'à l'enregistrement, et le flux de soumission les recalcule.

### 5.6 Step 4 – Checks (conStep4)

Formulaire frmChecks, avec les mêmes réglages. Champs : RiskData, RiskIT, RiskIP, RiskPricing, RiskLiability, RiskLaw, RiskConflict, RiskCritical, Comments.

```
RiskData      -> tglRiskData       libellé : Personal data / NDA
RiskIT        -> tglRiskIT         libellé : IT, cloud or system access
RiskIP        -> tglRiskIP         libellé : IP, research or sponsorship
RiskPricing   -> tglRiskPricing    libellé : Open-ended or uncapped pricing
RiskLiability -> tglRiskLiability  libellé : Liability or regulatory risk
RiskLaw       -> tglRiskLaw        libellé : Non-approved governing law or forum
RiskConflict  -> tglRiskConflict   libellé : Conflict of interest
RiskCritical  -> tglRiskCritical   libellé : Critical dependency or high-risk geography
Comments      -> txtComments
```

Sous chaque bascule, placer un court texte d'aide tiré de l'Annex 5, dans un libellé de couleur nfMuted.

À droite, une carte de résultat avec lblRiskProfile (`"Risk Profile : " & nfRiskProfile`), lblLegalTrigger (`If(nfLegalMandatory, "Revue Legal obligatoire : " & nfLegalReasons, "Pas de déclencheur Legal")`) et lblDDTier (`"Due Diligence Tier : " & nfDueDiligenceTier`).

Bascule Related Party : elle est saisie à l'étape 1 (RelatedPartyFlag). Rappeler sa valeur ici en lecture seule pour éviter les incohérences avec Conflict : libellé `"Related party déclarée à l'étape 1 : " & If(tglRelatedParty.Value, "Oui", "Non")`.

Pièces justificatives :

1. Insérer un second formulaire frmUpload : DataSource 'Procurement Records', Item varRec, et uniquement la carte Attachments. Renommer le contrôle en attUpload et fixer MaxAttachments à 1. Ce formulaire n'est jamais soumis. Il sert seulement à disposer d'un contrôle de pièce jointe, car Power Apps n'en propose pas hors d'un formulaire. Les pièces jointes doivent donc être activées sur la liste, mais rien n'y est jamais enregistré.
2. Liste déroulante cmbDocType, avec Items `Choices([@'Procurement Documents'].DocumentType)`.
3. Bouton btnUpload "Ajouter au dossier", avec DisplayMode `If(!IsEmpty(attUpload.Attachments) && !IsBlank(cmbDocType.Selected), DisplayMode.Edit, DisplayMode.Disabled)` et OnSelect :

```
Set(
    varUploadResult,
    UploadProcurementDocument.Run(
        varRec.ID,
        varRec.RecordID,
        cmbDocType.Selected.Value,
        {
            contentBytes: First(attUpload.Attachments).Value,
            name: First(attUpload.Attachments).Name
        }
    )
);
If(
    varUploadResult.result = "ok",
    Notify("Document ajouté.", NotificationType.Success); ResetForm(frmUpload); Refresh('Procurement Documents'),
    Notify(varUploadResult.message, NotificationType.Error)
)
```

4. Galerie galDocuments, avec Items :

```
SortByColumns(Filter('Procurement Documents', RecordID = varRec.RecordID), "Modified", SortOrder.Descending)
```

   Dans le modèle : ThisItem.'File name with extension', ThisItem.DocumentType.Value, `If(ThisItem.DocStatus.Value = "Superseded", "remplacé", "")`, et OnSelect `Launch(ThisItem.'Link to item')`.

### 5.7 Step 5 – Approvals (conStep5)

Formulaire frmApprovals : DataSource 'Procurement Records', Item varRec, mêmes réglages. Champs : Legal Reviewer, Finance Reviewer, Business Approver, Signature Authority.

Les reviewers doivent appartenir au groupe correspondant. Remplacer les listes déroulantes des cartes comme suit. Il faut d'abord déverrouiller la carte : Avancé > Déverrouiller.

Carte Legal Reviewer :

1. Renommer le contrôle en cmbLegalReviewer.
2. Items : `colLegalMembers`.
3. DisplayFields : `["displayName"]`. SearchFields : `["displayName", "mail"]`.
4. DefaultSelectedItems : `Filter(colLegalMembers, Lower(mail) = Lower(varRec.'Legal Reviewer'.Email))`.
5. Propriété Update de la carte :

```
If(
    IsBlank(cmbLegalReviewer.Selected),
    Blank(),
    {
        Claims: "i:0#.f|membership|" & Lower(cmbLegalReviewer.Selected.userPrincipalName),
        DisplayName: cmbLegalReviewer.Selected.displayName,
        Email: cmbLegalReviewer.Selected.mail,
        Department: "",
        JobTitle: "",
        Picture: ""
    }
)
```

Carte Finance Reviewer : même schéma, avec cmbFinanceReviewer et colFinanceMembers.

Carte Business Approver : même schéma, avec cmbBusinessApprover et colApproverMembers.

Carte Signature Authority : conserver la liste déroulante standard, renommée cmbSignatureAuthority. La matrice de signature (Annex 4) ne correspond à aucun groupe du cahier.

Visible de la carte Legal Reviewer : nfLegalMandatory. Si Legal n'est pas obligatoire, rien n'empêche d'ajouter un reviewer : mettre alors Visible à true, et la contrôler par le libellé « facultatif ».

Checklist (§7.5) : galerie galChecklist, avec Items :

```
With(
    {
        docs: Filter('Procurement Documents', RecordID = varRec.RecordID && DocStatus.Value <> "Superseded"),
        appr: Filter('Procurement Approvals', RecordID = varRec.RecordID && ApprovalVersion = varRec.RecordVersion)
    },
    Table(
        {
            Item: "Budget / value",
            Ok: !IsBlank(varRec.BudgetReference) && varRec.TotalExpectedCommitment > 0,
            Hint: "Budget Reference et total renseignés."
        },
        {
            Item: "Sourcing evidence",
            Ok: CountRows(Filter(docs, DocumentType.Value in ["Sourcing evidence", "Quote or offer", "Evaluation"])) > 0 ||
                (varRec.ProcurementLevel = 1 && !IsBlank(varRec.ValueCalculationBasis)),
            Hint: LookUp(nfThresholds, Level = varRec.ProcurementLevel).RequiredRouteEvidence
        },
        {
            Item: "Conflicts",
            Ok: !varRec.RiskConflict && !varRec.RelatedPartyFlag || varRec.LegalMandatory,
            Hint: "Conflit ou partie liée déclaré : la revue Legal doit être requise."
        },
        {
            Item: "Due diligence",
            Ok: varRec.DueDiligenceTier.Value = "Low" || CountRows(Filter(docs, DocumentType.Value = "Due diligence")) > 0,
            Hint: "Tier " & varRec.DueDiligenceTier.Value & " : rapport de due diligence attendu (Annex 5)."
        },
        {
            Item: "Legal review",
            Ok: !varRec.LegalMandatory ||
                CountRows(Filter(appr, ApprovalType.Value = "Legal" && Decision.Value in ["Approved", "Approved with conditions"])) > 0,
            Hint: If(varRec.LegalMandatory, "Décision Legal requise.", "Non requise.")
        },
        {
            Item: "Award approval",
            Ok: CountRows(Filter(appr, ApprovalType.Value = "Business" && Decision.Value in ["Approved", "Approved with conditions"])) > 0,
            Hint: "Décision du Business Approver."
        },
        {
            Item: "Signatory authority",
            Ok: !IsBlank(varRec.'Signature Authority'.Email),
            Hint: "Signataire désigné selon l'Annex 4."
        },
        {
            Item: "Contractual basis",
            // Annex 3 : jusqu'à 10 000 EUR, devis accepté suffisant ; au-delà, contrat écrit exécuté.
            Ok: If(
                varRec.TotalExpectedCommitment <= Value(LookUp('Procurement Settings', Title = "ContractRequired.Above", SettingValue)),
                CountRows(Filter(docs, DocumentType.Value in ["Contract", "Quote or offer", "Purchase order"])) > 0,
                CountRows(Filter(docs, DocumentType.Value = "Contract")) > 0
            ),
            Hint: If(
                varRec.TotalExpectedCommitment <= Value(LookUp('Procurement Settings', Title = "ContractRequired.Above", SettingValue)),
                "Annex 3 : devis signé ou formellement accepté, avec conditions expressément acceptées.",
                "Annex 3 : contrat écrit exécuté avant tout début d'exécution ou paiement."
            )
        }
    )
)
```

Dans le modèle : une icône avec Icon `If(ThisItem.Ok, Icon.CheckBadge, Icon.Warning)` et Color `If(ThisItem.Ok, nfNavy, nfMagenta)`, un libellé ThisItem.Item et un libellé ThisItem.Hint (couleur nfMuted).

La checklist est calculée sur les données enregistrées (varRec), et non sur la saisie en cours. Elle est donc exacte une fois le dossier enregistré.

Historique des décisions : galerie galDecisions, avec Items :

```
SortByColumns(
    Filter('Procurement Approvals', RecordID = varRec.RecordID),
    "ApprovalVersion", SortOrder.Descending, "Sequence", SortOrder.Ascending
)
```

Modèle :

```
"v" & ThisItem.ApprovalVersion & " · " & ThisItem.ApprovalType.Value & " · " & ThisItem.Approver.DisplayName
& " · " & ThisItem.Decision.Value & If(IsBlank(ThisItem.DecisionDate), "", " le " & Text(ThisItem.DecisionDate, "dd.mm.yyyy hh:mm"))
```

Ajouter un second libellé pour ThisItem.Comments et ThisItem.Conditions. Les versions antérieures restent visibles : c'est la piste d'audit du §7.5.

### 5.8 Step 6 – Sign off (conStep6)

Synthèse : un conteneur vertical de libellés en lecture seule. Elle est construite sur varRec, c'est-à-dire sur ce qui est enregistré, pour que l'utilisateur voie exactement ce qui sera soumis :

```
"Dossier : " & varRec.RecordID & " – " & varRec.Title & " (v" & varRec.RecordVersion & ")"
"Owner : " & varRec.'Project Owner'.DisplayName & " · Business Owner : " & varRec.'Business Owner'.DisplayName
"Fournisseur : " & varRec.SupplierName & " · Département : " & varRec.Department.Value
"Total : " & Text(varRec.TotalExpectedCommitment, "€ #,##0.00") & " · Niveau " & varRec.ProcurementLevel & " – " & varRec.ProcurementLevelName
"Route : " & varRec.ProcurementRoute & " · Autorité : " & varRec.ApprovalAuthority
"Risk Profile : " & varRec.RiskProfile.Value & " · Legal : " & If(varRec.LegalMandatory, "obligatoire", "non requis") & " · DD : " & varRec.DueDiligenceTier.Value
"Dernier PDF : " & If(IsBlank(varRec.LatestPDFUrl), "aucun", varRec.LatestPDFUrl)
```

Le dernier libellé est un lien : OnSelect `Launch(varRec.LatestPDFUrl)`.

Avertissement de cohérence : un libellé lblUnsaved avec Visible `frmWhat.Unsaved || frmHowMuch.Unsaved || frmChecks.Unsaved || frmApprovals.Unsaved`, Color nfMagenta et Text "Des modifications ne sont pas enregistrées. La synthèse affiche la dernière version enregistrée."

Champs manquants : galerie galMissing, avec Items nfMissing et Visible `varCanEdit && !IsEmpty(nfMissing)`. Modèle : `"Étape " & ThisItem.Step & " – " & ThisItem.Item`, et OnSelect `Set(varStep, ThisItem.Step)`.

Boutons d'action. Leur Visible suit le rôle et le statut. Ces contrôles relèvent du confort, la vraie vérification est faite par les flux.

```
btnSubmit  "Submit for Review"
    Visible     : varCanEdit
    DisplayMode : If(IsEmpty(nfMissing), DisplayMode.Edit, DisplayMode.Disabled)
    OnSelect    : Set(varAfterSave, "submit"); Select(btnSave)

btnPdf  "Generate PDF"
    Visible  : varRec.Status.Value <> "Draft" &&
               (Lower(varRec.'Project Owner'.Email) = nfUserEmail || varIsLegal || varIsFinance || varIsAdmin)
    OnSelect : Set(varAction, "GeneratePDF"); Select(btnRunAction)

btnContractSigned  "Contract Signed"
    Visible  : varRec.Status.Value = "Approved" &&
               (Lower(varRec.'Signature Authority'.Email) = nfUserEmail || varIsAdmin)
    OnSelect : Set(varAction, "ContractSigned"); Select(btnRunAction)

btnClose  "Close"
    Visible  : varRec.Status.Value = "Contract Signed" &&
               (Lower(varRec.'Project Owner'.Email) = nfUserEmail || varIsAdmin)
    OnSelect : Set(varAction, "Close"); Select(btnRunAction)

btnReopen  "Reopen"
    Visible  : varRec.Status.Value in ["Under Review", "Approved"] && (varIsLegal || varIsAdmin)
    OnSelect : Set(varAction, "Reopen"); Select(btnRunAction)

btnCancel  "Cancel"
    Visible  : (varRec.Status.Value in ["Draft", "Returned for Amendment"] && varCanEdit) ||
               (varIsAdmin && !(varRec.Status.Value in ["Closed", "Cancelled"]))
    OnSelect : Set(varAction, "Cancel"); Select(btnRunAction)
```

Zone de saisie txtActionComment, avec HintText "Motif ou commentaire (obligatoire pour Reopen et Cancel)".

Bouton masqué btnRunAction (Visible false), avec OnSelect :

```
If(
    varAction in ["Reopen", "Cancel"] && IsBlank(Trim(txtActionComment.Text)),
    Notify("Indiquez un motif.", NotificationType.Error),
    Set(varActionResult, RecordAction.Run(varRec.ID, varAction, Coalesce(txtActionComment.Text, "")));
    If(
        varActionResult.result = "ok",
        Notify(varActionResult.message, NotificationType.Success);
        Reset(txtActionComment);
        Set(varRec, LookUp('Procurement Records', ID = varRec.ID));
        Set(
            varCanEdit,
            varRec.Status.Value in ["Draft", "Returned for Amendment"] &&
            (Lower(varRec.'Project Owner'.Email) = nfUserEmail || Lower(varRec.'Business Owner'.Email) = nfUserEmail || varIsAdmin)
        ),
        Notify(varActionResult.message, NotificationType.Error)
    )
)
```

Panneau de décision (§7.5 et §7.6) : conteneur conDecision, avec Visible `!IsBlank(varMyApproval)`. Il contient :

1. Un libellé `"Votre décision est attendue en tant que " & varMyApproval.ApprovalType.Value & " (version " & varMyApproval.ApprovalVersion & ")"`.
2. Une zone de texte txtDecisionComment, multiligne.
3. Une zone de texte txtDecisionConditions, multiligne, avec HintText "Conditions (obligatoire pour Approve with conditions)".
4. Quatre boutons :

```
btnApprove            "Approve"                  OnSelect : Set(varDecision, "Approved"); Select(btnDecide)
btnApproveConditions  "Approve with conditions"  OnSelect : Set(varDecision, "Approved with conditions"); Select(btnDecide)
btnReturn             "Return for Amendment"     OnSelect : Set(varDecision, "Returned"); Select(btnDecide)
btnReject             "Reject"                   OnSelect : Set(varDecision, "Rejected"); Select(btnDecide)
```

5. Un bouton masqué btnDecide, avec OnSelect :

```
If(
    varDecision in ["Returned", "Rejected"] && IsBlank(Trim(txtDecisionComment.Text)),
    Notify("Un commentaire est obligatoire pour retourner ou rejeter le dossier.", NotificationType.Error),
    varDecision = "Approved with conditions" && IsBlank(Trim(txtDecisionConditions.Text)),
    Notify("Précisez les conditions.", NotificationType.Error),
    IfError(
        Patch(
            'Procurement Approvals',
            varMyApproval,
            {
                Decision: {Value: varDecision},
                Comments: txtDecisionComment.Text,
                Conditions: txtDecisionConditions.Text,
                DecisionDate: Now()
            }
        );
        Notify("Décision enregistrée. Le dossier est mis à jour par le workflow.", NotificationType.Success);
        Set(varMyApproval, Blank());
        Reset(txtDecisionComment);
        Reset(txtDecisionConditions),
        Notify("Décision non enregistrée : " & FirstError.Message, NotificationType.Error)
    )
)
```

La date de décision définitive est réécrite par le flux F3 avec l'heure du serveur. Celle de l'application n'est qu'indicative.

### 5.9 Enregistrement : btnSave

OnSelect :

```
If(
    !varCanEdit,
    Notify("Ce dossier n'est pas modifiable dans son statut actuel.", NotificationType.Warning),
    IfError(
        Set(
            varRec,
            Patch(
                'Procurement Records',
                LookUp('Procurement Records', ID = varRec.ID),
                frmWhat.Updates,
                frmHowMuch.Updates,
                frmChecks.Updates,
                frmApprovals.Updates,
                {
                    TotalExpectedCommitment: nfTotal,
                    ProcurementLevel: nfLevel.Level,
                    ProcurementLevelName: nfLevel.LevelName,
                    ProcurementRoute: nfLevel.Route,
                    CompetitionRequirement: nfLevel.CompetitionRequirement,
                    ApprovalAuthority: nfLevel.ApprovalAuthority,
                    LegalMandatory: nfLegalMandatory,
                    RiskProfile: If(nfRiskProfile = "", Blank(), {Value: nfRiskProfile}),
                    DueDiligenceTier: If(nfDueDiligenceTier = "", Blank(), {Value: nfDueDiligenceTier}),
                    LastStep: Max(Coalesce(varRec.LastStep, 1), varStep)
                }
            )
        );
        If(
            varAfterSave = "submit",
            If(
                IsEmpty(nfMissing),
                Set(varRec, Patch('Procurement Records', varRec, {Status: {Value: "Ready for Submission"}}));
                Set(varCanEdit, false);
                Notify("Dossier soumis. Le workflow contrôle le dossier et notifie les reviewers.", NotificationType.Success),
                Notify("Soumission impossible : des informations manquent (voir Sign off).", NotificationType.Error)
            ),
            Notify("Brouillon enregistré.", NotificationType.Success)
        ),
        Notify("Enregistrement impossible : " & FirstError.Message, NotificationType.Error)
    )
);
Set(varAfterSave, "")
```

Le Patch combine les quatre formulaires et les valeurs calculées. Les valeurs calculées ne sont donc jamais saisies par l'utilisateur, et elles sont réécrites à chaque enregistrement (§8.3). RecordID, Status, les dates d'audit et LatestPDFUrl ne figurent dans aucun formulaire, et l'application ne les écrit qu'aux endroits prévus.

## 6. Points de vigilance

Si les formules nommées refusent de référencer des contrôles (cela dépend de la version de Power Apps), déplacer nfTotal, nfLevel, nfRiskProfile, nfLegalMandatory, nfDueDiligenceTier et nfMissing dans un conteneur masqué de scrRecord. Chacune devient un libellé, et les autres formules lisent leur valeur, par exemple Value(lblTotalHidden.Text). La logique reste identique.

Deux utilisateurs qui modifient le même brouillon en même temps : le dernier qui enregistre l'emporte, car SharePoint n'offre pas de contrôle de concurrence par Patch. Si c'est un risque réel, ajouter dans btnSave une vérification `LookUp('Procurement Records', ID = varRec.ID).Modified > varRec.Modified` avant le Patch, et demander à l'utilisateur de recharger le dossier.

Performances : les galeries de l'accueil ne chargent que les dossiers de l'utilisateur. Les listes Procurement Config, Settings et Policy Links sont petites et lues une seule fois par les formules nommées. Les colonnes filtrées sont indexées par le script.

Accessibilité (§12) : renseigner AccessibleLabel sur tous les boutons d'icône et sur les bascules, vérifier l'ordre de tabulation dans chaque conteneur (propriété TabIndex), et garder les couleurs de texte nfNavy sur fond blanc ou White sur fond nfNavy. Le cyan ne doit pas porter de texte, son contraste est insuffisant.

Intégration dans SharePoint : ajouter la webpart Power Apps sur une page du site Legal Department, avec l'identifiant de l'application. La largeur minimale utile est d'environ 1000 px. Sur tablette, préférer l'application Power Apps ou le navigateur en plein écran.
