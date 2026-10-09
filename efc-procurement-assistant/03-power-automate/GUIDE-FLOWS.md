# Flux Power Automate

Tous les flux sont créés dans la Solution, appartiennent à un compte de service dédié (par exemple svc-procurement@efc...) et utilisent ses connexions. Ce compte doit être membre du groupe Propriétaires du site Legal Department et disposer d'une licence Microsoft 365 avec Exchange (pour l'envoi depuis une boîte partagée) et OneDrive (pour la conversion PDF). Si un flux est la propriété d'une personne, il s'arrête le jour où cette personne quitte EFC.

Dans les expressions ci-dessous, les noms d'actions correspondent aux noms à donner aux actions dans le concepteur. Renommez chaque action dès sa création : par exemple, une action renommée « Get record » devient body('Get_record') dans les expressions.

Tous les flux suivent la même structure de gestion d'erreur, décrite à la fin (bloc E). Les permissions ne sont modifiées que par le flux enfant FP. Les flux enfants imposent que tous les flux soient dans la même Solution.

## Vue d'ensemble

| Flux | Déclencheur | Rôle |
|---|---|---|
| FP Set permissions | Flux enfant | Seul flux qui modifie des permissions (option B). Appelé par tous les autres. |
| F0 RecordAction | Power Apps (V2) | Actions privilégiées : GeneratePDF, ContractSigned, Close, Reopen, Cancel, RepairPermissions. Contrôle du rôle côté serveur. |
| F1 Record setup | Création d'un élément Records | Filet de sécurité RecordID, historique Created, dossier documentaire, permissions initiales. |
| F1b Owner change | Modification d'un brouillon | Recalcule les permissions si le Project Owner ou le Business Owner change. |
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

## Permissions – option B (accès limité dossier par dossier)

Décision retenue : chaque dossier n'est visible que par les personnes qui y ont un rôle, ainsi que par Legal, Finance, Auditors et Administrators. Le principe est simple. Aucun utilisateur ne tient ses droits d'un niveau supérieur : chaque dossier, chaque dossier documentaire et chaque ligne d'approbation reçoit ses propres permissions, recalculées entièrement à chaque changement d'état par un flux enfant unique, FP. Aucun autre flux ne manipule de permissions. Tous appellent FP, ce qui garantit une règle unique et vérifiable.

### Niveau liste (posé par le script, une fois)

```
Procurement Records     Users : EFC Contribute without delete   Administrators : Full   Propriétaires du site : Full
Procurement Approvals   Administrators : Full   Propriétaires du site : Full
Procurement Documents   Administrators : Full   Propriétaires du site : Full
Procurement History     Legal, Finance, Auditors : Read   Administrators : Full   Propriétaires du site : Full
Config, Settings, Policy Links   Users, Legal, Finance, Approvers, Auditors : Read   Administrators : Full
```

Les membres et visiteurs du site Legal Department perdent leurs droits hérités sur ces listes : faire partie du département Legal ne donne pas accès aux dossiers, seule l'appartenance aux groupes EFC-Procurement compte. SharePoint accorde automatiquement un « accès limité » au site à ceux qui ont un droit sur une liste ou un élément, ce qui suffit à l'application.

Le niveau « EFC Contribute without delete » est créé par le script : il reprend Collaboration sans la suppression d'éléments ni de versions. Personne, hors administrateurs, ne peut donc supprimer un dossier, une décision ou une pièce. Un dossier abandonné se clôt par Cancel, et la piste d'audit reste entière.

Sur Procurement Records, le droit de liste des Users ne sert qu'à créer un dossier. Un dossier tout juste créé hérite pendant quelques secondes de ce droit, jusqu'à ce que F1 lui applique ses permissions propres. À ce moment, il ne contient qu'un titre provisoire et le nom de son créateur. Ce délai est accepté.

### Droits par objet (calculés par FP)

Dossier (Procurement Records) :

```
                        Draft                  Returned for Amendment   Under Review → Contract Signed   Closed / Cancelled
Project Owner           Contribute s. suppr.   Contribute s. suppr.     Read                             Read
Business Owner          Contribute s. suppr.   Contribute s. suppr.     Read                             Read
Créateur (Author)       Read                   Read                     Read                             Read
Reviewers désignés *    –                      Read                     Read                             Read
Legal, Finance          Read                   Read                     Read                             Read
Auditors                Read                   Read                     Read                             Read
Administrators          Full                   Full                     Full                             Full
* Legal Reviewer, Finance Reviewer, Business Approver, Signature Authority
```

Dossier documentaire (Procurement Documents/<RecordID>) : mêmes personnes, mais le Project Owner et le Business Owner gardent « Contribute sans suppression » jusqu'à Closed ou Cancelled. Ils doivent pouvoir déposer offres, contrat et bon de commande après l'approbation.

