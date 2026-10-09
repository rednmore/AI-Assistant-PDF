# Flux Power Automate

Tous les flux sont créés dans la Solution, appartiennent à un compte de service dédié (par exemple svc-procurement@efc...) et utilisent ses connexions. Ce compte doit être membre du groupe Propriétaires du site Legal Department et disposer d'une licence Microsoft 365 avec Exchange (pour l'envoi depuis une boîte partagée) et OneDrive (pour la conversion PDF). Si un flux est la propriété d'une personne, il s'arrête le jour où cette personne quitte EFC.

Dans les expressions ci-dessous, les noms d'actions correspondent aux noms à donner aux actions dans le concepteur. Renommez chaque action dès sa création : par exemple, une action renommée « Get record » devient body('Get_record') dans les expressions.

Tous les flux suivent la même structure de gestion d'erreur, décrite à la fin (bloc E). La gestion des permissions est décrite une seule fois (bloc P) et réutilisée.

## Vue d'ensemble

| Flux | Déclencheur | Rôle |
|---|---|---|
| F0 RecordAction | Power Apps (V2) | Actions privilégiées : GeneratePDF, ContractSigned, Close, Reopen, Cancel. Contrôle du rôle côté serveur. |
| F1 Record setup | Création d'un élément Records | Filet de sécurité RecordID, historique Created, dossier documentaire, permissions initiales. |
| F2 Submit for Review | Status = Ready for Submission | Contrôle serveur, création des approbations, verrouillage, notification. |
| F3 Decision orchestration | Décision saisie dans Approvals | Enchaînement des séquences, Approved, Returned, Rejected. |
| F4 Amendment | Status = Returned for Amendment et AmendmentPending = Oui | Nouvelle version, déverrouillage, notification de l'owner. |
| F5 PDF generation | PdfRequested = Oui | PDF versionné, ancien PDF marqué Superseded, LatestPDFUrl. |
| F6 Closure | Status = Contract Signed ou Closed | Horodatage, contrôle documentaire, PDF, notifications. |
| F7 UploadProcurementDocument | Power Apps (V2) | Dépôt d'une pièce dans Procurement Documents avec ses métadonnées. |

Les flux communiquent entre eux par des colonnes signal (PdfRequested, AmendmentPending) plutôt que par des flux enfants. Cela fonctionne hors Solution, et chaque flux reste testable seul. Pour éviter les boucles, chaque déclencheur porte une condition stricte. Un flux qui modifie l'élément sur lequel il est déclenché le fait toujours de façon à rendre sa propre condition fausse.

Règle d'historique : l'événement est écrit par le flux qui connaît la personne à l'origine de l'action. F0 écrit Reopened, ContractSigned, Closed et Cancelled. F2 écrit Submitted. F3 écrit Decision, Returned, Rejected et Approved. F5 écrit PDFGenerated, F7 écrit DocumentUploaded.

## Paramètres communs

Plusieurs flux lisent Procurement Settings. Pour une clé, utiliser l'action SharePoint « Obtenir des éléments » sur Procurement Settings, avec la requête de filtre `Title eq 'GroupId.Administrators'` et un nombre maximal d'éléments à 1. La valeur s'obtient par :

```
first(body('Get_setting_admins')?['value'])?['SettingValue']
```

Pour éviter de multiplier les appels à SharePoint, lire toute la liste une fois : action « Get settings », Obtenir des éléments, sans filtre. Puis, pour chaque clé nécessaire, ajouter une action « Filtrer le tableau » (Filter array), avec From `body('Get_settings')?['value']` et la condition `@equals(item()?['Title'], 'GroupId.Administrators')`. Ajouter ensuite une action Compose nommée selon la clé (par exemple Setting_GroupAdmins, Setting_AppUrl, Setting_LegalMinLevel), qui contient `first(body('Filter_admins'))?['SettingValue']`.

Rôles d'un utilisateur : action Office 365 Groupes « Répertorier les membres du groupe » (List group members) sur l'identifiant de groupe, puis « Filtrer le tableau » avec la condition `@equals(toLower(item()?['userPrincipalName']), toLower(variables('UserEmail')))`. L'utilisateur est membre si `greater(length(body('Filter_admin_member')), 0)`.

## Bloc P – permissions d'un élément

Ce bloc remet à zéro les permissions d'un élément et attribue une liste explicite de droits. Il s'agit d'une Étendue (Scope) nommée « Set permissions », qui reçoit dans une action Compose « Principals » un tableau de la forme :

```
[
  {"logon": "i:0#.f|membership|owner@efc.example", "role": 1073741827},
  {"logon": "c:0t.c|tenant|<ObjectId groupe Legal>", "role": 1073741826}
]
```

