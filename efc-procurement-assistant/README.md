# EFC Procurement Assistant – kit de construction

Ce dossier traduit le cahier des charges « EFC Procurement Assistant, Draft 1.0 » en éléments directement exécutables ou copiables dans Power Platform. Il ne remplace pas la recette Legal/Finance. Les règles de calcul sont reprises du prototype V3.2 FINAL R4. Les écarts entre le prototype et les annexes sont listés à la fin de ce document.

## Contenu

1. `01-sharepoint/Provision-EFC-Procurement.ps1` : script PnP PowerShell qui crée les listes complémentaires, la bibliothèque documentaire, les listes de paramétrage, les colonnes techniques manquantes, les index et les permissions de l'option B au niveau des listes. Il ne modifie aucune colonne existante de Procurement Records.
2. `02-power-apps/GUIDE-POWER-APPS.md` : construction de la Canvas App écran par écran, avec les noms de contrôles et toutes les formules Power Fx.
3. `02-power-apps/App.Formulas.fx` : les formules nommées (calcul du total, route, risques, champs manquants) à coller dans la propriété Formulas de l'objet App.
4. `03-power-automate/GUIDE-FLOWS.md` : le flux enfant de permissions FP et les neuf flux, action par action, avec les expressions et les conditions de déclenchement.
5. `04-pdf/procurement-record-template.html` : le gabarit HTML converti en PDF par le flux de génération.
6. `05-tests/PLAN-DE-RECETTE.md` : les scénarios AT-01 à AT-14 du cahier et AT-15 à AT-20 propres à cette conception, rattachés aux composants qui les couvrent, avec les jeux de données de test.

## Ordre de construction

1. Créer les groupes Entra ID listés au point 5.1 du cahier et noter leurs identifiants (Object ID).
2. Exécuter le script SharePoint avec les six identifiants de groupes, en tant qu'administrateur de la collection de sites. Il crée les listes, pose les permissions de l'option B et renseigne Procurement Settings. Compléter ensuite AdminEmail et AppUrl.
3. Créer une Solution Power Platform « EFC Procurement Assistant » et y créer toutes les ressources suivantes, afin de pouvoir les exporter vers test et production.
4. Créer le compte de service et lui donner les droits de propriétaire du site. Construire ensuite le flux enfant FP, puis F1, F1b, F5 et F7. FP doit être testé en premier, car tous les autres flux en dépendent : créer un élément de test et appeler FP à la main, puis vérifier les autorisations de l'élément dans SharePoint.
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

## Règles reprises du prototype V3.2 FINAL R4

Les règles de calcul sont reprises à l'identique du prototype. Elles ont été comparées à leur transcription sur 200 000 cas, bornes comprises, sans écart. Ce contrôle porte sur une réécriture JavaScript des formules, et non sur Power Fx exécuté : la recette AT-04 et AT-05 reste nécessaire.

