Mémoire I5
=========

Titre : Migration du système de collecte de données d'une plate-forme de surveillance de marque sur internet vers le Cloud d'Amazon

Idée de plan :

 * Présentation de l'entreprise
 * Présentation du produit existant
 * Ce qui motive cette migration
    * A court terme
    * A plus long terme
 * Présentation du Cloud d'Amazon
 * S.W.O.T.
 * Estimation des coûts – Coûts possibles chez les concurrents (OVH, Google, Azure) – Étude du marché
 * Procédure générale de migration
 * Un nouveau système de base de données – Elasticsearch
 * Architecture globale mise en place
 * Écriture d'un scheduler – Chef d'orchestre d'Amazon
 * Écriture de la tâche hadoop
 * Migration du code existant
 * Coûts observés, comparaison aux estimations
 * Force / faiblesse par rapport aux attentes
 * Bilan

#Présentation du produit existant
Keepalert est une plate-forme de surveillance de marques sur internet décomposée en 4 modules indépendants proposant différents types de protection :
Le module noms de domaine protège les marques des sites de cyber-squatting et de contrefaçon. Ce module collecte diverses données, dont:

 * Les données Whois,\footnote{
 Contraction de l'Anglais Who Is.
 Ces données sont fournies par les registres de noms de domaine, et permettent d'en récupérer les données légales et techniques comme la date du dépôt, à qui appartient le domaine, les coordonnées des entités le gérant, etc.
 }
 * Des captures d'écran des sites,
 * Des adresses I.P,
 * Le contenu HTML des pages,
 * Le module Web 2 surveille les réseaux sociaux (Facebook, Youtube, Référencement de sites dans les moteurs de recherche, …), qui reprend la plupart des données collectées dans le module Noms de domaine,
 * Le module de marquage de page, qui collecte et analyse la provenance des visiteurs sur les sites officiel de nos clients,
 * Le module de détection de contenu similaire
 
Afin de collecter toutes ces données l'architecture suivante a été imaginée : TODO

