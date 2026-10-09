// =============================================================================
// EFC Procurement Assistant – App.Formulas
// À coller dans : Arborescence > App > propriété Formulas.
// Les formules nommées sont recalculées automatiquement dès qu'un contrôle change :
// le total, la route et les risques restent toujours cohérents avec la saisie (§8.3).
// Les noms de contrôles sont ceux du GUIDE-POWER-APPS.md.
// =============================================================================

// ---- Utilisateur et paramètres ---------------------------------------------

nfUserEmail = Lower(User().Email);

nfThresholds = Sort('Procurement Config', Level, SortOrder.Ascending);

nfNearPct = Coalesce(Value(LookUp('Procurement Settings', Title = "NearThresholdPercent", SettingValue)), 10) / 100;

nfLegalMinLevel = Coalesce(Value(LookUp('Procurement Settings', Title = "LegalMandatory.MinLevel", SettingValue)), 3);

nfAppUrl = LookUp('Procurement Settings', Title = "AppUrl", SettingValue);

// ---- Palette (cahier §12) ----------------------------------------------------

nfNavy = ColorValue("#0D2D5C");
nfCyan = ColorValue("#1ED7E5");
nfPurple = ColorValue("#A675B7");
nfMagenta = ColorValue("#EF234B");
nfBackground = ColorValue("#F3F7FB");
nfBorder = ColorValue("#D9E2EC");
nfMuted = ColorValue("#5B6B7F");

// ---- Step 2 : total (§8.1) -------------------------------------------------

nfHasNegative =
    Coalesce(Value(txtMainPrice.Text), 0) < 0 ||
    Coalesce(Value(txtOptionsValue.Text), 0) < 0 ||
    Coalesce(Value(txtRenewalsValue.Text), 0) < 0 ||
    Coalesce(Value(txtRecurringAnnualValue.Text), 0) < 0 ||
    Coalesce(Value(txtRecurringYears.Text), 0) < 0 ||
    Coalesce(Value(txtImplementationValue.Text), 0) < 0 ||
    Coalesce(Value(txtFeesExpensesValue.Text), 0) < 0 ||
    Coalesce(Value(txtRelatedPurchasesValue.Text), 0) < 0;

nfYearsNotInteger =
    !IsBlank(txtRecurringYears.Text) &&
    Mod(Coalesce(Value(txtRecurringYears.Text), 0), 1) <> 0;

nfTotal =
    Coalesce(Value(txtMainPrice.Text), 0) +
    Coalesce(Value(txtOptionsValue.Text), 0) +
    Coalesce(Value(txtRenewalsValue.Text), 0) +
    Coalesce(Value(txtRecurringAnnualValue.Text), 0) * Coalesce(Value(txtRecurringYears.Text), 0) +
    Coalesce(Value(txtImplementationValue.Text), 0) +
    Coalesce(Value(txtFeesExpensesValue.Text), 0) +
    Coalesce(Value(txtRelatedPurchasesValue.Text), 0);

// ---- Step 3 : route automatique (§8.2) ---------------------------------------
// Bornes lues dans Procurement Config : MinValueExcl < total <= MaxValueIncl.
// Une borne vide signifie « pas de limite ».

nfLevel =
    LookUp(
        nfThresholds,
        (IsBlank(MinValueExcl) || nfTotal > MinValueExcl) &&
        (IsBlank(MaxValueIncl) || nfTotal <= MaxValueIncl)
    );

// Prototype : v > 0 && v <= seuil && v > seuil x 0,95, pour les seuils 25 000, 50 000 et 250 000.
nfNearThreshold =
    nfTotal > 0 &&
    !IsBlank(nfLevel.MaxValueIncl) &&
    nfTotal > nfLevel.MaxValueIncl * (1 - nfNearPct);

nfNextLevel = LookUp(nfThresholds, Level = nfLevel.Level + 1);

// ---- Step 4 : risques et déclencheurs -------------------------------------
// Règles reprises du prototype V3.2 FINAL R4 (hasLegalTrigger, riskProfile, autoDD).

nfRiskProfile =
    If(
        tglRiskCritical.Value || tglRiskConflict.Value || tglRelatedParty.Value, "High",
        Coalesce(nfLevel.Level, 0) >= 3 || tglRiskData.Value || tglRiskIT.Value || tglRiskIP.Value, "Medium",
        IsBlank(nfLevel), "",
        "Low"
    );

// Prototype : le Due Diligence Tier est égal au Risk Profile.
nfDueDiligenceTier = nfRiskProfile;