Les identifiants de rôles SharePoint sont les suivants : Read = 1073741826, Contribute = 1073741827, Edit = 1073741830, Full Control = 1073741829. Un groupe de sécurité Entra se déclare avec le préfixe c:0t.c|tenant|. Un groupe Microsoft 365 se déclare avec c:0o.c|federateddirectoryclaimprovider|.

Toutes les actions sont des « Envoyer une requête HTTP à SharePoint » sur le site Legal Department, avec les en-têtes `Accept: application/json;odata=nometadata` et `Content-Type: application/json;odata=nometadata`.

1. Reset : POST `_api/web/lists/getbytitle('<Liste>')/items(<ID>)/resetroleinheritance`
2. Break : POST `_api/web/lists/getbytitle('<Liste>')/items(<ID>)/breakroleinheritance(copyRoleAssignments=false,clearSubscopes=true)`
3. Owner group : GET `_api/web/associatedownergroup`, puis POST `_api/web/lists/getbytitle('<Liste>')/items(<ID>)/roleassignments/addroleassignment(principalid=@{body('Owner_group')?['Id']},roledefid=1073741829)`
4. Appliquer à chacun sur outputs('Principals') :
    1. POST `_api/web/ensureuser`, avec le corps `{"logonName": "@{items('Apply_to_each_principal')?['logon']}"}`, action nommée Ensure_principal.
    2. POST `_api/web/lists/getbytitle('<Liste>')/items(<ID>)/roleassignments/addroleassignment(principalid=@{body('Ensure_principal')?['Id']},roledefid=@{items('Apply_to_each_principal')?['role']})`

La remise à zéro préalable (étape 1) est indispensable. Sur un élément dont l'héritage est déjà rompu, breakroleinheritance ne fait rien, et les anciens droits resteraient en place.

Pour une bibliothèque, le même bloc s'applique au dossier du record. L'élément de dossier a un ID comme un élément de liste.

## Matrice des permissions

Le niveau liste (droits hérités) est réglé une fois pour toutes à la main :

```
Procurement Records     EFC-Procurement-Users : Contribute   Auditors : Read   Administrators : Full
Procurement Approvals   EFC-Procurement-Users : Read (option A) / aucun (option B)   Administrators : Full
Procurement History     Legal, Finance, Auditors : Read   Users : aucun   Administrators : Full
Procurement Documents   EFC-Procurement-Users : Read (option A) / aucun (option B)   Administrators : Full
Config, Settings, Policy Links   Users : Read   Administrators : Full
```

Droits par élément dans Procurement Records, appliqués par les flux avec le bloc P. Le groupe Propriétaires du site (et donc le compte de service) garde toujours Full Control.

```
                       Draft / Returned            Under Review / Approved / Contract Signed   Closed / Cancelled
Project Owner          Contribute                  Read                                        Read
Business Owner         Contribute                  Read                                        Read
Reviewers désignés     –                           Read                                        Read
Signature Authority    –                           Read                                        Read
Legal, Finance         Read                        Read                                        Read
Auditors               Read                        Read                                        Read
Administrators         Full                        Full                                        Full
Option A : Users       Read (hérité avant F2)      Read                                        Read
```

L'option A ne casse l'héritage qu'à la soumission (F2), et chaque utilisateur EFC peut lire tous les dossiers. L'option B le casse dès la création (F1), et seules les personnes listées voient le dossier. Les galeries de l'application respectent ces droits automatiquement.

Lignes de Procurement Approvals : à leur création (F2), l'approbateur reçoit Contribute sur sa propre ligne. Le Project Owner, Legal, Finance et Auditors reçoivent Read. Un approbateur ne peut donc pas modifier la décision d'un autre.

## F0 RecordAction

Déclencheur : Power Apps (V2), avec trois entrées : RecordItemId (Nombre), Action (Texte), Comment (Texte).