Ligne d'approbation (Procurement Approvals) : l'approbateur dispose de « Contribute sans suppression » uniquement tant que sa ligne est Pending. Une ligne Not started ou déjà décidée lui est en lecture seule. Il ne peut donc ni décider avant son tour, ni modifier sa décision après traitement. Le Project Owner, Legal, Finance et Auditors ont Read, Administrators Full.

Le créateur garde la lecture lorsqu'il transmet le dossier à un autre Project Owner : il ne perd pas la trace de ce qu'il a initié, mais ne peut plus le modifier.

### FP Set permissions (flux enfant)

À créer en premier, dans la Solution. Déclencheur : « Déclencher manuellement un flux », avec les entrées Target (Texte : record, folder ou approval), RecordItemId (Nombre) et ApprovalItemId (Nombre, 0 si sans objet). Dans les propriétés du flux, pour les utilisateurs en exécution seule, choisir la connexion du compte de service, et non « fournie par l'utilisateur ». Un flux enfant doit se terminer par l'action « Répondre à une application ou un flux PowerApp ».

1. Obtenir l'élément Get_record (Procurement Records, ID = RecordItemId), puis lire les paramètres GroupId.Legal, GroupId.Finance, GroupId.Auditors, GroupId.Administrators et RoleDefId.ContributeNoDelete (voir Paramètres communs).
2. Composes :

```
Status        body('Get_record')?['Status']?['Value']
IsDraft       equals(outputs('Status'), 'Draft')
IsEditable    contains(createArray('Draft', 'Returned for Amendment'), outputs('Status'))
IsFinal       contains(createArray('Closed', 'Cancelled', 'Rejected'), outputs('Status'))
CND           outputs('Setting_RoleCND')
```

3. Compose GroupPrincipals :

```
[
  {"logon": "c:0t.c|tenant|@{outputs('Setting_GroupLegal')}", "role": "1073741826"},
  {"logon": "c:0t.c|tenant|@{outputs('Setting_GroupFinance')}", "role": "1073741826"},
  {"logon": "c:0t.c|tenant|@{outputs('Setting_GroupAuditors')}", "role": "1073741826"},
  {"logon": "c:0t.c|tenant|@{outputs('Setting_GroupAdmins')}", "role": "1073741829"}
]
```

4. Initialiser les variables ListTitle (chaîne), ItemId (entier) et People (tableau).
5. Commutateur sur Target :

    record
    - ListTitle = Procurement Records, ItemId = RecordItemId.
    - People :

```
[
  {"logon": "i:0#.f|membership|@{toLower(coalesce(body('Get_record')?['ProjectOwner']?['Email'], ''))}", "role": "@{if(outputs('IsEditable'), outputs('CND'), '1073741826')}"},
  {"logon": "i:0#.f|membership|@{toLower(coalesce(body('Get_record')?['BusinessOwner']?['Email'], ''))}", "role": "@{if(outputs('IsEditable'), outputs('CND'), '1073741826')}"},
  {"logon": "i:0#.f|membership|@{toLower(coalesce(body('Get_record')?['Author']?['Email'], ''))}", "role": "1073741826"},
  {"logon": "i:0#.f|membership|@{if(outputs('IsDraft'), '', toLower(coalesce(body('Get_record')?['LegalReviewer']?['Email'], '')))}", "role": "1073741826"},
  {"logon": "i:0#.f|membership|@{if(outputs('IsDraft'), '', toLower(coalesce(body('Get_record')?['FinanceReviewer']?['Email'], '')))}", "role": "1073741826"},
  {"logon": "i:0#.f|membership|@{if(outputs('IsDraft'), '', toLower(coalesce(body('Get_record')?['BusinessApprover']?['Email'], '')))}", "role": "1073741826"},
  {"logon": "i:0#.f|membership|@{if(outputs('IsDraft'), '', toLower(coalesce(body('Get_record')?['SignatureAuthority']?['Email'], '')))}", "role": "1073741826"}
]
```

    folder
    - SharePoint « Obtenir les métadonnées du dossier à l'aide du chemin », avec le chemin `/Procurement Documents/@{body('Get_record')?['RecordID']}`. Action Get_folder. ListTitle = Procurement Documents, ItemId = `body('Get_folder')?['ItemId']`.
    - People : identique à record, en remplaçant l'expression de rôle des deux owners par `@{if(outputs('IsFinal'), '1073741826', outputs('CND'))}`.

    approval
    - Obtenir l'élément Get_approval (Procurement Approvals, ID = ApprovalItemId). ListTitle = Procurement Approvals, ItemId = ApprovalItemId.
    - People :