// Prototype : niveau >= 3 ou l'un des déclencheurs Annex 3 cochés, ou related party.
nfLegalPrototype =
    Coalesce(nfLevel.Level, 0) >= nfLegalMinLevel ||
    tglRelatedParty.Value ||
    tglRiskData.Value ||
    tglRiskIT.Value ||
    tglRiskIP.Value ||
    tglRiskPricing.Value ||
    tglRiskLiability.Value ||
    tglRiskLaw.Value ||
    tglRiskConflict.Value;

// EXTENSION non présente dans le prototype, tirée des annexes (à confirmer par Legal) :
// - Annex 3 : « employment or individual-consultant classification » déclenche Legal quelle que soit la valeur ;
// - Annex 5 : un profil High impose une « enhanced Legal/Compliance review » ; seul RiskCritical
//   produit High sans être déjà un déclencheur Legal.
// Pour revenir strictement au prototype : nfLegalAnnexExtension = false;
nfLegalAnnexExtension =
    cmbPurchaseType.Selected.Value = "Consultant or individual" ||
    tglRiskCritical.Value;

nfLegalMandatory = nfLegalPrototype || nfLegalAnnexExtension;

nfLegalReasons =
    Concat(
        Filter(
            Table(
                {On: Coalesce(nfLevel.Level, 0) >= nfLegalMinLevel, Txt: "niveau " & nfLevel.Level},
                {On: tglRelatedParty.Value, Txt: "related party"},
                {On: tglRiskData.Value, Txt: "données personnelles / NDA"},
                {On: tglRiskIT.Value, Txt: "IT / cloud"},
                {On: tglRiskIP.Value, Txt: "IP / sponsorship"},
                {On: tglRiskPricing.Value, Txt: "prix ouvert"},
                {On: tglRiskLiability.Value, Txt: "responsabilité / réglementaire"},
                {On: tglRiskLaw.Value, Txt: "droit ou for non approuvé"},
                {On: tglRiskConflict.Value, Txt: "conflit"},
                {On: cmbPurchaseType.Selected.Value = "Consultant or individual", Txt: "consultant individuel (Annex 3)"},
                {On: tglRiskCritical.Value, Txt: "dépendance critique (Annex 5)"}
            ),
            On
        ),
        Txt, ", "
    );

// ---- Step 6 : champs manquants et conditions non satisfaites (§7.6) ---------

nfMissing =
    Filter(
        Table(
            {Step: 1, Item: "Procurement Title", IsMissing: IsBlank(Trim(txtTitle.Text))},
            {Step: 1, Item: "Department", IsMissing: IsBlank(cmbDepartment.Selected)},
            {Step: 1, Item: "Business Need and Scope", IsMissing: IsBlank(Trim(txtBusinessNeed.Text))},
            {Step: 1, Item: "Purchase Type", IsMissing: IsBlank(cmbPurchaseType.Selected)},
            {Step: 1, Item: "Project Owner", IsMissing: IsBlank(cmbProjectOwner.Selected)},
            {Step: 1, Item: "Business Owner", IsMissing: IsBlank(cmbBusinessOwner.Selected)},
            {Step: 1, Item: "Funding Source", IsMissing: IsBlank(cmbFundingSource.Selected)},
            {Step: 1, Item: "Procurement Context", IsMissing: IsBlank(cmbProcurementContext.Selected)},
            {Step: 2, Item: "Currency Treatment", IsMissing: IsBlank(cmbCurrencyTreatment.Selected)},
            {Step: 2, Item: "Aucune valeur négative", IsMissing: nfHasNegative},
            {Step: 2, Item: "Recurring Years en années entières", IsMissing: nfYearsNotInteger},
            {Step: 2, Item: "Total Expected Commitment supérieur à zéro", IsMissing: nfTotal <= 0},
            {
                Step: 2,
                Item: "Équivalent EUR confirmé par Finance (les seuils en dépendent)",
                IsMissing: cmbCurrencyTreatment.Selected.Value = "Finance confirmation pending"
            },
            {Step: 3, Item: "Route calculée (paramètres Procurement Config)", IsMissing: IsBlank(nfLevel)},
            {Step: 5, Item: "Finance Reviewer", IsMissing: IsBlank(cmbFinanceReviewer.Selected)},
            {Step: 5, Item: "Legal Reviewer (revue Legal obligatoire)", IsMissing: nfLegalMandatory && IsBlank(cmbLegalReviewer.Selected)},
            {Step: 5, Item: "Business Approver", IsMissing: IsBlank(cmbBusinessApprover.Selected)},
            {
                Step: 5,
                Item: "Business Approver différent du Project Owner",
                IsMissing: !IsBlank(cmbBusinessApprover.Selected) &&
                    Lower(cmbBusinessApprover.Selected.mail) = Lower(cmbProjectOwner.Selected.Email)
            }
        ),
        IsMissing
    );

nfStepsWithMissing = Distinct(nfMissing, Step);