1. Niveau : aucun niveau si le total est nul. Niveau 1 jusqu'à 25 000 inclus, niveau 2 jusqu'à 50 000 inclus, niveau 3 jusqu'à 250 000 inclus, niveau 4 au-delà. Un montant de 25 000,01 relève donc du niveau 2.
2. Alerte de seuil : elle s'affiche lorsque le total dépasse 95 % d'un seuil sans l'atteindre (paramètre NearThresholdPercent = 5). Le texte est celui du prototype : la route supérieure doit être envisagée, sauf alternative documentée approuvée par Finance et Legal.
3. Routes, exigences de concurrence, autorités d'approbation et preuves attendues : textes du prototype, stockés dans Procurement Config.
4. Legal obligatoire : niveau 3 ou plus, ou related party, ou l'un des risques suivants : données personnelles, IT, IP, prix ouvert, responsabilité, droit ou for non approuvé, conflit.
5. Risk Profile : High en cas de dépendance critique, de conflit ou de related party. Medium si le niveau est 3 ou plus, ou en cas de données personnelles, d'IT ou d'IP. Low dans les autres cas, et vide tant qu'aucun niveau n'est calculé.
6. Due Diligence Tier : identique au Risk Profile.
7. Valeurs de choix (départements, types d'achat, financement, contexte, traitement de la devise) et valeurs par défaut à la création : celles du prototype. Le script signale tout écart avec les colonnes SharePoint existantes.
8. Résumés de la Policy et des Annexes 1 à 5 : textes du prototype, chargés dans Procurement Policy Links.

## Écarts entre le prototype et les annexes

En lisant le prototype à côté de ses propres résumés d'annexes, j'ai relevé quatre incohérences. Les deux premières sont corrigées dans le kit, mais isolées pour pouvoir être retirées facilement. Les deux autres restent à trancher.

1. L'Annex 3 rend la revue Legal obligatoire, quelle que soit la valeur, pour la « classification employment or individual consultant ». Le prototype ne l'applique pas, alors qu'il propose le type d'achat « Consultant or individual ». Le kit l'applique.
2. L'Annex 5 impose, pour un profil High, une « enhanced Legal/Compliance review ». Le prototype classe un dossier High dès que la case Critical est cochée, mais sans déclencher Legal. Le kit déclenche Legal dans ce cas. Ces deux ajouts se trouvent dans la seule formule nfLegalAnnexExtension (et dans la condition correspondante du flux F2). Pour revenir strictement au prototype, il suffit de la mettre à false.
3. L'Annex 5 range « material value » parmi les critères du risque Medium. Le prototype ne relève le profil à Medium qu'à partir du niveau 3. Un achat de 45 000 EUR sans autre risque reste donc Low. Le kit suit le prototype. Legal doit dire si « material value » commence au niveau 2.
4. L'Annex 5 classe High les cas « public officials », « complex ownership » et « adverse information », pour lesquels le prototype n'a aucune case à cocher. Ils ne peuvent donc pas déclencher le profil High. Si Legal le souhaite, il faut ajouter une case au Step 4 et une colonne.

Deux règles des annexes, absentes du prototype, sont ajoutées parce qu'elles s'automatisent sans interprétation :

1. Annex 3 : jusqu'à 10 000 EUR, un devis accepté suffit comme base contractuelle. Au-delà, un contrat écrit exécuté est exigé avant toute exécution ou tout paiement. La checklist et l'action Contract Signed appliquent cette règle (paramètre ContractRequired.Above).
2. Annex 2 : interdiction de l'auto-approbation. Le Business Approver doit être différent du Project Owner.

Le kit introduit aussi une règle de sa propre initiative : un dossier dont le traitement de la devise est « Finance confirmation pending » ne peut pas être soumis. Le niveau dépend d'un montant en EUR qui n'est pas encore confirmé, et les approbateurs se prononceraient sur une route peut-être fausse. Cette règle est une ligne de nfMissing et une condition de F2, faciles à retirer.

Restent hors calcul, faute de règle exploitable : l'effet du financement « Grant or donor funding » et « Public or restricted funding » (les conditions d'un bailleur imposent souvent des règles d'achat plus strictes que la Policy), l'« approbation de gouvernance » exigée pour un profil High, et la composition exacte des autorités par niveau, que le prototype décrit par des fonctions (« Relevant Director or approved equivalent ») et non par des groupes.

Les liens vers la Policy et les Annexes sont, dans le prototype, des recherches SharePoint (search.aspx?q=...). Ce ne sont pas des liens directs vers la version publiée, comme l'exige le §7.7. Ils sont repris tels quels dans Procurement Policy Links, et doivent être remplacés dès que les documents approuvés sont publiés. Les sources indiquent d'ailleurs que ces documents sont encore des drafts.

Séquence d'approbation (point non couvert par le prototype, qui se limite à une checklist déclarative) : Finance, et Legal si requis, en parallèle, puis le Business Approver. La signature est confirmée séparément au passage en Contract Signed. Le prototype rappelle d'ailleurs que « award approval remains separate from signature authority ».

## Sécurité : option B retenue

Chaque dossier n'est visible que par les personnes qui y jouent un rôle : Project Owner, Business Owner, créateur, puis, à partir de la soumission, les reviewers désignés et la Signature Authority. S'y ajoutent Legal, Finance et Auditors, en lecture, et Administrators. Un employé EFC sans rôle sur un dossier ne le voit pas, ni dans l'application ni dans SharePoint. Les membres du site Legal Department n'y ont pas accès du seul fait de leur appartenance au site.

La mise en œuvre tient en trois éléments. Le script rompt l'héritage des listes et pose les droits des groupes. Un flux enfant unique, FP, calcule les droits de chaque dossier, de son dossier documentaire et de chaque ligne d'approbation à partir de leur état, et il est le seul à toucher aux permissions. Enfin, un niveau de permission sans suppression garantit que personne, hors administrateurs, ne peut effacer un dossier, une décision ou une pièce.

Conséquences à connaître. Legal et Finance lisent tous les dossiers : c'est l'« accès large Legal » du point 16.2. Le restreindre par département ne demande de modifier que FP. Un approbateur ne peut décider qu'à son tour, et sa décision est figée dès qu'elle est traitée. Un dossier transmis à un autre Project Owner reste lisible par son créateur. Les volumes d'EFC restent très loin de la limite SharePoint d'environ 50 000 objets à permissions uniques par liste (5 000 recommandés), à raison d'un dossier, un dossier documentaire et trois à six lignes d'approbation par procurement.

## Décisions ouvertes

Les décisions du point 16.2 qui restent ouvertes n'empêchent pas de construire. Elles sont isolées dans Procurement Config, Procurement Settings, la formule nfLegalAnnexExtension, le flux F2 ou le flux FP.
