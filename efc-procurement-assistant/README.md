# EFC Procurement Assistant – kit de construction

Ce dossier traduit le cahier des charges « EFC Procurement Assistant, Draft 1.0 » en éléments directement exécutables ou copiables dans Power Platform. Il ne remplace pas la recette Legal/Finance : plusieurs règles du cahier sont renvoyées à « la règle validée », et j'ai dû poser des hypothèses explicites, regroupées à la fin de ce document.

## Contenu

1. `01-sharepoint/Provision-EFC-Procurement.ps1` : script PnP PowerShell qui crée les listes complémentaires, la bibliothèque documentaire, les listes de paramétrage, les colonnes techniques manquantes et les index. Il ne modifie aucune colonne existante de Procurement Records.
2. `02-power-apps/GUIDE-POWER-APPS.md` : construction de la Canvas App écran par écran, avec les noms de contrôles et toutes les formules Power Fx.
3. `02-power-apps/App.Formulas.fx` : les formules nommées (calcul du total, route, risques, champs manquants) à coller dans la propriété Formulas de l'objet App.
4. `03-power-automate/GUIDE-FLOWS.md` : les huit flux, action par action, avec les expressions et les conditions de déclenchement.
5. `04-pdf/procurement-record-template.html` : le gabarit HTML converti en PDF par le flux de génération.
6. `05-tests/PLAN-DE-RECETTE.md` : les scénarios AT-01 à AT-14 rattachés aux composants qui les couvrent, avec les jeux de données de test.

## Ordre de construction

1. Créer les groupes Entra ID listés au point 5.1 du cahier et noter leurs identifiants (Object ID).
2. Exécuter le script SharePoint, puis renseigner les identifiants de groupes et l'adresse de l'administrateur dans la liste Procurement Settings.
3. Créer une Solution Power Platform « EFC Procurement Assistant » et y créer toutes les ressources suivantes, afin de pouvoir les exporter vers test et production.
4. Construire les flux F1, F5 et F7 en premier : la numérotation, le PDF et le téléversement sont indépendants et faciles à tester seuls.
5. Construire l'application en suivant le guide, puis les flux F0, F2, F3, F4 et F6.
6. Dérouler le plan de recette avec un compte de chaque profil.

## Choix d'architecture qui s'écartent du cahier ou le précisent

Le calcul de la route ne peut pas reposer uniquement sur Power Apps. Pour enregistrer un dossier depuis l'application, l'utilisateur doit avoir le droit de modifier la liste SharePoint, ce qui lui permet aussi de la modifier directement dans SharePoint, y compris le statut et le niveau calculé. J'ai donc prévu deux protections. D'une part, le flux de soumission recalcule le total et le niveau à partir des paramètres et refuse la soumission en cas d'écart. D'autre part, dès la soumission, le dossier passe en lecture seule pour le demandeur au moyen de permissions par élément ; seul le compte de service des flux peut encore le modifier. Les actions privilégiées (Contract Signed, Close, Reopen, Cancel, génération manuelle du PDF) passent par un flux appelé depuis l'application, qui vérifie le rôle de l'utilisateur côté serveur. Les contrôles de rôle dans l'application ne servent qu'au confort d'affichage. Ils ne constituent pas une sécurité.

Le RecordID est attribué par l'application au moment de la création, sous la forme PR-AAAA-NNNN où NNNN est l'identifiant SharePoint de l'élément. Il est unique, immuable et sans risque de doublon lorsque deux utilisateurs créent un dossier en même temps, ce qu'un compteur géré par un flux ne garantit pas sans verrou. Conséquence à accepter : la numérotation ne repart pas à 0001 chaque année. Si Legal exige une remise à zéro annuelle, il faut un compteur dans Procurement Settings et un flux F1 avec une concurrence limitée à 1. Le flux F1 reste prévu comme filet de sécurité pour attribuer le RecordID s'il manque.

Les approbations sont saisies dans l'application, sur la liste Procurement Approvals, et non avec l'action « Démarrer et attendre une approbation ». Cette action expire au bout de 30 jours, ne gère pas proprement les versions et masque les décisions dans un historique difficile à auditer. Ici, chaque décision est une ligne horodatée, rattachée à la version du dossier, conformément aux points 7.5 et 9.3.

