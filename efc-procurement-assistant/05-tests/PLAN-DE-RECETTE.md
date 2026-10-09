# Plan de recette

Prévoir six comptes de test, chacun membre d'un seul groupe : un requester (Users), un second requester utilisé comme Business Owner, un membre Legal, un membre Finance, un Business Approver (Approvers) et un auditeur. Ajouter un compte Administrators. Le Project Owner et le Business Approver doivent être deux personnes distinctes.

## Jeux de données

Calcul du total (AT-03) :

```
Main Price 10 000 · Options 2 000 · Renewals 3 000 · Recurring 4 000 x 3 ans · Implementation 1 500
Fees 500 · Related Purchases 1 000
Total attendu : 10 000 + 2 000 + 3 000 + 12 000 + 1 500 + 500 + 1 000 = 30 000,00 → niveau 2, Market assessment
```

Bornes des seuils (AT-04). Chaque montant est saisi dans Main Price seul :

```
0,00        → aucun niveau, soumission bloquée
25 000,00   → niveau 1   Standard     Direct appointment
25 000,01   → niveau 2   Controlled   Market assessment
50 000,00   → niveau 2
50 000,01   → niveau 3   Enhanced     Competitive request for proposals
250 000,00  → niveau 3
250 000,01  → niveau 4   Strategic    Market information request followed by competitive RFP
47 500,00   → niveau 2, sans alerte de seuil (95 % de 50 000 exactement)
47 500,01   → niveau 2, avec alerte de seuil
23 750,01   → niveau 1, avec alerte de seuil
250 000,00  → niveau 3, avec alerte de seuil
```

Validation des montants : -1 dans Options doit bloquer la soumission. 2,5 dans Recurring Years doit afficher l'erreur « années entières » et bloquer la soumission.

Déclencheurs (AT-05) : les résultats suivent le prototype, sauf les deux lignes marquées « extension », qui découlent des Annexes 3 et 5 (README).

```
Niveau 1, aucun risque                 → Legal non requis · Risk Low · DD Low
Niveau 1, IT seul                      → Legal obligatoire · Risk Medium · DD Medium
Niveau 1, Open-ended pricing seul      → Legal obligatoire · Risk Low · DD Low
Niveau 1, Personal Data seul           → Legal obligatoire · Risk Medium · DD Medium
Niveau 1, Conflict seul                → Legal obligatoire · Risk High · DD High
Niveau 1, Related party (étape 1)      → Legal obligatoire · Risk High · DD High
Niveau 2 (45 000), aucun risque        → Legal non requis · Risk Low · DD Low
Niveau 3 (60 000), aucun risque        → Legal obligatoire · Risk Medium · DD Medium
Niveau 1, Critical seul                → Risk High · DD High · Legal obligatoire (extension Annex 5 ; prototype : non)
Niveau 1, Consultant or individual     → Risk Low · Legal obligatoire (extension Annex 3 ; prototype : non)
Currency « Finance confirmation pending » → soumission bloquée
```

## Scénarios

