# Guide de l’utilisateur de Quilland

[English](user-guide.md) · Français

Quilland est un espace d’écriture pour macOS. Un livre est un dossier de fichiers simples sur votre disque : le texte en Markdown, tout le reste en JSON. Rien n’est envoyé ailleurs. Les assistants IA, facultatifs, utilisent un modèle qui tourne sur votre propre ordinateur, grâce à [LM Studio](https://lmstudio.ai).

Les noms de menus et de boutons cités ici sont ceux de l’interface en français (*Réglages ▸ Général ▸ Langue de l’interface*).

Sommaire

1. [Premiers pas](#1-premiers-pas)
2. [La fenêtre](#2-la-fenêtre)
3. [Écrire](#3-écrire)
4. [Structure, parties, chapitres, scènes](#4-structure-parties-chapitres-scènes)
5. [Personnages, Monde, Événements et relations](#5-personnages-monde-événements-documentation-et-relations)
6. [Le Plan](#6-le-plan)
7. [Recherche, remplacement, relecture, fils perdus](#7-recherche-remplacement-relecture-fils-perdus)
8. [Les assistants IA](#8-les-assistants-ia)
9. [Instantanés](#9-instantanés)
10. [Import et export](#10-import-et-export)
11. [Réglages](#11-réglages)
12. [Raccourcis clavier](#12-raccourcis-clavier)
13. [Vos fichiers](#13-vos-fichiers)
14. [Dépannage](#14-dépannage)

---

## 1. Premiers pas

**Construire et ouvrir l’application.** Voir le [README](../README.md) : `./make-app.sh` produit `Quilland.app`, que l’on ouvre comme n’importe quelle application du Mac.

**Un nouveau livre.** *Fichier ▸ Nouveau livre…* demande un titre, un auteur, la langue du livre (anglais par défaut, mais aussi russe et français) et un dossier. Vous pouvez commencer par le texte ou par le plan. Le livre apparaît sous forme de dossier : vous pouvez le placer sous Git, le copier, ou le rouvrir plus tard avec *Fichier ▸ Ouvrir un livre…* (⌘O) ou *Ouvrir récent*.

**Un manuscrit existant.** *Fichier ▸ Importer…* (⇧⌘I) lit un fichier Markdown, texte brut ou HTML et propose de le découper en chapitres et en scènes. Voir [Import et export](#10-import-et-export). Gardez votre fichier d’origine : l’import en fait une copie.

**Sauvegardez d’abord.** Quilland est en cours de construction. En plus des [instantanés](#9-instantanés) automatiques, gardez votre propre copie de tout ce qui compte pour vous.

## 2. La fenêtre

Le menu Présentation (⌘1–⌘9 et ⌘0) choisit ce que montre la zone principale.

**Vues d’écriture**

| Vue | Touche | Description |
| --- | --- | --- |
| Panneaux | ⌘1 | La disposition classique : l’arborescence de la structure à gauche, une scène au milieu, un panneau à onglets à droite. |
| Livre | ⌘2 | Les scènes les unes après les autres dans un seul défilement, comme le manuscrit. Un bandeau fin entre les scènes indique le titre, le statut et le nombre de caractères. Chaque scène reste son propre fichier. |
| Comparer | ⌘3 | Deux vues Livre côte à côte, toutes deux modifiables. On peut ouvrir la même scène dans les deux : c’est un seul texte avec un seul historique d’annulation. La recherche suit le côté où se trouve votre curseur : un résultat ne fait défiler que ce côté, et « Cette scène », « Chapitre » et « Partie » partent de sa scène. |

**Vues en pleine fenêtre**

| Vue | Touche | Description |
| --- | --- | --- |
| Plan détaillé | ⌘4 | La structure à gauche, les détails de la section choisie (synopsis, note, statut) à droite. |
| Plan | ⌘5 | Une toile de cartes sur des lignes narratives. |
| Personnages | ⌘6 | Les fiches des personnages et les relations entre eux. |
| Monde | ⌘7 | Mondes et lieux sous forme d’arbre. |
| Événements | ⌘8 | Les événements de l’histoire. |
| Documentation | ⌘9 | Votre matériel de référence : notes, sources et fichiers. |
| Rappels | ⌘0 | Une liste de choses à faire pour le livre. |

**Autour du texte**

- **Le panneau de droite** a les onglets *Section*, *Personnages*, *Monde*, *Événements*, *Documentation* et *Discussion*. Il suit le curseur après un court délai ; cochez *Épingler* pour le garder sur un élément. Affichez-le ou masquez-le avec ⌥⌘R. Un personnage ou un lieu est « dans » la scène quand son nom est dans le texte, ou que la scène figure sur sa fiche (une ligne saisie pour elle ou, pour un personnage, son point de vue) ; le panneau et les fiches suivent la même règle, si bien qu’un narrateur jamais nommé apparaît dans les scènes auxquelles vous l’avez lié. Pour un personnage ou un lieu qui n’est pas dans la scène, le bouton *Ajouter à cette scène* (sous la liste ; activez *Tous* pour voir tout le monde) le lie à la main, et *Retirer de cette scène* enlève un tel lien. **Depuis le texte :** sélectionnez un nom (quelques mots) et faites un clic droit : *Créer un personnage à partir de…* et *Créer un lieu à partir de…* créent la fiche portant ce nom et lient la scène, et *Ajouter … comme nom de* donne une fiche existante un nom de plus (un surnom, une autre forme), que la reconnaissance connaît ensuite.
- **Le panneau du bas** contient *Recherche*, *Remplacer*, *Relecture*, *Fils perdus* et *Suggestions*. Il s’ouvre depuis les commandes qui l’utilisent.
- **La barre d’état** indique le nombre de caractères de la scène où se trouve le curseur, celui du livre et la variation du jour, la langue de saisie, et « Enregistré ».
- **Le mode concentration** (⌃⌘↩, dans la vue Livre) masque tout sauf le texte et garde la ligne que vous tapez au milieu de l’écran.
- **Le défilement machine à écrire** (⌥⌘T) fait de même dans les vues ordinaires.
- **Aller à la scène…** (⌘J) trouve une scène par son nom : une liste s’ouvre, tapez pour filtrer, les flèches et Retour choisissent, Échap ferme. Elle fonctionne dans toutes les vues ; dans Livre et Comparer, la liste s’ouvre sous la barre de chemin, et dans Comparer le côté où se trouve votre curseur change pendant que l’autre reste. Depuis les autres vues, elle s’ouvre en haut de la fenêtre et vous mène à la scène dans le texte. Un lien vers une scène depuis une vue de fiches arrive du côté de Comparer où vous étiez en dernier.
- **Précédent** (⌘[) et **Suivant** (⌘]) du menu Présentation reviennent aux vues où vous êtes passé et avancent de nouveau, comme dans un navigateur. Chaque changement de vue compte, que vous ayez suivi un lien (par exemple d’un lieu vers une scène), appuyé sur ⌘1–⌘0 ou sur Échap. Précédent revient à la même fiche (le personnage, le lieu, l’événement, le document ou la section choisis) et, dans les vues d’écriture, à la même scène et au même curseur. Un nouveau changement de vue supprime le chemin vers l’avant. La barre d’état montre le parcours à son extrémité droite, sous la forme `Personnages ‹ ● › Événements` : la vue où Précédent mènerait, un point pour la vue où vous êtes, et la vue où Suivant mènerait.

Faire glisser les bordures entre les panneaux change leur taille ; Quilland s’en souvient.

## 3. Écrire

L’éditeur montre votre texte tel qu’il apparaîtra. Le fichier est en Markdown, mais vous ne tapez pas de symboles Markdown : les titres, le gras, l’italique et les blocs détachés s’affichent mis en forme.

Il n’y a pas de barre d’outils de mise en forme. Utilisez le clavier ou le menu **Format** :

| Quoi | Touche |
| --- | --- |
| Gras | ⌘B |
| Italique | ⌘I |
| Titre 1, 2, 3 | ⌥⌘1, ⌥⌘2, ⌥⌘3 |
| Corps de texte | ⌥⌘0 |
| Bloc détaché (une citation, une lettre) | ⌘' |
| Séparation de scène | ⇧⌘↩ |
| Note de bas de page… | ⌃⌘N |

**Corrections de frappe.** Pour le russe, l’anglais et le français (les livres français reçoivent des guillemets « »), Quilland peut remplacer des caractères pendant que vous écrivez : guillemets, tirets de dialogue, etc. Les points de suspension restent trois points. Chaque correction se règle dans *Réglages ▸ Écriture*.

**Une pause.** Une ligne vide saisie entre deux paragraphes (une pause après une épigraphe, par exemple) est conservée : elle est enregistrée dans le fichier comme un paragraphe `&nbsp;` et se retrouve à l’ouverture du livre. Une ligne vide au tout début ou à la toute fin d’une scène n’est pas conservée. Les lignes vides ne sont pas comptées comme du texte et apparaissent comme un blanc à l’export.

**Orthographe.** Le correcteur du système souligne les fautes. Faites un clic droit sur un mot pour voir les corrections. *Ajouter au dictionnaire* dans le panneau de relecture apprend un mot au livre seul, tout comme *Apprendre l’orthographe* dans le menu contextuel d’un mot. Les mots sont listés (et peuvent être retirés) dans *Réglages du livre ▸ Dictionnaire* et conservés dans `dictionary.json`. Les mots qu’une version antérieure de Quilland a appris au système lui-même (par *Apprendre l’orthographe*) sont dans le dictionnaire du système, que macOS ne laisse pas lire à une application : ajoutez-les de nouveau ici si vous voulez qu’ils suivent le livre.

**Le menu du clic droit** est court : Couper, Copier, Coller, Coller et adapter le style, Orthographe et grammaire, et le sous-menu IA. Le reste du menu de texte du système (polices, substitutions, voix, etc.) est volontairement omis.

**Taille du texte du livre.** *Présentation ▸ Texte du livre plus grand / Texte du livre plus petit / Taille habituelle du texte du livre* (⌥⌘+, ⌥⌘−, ⌥⌘0) changent la taille du texte du livre. La police, l’interligne et la largeur de lecture sont dans *Réglages ▸ Apparence*. Ces réglages ne changent que le texte du livre, pas les libellés de l’application.

**Annuler et rétablir** (⌘Z, ⇧⌘Z) fonctionnent dans le texte. Les changements de structure (déplacer ou supprimer des sections) ont leur propre annulation, signalée par un bandeau au-dessus de l’arborescence.

## 4. Structure, parties, chapitres, scènes

Un livre se compose de **parties** (facultatives), de **chapitres** et de **scènes**. La scène est l’unité dans laquelle on écrit : chaque scène est son propre fichier. L’arborescence à gauche (vue Panneaux) ou le Plan détaillé montre la structure. La flèche à côté du « + » sous l’arborescence replie toutes les parties et tous les chapitres, ou les déplie à nouveau.

Le menu **Section** fait le travail. Il ne propose que ce qui est possible à ce moment : par exemple, *Monter* est grisé pour la première scène du livre ou le premier chapitre, *Fusionner avec la scène suivante* pour la dernière scène, et *Statut* quand un chapitre est choisi.



- *Nouvelle scène* (⌘N), *Nouvelle scène avant*, *Nouveau chapitre* (⇧⌘N), *Nouvelle partie* (⌥⇧⌘N)
- *Renommer*, et *Statut* (par exemple brouillon, terminé) ; le point coloré dans l’arborescence indique le statut
- *Monter / Descendre* (⌥⌘↑, ⌥⌘↓), ou glisser-déposer dans l’arborescence ; une scène au bord de son chapitre passe dans le chapitre voisin (à la fin du précédent, ou au début du suivant)
- *Couper la scène ici* (⌥⌘↩) coupe à l’endroit du curseur ; *Fusionner avec la scène suivante / précédente* ; *Fusionner les scènes choisies* réunit les scènes sélectionnées (la fusion demande toujours confirmation et ne se fait qu’au sein d’un chapitre : déplacez d’abord la scène dans l’autre chapitre si nécessaire)
- *Regrouper dans une nouvelle partie…* et *Dégrouper la partie…*
- *Supprimer…* demande toujours confirmation

Chaque section a aussi un **synopsis** et une **note**, modifiables dans l’onglet *Section* du panneau de droite ou dans le Plan détaillé. Le synopsis peut être écrit par l’IA (voir plus bas).

## 5. Personnages, Monde, Événements, Documentation et relations

Ces vues conservent des fiches : un nom, des alias, une description, des notes et les champs du type. Quilland connaît les noms et les alias ; le panneau de droite montre donc quels personnages et quels lieux apparaissent dans la scène que vous écrivez.

- **Personnages** (⌘6) : la liste à gauche, la fiche à droite. Un personnage a une liste de scènes où il apparaît et une liste de relations. La liste contient les scènes qui nomment le personnage, celles dont il est le point de vue, et celles que vous ajoutez à la main avec *Ajouter une scène…* (pour une scène où le nom n’est pas écrit) ; saisissez ce que fait le personnage, et *Supprimer le lien* enlève la ligne et le point de vue.
- **Les relations** relient deux personnages (par exemple « sœur », « ennemi ») et peuvent s’ouvrir comme une fiche à part.
- **Monde** (⌘7) : mondes et lieux sous forme d’arbre, avec une fiche pour chacun. Un lieu liste les scènes qui le nomment ; *Ajouter une scène…* en lie une où le nom n’est pas écrit, vous saisissez ce qui s’y passe, et *Supprimer le lien* retire la ligne.
- **Événements** (⌘8) : ce qui se passe dans l’histoire, avec les scènes et les personnages concernés. La liste est groupée sous un titre pour chaque scène (la première scène à laquelle un événement est lié), dans l’ordre du livre, les événements sans scène à la fin. Deux événements d’une même scène se mettent en ordre **à la main** : faites glisser l’un vers le haut ou le bas dans son groupe, ou utilisez *Monter* et *Descendre* du menu contextuel, ou ⌥⌘↑ et ⌥⌘↓. Un événement ne quitte pas sa scène en étant déplacé : sa scène est décidée par ses liens. L’ordre est gardé dans les fichiers des événements (un nombre `order`, donné seulement aux événements de la scène que vous réordonnez), et le classement est désactivé pendant que la liste est filtrée.
- **Documentation** (⌘9) : le matériel rassemblé pour le livre, par exemple l’histoire de l’enseignement musical aux États-Unis. Un *document* a un titre, une *source* (un livre, un article, une adresse), votre propre texte et, si vous le souhaitez, un fichier. Chaque élément est facultatif : un document peut être seulement du texte, seulement un fichier, ou les deux. Un fichier est soit *copié dans le livre* (il voyage avec le livre et son historique Git ; Quilland demande d’abord au-delà de 20 Mo), soit seulement *lié* (il reste où il est, hors du livre ; le lien vaut pour ce Mac, et si le fichier bouge, Quilland l’indique comme introuvable sans l’oublier). *Ouvrir* et *Afficher dans le Finder* agissent sur le fichier. Un document peut être lié au livre entier, à une scène, à un personnage, à un lieu ou à un événement, avec une remarque pour chacun ; un double-clic sur un lien y mène. L’onglet *Documentation* du panneau de droite liste les documents liés à la scène où vous êtes et permet de lire et de modifier leur texte. Pour ajouter une note sans quitter le texte, saisissez un titre dans le champ en haut de l’onglet et appuyez sur Retour : le document est lié à la scène où vous êtes, et le curseur passe dans son texte. *À partir d’un fichier…* crée un document à partir d’un fichier (copié dans le livre, ou seulement lié au-delà de 20 Mo). Le filtre de la liste cherche dans les titres, les sources, les remarques et les textes. Un document supprimé va dans le dossier corbeille.

**La même personne sur deux fiches.** Si l’IA (ou vous) a créé deux fiches pour une même personne, faites un clic droit sur celle à retirer, ou appuyez sur *Fusionner avec…* sur sa fiche, puis choisissez le personnage à garder. Le nom et les alias de la fiche retirée deviennent des alias du personnage gardé, si bien que l’IA et la reconnaissance dans le texte reconnaissent ce nom désormais ; son profil, ses notes, ses scènes et ses relations s’ajoutent à ceux du personnage gardé, et la fiche va dans le dossier corbeille du livre. Un instantané est pris d’abord, et le bouton Annuler du bandeau (ou ⌘Z) annule la fusion.

**Lieux et mondes.** Dans la vue Monde, faites un clic droit sur un lieu ou un monde (ou utilisez les boutons de sa fiche) pour des outils du même genre : *Fusionner avec…* réunit deux lieux, ou deux mondes, en un seul (le nom du retiré devient un alias, ses lieux et ses liens passent à l’autre). Si l’IA a pris un monde entier pour un lieu, choisissez *Transformer en monde…* : le lieu devient un monde à part et les lieux qu’il contient sont au premier niveau de ce monde. L’inverse, *Transformer en lieu…*, place un monde dans un autre monde, ou dans l’un de ses lieux. Chacune est un changement unique avec un instantané avant et après, et Annuler l’annule.

Les noms sont repérés par des règles qui gèrent les terminaisons russes (« Анне » est reconnu comme « Анна »), si bien qu’une liste d’alias suffit généralement.

**Rappels (⌘0).** Une liste de choses à vérifier, corriger ou faire pour le livre. Saisissez-en une en bas et appuyez sur Retour (un rappel peut avoir plusieurs lignes : Maj-Retour passe à la ligne ; les lignes longues passent à la ligne d’elles-mêmes) ; cochez la case quand c’est fait (les rappels faits passent sous un titre « Fait » et peuvent revenir) ; cliquez sur le texte pour le modifier ; ✕ le supprime, et le bandeau qui suit propose d’annuler. La liste est enregistrée dans `reminders.json`, dans le dossier du livre, et suit donc le livre avec Git. À l’ouverture d’un livre qui a des rappels en attente, une fenêtre les liste ; cochez-y ceux que vous avez faits, puis fermez-la. *Réglages ▸ Général* peut désactiver cette fenêtre.

## 6. Le Plan

Le Plan (⌘5) est une toile. Une **carte** est l’idée de quelque chose qui va se passer. Les cartes se placent sur des **lignes narratives**, des couloirs horizontaux qui ont un nom et une couleur. Faites glisser une carte le long d’une ligne ou d’une ligne à l’autre. Les événements déjà écrits apparaissent sur la même toile en gris : on voit ce qui est fait et ce qui reste prévu.

- **Pas de chevauchement.** Deux cartes, ou deux événements, ne se tiennent jamais au même endroit sur une ligne : celle qu’on dépose (ou qu’on met sur le plan) là où une autre de son genre se trouve passe à une nouvelle rangée juste après, sans que rien d’autre bouge. Des éléments de lignes différentes peuvent être au même niveau, ce qui veut dire au même moment, et une carte peut recouvrir un événement (ce sont deux couches). Une carte flottante déposée sur une autre carte flottante est descendue vers une place libre.
- **Couleurs des cartes et des événements.** Cliquez sur une carte ou un événement, et ⌘-cliquez (ou Maj-cliquez) sur d’autres pour en choisir plusieurs. Un élément choisi est teinté, entouré d’un trait épais et marqué d’une coche, et la barre d’outils indique combien sont choisis ; un clic sur la toile vide annule le choix. Faites un clic droit sur l’un des éléments choisis et choisissez *Couleur ▸* une couleur, montrée par un petit carré à côté de son nom : toutes les cartes et tous les événements choisis la reçoivent d’un coup, et un seul Annuler la retire. *Aucune couleur* (proposé quand un événement est parmi eux) rend à un événement son aspect neutre. La couleur d’une carte peut aussi se régler dans sa fenêtre (double-clic). La couleur d’un événement est conservée dans le fichier de l’événement.
- Double-cliquez sur le titre d’une ligne pour le modifier, ou faites un clic droit pour *Modifier…*, la couleur, le déplacement et la suppression.
- *Afficher à partir de* limite le plan à une partie du livre.
- ⌘+ et ⌘− zooment la toile, ⇧⌘0 l’ajuste à la fenêtre.

## 7. Recherche, remplacement, relecture, fils perdus

Les quatre se trouvent dans le panneau du bas.

**Recherche** (⌘F) trouve du texte au fil de la frappe, dans les scènes et, si vous le choisissez, dans les notes et les synopsis. ⌘G et ⇧⌘G passent à l’occurrence suivante et à la précédente.

**Remplacer** (⌥⌘F) est volontairement prudent. Vous choisissez à chaque fois où chercher. Les résultats sont décochés tant que vous ne les cochez pas. Entrée ne remplace jamais. Chaque remplacement affiche un avertissement avec *Annuler* par défaut, prend d’abord un instantané et peut être annulé. Un remplacement vide supprime les occurrences, et le bouton le dit.

**Relecture** (⌥⌘P) liste les problèmes d’une scène, d’un chapitre ou du livre :

- *Règles* : la typographie, comme les tirets, les espaces et les guillemets
- *Orthographe*, avec le dictionnaire du système et le dictionnaire propre au livre (les noms de personnages ne sont pas signalés)
- *Vérifier la grammaire* utilise l’IA pour proposer des corrections sous forme de paire avant/après

Choisissez un résultat pour voir ce que fait la règle. *Accepter* modifie le texte (⌘Z l’annule), *Ignorer* masque le résultat définitivement, *Ajouter au dictionnaire* apprend un mot, et *Tout accepter dans cette scène* applique toute la liste de cette scène. *Réafficher les ignorés* ramène les résultats masqués. Entrée n’accepte jamais un résultat.

**Fils perdus** (⌥⌘L) liste les problèmes du livre lui-même : fichiers endommagés ou manquants et enregistrements qui ne pointent vers rien, pour que vous les voyiez et décidiez quoi faire.

## 8. Les assistants IA

L’IA est facultative. Tout le reste fonctionne sans elle. Elle utilise un modèle qui tourne sur votre ordinateur ; rien n’en sort.

**Mise en place**

1. Installez [LM Studio](https://lmstudio.ai) et chargez un modèle. Quilland a été réglé avec `qwen3-14b` ; d’autres peuvent donner de moins bons résultats.
2. Démarrez le serveur local de LM Studio (l’adresse par défaut est `http://localhost:1234`).
3. Dans Quilland, ouvrez *Réglages ▸ IA* et lancez le test de connexion. Il indique le nom du modèle et le nombre de tokens qu’il lit d’un coup.

Le menu IA affiche l’état de la connexion en haut. Tout ce que propose le modèle est une **suggestion**. Rien n’est enregistré avant que vous l’acceptiez.

**Ce qu’elle peut faire**

| Action | Où | Ce qu’elle fait |
| --- | --- | --- |
| Continuer l’écriture | menu IA, ⌃⌘G ; clic droit ▸ IA | Écrit le paragraphe suivant en texte estompé. **Tab** l’accepte, **Échap** l’abandonne. *…avec une direction* (⇧⌃⌘G) permet d’indiquer où aller. |
| Écrire un synopsis | menu IA, ⌃⌘Y ; le bouton *Écrire avec l’IA* de l’onglet Section | Écrit un court résumé de la scène dans un synopsis vide. |
| Recueillir depuis le livre… | menu IA, ⌥⌘K | Lit les scènes et propose des personnages, des lieux, des événements et des relations, avec les citations dont ils proviennent. La fenêtre s’ouvre sur la scène courante (le livre entier si aucune n’est courante) ; choisissez le chapitre, la partie ou le livre entier pour lire davantage. Chaque lancement lit toutes les scènes de la portée choisie et repart d’une liste de suggestions vide : ce qu’un lancement précédent avait trouvé, et ce qui attendait encore, est retiré. |
| Vérifier la cohérence… | menu IA, ⌥⌘Y ; clic droit ▸ IA | Cherche des contradictions entre les scènes (couleur des yeux, âge, qui sait quoi). Chaque résultat cite les deux passages. |
| Vérifier la grammaire | menu IA, ⌥⇧⌘G ; le panneau Relecture | Propose des corrections de grammaire. |
| Discussion | l’onglet *Discussion* du panneau de droite | Posez des questions sur votre livre. Joignez la scène, les personnages, les lieux ou le plan avec **@**. Le modèle ne fait que répondre ; il ne change rien. |
| Actions | menu IA ▸ Actions | Vos propres prompts enregistrés. |

Toutes les propositions vont dans l’onglet **Suggestions** du panneau du bas (⌥⇧⌘J). Cochez ce que vous voulez et acceptez-le. Les citations sont vérifiées par rapport au texte : une citation inventée par le modèle est écartée.

**Vos propres prompts.** Dans l’onglet Discussion, un prompt peut être enregistré avec *Enregistrer le prompt comme action…*. Les actions enregistrées apparaissent dans le menu IA et dans *Réglages ▸ Prompts de l’IA* à côté de celles qui sont intégrées. Les prompts intégrés portent la mention « Système » ; les vôtres n’en ont pas et peuvent être renommés, modifiés et supprimés. Vous pouvez aussi y changer la formulation des prompts intégrés. Le paramètre `{language}` est remplacé par la langue du livre.

Une tâche longue (recueillir depuis tout le livre, vérifier la cohérence) affiche une barre de progression et peut être arrêtée.

## 9. Instantanés

Un instantané est une copie de tout le livre à un moment donné. Quilland en prend un automatiquement toutes les 15 minutes pendant que vous écrivez (l’intervalle se change dans *Réglages ▸ Général*) et avant les opérations risquées comme Remplacer.

- *Fichier ▸ Enregistrer un instantané* (⌘S) et *Enregistrer un instantané nommé…* (⌥⌘S) créent les vôtres.
- *Fichier ▸ Instantanés…* (⇧⌘S) les liste et en restaure un.
- Les instantanés sont économiques : ils partagent sur le disque les fichiers inchangés, et les plus anciens sont éclaircis.

## 10. Import et export

**Importer** (*Fichier ▸ Importer…*, ⇧⌘I) lit un fichier Markdown, texte brut ou HTML. Choisissez l’encodage si le texte semble faux. La fenêtre liste les sortes de lignes qui ressemblent à des titres (titres de niveau 1 à 6, « Chapitre N », « Prologue », nombres, courtes lignes en capitales…) ; pour chacune, *Devient* indique ce qu’elle produit : une partie, un chapitre, une scène ou « pas un titre ». Vérifiez l’aperçu de l’arborescence avant de confirmer. On peut importer dans un nouveau livre ou à la fin du livre ouvert. L’import peut être annulé.

Pas encore disponible : importer tout un dossier de fichiers Markdown, et importer au milieu d’un livre.

**Exporter** (*Fichier ▸ Exporter…*, ⌘E) écrit en DOCX, PDF, FB2, EPUB, HTML ou texte brut (toujours en UTF-8). La fenêtre propose des profils, une liste des sections à inclure et un aperçu quand Quilland dessine lui-même le fichier. Les fichiers DOCX ont été vérifiés dans Pages, pas dans Microsoft Word.

## 11. Réglages

*Quilland ▸ Réglages…* (⌘,) comporte ces sections : Général, Apparence, Écriture, Panneaux, IA, Prompts de l’IA et Raccourcis. Le champ de recherche en haut trouve un réglage par son nom.

- **Général :** langue de l’interface (anglais, russe et français ; l’anglais est la langue par défaut), dossier des livres, liste des livres récents, ce qui s’ouvre au démarrage, intervalle des instantanés.
- **Apparence :** police, taille du texte, interligne, largeur de lecture d’une feuille, clair ou sombre.
- **Écriture :** corrections de frappe et orthographe.
- **Panneaux :** les onglets du panneau de droite et la vitesse à laquelle il suit le curseur.
- **IA :** l’adresse de LM Studio, le modèle et le test de connexion.
- **Prompts de l’IA :** les prompts de chaque assistant et vos actions enregistrées.
- **Raccourcis :** changer la touche de n’importe quelle commande. Sélectionnez une ligne et appuyez sur la nouvelle touche.

*Fichier ▸ Réglages du livre…* (⇧⌘,) contient ce qui appartient à un seul livre : sa langue, son titre et sa couverture, sa taille cible et son propre dictionnaire.

**Taille du livre.** Choisissez un *Type de livre* (très courte fiction, nouvelle, longue nouvelle, novella, court roman, roman, épopée) et Quilland renseigne une *Taille cible* typique pour la langue du livre, en caractères espaces compris ; vous pouvez saisir un autre nombre, et le type devient alors « Taille personnalisée ». Sous la cible, vous la voyez en mots, et pour les livres russes et ukrainiens en feuillets d’auteur (1 feuillet = 40 000 caractères espaces compris). *Taille actuelle* montre la taille du livre à cet instant (caractères, mots, feuillets) et le chemin parcouru, avec une barre ; la barre d’état affiche la même chose : « livre 123 456 sur 540 000 (23 %) ». Changer la langue d’un livre qui a un type donne la cible du type dans la nouvelle langue.

## 12. Raccourcis clavier

Ce sont les raccourcis par défaut. Chacun peut être changé dans *Réglages ▸ Raccourcis*.

**Fichiers**

| Touche | Commande |
| --- | --- |
| ⌘N | Nouveau livre (seulement quand aucun livre n’est ouvert ; avec un livre ouvert, ⌘N est Nouvelle scène) |
| ⌘O | Ouvrir un livre |
| ⌘S | Enregistrer un instantané |
| ⌥⌘S | Enregistrer un instantané nommé |
| ⇧⌘S | Instantanés |
| ⇧⌘I | Importer |
| ⌘E | Exporter |

**Présentation**

| Touche | Commande |
| --- | --- |
| ⌘1 ⌘2 ⌘3 | Panneaux, Livre, Comparer |
| ⌘4 ⌘5 ⌘6 ⌘7 ⌘8 ⌘9 ⌘0 | Plan détaillé, Plan, Personnages, Monde, Événements, Documentation, Rappels |
| ⌘J | Aller à la scène |
| ⌘[ ⌘] | Précédent, Suivant entre les vues |
| ⌥⌘R | Afficher ou masquer le panneau de droite |
| ⌃⌘↩ | Mode concentration |
| ⌥⌘T | Défilement machine à écrire |
| ⌘+ ⌘− ⇧⌘0 | Zoom du Plan, ajustement à la fenêtre |
| ⌥⌘+ ⌥⌘− ⌥⌘0 | Texte du livre plus grand, plus petit, taille habituelle |

**Recherche et vérification**

| Touche | Commande |
| --- | --- |
| ⌘F, ⌥⌘F | Rechercher, Remplacer |
| ⌘G, ⇧⌘G | Occurrence suivante, précédente |
| ⌥⌘P | Relire |
| ⌥⌘L | Fils perdus |

**Écriture**

| Touche | Commande |
| --- | --- |
| ⌘B, ⌘I | Gras, italique |
| ⌥⌘1 ⌥⌘2 ⌥⌘3 ⌥⌘0 | Titres 1 à 3, corps de texte |
| ⌘' | Bloc détaché |
| ⇧⌘↩ | Séparation de scène |
| ⌃⌘N | Note de bas de page |
| ⌘N, ⇧⌘N, ⌥⇧⌘N | Nouvelle scène (avec un livre ouvert), nouveau chapitre, nouvelle partie |
| ⌥⌘↩ | Couper la scène ici |
| ⌥⌘↑, ⌥⌘↓ | Monter, descendre la section |

**IA**

| Touche | Commande |
| --- | --- |
| ⌃⌘G | Continuer l’écriture (Tab accepte, Échap abandonne) |
| ⇧⌃⌘G | Continuer l’écriture avec une direction |
| ⌃⌘Y | Écrire un synopsis |
| ⌥⌘K | Recueillir depuis le livre |
| ⌥⇧⌘G | Vérifier la grammaire |
| ⌥⌘Y | Vérifier la cohérence |
| ⌥⇧⌘J | Afficher les suggestions |

## 13. Vos fichiers

Un livre est un dossier. Vous pouvez l’ouvrir dans le Finder, le placer sous Git et le copier. En résumé :

- `book.json` : le titre, la langue et les réglages du livre. `reminders.json` : les rappels.
- `manuscript/` : la structure. Chaque scène est un fichier `.md` (le texte) avec un fichier `.json` à côté (statut, synopsis, note) ; les chapitres et les parties sont des dossiers.
- Des dossiers pour les personnages, le monde, les événements, les relations et le plan contiennent un fichier JSON par fiche. `research/` contient les documents : un fichier `.json`, un fichier `.md` pour le texte et un dossier `<id>.file/` pour un fichier copié.
- Les instantanés et le cache de recherche sont conservés à côté du livre et peuvent être supprimés sans risque ; Quilland reconstruit le cache.

Les réglages propres à Quilland se trouvent dans votre dossier utilisateur : les préférences, `prompts.json` (prompts modifiés) et `actions.json` (actions enregistrées). Vous pouvez les sauvegarder ou les copier sur un autre Mac.

Ne modifiez les fichiers en dehors de Quilland que lorsque l’application est fermée, et gardez une copie. Si un autre programme modifie une scène pendant que Quilland l’a ouverte (un checkout Git, un dossier synchronisé), Quilland garde cette version dans le dossier corbeille et le signale avant d’enregistrer la sienne, pour que ni l’une ni l’autre ne soit perdue ; un enregistrement qui échoue s’affiche dans la barre d’état comme « Non enregistré ». Si un fichier est endommagé, *Fils perdus* le désigne.

## 14. Dépannage

**Le menu IA est grisé.** La ligne d’état en haut du menu IA en donne la raison : en général LM Studio n’est pas lancé, son serveur est arrêté ou aucun modèle n’est chargé. Corrigez cela, puis utilisez le test de connexion dans *Réglages ▸ IA*.

**Une longue tâche de l’IA semble bloquée.** Cherchez la barre de progression et la ligne d’état orange. Un modèle local peut mettre plusieurs minutes sur un long livre. Le bouton *Arrêter* met fin à la tâche et garde ce qui a été trouvé.

**Les réponses du modèle sont médiocres ou dans la mauvaise langue.** Essayez un modèle plus grand. Vérifiez la langue du livre dans *Réglages du livre* et lisez le prompt dans *Réglages ▸ Prompts de l’IA*.

**Un nom n’est pas trouvé dans une scène.** Ajoutez la forme comme alias sur la fiche.

**Quelque chose a changé alors qu’il ne fallait pas.** Ouvrez *Fichier ▸ Instantanés…* et restaurez le livre tel qu’il était avant le changement.

**L’application se comporte bizarrement après une mise à jour.** Quittez-la complètement (⌘Q), puis rouvrez-la.

Si vous trouvez un problème, signalez-le avec les étapes qui le provoquent.