#Motivations
Cette architecture imaginée il y a de cela plus de 7 ans, bien que fonctionnelle, montre ses limites :

 * En termes de capacité de traitement, certaines études ne sont pas livrées dans des délais raisonnables, la file de traitement des serveurs de production étant constamment pleine,
 * En termes de stockage des données, la taille de la base contenant les données récoltées est trop importante pour en modifier la structure, 
   il nous est donc impossible de proposer de nouveaux indicateurs pour nous démarquer de la concurrence (stockage HTML, contenu textuel, identifiants Ad Sence),
 * La production d'études plus volumineuses nous est impossible dans des délais raisonnables, et bloque la production des autres études,
 * Le moteur de base de données utilisé ne propose pas par défaut de moteur de recherche satisfaisant, une solution annexe basée sur SOLR a due être mise en place (pour faire des recherches sur le HTML des pages récoltées),
 * Les différentes étapes de récoltes étant totalement séparées, il arrive qu'une étude reste incomplète en fin de traitement en raison de la complexité de l'architecture (notamment pour les captures d'écran).

Notre objectif à court terme est de nous affranchir ces limites. 

Cette migration doit nous permettre de fournir des résultats rapides et complets pour n'importe quelle taille d'étude. 
Nous devons également être en mesure d'exploiter cette masse de données, notamment par le biais de la recherche full-text\footnote{TODO}.

Mais cette démarche est aussi motivée par un objectif de refonte sur le long terme :

 * La mise à disposition d'une API RESTFUL pour nos clients (qui ne fait pas partie de ce mémoire),
 * L'enrichissement des études via de nouvelles données (classement du site, sauvegarde des entrées DNS MX, etc),
 * L'enrichissement des études via l'indexation du rendu du site (pour proposer par exemple une recherche par logo de marque).

Afin d'atteindre ces objectifs, une refonte du cœur de la plate-forme est nécessaire :

 *   Pour réduire au maximum les temps de traitement nécessaires pour l'étude des noms de domaines, la scalabilité horizontale doit être exploitée. 
     En effet si il est possible de paralléliser sur une même machine la collecte des données, celle-ci sera vite limitée en termes de mémoire, de CPU et de bande passante. 

     En revanche, en parallélisant ces traitements sur un cluster de calcul il est possible de s'affranchir des limites de mémoire, de CPU, et dans une moindre mesure de bande passante 
     (en fonction de la répartition des machines dans le data-center).

 *   Pour permettre l'enrichissement des données un nouveau moteur de stockage doit être envisagé. 

     MySQL utilisé actuellement montre ses limites en termes de recherche, mais aussi de stockage : le modèle de donné étant figé il n'est pas facile à faire évoluer.
     En effet pour ajouter un champ dans une table MySQL doit dupliquer la table pour en migrer les données. Ainsi l'espace nécessaire pour ajouter un champ à une table de 100Go est de 200Go.

     Pour de petites quantités de données cela ne pose aucun soucis. 

     Dans notre cas nous voulons stocker des données de plus en plus volumineuses, si bien qu'il nous sera très rapidement impossible de modifier la structure de nos données. 
     Cette volumétrie pouvant très rapidement exploser, une base de données permettant de répartir les entrées dans un cluster pourrait nous éviter des problèmes de performances et de capacité de stockage. 

     Il nous faut donc un système de base de données s'affranchissant en partie du schémas, disposant de mécanismes de recherche avancés et dans l'idéal proposant une architecture en cluster.

On dégage ainsi deux axes de travail (qui sont la récolte de données et le stockage de celles-ci) ayant un point commun : la répartition de la charge sur un cluster. 
Il nous faut donc tendre vers une architecture favorisant la scalabilité horizontale.

Une autre particularité à relever est la ponctualité des études : il est inutile d'avoir une dizaine de machines allumées, elles ne sont utiles que lorsqu'il faut récolter des données. 
Il serait donc judicieux de trouver un fournisseur louant des machines à la demande, au moins pour cette partie de la plate-forme.

#Présentation du Cloud d'Amazon
Amazon met à disposition de nombreux services basés sur son Cloud : Amazon Web Service (AWS).

Parmi ces services on peut noter Elastic Cloud Compute, Simple Storage Service (S3) et Elastic MapReduce.

##Généralités
Le Cloud d'Amazon étant de base mondial pour des raisons internes à Amazon (la vente de biens dans tout le globe), il est réparti sur plusieurs data-centers eux mêmes répartis sur tous les continents.

Ainsi lorsque l'on désire en utiliser les services, la première étape est de choisir dans quel centre il faut allouer les ressources. Cette étape est obligatoire pour la quasi totalité des services, à quelques exceptions près.

Ces data-centers sont mis à disposition seuls ou en groupes sous le nom de région, de sorte que chaque région soit totalement indépendante. 

À titre d'information, voici la liste des régions mis à disposition lors de la rédaction de ce document :

|Code           | Name                     |
|--------------:|--------------------------|
|ap-northeast-1 | Asia Pacific (Tokyo)     |
|ap-southeast-1 | Asia Pacific (Singapore) |
|ap-southeast-2 | Asia Pacific (Sydney)    |
|eu-central-1   | EU (Frankfurt)           |
|eu-west-1      | EU (Ireland)             |
|sa-east-1      | South America (Sao Paulo)|
|us-east-1      | US East (N. Virginia)    |
|us-west-1      | US West (N. California)  |
|us-west-2      | US West (Oregon)         |

Les régions sont elle-même découpées en zone de disponibilité (Availability Zone). Ces zones sont reliées au sein d'une même région via des liens réseau à faible latence. 
En revanche la communication inter-région nécessite une communication via Internet.

Le choix de la région utilisée est important pour plusieurs raisons :

 * Le prix des ressources varient en fonction de la région,
 * La législation appliquée aux données contenues dans les data-center dépendent du pays hébergeant,
 * La distance physique entre la région choisie et les principaux consommateurs des ressources allouées peut changer l'expérience utilisateur (lien des qualité réseau, temps de latence, etc.).
 * La plupart des services nécessitent le choix d'une région ou d'une zone de disponibilité.

##Amazon Elastic Cloud Compute
Ce service (abrégé EC2) permet de louer à l'heure des machines virtuelles aux configurations diverses, réparties en plusieurs catégories différenciées par les ratio mémoire/cpu/stockage proposés.

Chaque type d'instance est nommé d'après le schéma suivant (Type)(Génération).(Taille).
Par exemple, il existe des instances d'usage général (M), optimisées calcul (C), ou encore optimisées pour la mémoire (R).
Ainsi une instance d'usage général, de 3ème génération (la génération actuelle) de taille large sera nommée `m3.medium`. 

Le tableau listant toutes les instances existantes est disponible sur <https://aws.amazon.com/fr/ec2/instance-types/>.

Les instances EC2 doivent être lancées dans une zone de disponibilité, ou à défaut dans une région (la zone est alors choisie au hasard). 

Leur coût horaire dépend non seulement de la région, mais aussi du mode d'allocation choisi :

 *   Les instances à la demande proposent un coût horaire fixe,
 *   Les instances « SPOT » proposent un coût horaire variable mais généralement très inférieur aux instances à la demande (on peut trouver des prix jusqu'à 8 fois inférieurs). 
 
     Le prix des instances est basé sur la loi de l'offre (la quantité de machines non utilisées) et de la demande. 
     Il est possible de spécifier un prix horaire maximum afin d'éviter de devoir débourser de grosses sommes en cas de pic d'utilisation. La machine allouée sera alors éteinte.

 *   Les instances réservées d'utilisation légère, moyenne ou intensives, qui permettent une réduction du prix des instances à la demande de l'ordre de 30 % à 60 % pour les instances de plus grande taille.

     Après avoir payé des frais initiaux, le coût horaire d'un certain nombre d'instance est diminué (il peut même être annulé si l'on paie tous les frais pour 1 ou 3 ans en une seule fois).

Dans le cas général, le coût d'une instance peut être déterminé par la formule suivante : $$\text{coût} = \text{coût horaire de l'instance} \times \text{nombre d'heure d'utilisation}$$
Il faut par ailleurs noter que chaque heure entamée est une heure consommée.

Ces différents modes d'allocation permettent de couvrir la plupart des besoins :

 * Pour des services ponctuels les instances à la demande sont généralement suffisantes,
 * Si ces services ne sont pas critiques et peuvent être interrompus, les instances de type SPOT peuvent être intéressantes afin de diminuer radicalement les coûts,
 * Pour des services critiques disponibles en permanence ou ponctuels, des instances réservées sont conseillées (le type de réservation dépend du nombre d'heure consommées par mois).

En plus du coût horaire de base lié à l'instance, on retrouve d'autres charges liées à l'utilisation d'autres ressources dans le Cloud, comme la bande passante, de l'espace disque supplémentaire ou encore les entrées/sorties disque.
Ces tarifs dépendent généralement eux aussi de la région choisie.

Par exemple, en Irelande le rapatriement de données depuis Internet coûte $0,01 par Go. Pour plus de détails il est possible de consulter la grille tarifaire sur <https://aws.amazon.com/fr/ec2/pricing/>.
//TODO → Parler AMI ? EBS ? Instance-store ? HVM/PV ?

##Amazon Simple Storage Service
Abrégé S3, le service de stockage d'Amazon permet de sauvegarder durablement dans son cloud des données arbitraires à prix réduit, et avec une durabilité de l'ordre de 99,999999999 % et une disponibilité de 99,99 % sur un an.

Les données sont stockées dans une région, et dupliquées dans plusieurs data-center (de façon à pouvoir supporter la perte de deux centres de données).

Ce service est en réalité propulsé par un moteur de base de données de type clé/valeur.  
Il est donc possible de nommer ses données de manière hiérarchisée, comme sur un système de fichier classique (par exemple : `dossier/autre_dossier/mon_fichier`).

Afin d'utiliser ce service, il est nécessaire de créer un dépôt de données (bucket dans la terminologie  AWS). 
L'espace disponible dans un bucket est virtuellement illimité (on estime à 2 000 000 000 000 – deux billions le nombre d'objets stocké en Mars 2013… il y a 2 ans !), 
les données sont stockées dans la région spécifiée lors de la création de celui-ci.

De plus, à chaque bucket peut être attaché de nombreuses options permettant de :

 *  Gérer les droits en fonction de l'utilisateur,
 *  Donner un accès en lecture seule à n'importe qui via une adresse internet HTTP,
 *  Gérer le cycle de vie des objets (gestion d'un Time To Live, archivage, etc.),
 *  Gérer les versions des données (et donc pouvoir annuler des suppressions, des modification, etc.)
 *  Activer un cryptage AES des données,
 *  Et quelques autres options non listées ici.

Le coût de ce service est très faible, par exemple en Irelande le prix par Go par mois est de $0,03. 
En plus du stockage sont facturés les requêtes d'insertion de données, de listage, de récupération et la bande passante utilisée.

Pour plus de détails sur les tarifs en vigueur consultez la grille tarifaire sur <https://aws.amazon.com/fr/s3/pricing/>. 

##Amazon Elastic MapReduce
Ce service s'appuie sur EC2 pour lancer et configurer des instances avec Hadoop, un Framework\footnote{TODO} de calcul distribué très connu basé sur MapReduce (nous en reparlerons plus loin). 

Il permet de faire abstraction de la configuration des machines virtuelles et de Hadoop.

Il permet également d'utiliser Amazon S3 comme espace de stockage pour les données des tâches à effectuer (aussi bien en entrée qu'en sortie).

Afin d'utiliser ce service, il est nécessaire de spécifier dans quelle région les instances EC2 doivent être lancées, ainsi que leur type et leur nombre.
Les instances du cluster peuvent avoir 3 rôles différents:

 * La machine Master,
 * Les machines Core,
 * Les machines Task.

#SWOT
