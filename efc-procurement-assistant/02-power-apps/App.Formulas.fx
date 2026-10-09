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

nfNearThreshold =
    !IsBlank(nfLevel.MaxValueIncl) &&
    nfTotal >= nfLevel.MaxValueIncl * (1 - nfNearPct);

nfNextLevel = LookUp(nfThresholds, Level = nfLevel.Level + 1);

// ---- Step 4 : risques et déclencheurs (HYPOTHÈSES README §3 à §5) -----------

nfRiskCount =
    CountRows(
        Filter(
            Table(
                {On: tglRelatedParty.Value},
                {On: tglRiskData.Value},
                {On: tglRiskIT.Value},
                {On: tglRiskIP.Value},
                {On: tglRiskPricing.Value},
                {On: tglRiskLiability.Value},
                {On: tglRiskLaw.Value},
                {On: tglRiskConflict.Value},
                {On: tglRiskCritical.Value}
            ),
            On
        )
    );

nfRiskProfile =
    If(
        tglRiskConflict.Value || tglRelatedParty.Value || tglRiskCritical.Value || nfRiskCount >= 3, "High",
        nfRiskCount >= 1, "Medium",
        "Low"
    );

nfLegalMandatory =
    Coalesce(nfLevel.Level, 1) >= nfLegalMinLevel ||
    tglRelatedParty.Value ||
    tglRiskData.Value ||
    tglRiskIP.Value ||
    tglRiskLiability.Value ||
    tglRiskLaw.Value ||
    tglRiskConflict.Value;

nfDueDiligenceTier =
    If(
        nfRiskProfile = "High" || nfLevel.Level = 4, "High",
        nfRiskProfile = "Medium" || nfLevel.Level = 3, "Medium",
        "Low"
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