1. Initialiser la variable UserEmail (chaîne) : `toLower(triggerOutputs()?['headers']?['x-ms-user-email'])`
2. Initialiser la variable Result (chaîne) à error, et la variable Message (chaîne) à « Action non autorisée. ».
3. Étendue Try :
    1. SharePoint « Obtenir l'élément » sur Procurement Records, avec l'ID `triggerBody()?['number']` (nom de l'entrée RecordItemId). Nommer l'action Get_record.
    2. Composes Status `body('Get_record')?['Status']?['Value']`, IsOwner `or(equals(toLower(body('Get_record')?['ProjectOwner']?['Email']), variables('UserEmail')), equals(toLower(body('Get_record')?['BusinessOwner']?['Email']), variables('UserEmail')))`, IsSignatory `equals(toLower(body('Get_record')?['SignatureAuthority']?['Email']), variables('UserEmail'))`. Les noms internes Person (ProjectOwner, etc.) sont à vérifier dans les paramètres de la liste.
    3. Rôles IsAdmin, IsLegal, IsFinance, selon la méthode des paramètres communs.
    4. Commutateur (Switch) sur `triggerBody()?['text']` (Action) :

    GeneratePDF
    - Condition : `and(not(equals(outputs('Status'), 'Draft')), or(outputs('IsOwner'), outputs('IsAdmin'), outputs('IsLegal'), outputs('IsFinance')))`
    - Si vrai : mettre à jour l'élément avec PdfRequested = Oui et PdfReason = Manual. Définir Result = ok et Message = « Génération du PDF lancée ; le lien apparaîtra sous une minute. »

    ContractSigned
    - Condition : `and(equals(outputs('Status'), 'Approved'), or(outputs('IsSignatory'), outputs('IsAdmin')))`
    - Si vrai : SharePoint « Obtenir les fichiers (propriétés uniquement) » sur Procurement Documents. La requête de filtre applique l'Annex 3 : jusqu'à 10 000 EUR (paramètre ContractRequired.Above), `RecordID eq '@{body('Get_record')?['RecordID']}' and (DocumentType eq 'Contract' or DocumentType eq 'Quote or offer' or DocumentType eq 'Purchase order')`. Au-delà, `RecordID eq '@{body('Get_record')?['RecordID']}' and DocumentType eq 'Contract'`. Choisir le filtre avec une Condition sur `lessOrEquals(float(body('Get_record')?['TotalExpectedCommitment']), float(outputs('Setting_ContractAbove')))`.
    - Si aucun fichier n'est trouvé : Message = « Annex 3 : déposez le contrat exécuté (ou, jusqu'à 10 000 EUR, le devis accepté) avant de confirmer la signature. »
    - Sinon : mettre à jour Status = Contract Signed, et créer dans History un élément ContractSigned avec PerformedBy = UserEmail. Result = ok.

    Close
    - Condition : `and(equals(outputs('Status'), 'Contract Signed'), or(outputs('IsOwner'), outputs('IsAdmin')))`
    - Si vrai : Status = Closed, et un élément History Closed. Result = ok.

    Reopen
    - Condition : `and(or(equals(outputs('Status'), 'Under Review'), equals(outputs('Status'), 'Approved')), or(outputs('IsLegal'), outputs('IsAdmin')), not(empty(triggerBody()?['text_1'])))`. text_1 est l'entrée Comment.
    - Si vrai : Status = Returned for Amendment, AmendmentPending = Oui, AmendmentReason = Comment. Créer un élément History Reopened avec le motif. Result = ok. F4 prend le relais.

    Cancel
    - Condition : `and(not(contains(createArray('Closed', 'Cancelled'), outputs('Status'))), or(and(contains(createArray('Draft', 'Returned for Amendment'), outputs('Status')), outputs('IsOwner')), outputs('IsAdmin')), not(empty(triggerBody()?['text_1'])))`
    - Si vrai : Status = Cancelled. Passer les approbations en attente à Cancelled (comme dans F3, branche Returned, étape 1). Appliquer le bloc P avec tout le monde en Read. Créer un élément History Cancelled avec le motif. Result = ok.

4. Étendue Catch : bloc E.
5. « Répondre à une application ou un flux PowerApp », exécutée après Try et Catch, quel que soit leur résultat, avec deux sorties texte : result = `variables('Result')` et message = `variables('Message')`.

## F1 Record setup

Déclencheur : SharePoint « Lorsqu'un élément est créé » sur Procurement Records.

1. Condition `empty(triggerOutputs()?['body/RecordID'])`. Si vrai, mettre à jour l'élément avec RecordID = `concat('PR-', formatDateTime(triggerOutputs()?['body/Created'], 'yyyy'), '-', formatNumber(triggerOutputs()?['body/ID'], '0000'))`.
2. SharePoint « Créer un dossier » dans Procurement Documents, avec pour chemin le RecordID.
3. Créer un élément History : EventType Created, PerformedBy = Author, NewStatus Draft, VersionNumber 1.
4. Option B seulement : appliquer le bloc P sur l'élément Records (Author en Contribute, Legal/Finance/Auditors en Read, Administrators en Full), puis sur le dossier documentaire avec les mêmes principaux.
5. Option B, pour le Business Owner : il est choisi après la création. Ajouter un flux F1b, déclenché par « Lorsqu'un élément est créé ou modifié », avec la condition `and(equals(triggerOutputs()?['body/Status/Value'], 'Draft'), not(empty(triggerOutputs()?['body/BusinessOwner/Email'])))`. Ce flux appelle « Obtenir les modifications d'un élément ou d'un fichier (propriétés uniquement) », avec Since = `triggerOutputs()?['body/{TriggerWindowStartToken}']`. Si `body('Get_changes')?['ColumnHasChanged']?['BusinessOwner']` est vrai, il ajoute le Business Owner en Contribute (addroleassignment seul, sans reset).