| ID | Étapes | Résultat attendu | Composants |
|---|---|---|---|
| AT-01 | Requester : New Procurement. | Un élément Draft est créé, avec RecordID PR-AAAA-NNNN, Project Owner = requester et version 1. Historique Created. Dossier documentaire créé. | btnNew, F1 |
| AT-02 | Saisir les étapes 1 et 2, enregistrer, fermer le navigateur, rouvrir depuis My Drafts. | Toutes les valeurs sont restituées, et l'application s'ouvre sur la dernière étape enregistrée. | btnSave, LastStep, galRecords |
| AT-03 | Jeu « calcul du total ». | Le total affiché et le total enregistré valent 30 000,00. | nfTotal, btnSave |
| AT-04 | Jeux « bornes des seuils ». | Le niveau, la route et l'alerte sont conformes au tableau. | nfLevel, Procurement Config |
| AT-05 | Jeux « déclencheurs ». | Legal Mandatory, Risk Profile et DD Tier sont conformes au tableau. | nfLegalMandatory, nfRiskProfile |
| AT-06 | Le requester A crée un brouillon. Le requester B ouvre My Drafts. | B ne voit pas le brouillon de A, sauf s'il en est le Business Owner. En option B, B ne le trouve pas non plus par Search. | galRecords, F1 (option B) |
| AT-07 | Soumettre un dossier incomplet, puis un dossier complet. | Dossier incomplet : le bouton est désactivé et la liste des manques s'affiche. Dossier complet : statut Under Review, SubmittedOn renseigné, approbations Finance et (si requis) Legal en Pending, Business en Not started, e-mails reçus, PDF V001 créé. | nfMissing, F2, F5 |
| AT-07b | Modifier directement dans SharePoint le TotalExpectedCommitment d'un brouillon (le mettre à 1 000 pour un dossier de 80 000), puis soumettre. | Soumission refusée, statut ramené à Draft, motif « Total incohérent » ou « Niveau incohérent ». | F2 |
| AT-07c | Choisir le Project Owner comme Business Approver. | Soumission bloquée dans l'application et refusée par F2. | nfMissing, F2 |
| AT-08 | Le Finance Reviewer retourne le dossier avec un commentaire. | Statut Returned for Amendment, version 2, motif conservé dans l'historique et AmendmentReason, owner notifié, dossier de nouveau modifiable par l'owner et le Business Owner uniquement. Les approbations restantes de la version 1 passent à Cancelled. | F3, F4 |
| AT-09 | Après AT-08, modifier le montant, resoumettre, approuver. | Le PDF V001 existe toujours, marqué Superseded. Le PDF V002 est créé, et LatestPDFUrl pointe vers lui. Aucun fichier n'a été écrasé. | F5 |
| AT-10 | Finance approuve sous conditions, Legal approuve, le Business Approver approuve. | Trois lignes conservent l'approbateur, la date serveur, le commentaire, les conditions et la version. La séquence 2 n'est sollicitée qu'après les deux décisions de la séquence 1. Statut Approved, ApprovedOn renseigné. | F3, galDecisions |
| AT-10b | Finance et Legal valident à quelques secondes d'intervalle. | Le Business Approver est sollicité une seule fois. | F3 (concurrence 1) |
| AT-11 | Un requester tente, dans SharePoint, de modifier un dossier Under Review, de modifier la ligne d'approbation d'un autre, et d'ouvrir un dossier d'un autre service (option B). | Les trois actions sont refusées par SharePoint. Une modification de la décision d'autrui par une personne ayant des droits étendus est détectée par F3 et annulée. | Bloc P, F3 |
| AT-12 | Depuis chaque étape, ouvrir Policy & Annexes et chaque lien. | Les six documents publiés s'ouvrent. Une URL modifiée dans la liste est prise en compte sans republier l'application. | conPolicy |
| AT-13 | Renommer temporairement la bibliothèque Procurement Documents, puis demander un PDF. | L'historique contient un FlowError, et l'administrateur reçoit un e-mail avec le RecordID, l'erreur et le lien vers l'exécution. Le dossier reste dans son état précédent. Après correction, la relance aboutit. | Bloc E |
| AT-14 | Ouvrir l'application à 1366 x 768, 1920 x 1080, sur un iPad en paysage et dans la webpart SharePoint. | Pas de chevauchement ni de défilement horizontal, et le pied de page reste visible. | Conteneurs |
| AT-15 | Signature Authority : Contract Signed sans contrat déposé, puis avec contrat. Owner : Close. | Sans contrat, l'action est refusée avec un message. Avec contrat : ContractSignedOn renseigné et PDF généré. Close : ClosedOn renseigné, dossier en lecture seule pour tous et PDF final généré. | F0, F6 |
| AT-16 | Auditeur : ouvrir un dossier clos, l'historique et les documents. | Tout est consultable, aucun bouton de modification n'est visible, et toute modification par SharePoint est refusée. | Matrice des permissions |

AT-07b, AT-07c, AT-10b, AT-15 et AT-16 ne figurent pas dans le cahier. Ils testent les protections ajoutées par cette conception. Sans eux, la recette pourrait valider une application qui fonctionne mais qui se contourne.

## Procès-verbal

Pour chaque scénario, consigner la date, le testeur, le compte utilisé, le résultat (conforme ou non conforme), le RecordID de test et, en cas d'écart, la référence de l'anomalie. La recette est prononcée par le Product Owner Legal, après validation Finance des scénarios AT-03, AT-04 et AT-10.