```
[
  {"logon": "i:0#.f|membership|@{toLower(coalesce(body('Get_approval')?['Approver']?['Email'], ''))}", "role": "@{if(equals(body('Get_approval')?['Decision']?['Value'], 'Pending'), outputs('CND'), '1073741826')}"},
  {"logon": "i:0#.f|membership|@{toLower(coalesce(body('Get_record')?['ProjectOwner']?['Email'], ''))}", "role": "1073741826"}
]
```

6. Filtrer le tableau Principals, avec From `union(variables('People'), outputs('GroupPrincipals'))` et la condition `@not(endsWith(item()?['logon'], '|'))`. Cette condition écarte les personnes non renseignées.
7. Appliquer les permissions. Toutes les actions sont des « Envoyer une requête HTTP à SharePoint » sur le site Legal Department, avec les en-têtes `Accept: application/json;odata=nometadata` et `Content-Type: application/json;odata=nometadata`. L'URI de base est `_api/web/lists/getbytitle('@{variables('ListTitle')}')/items(@{variables('ItemId')})`.
    1. POST `<base>/resetroleinheritance`
    2. POST `<base>/breakroleinheritance(copyRoleAssignments=false,clearSubscopes=true)`
    3. GET `_api/web/associatedownergroup` (action Owner_group), puis POST `<base>/roleassignments/addroleassignment(principalid=@{body('Owner_group')?['Id']},roledefid=1073741829)`
    4. Appliquer à chacun sur `body('Principals')`, avec une concurrence de 1 :
        1. POST `_api/web/ensureuser`, corps `{"logonName": "@{items('Apply_to_each_principal')?['logon']}"}`. Action Ensure_principal.
        2. POST `<base>/roleassignments/addroleassignment(principalid=@{body('Ensure_principal')?['Id']},roledefid=@{items('Apply_to_each_principal')?['role']})`
8. Répondre avec result = ok. En cas d'échec (bloc E), répondre avec result = error et le message, pour que le flux appelant journalise l'erreur.

Le reset de l'étape 1 est indispensable : sur un élément dont l'héritage est déjà rompu, breakroleinheritance ne fait rien, et les anciens droits resteraient en place. Le groupe Propriétaires est ajouté en premier, pour que le compte de service ne perde jamais l'accès en cours de traitement.

Une même personne peut apparaître deux fois, par exemple comme Project Owner et Business Owner. SharePoint cumule simplement les deux attributions, sans erreur.

Comme FP recalcule toujours l'intégralité des droits à partir de l'état courant, l'appeler une fois de trop est sans conséquence. Si deux appels se chevauchaient sur le même objet et laissaient une permission incomplète, l'action RepairPermissions de F0, réservée aux administrateurs, la recalcule.

Appels de FP par les autres flux :

```
F1   création             record, folder
F1b  changement d'owner   record, folder
F2   soumission           approval (chaque ligne créée), record, folder
F3   décision             approval (ligne décidée, lignes activées, lignes annulées)
F4   retour / reopen      record, folder, approval (lignes annulées)
F6   clôture              record, folder
F0   Cancel               record, folder, approval (lignes annulées)
F0   RepairPermissions    record, folder, approval (toutes les lignes du dossier)
```

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
    - Si vrai : Status = Cancelled. Passer les approbations en attente à Cancelled (comme dans F3, branche Returned, étape 1). Appeler FP pour record, folder et chaque ligne annulée. Créer un élément History Cancelled avec le motif. Result = ok.

    RepairPermissions
    - Condition : `outputs('IsAdmin')`
    - Si vrai : appeler FP pour record et folder. Puis « Obtenir des éléments » Procurement Approvals, avec le filtre `RecordID eq '@{body('Get_record')?['RecordID']}'`, et appeler FP (approval) pour chaque ligne. Créer un élément History PermissionsRepaired, avec PerformedBy = UserEmail. Result = ok.

4. Étendue Catch : bloc E.
5. « Répondre à une application ou un flux PowerApp », exécutée après Try et Catch, quel que soit leur résultat, avec deux sorties texte : result = `variables('Result')` et message = `variables('Message')`.

## F1 Record setup

Déclencheur : SharePoint « Lorsqu'un élément est créé » sur Procurement Records.