Le PDF est produit à partir d'un gabarit HTML converti par l'action OneDrive « Convertir un fichier ». Le gabarit Word aurait nécessité le connecteur Premium « Word Online (Business) », et il gère mal le tableau des décisions, dont le nombre de lignes varie. Avec ce choix, toute la solution fonctionne avec des connecteurs Standard, couverts par les licences Microsoft 365, sans licence Power Apps Premium.

Chaque resoumission crée une nouvelle version du dossier et un jeu complet de nouvelles approbations. Les décisions des versions précédentes sont conservées et ne sont jamais écrasées. C'est le comportement le plus prudent tant que la matrice des modifications matérielles (point 16.2) n'est pas validée. Lorsqu'elle le sera, elle s'implémentera dans le flux F2 sans changer le modèle de données.

Le cycle de vie du cahier ne contient pas de statut « Rejected », alors que l'action Reject existe. En attendant une décision, un rejet fait passer le dossier en Cancelled, et l'historique enregistre un événement « Rejected » avec son motif. Je recommande d'ajouter le statut Rejected au choix Status : un rejet et une annulation par le demandeur n'ont pas la même portée dans une piste d'audit.

Dans la bibliothèque, les colonnes s'appellent DocVersion et DocStatus, et non Version et Status. « Version » est un nom de champ système dans une bibliothèque SharePoint, et l'utiliser crée des confusions dans Power Automate.

Colonnes ajoutées à Procurement Records : RecordVersion, LastStep, AmendmentPending, AmendmentReason, PdfRequested, PdfReason. Le cahier demande de reprendre « la dernière étape enregistrée » et de versionner le dossier, mais le schéma de l'annexe A ne comporte aucune colonne pour cela. Le point 9 autorise les ajouts documentés. Celui-ci est documenté dans le script.

## Hypothèses à faire valider par Legal et Finance

Les règles suivantes sont paramétrables ou isolées dans une seule formule. Elles doivent être confrontées au prototype HTML V3.2 FINAL R4, que je n'ai pas eu entre les mains.

1. Seuils : un montant de 25 000,00 EUR exactement relève du niveau 1, et 25 000,01 EUR du niveau 2. Le cahier écrit « 25,001 », ce qui laisse un vide pour les montants avec centimes. Les bornes sont stockées dans Procurement Config sous la forme « strictement supérieur à » et « inférieur ou égal à ».
2. Alerte de proximité d'un seuil : elle s'affiche lorsque le total atteint 90 % du plafond du niveau courant (paramètre NearThresholdPercent = 10).
3. Legal Mandatory vaut Oui si le niveau est supérieur ou égal à 3 (paramètre LegalMandatory.MinLevel) ou si l'un des indicateurs suivants est coché : Related Party, Personal Data/NDA, IP/Research/Sponsorship, Liability/Regulatory, Non-approved Law/Forum, Conflict.
4. Risk Profile vaut High si Conflict, Related Party ou Critical Dependency est coché, ou si au moins trois risques sont cochés. Il vaut Medium si un ou deux risques sont cochés, et Low sinon.
5. Due Diligence Tier vaut High si le profil de risque est High ou si le niveau est 4, Medium si le profil est Medium ou si le niveau est 3, et Low sinon.
6. Séquence d'approbation : Finance, et Legal si Legal Mandatory, en parallèle (séquence 1), puis Business Approver (séquence 2). La signature n'est pas une approbation. Elle est confirmée séparément par la Signature Authority au passage en Contract Signed, conformément au principe de séparation du point 2.
7. Le Business Approver doit être une personne différente du Project Owner. Le cahier ne le dit pas explicitement, mais c'est la conséquence directe de la séparation des fonctions qu'il pose.
8. Le Total Expected Commitment doit être strictement positif pour soumettre.

## Décisions ouvertes qui bloquent la mise en production

La première décision ouverte, la sécurité par dossier, conditionne le flux F1. L'option A donne à tous les membres d'EFC-Procurement-Users la lecture de tous les dossiers, et seule la modification est verrouillée après la soumission. L'option B donne à chaque dossier, dès sa création, des permissions propres : ses owners, Legal, Finance, Auditors et Administrators. Compte tenu des données de due diligence et de conflits d'intérêts (point 13), je recommande l'option B. Sa limite technique (environ 50 000 permissions uniques par liste, 5 000 recommandées) n'est pas un sujet à l'échelle des achats d'EFC. Le guide des flux décrit les deux options.

Les autres décisions du point 16.2 n'empêchent pas de construire, car elles sont isolées dans Procurement Config, Procurement Settings ou le flux F2.