## F2 Submit for Review

Déclencheur : SharePoint « Lorsqu'un élément est créé ou modifié » sur Procurement Records. Dans Paramètres du déclencheur :

```
Conditions de déclenchement : @equals(triggerOutputs()?['body/Status/Value'], 'Ready for Submission')
Contrôle de concurrence : activé, degré 1
```

1. Initialiser la variable Errors (tableau) à `[]`.
2. Obtenir des éléments sur Procurement Config (action Get_config) et lire les paramètres (Get_settings).
3. Compose ServerTotal :

```
add(add(add(add(add(add(
  float(coalesce(triggerOutputs()?['body/MainPrice'], 0)),
  float(coalesce(triggerOutputs()?['body/OptionsValue'], 0))),
  float(coalesce(triggerOutputs()?['body/RenewalsValue'], 0))),
  mul(float(coalesce(triggerOutputs()?['body/RecurringAnnualValue'], 0)), float(coalesce(triggerOutputs()?['body/RecurringYears'], 0)))),
  float(coalesce(triggerOutputs()?['body/ImplementationValue'], 0))),
  float(coalesce(triggerOutputs()?['body/FeesExpensesValue'], 0))),
  float(coalesce(triggerOutputs()?['body/RelatedPurchasesValue'], 0)))
```

4. Filtrer le tableau Filter_level, avec From `body('Get_config')?['value']` et la condition (mode avancé) :

```
@and(
  or(equals(item()?['MinValueExcl'], null), greater(outputs('ServerTotal'), item()?['MinValueExcl'])),
  or(equals(item()?['MaxValueIncl'], null), lessOrEquals(outputs('ServerTotal'), item()?['MaxValueIncl']))
)
```

5. Compose ServerLevel : `first(body('Filter_level'))?['Level']`
6. Compose ServerLegal :

```
or(
  greaterOrEquals(coalesce(outputs('ServerLevel'), 0), int(outputs('Setting_LegalMinLevel'))),
  equals(triggerOutputs()?['body/RelatedPartyFlag'], true),
  equals(triggerOutputs()?['body/RiskData'], true),
  equals(triggerOutputs()?['body/RiskIT'], true),
  equals(triggerOutputs()?['body/RiskIP'], true),
  equals(triggerOutputs()?['body/RiskPricing'], true),
  equals(triggerOutputs()?['body/RiskLiability'], true),
  equals(triggerOutputs()?['body/RiskLaw'], true),
  equals(triggerOutputs()?['body/RiskConflict'], true),
  equals(triggerOutputs()?['body/PurchaseType/Value'], 'Consultant or individual'),
  equals(triggerOutputs()?['body/RiskCritical'], true)
)
```

Les huit premières conditions sont celles du prototype. Les deux dernières sont l'extension tirée des Annexes 3 et 5 (formule nfLegalAnnexExtension dans l'application). Si Legal les écarte, il faut les retirer aux deux endroits.

7. Contrôles. Pour chacun, une Condition qui, si elle est vraie, ajoute un message au tableau Errors :
    - Écart de total : `or(greater(sub(outputs('ServerTotal'), float(coalesce(triggerOutputs()?['body/TotalExpectedCommitment'], 0))), 0.01), less(sub(outputs('ServerTotal'), float(coalesce(triggerOutputs()?['body/TotalExpectedCommitment'], 0))), -0.01))` → message « Total incohérent ».
    - Niveau : `not(equals(outputs('ServerLevel'), triggerOutputs()?['body/ProcurementLevel']))` → message « Niveau incohérent ».
    - Legal : `and(outputs('ServerLegal'), not(equals(triggerOutputs()?['body/LegalMandatory'], true)))` → message « Revue Legal requise mais non enregistrée ».
    - Total nul : `lessOrEquals(outputs('ServerTotal'), 0)` → message « Aucun montant : niveau non déterminé ».
    - Champs obligatoires : `or(empty(triggerOutputs()?['body/Title']), empty(triggerOutputs()?['body/Department/Value']), empty(triggerOutputs()?['body/BusinessNeed']), empty(triggerOutputs()?['body/PurchaseType/Value']), empty(triggerOutputs()?['body/ProjectOwner/Email']), empty(triggerOutputs()?['body/BusinessOwner/Email']), empty(triggerOutputs()?['body/FundingSource/Value']), empty(triggerOutputs()?['body/ProcurementContext/Value']), empty(triggerOutputs()?['body/CurrencyTreatment/Value']), empty(triggerOutputs()?['body/FinanceReviewer/Email']), empty(triggerOutputs()?['body/BusinessApprover/Email']), and(outputs('ServerLegal'), empty(triggerOutputs()?['body/LegalReviewer/Email'])))` → message « Champs obligatoires manquants ».
    - Change : `equals(triggerOutputs()?['body/CurrencyTreatment/Value'], 'Finance confirmation pending')` → message « Équivalent EUR non confirmé par Finance ».
    - Séparation des fonctions : `equals(toLower(triggerOutputs()?['body/BusinessApprover/Email']), toLower(triggerOutputs()?['body/ProjectOwner/Email']))` → message « Le Business Approver ne peut pas être le Project Owner ».
