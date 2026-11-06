# Anime Chat — Netlify + Supabase

Le site fourni est une interface web HTML/JavaScript publiée sur Netlify. Supabase gère les comptes, les profils, les messages et les médias.

## Ce que fait cette version
- Inscription et connexion avec un pseudo et un mot de passe (aucun e-mail/téléphone demandé aux membres).
- Les pseudos sont convertis en interne en `pseudo@animechat.invalid` pour Supabase Auth.
- Les pseudos sont uniques sans distinction majuscules/minuscules.
- Le profil reprend automatiquement le pseudo du compte et ne peut pas être renommé pour éviter l'usurpation.
- Les nouveaux comptes reçoivent automatiquement le rôle `member`.
- Le rôle `admin` ne peut être attribué que depuis Supabase SQL Editor.
- Les règles RLS protègent les profils, les messages et les conversations privées.

## Installation Supabase — dans cet ordre

1. Dans Supabase, ouvre **Authentication > Sign In / Providers > Email** et désactive **Confirm email**.
2. Désactive temporairement **Allow new users to sign up** dans les paramètres d'authentification.
3. Ouvre **SQL Editor > New query**.
4. Ouvre `setup-comptes.sql`, copie tout son contenu, colle-le dans SQL Editor et clique sur **Run**.
5. Dans **Authentication > Users > Add user**, crée le compte administrateur :
   - Email : `kems@animechat.invalid`
   - Mot de passe : choisis-le toi-même et garde-le secret.
   - Si un champ de métadonnées utilisateur est proposé, tu peux mettre `{"username":"KEMS"}`.
6. Dans SQL Editor, exécute cette commande pour attribuer le rôle ADMIN au compte réservé :

```sql
insert into public.chat_roles (user_id, role)
select id, 'admin'
from auth.users
where lower(email) = 'kems@animechat.invalid'
on conflict (user_id) do update set role = 'admin';
```

7. Vérifie que la requête a ajouté/modifié une ligne. Ensuite seulement, réactive **Allow new users to sign up**.
8. Dans **Authentication > URL Configuration**, ajoute l'URL exacte de ton site Netlify aux URL autorisées.

**Important :** crée le compte Kems avant de réactiver les inscriptions publiques. L'adresse interne unique réserve alors ce pseudo : une autre personne ne pourra pas créer ce compte.

## Configuration du site

`config.js` contient l'URL et la clé publishable de Supabase. Dans l'archive actuelle, ces valeurs sont déjà renseignées. Vérifie qu'elles correspondent bien à TON projet Supabase.

La clé `publishable` peut être utilisée dans le navigateur avec les règles RLS. Ne mets jamais la clé `service_role` dans `config.js` ou dans le site.

## À savoir
- Les mots de passe sont gérés par Supabase Auth, jamais stockés dans la table des profils.
- Sans adresse e-mail réelle, les membres ne peuvent pas recevoir de lien de réinitialisation. En cas de mot de passe oublié, l'administrateur devra aider à réinitialiser le compte depuis Supabase.
- Le panneau complet de modération (bannissement, suppression des messages d'autres membres, gestion des comptes) n'est pas encore développé.
- Les anciennes données anonymes ne sont pas automatiquement associées aux nouveaux comptes.
- Les médias du bucket `media` utilisent des URL publiques pour leur affichage. N'y téléverse pas de document confidentiel.
- Après installation, teste avec deux comptes distincts : inscription, reconnexion, profil, message public, discussion privée, story, invitation de jeu et déconnexion.

## Sécurité des conversations
Le SQL vérifie que l'identifiant de l'utilisateur connecté figure dans le chemin d'une conversation privée. Il empêche aussi un membre d'injecter des messages dans la conversation privée de deux autres personnes.