1. Compose RecordID : `coalesce(triggerOutputs()?['body/RecordID'], concat('PR-', formatDateTime(triggerOutputs()?['body/Created'], 'yyyy'), '-', formatNumber(triggerOutputs()?['body/ID'], '0000')))`. L'application écrit le RecordID quelques instants après la création. Le flux peut donc le recevoir vide, et le calcule alors avec la même formule.
2. Condition `empty(triggerOutputs()?['body/RecordID'])`. Si vrai, mettre à jour l'élément avec RecordID = `outputs('RecordID')`.
3. SharePoint « Créer un dossier » dans Procurement Documents, avec le chemin `outputs('RecordID')`.
4. Exécuter le flux enfant FP avec Target = record et RecordItemId = ID, puis avec Target = folder.
5. Créer un élément History : EventType Created, PerformedBy = Author, NewStatus Draft, VersionNumber 1.

Le flux FP de l'étape 4 lit le RecordID dans l'élément. Si l'application ne l'a pas encore écrit, l'étape 2 l'a fait. Placer les étapes 2 et 3 avant l'étape 4 n'est donc pas facultatif.

## F1b Owner change

Déclencheur : « Lorsqu'un élément est créé ou modifié » sur Procurement Records, avec la condition :

```
@and(
  contains(createArray('Draft', 'Returned for Amendment'), triggerOutputs()?['body/Status/Value']),
  not(equals(triggerOutputs()?['body/Created'], triggerOutputs()?['body/Modified']))
)
```

1. SharePoint « Obtenir les modifications d'un élément ou d'un fichier (propriétés uniquement) », avec Since = `triggerOutputs()?['body/{TriggerWindowStartToken}']`. Action Get_changes.
2. Condition `or(equals(body('Get_changes')?['ColumnHasChanged']?['ProjectOwner'], true), equals(body('Get_changes')?['ColumnHasChanged']?['BusinessOwner'], true))`.
3. Si vrai : FP record, puis FP folder.

L'ancien Business Owner perd ainsi son accès dès qu'il est remplacé. Le flux se déclenche à chaque enregistrement d'un brouillon, mais il s'arrête à l'étape 2 dans la grande majorité des cas.

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
    4. Après chaque création : FP avec Target = approval et ApprovalItemId = ID de la ligne créée. Les lignes Pending donnent la main à leur approbateur, la ligne Business (Not started) lui reste en lecture seule.
11. Mettre à jour l'élément Records : Status Under Review, SubmittedOn `utcNow()`, PdfRequested Oui, PdfReason Submission. L'action « Mettre à jour l'élément » exige les colonnes obligatoires : passer Title depuis le déclencheur.
12. FP record, puis FP folder. Le dossier passe en lecture seule pour ses owners, et les reviewers désignés y accèdent.
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
2. Mettre à jour la ligne d'approbation avec Processed = Oui et DecisionDate = `utcNow()`, puis appeler FP approval sur cette ligne. La décision n'étant plus Pending, l'approbateur passe en lecture seule et ne peut plus la modifier.
3. Obtenir l'élément Records : action Get_record, avec l'ID `triggerOutputs()?['body/ProcurementRecord/Id']`.
4. Condition de cohérence : `and(equals(body('Get_record')?['Status']?['Value'], 'Under Review'), equals(triggerOutputs()?['body/ApprovalVersion'], body('Get_record')?['RecordVersion']))`. Si faux, la décision porte sur une version périmée : passer la ligne en Cancelled, créer un élément History et Terminer.
5. Créer un élément History : EventType Decision, PerformedBy = Approver, VersionNumber = ApprovalVersion, ChangeSummary = `concat(triggerOutputs()?['body/ApprovalType/Value'], ' : ', triggerOutputs()?['body/Decision/Value'], '. ', coalesce(triggerOutputs()?['body/Comments'], ''), if(empty(triggerOutputs()?['body/Conditions']), '', concat(' Conditions : ', triggerOutputs()?['body/Conditions'])))`.
6. Commutateur sur Decision :

    Returned
    1. Obtenir des éléments sur Procurement Approvals, avec le filtre `RecordID eq '@{triggerOutputs()?['body/RecordID']}' and ApprovalVersion eq @{triggerOutputs()?['body/ApprovalVersion']} and (Decision eq 'Pending' or Decision eq 'Not started')`. Pour chaque élément : Decision = Cancelled, Processed = Oui, puis FP approval sur la ligne.
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
    4. Si des lignes existent : Compose NextSeq `first(body('Next_rows')?['value'])?['Sequence']`. Pour chaque ligne où Sequence = NextSeq : Decision Pending, RequestedOn `utcNow()`, puis FP approval sur la ligne (l'approbateur reçoit la main), puis envoyer un e-mail à l'approbateur (même modèle que F2).
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
3. FP record, FP folder, et FP approval pour chaque ligne annulée à l'étape 1. Le Project Owner et le Business Owner retrouvent la main sur le dossier.
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
3. FP record, puis FP folder : tout le monde passe en lecture seule.
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