8. Condition `greater(length(variables('Errors')), 0)` :
    - Si vrai (soumission refusée) : mettre à jour l'élément avec Status = Draft et AmendmentReason = `join(variables('Errors'), '; ')`. Créer un élément History SubmissionRefused. Envoyer un e-mail au Project Owner avec la liste des erreurs et le lien vers le dossier. Puis Terminer avec l'état Réussi.
    - Si faux : poursuivre.
9. Compose Version : `coalesce(triggerOutputs()?['body/RecordVersion'], 1)`
10. Créer les lignes Procurement Approvals avec « Créer un élément ». Champs communs : Title `concat(triggerOutputs()?['body/RecordID'], ' - <Type> - v', outputs('Version'))`, ProcurementRecord Id = ID, RecordID, ApprovalVersion = Version, RequestedBy Claims = e-mail du Project Owner, Processed = Non.
    1. Finance : ApprovalType Finance, Sequence 1, Approver = FinanceReviewer Email, Decision Pending, RequestedOn `utcNow()`.
    2. Legal, si `or(outputs('ServerLegal'), not(empty(triggerOutputs()?['body/LegalReviewer/Email'])))` : ApprovalType Legal, Sequence 1, Decision Pending, RequestedOn `utcNow()`.
    3. Business : ApprovalType Business, Sequence 2, Approver = BusinessApprover Email, Decision Not started.
    4. Après chaque création : bloc P sur la ligne créée (approbateur en Contribute, Project Owner, Legal, Finance et Auditors en Read).
11. Mettre à jour l'élément Records : Status Under Review, SubmittedOn `utcNow()`, PdfRequested Oui, PdfReason Submission. L'action « Mettre à jour l'élément » exige les colonnes obligatoires : passer Title depuis le déclencheur.
12. Bloc P sur l'élément Records, selon la matrice (colonne Under Review).
13. Créer un élément History : EventType Submitted, PerformedBy = `triggerOutputs()?['body/Editor/Email']` (la personne qui a soumis), PreviousStatus Draft, NewStatus Under Review, VersionNumber = Version.
14. Envoyer un e-mail depuis une boîte partagée (Office 365 Outlook « Envoyer un e-mail à partir d'une boîte aux lettres partagée (V2) ») au Finance Reviewer et, s'il y a lieu, au Legal Reviewer, avec le lien suivant :

```
concat(outputs('Setting_AppUrl'), '?recordId=', triggerOutputs()?['body/ID'], '&view=decision')
```

Modèle de message :

```
Objet : [Procurement] Revue demandée – @{triggerOutputs()?['body/RecordID']} – @{triggerOutputs()?['body/Title']}

Bonjour,

Le dossier @{triggerOutputs()?['body/RecordID']} « @{triggerOutputs()?['body/Title']} » attend votre revue.
Total : EUR @{formatNumber(outputs('ServerTotal'), 'N2')} · Niveau @{outputs('ServerLevel')} · Route : @{triggerOutputs()?['body/ProcurementRoute']}

Ouvrir le dossier : <lien>

Ce message est envoyé automatiquement par l'EFC Procurement Assistant.
```

## F3 Decision orchestration

Déclencheur : SharePoint « Lorsqu'un élément est créé ou modifié » sur Procurement Approvals.

```
Conditions de déclenchement :
@and(
  contains(createArray('Approved', 'Approved with conditions', 'Returned', 'Rejected'), triggerOutputs()?['body/Decision/Value']),
  not(equals(triggerOutputs()?['body/Processed'], true))
)
Contrôle de concurrence : activé, degré 1
```

La concurrence à 1 est indispensable. Sans elle, si Finance et Legal décident à la même minute, deux exécutions peuvent conclure chacune qu'il reste une approbation en attente, et le dossier ne passerait jamais en séquence 2.

1. Contrôle d'auteur : Condition `equals(toLower(triggerOutputs()?['body/Editor/Email']), toLower(triggerOutputs()?['body/Approver/Email']))`. Si faux, quelqu'un d'autre que l'approbateur a modifié la ligne : remettre Decision = Pending, créer un élément History FlowError et prévenir l'administrateur. Puis Terminer.
2. Mettre à jour la ligne d'approbation avec Processed = Oui et DecisionDate = `utcNow()`.
3. Obtenir l'élément Records : action Get_record, avec l'ID `triggerOutputs()?['body/ProcurementRecord/Id']`.
4. Condition de cohérence : `and(equals(body('Get_record')?['Status']?['Value'], 'Under Review'), equals(triggerOutputs()?['body/ApprovalVersion'], body('Get_record')?['RecordVersion']))`. Si faux, la décision porte sur une version périmée : passer la ligne en Cancelled, créer un élément History et Terminer.
5. Créer un élément History : EventType Decision, PerformedBy = Approver, VersionNumber = ApprovalVersion, ChangeSummary = `concat(triggerOutputs()?['body/ApprovalType/Value'], ' : ', triggerOutputs()?['body/Decision/Value'], '. ', coalesce(triggerOutputs()?['body/Comments'], ''), if(empty(triggerOutputs()?['body/Conditions']), '', concat(' Conditions : ', triggerOutputs()?['body/Conditions'])))`.
6. Commutateur sur Decision :

    Returned
    1. Obtenir des éléments sur Procurement Approvals, avec le filtre `RecordID eq '@{triggerOutputs()?['body/RecordID']}' and ApprovalVersion eq @{triggerOutputs()?['body/ApprovalVersion']} and (Decision eq 'Pending' or Decision eq 'Not started')`. Pour chaque élément : Decision = Cancelled, Processed = Oui.
    2. Mettre à jour Records : Status Returned for Amendment, AmendmentPending Oui, AmendmentReason = Comments.
    3. Créer un élément History Returned. F4 prend le relais (version, déverrouillage, notification).

    Rejected
    1. Annuler les lignes en attente, comme pour Returned.
    2. Mettre à jour Records : Status Cancelled (ou Rejected si ce statut est ajouté), PdfRequested Oui, PdfReason Rejected.
    3. Créer un élément History Rejected, avec le motif.
    4. Envoyer un e-mail au Project Owner et au Business Owner.

    Approved, Approved with conditions (cas par défaut)
    1. Obtenir des éléments Pending_same_seq : filtre `RecordID eq '...' and ApprovalVersion eq ... and Sequence eq @{triggerOutputs()?['body/Sequence']} and Decision eq 'Pending'`.
    2. Si `greater(length(body('Pending_same_seq')?['value']), 0)` : d'autres décisions de la même séquence sont attendues. Terminer avec l'état Réussi.
    3. Obtenir des éléments Next_rows : filtre `RecordID eq '...' and ApprovalVersion eq ... and Decision eq 'Not started'`, avec le tri `Sequence asc`.
    4. Si des lignes existent : Compose NextSeq `first(body('Next_rows')?['value'])?['Sequence']`. Pour chaque ligne où Sequence = NextSeq : Decision Pending, RequestedOn `utcNow()`, puis envoyer un e-mail à l'approbateur (même modèle que F2).
    5. Sinon, toutes les séquences sont approuvées : mettre à jour Records avec Status Approved, ApprovedOn `utcNow()`, PdfRequested Oui et PdfReason Approved. Créer un élément History Approved. Envoyer un e-mail au Project Owner et à la Signature Authority, en rappelant que la signature reste soumise à l'Annex 4 et au Register of Signatories.

Une approbation « with conditions » compte comme une approbation pour l'enchaînement. Les conditions figurent dans l'historique, dans le PDF et dans l'e-mail final.

## F4 Amendment

Déclencheur : « Lorsqu'un élément est créé ou modifié » sur Procurement Records.

```
@and(
  equals(triggerOutputs()?['body/Status/Value'], 'Returned for Amendment'),
  equals(triggerOutputs()?['body/AmendmentPending'], true)
)
```

1. Annuler les lignes d'approbation encore Pending ou Not started de la version courante. C'est nécessaire dans le cas Reopen, où F3 n'est pas passé.
2. Mettre à jour Records : RecordVersion = `add(coalesce(triggerOutputs()?['body/RecordVersion'], 1), 1)`, AmendmentPending Non.
3. Bloc P selon la matrice (colonne Draft / Returned) : Project Owner et Business Owner en Contribute.
4. Envoyer un e-mail au Project Owner avec le motif (AmendmentReason) et le lien vers le dossier.

Le passage à une nouvelle version au moment du retour garantit que tout ce qui sera approuvé ensuite l'est sur la version modifiée. Les approbations et le PDF de la version précédente restent intacts (§6.3, AT-09).

## F5 PDF generation

Déclencheur : « Lorsqu'un élément est créé ou modifié » sur Procurement Records, avec la condition `@equals(triggerOutputs()?['body/PdfRequested'], true)` et une concurrence de 1.

1. Mettre à jour Records : PdfRequested Non. Cette action vient en premier, pour qu'un second déclenchement ne produise pas de doublon.
2. Obtenir des éléments Get_approvals sur Procurement Approvals : filtre `RecordID eq '...' and ApprovalVersion eq @{triggerOutputs()?['body/RecordVersion']}`, tri `Sequence asc`.
3. Sélectionner (Select), en mode texte, sur `body('Get_approvals')?['value']` :

```
concat('<tr><td>', item()?['ApprovalType']?['Value'], '</td><td>', item()?['Approver']?['DisplayName'], '</td><td>',
item()?['Decision']?['Value'], '</td><td>', if(empty(item()?['DecisionDate']), '', formatDateTime(item()?['DecisionDate'], 'dd.MM.yyyy HH:mm')),
'</td><td>', coalesce(item()?['Comments'], ''), '</td><td>', coalesce(item()?['Conditions'], ''), '</td></tr>')
```

4. Compose ApprovalRows : `join(body('Select_rows'), '')`
5. Compose Html : coller le contenu de 04-pdf/procurement-record-template.html. Les expressions @{...} du gabarit sont évaluées à l'exécution. Vérifier après collage qu'elles apparaissent bien comme des jetons d'expression. Les champs de texte libre (Title, BusinessNeed, InitialRisks, ValueCalculationBasis, Comments, ainsi que Comments et Conditions dans le Select) doivent être échappés : un « < » ou un « & » saisi par l'utilisateur casserait la mise en page ou supprimerait du texte dans le PDF. Envelopper chacun de ces champs dans `replace(replace(replace(coalesce(<champ>, ''), '&', '&amp;'), '<', '&lt;'), '>', '&gt;')`.
6. Compose FileName :

```
concat(triggerOutputs()?['body/RecordID'], '_V', formatNumber(coalesce(triggerOutputs()?['body/RecordVersion'], 1), '000'), '_', replace(triggerOutputs()?['body/Status/Value'], ' ', ''), '.pdf')
```

7. Unicité : un PDF existant n'est jamais remplacé (§10). Faire un « Obtenir les fichiers (propriétés uniquement) » avec le filtre `FileLeafRef eq '@{outputs('FileName')}'`. Si un fichier existe, par exemple lors d'une génération manuelle répétée dans le même statut, utiliser plutôt `replace(outputs('FileName'), '.pdf', concat('_', formatDateTime(utcNow(), 'yyyyMMddHHmm'), '.pdf'))`. Stocker le nom retenu dans une variable FinalName.
8. OneDrive Entreprise « Créer un fichier » : dossier /EFC-Procurement-Temp, nom `concat(guid(), '.html')`, contenu `outputs('Html')`. Action Create_temp.
9. OneDrive Entreprise « Convertir un fichier », avec l'ID de fichier `body('Create_temp')?['Id']` et le type PDF. Action Convert.
10. SharePoint « Créer un fichier » : dossier `/Procurement Documents/@{triggerOutputs()?['body/RecordID']}`, nom FinalName, contenu `body('Convert')`. Action Create_pdf.
11. SharePoint « Mettre à jour les propriétés du fichier », avec l'ID `body('Create_pdf')?['ItemId']` : RecordID, ProcurementRecord Id, DocumentType Generated PDF, DocVersion = RecordVersion, DocStatus Current, DocOwner = Project Owner.
12. OneDrive « Supprimer un fichier » sur Create_temp.
13. Anciens PDF : obtenir les fichiers avec le filtre `RecordID eq '...' and DocumentType eq 'Generated PDF' and DocStatus eq 'Current' and ID ne @{body('Create_pdf')?['ItemId']}`. Pour chacun, DocStatus = Superseded. Seule la métadonnée change, le fichier n'est pas modifié.
14. SharePoint « Obtenir les propriétés du fichier » sur ItemId (action Get_pdf_props), puis mettre à jour Records avec LatestPDFUrl = `body('Get_pdf_props')?['{Link}']`.
15. Créer un élément History : EventType PDFGenerated, PDFUrl, VersionNumber, ChangeSummary = PdfReason.

## F6 Closure

Déclencheur : « Lorsqu'un élément est créé ou modifié » sur Procurement Records.

```
@or(
  and(equals(triggerOutputs()?['body/Status/Value'], 'Contract Signed'), empty(triggerOutputs()?['body/ContractSignedOn'])),
  and(equals(triggerOutputs()?['body/Status/Value'], 'Closed'), empty(triggerOutputs()?['body/ClosedOn']))
)
```

Commutateur sur Status :

Contract Signed :
1. Mettre à jour ContractSignedOn `utcNow()`, PdfRequested Oui, PdfReason Contract Signed.
2. Envoyer un e-mail au Project Owner, au Legal Reviewer et au Finance Reviewer.

Closed :
1. Contrôle documentaire : obtenir les fichiers du record par type, et calculer la liste des types attendus absents. Le minimum est Contract ou Purchase order, plus Due diligence si le tier n'est pas Low, et Sourcing evidence si le niveau est 2 ou plus. Une liste non vide n'empêche pas la clôture, déjà décidée par F0, mais elle est envoyée à l'administrateur et inscrite dans l'historique.
2. Mettre à jour ClosedOn `utcNow()`, PdfRequested Oui, PdfReason Closed.
3. Bloc P : tout le monde en Read.
4. Envoyer un e-mail aux parties concernées.

## F7 UploadProcurementDocument

Déclencheur : Power Apps (V2), avec les entrées RecordItemId (Nombre), RecordID (Texte), DocumentType (Texte) et file (Fichier).

1. Variables UserEmail (comme dans F0), Result = error, Message.
2. Try :
    1. Obtenir l'élément Records. Vérifier que le statut n'est ni Closed ni Cancelled, et que l'utilisateur est owner, reviewer désigné ou administrateur. Sinon, Message = « Dépôt non autorisé pour ce dossier. »
    2. SharePoint « Créer un fichier » : dossier `/Procurement Documents/@{triggerBody()?['text']}`, nom `concat(formatDateTime(utcNow(), 'yyyyMMdd-HHmmss'), '_', triggerBody()?['file']?['name'])`, contenu `base64ToBinary(triggerBody()?['file']?['contentBytes'])`. L'horodatage dans le nom empêche d'écraser un document existant.
    3. Mettre à jour les propriétés du fichier : RecordID, ProcurementRecord, DocumentType, DocVersion = RecordVersion, DocStatus Current, DocOwner = UserEmail.
    4. Créer un élément History DocumentUploaded, avec PerformedBy = UserEmail.
    5. Result = ok, Message = « Document ajouté. »
3. Catch : bloc E.
4. Répondre à Power Apps avec result et message.

Taille de fichier : la transmission depuis Power Apps est limitée (environ 50 Mo par appel en pratique). Les très gros dossiers d'offres doivent être déposés directement dans le dossier SharePoint du record, où ils reçoivent les mêmes métadonnées par les colonnes de la bibliothèque.

## Bloc E – gestion d'erreur (tous les flux)

1. Regrouper toutes les actions métier dans une Étendue nommée Try.
2. Ajouter une Étendue Catch. Dans Configurer l'exécution après, cocher « a échoué » et « a expiré ».
3. Dans Catch :
    1. Filtrer le tableau Failed_actions, avec From `result('Try')` et la condition `@equals(item()?['status'], 'Failed')`.
    2. Compose RunUrl :

```
concat('https://make.powerautomate.com/environments/', workflow()?['tags']?['environmentName'], '/flows/', workflow()?['name'], '/runs/', workflow()?['run']?['name'])
```

    3. Créer un élément History : EventType FlowError, RecordID quand il est connu, ChangeSummary = `concat(workflow()?['tags']?['flowDisplayName'], ' : ', string(first(body('Failed_actions'))?['error']))`.
    4. Envoyer un e-mail à AdminEmail avec le nom du flux, le RecordID, l'erreur et RunUrl.
    5. Dans F0 et F7 : Message = « Erreur technique, l'administrateur a été prévenu. »
    6. Terminer avec l'état Échec, sauf dans F0 et F7, qui doivent encore répondre à Power Apps.

Aucune donnée n'est perdue en cas d'échec. Le dossier reste dans son dernier état cohérent, puisque les mises à jour de statut sont faites en fin de flux, après les créations de lignes. L'administrateur relance l'exécution depuis RunUrl après correction (AT-13).
