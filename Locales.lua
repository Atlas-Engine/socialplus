local ADDON_NAME, ns = ...
ns.L = {}
local L = ns.L

-----------------------------------------------------------------------
-- Localization: English (base) with per-locale overrides below.
-- Any key not overridden by the active locale falls back to English.
-----------------------------------------------------------------------

----------------------------------------------------------------
-- General
----------------------------------------------------------------
L.ADDON_NAME              = "SocialPlus"

----------------------------------------------------------------
-- Interaction Menu
----------------------------------------------------------------
L.MENU_INTERACT           = "Interact"
L.MENU_WHISPER            = "Whisper"
L.MENU_INVITE             = "Invite"
L.MENU_SUGGEST            = "Suggest Invite"
L.MENU_COPY_NAME          = "Copy Character Name"
L.MENU_VIEW_FRIENDS       = "View Friends List"

L.MENU_GROUPS             = "Group Management"
L.MENU_CREATE_GROUP       = "Create a Group"
L.MENU_ADD_TO_GROUP       = "Add to Group"
L.MENU_MOVE_TO_GROUP      = "Move to Another Group"
L.MENU_REMOVE_FROM_GROUP  = "Remove from Group"
L.MENU_REMOVE_FROM_NAMED  = "Remove from %s"

L.MENU_OTHER_OPTIONS      = "Additional Options"
L.MENU_SET_NOTE           = "Set Note"
L.MENU_REMOVE_BNET        = "Remove Battle.net Friend"
L.MENU_ADD_FAVORITE       = "Add to Favorites"
L.MENU_REMOVE_FAVORITE    = "Remove from Favorites"

----------------------------------------------------------------
-- Search & grouping
----------------------------------------------------------------
L.SEARCH_PLACEHOLDER      = "Names/Groups/Classes"
L.GROUP_UNGROUPED         = "General"
L.GROUP_FAVORITES         = "Favorites"
L.GROUP_INGAME            = "In-game Friends"

----------------------------------------------------------------
-- Group menu (header right-click)
----------------------------------------------------------------
L.GROUP_INVITE_ALL        = "Invite All"
L.GROUP_RENAME            = "Rename Group"
L.GROUP_REMOVE            = "Delete Group"
L.GROUP_SETTINGS          = "SocialPlus Settings"
L.GROUP_NO_GROUPS         = "No groups available"
L.GROUP_NO_GROUPS_REMOVE  = "No groups to remove"
L.GROUP_MUTE_NOTIFICATIONS = "Mute Notifications"

----------------------------------------------------------------
-- Settings toggles
----------------------------------------------------------------
L.SETTING_HIDE_OFFLINE       = "Hide offline friends"
L.SETTING_SHOW_LEVEL         = "Display friends levels"
L.SETTING_COLOR_NAMES        = "Color names by class"
L.SETTING_PRIORITIZE_PREFIX  = "Show "
L.SETTING_PRIORITIZE_SUFFIX  = " friends first"
L.SETTING_SCROLL_SPEED       = "Scroll speed"
L.SETTING_SCROLL_SPEED_DESC  = "Adjust the scroll speed for the friends list."
L.SETTING_SECTION_NOTIFICATIONS = "Notifications"
L.SETTING_NOTIFY_ENABLE      = "Notify when friends come online"
L.SETTING_NOTIFY_OFFLINE     = "Notify when friends go offline"
L.SETTING_NOTIFY_SAME_VERSION_PREFIX = "Only notify for "
L.SETTING_NOTIFY_SAME_VERSION_SUFFIX = " friends"
L.SETTING_NOTIFY_SOUND       = "Play a sound with notifications"

----------------------------------------------------------------
-- Popup titles
----------------------------------------------------------------
L.POPUP_RENAME_TITLE        = "Group Name"
L.POPUP_CREATE_TITLE        = "New Group Name"
L.POPUP_NOTE_TITLE          = "Enter a note for this friend"
L.POPUP_COPY_TITLE          = "Character Name (Ctrl+C to copy):"

----------------------------------------------------------------
-- Extra messages
----------------------------------------------------------------
L.INVITE_REASON_NOT_WOW     = "This friend is not currently in World of Warcraft."
L.INVITE_REASON_WRONG_PROJECT = "This friend is not on your WoW version."
L.INVITE_REASON_NO_REALM      = "This friend is in a different region."
L.INVITE_REASON_OPPOSITE_FACTION = "This friend is on the opposite faction."
L.INVITE_REASON_ALREADY_GROUPED = "This friend is already in your group."

L.CONFIRM_REMOVE_BNET_TEXT  = 'Are you sure you want to remove "%s"?\n\nType "YES" to confirm.'
L.CONFIRM_REMOVE_BNET_WORD  = "YES"
L.MSG_REMOVE_FRIEND_SUCCESS = 'Successfully removed %s.'
L.INVITE_GENERIC_FAIL       = "You cannot invite this friend."
L.CONFIRM_DELETE_GROUP_TEXT = 'Delete the group "%s"?\n\nFriends in it will become ungrouped.'
L.MSG_INVITE_ACCEPT_BROKEN  = "|cffff9955SocialPlus:|r this friend request couldn't be accepted (the request itself appears broken, not SocialPlus). Try the Battle.net app, or ask the sender to cancel and send it again."

----------------------------------------------------------------
-- Friend online/offline notifications
----------------------------------------------------------------
L.NOTIFY_ONLINE_MSG         = "%s is now |cFF00FF00online|r"
L.NOTIFY_OFFLINE_MSG        = "%s is now |cFFFF0000offline|r"
L.TOOLTIP_ALSO_ONLINE       = "Also online: %s"
L.REGION_NA                 = "NA"
L.REGION_EU                 = "EU"
L.WOW_VERSION_RETAIL        = "Retail"
L.WOW_VERSION_CLASSIC_ERA   = "Classic"
L.WOW_VERSION_TBC           = "TBC"
L.WOW_VERSION_WOTLK         = "WotLK"
L.WOW_VERSION_CATA          = "Cata"
L.WOW_VERSION_MOP           = "MoP"

-----------------------------------------------------------------------
-- Locale overrides
-----------------------------------------------------------------------
local locale = GetLocale()

if locale == "frFR" then
    ----------------------------------------------------------------
    -- Interaction Menu (right-click friend)
    ----------------------------------------------------------------
    L.MENU_INTERACT           = "Interagir"
    L.MENU_WHISPER            = "Chuchoter"
    L.MENU_INVITE             = "Inviter"
    L.MENU_SUGGEST            = "Suggérer une invitation"
    L.MENU_COPY_NAME          = "Copier le nom du personnage"
    L.MENU_VIEW_FRIENDS       = "Voir ses amis"

    L.MENU_GROUPS             = "Gestion des groupes"
    L.MENU_CREATE_GROUP       = "Créer un groupe"
    L.MENU_ADD_TO_GROUP       = "Ajouter au groupe"
    L.MENU_MOVE_TO_GROUP      = "Déplacer vers un autre groupe"
    L.MENU_REMOVE_FROM_GROUP  = "Retirer du groupe"
    L.MENU_REMOVE_FROM_NAMED  = "Retirer de %s"

    L.MENU_OTHER_OPTIONS      = "Options supplémentaires"
    L.MENU_SET_NOTE           = "Définir une note"
    L.MENU_REMOVE_BNET        = "Retirer l’ami Battle.net"
    L.MENU_ADD_FAVORITE       = "Ajouter aux favoris"
    L.MENU_REMOVE_FAVORITE    = "Retirer des favoris"

    ----------------------------------------------------------------
    -- Search & grouping
    ----------------------------------------------------------------
    L.SEARCH_PLACEHOLDER      = "Noms/Groupes/Classes"
    L.GROUP_UNGROUPED         = "Général"
    L.GROUP_FAVORITES         = "Favoris"
    L.GROUP_INGAME            = "Amis en jeu"

    ----------------------------------------------------------------
    -- Group menu (header right-click)
    ----------------------------------------------------------------
    L.GROUP_INVITE_ALL        = "Inviter tout le groupe"
    L.GROUP_RENAME            = "Renommer le groupe"
    L.GROUP_REMOVE            = "Supprimer le groupe"
    L.GROUP_SETTINGS          = "Paramètres SocialPlus"
    L.GROUP_NO_GROUPS         = "Aucun groupe disponible"
    L.GROUP_NO_GROUPS_REMOVE  = "Aucun groupe à retirer"
    L.GROUP_MUTE_NOTIFICATIONS = "Couper les notifications"

    ----------------------------------------------------------------
    -- Settings toggles (group submenu)
    ----------------------------------------------------------------
    L.SETTING_HIDE_OFFLINE       = "Masquer les amis hors ligne"
    L.SETTING_SHOW_LEVEL         = "Afficher les niveaux des amis"
    L.SETTING_COLOR_NAMES        = "Colorer les noms selon la classe"
    L.SETTING_PRIORITIZE_PREFIX  = "Afficher les amis "
    L.SETTING_PRIORITIZE_SUFFIX  = " en premier"
    L.SETTING_SCROLL_SPEED       = "Vitesse de défilement"
    L.SETTING_SCROLL_SPEED_DESC  = "Ajuste la vitesse de défilement de la liste d’amis."
    L.SETTING_SECTION_NOTIFICATIONS = "Notifications"
    L.SETTING_NOTIFY_ENABLE      = "Notifier quand un ami se connecte"
    L.SETTING_NOTIFY_OFFLINE     = "Notifier quand un ami se déconnecte"
    L.SETTING_NOTIFY_SAME_VERSION_PREFIX = "Notifier uniquement pour les amis "
    L.SETTING_NOTIFY_SAME_VERSION_SUFFIX = ""
    L.SETTING_NOTIFY_SOUND       = "Jouer un son avec les notifications"

    ----------------------------------------------------------------
    -- Popup titles
    ----------------------------------------------------------------
    L.POPUP_RENAME_TITLE        = "Nom du groupe"
    L.POPUP_CREATE_TITLE        = "Nom du nouveau groupe"
    L.POPUP_NOTE_TITLE          = "Ajouter ou modifier une note"
    L.POPUP_COPY_TITLE          = "Nom du personnage (Ctrl+C pour copier) :"

    ----------------------------------------------------------------
    -- Extra messages
    ----------------------------------------------------------------
    L.INVITE_REASON_NOT_WOW     = "Cet ami n’est pas actuellement dans World of Warcraft."
    L.INVITE_REASON_WRONG_PROJECT = "Cet ami n’utilise pas la même version de WoW que vous."
    L.INVITE_REASON_NO_REALM      = "Cet ami se trouve dans une autre région."
    L.INVITE_REASON_OPPOSITE_FACTION = "Cet ami appartient à la faction adverse."
    L.INVITE_REASON_ALREADY_GROUPED = "Cet ami est déjà dans votre groupe."

    L.CONFIRM_REMOVE_BNET_TEXT  = 'Voulez-vous vraiment retirer "%s" ?\n\nTapez "OUI" pour confirmer.'
    L.CONFIRM_REMOVE_BNET_WORD  = "OUI"
    L.MSG_REMOVE_FRIEND_SUCCESS = 'Vous avez retiré %s avec succès.'
    L.INVITE_GENERIC_FAIL       = "Vous ne pouvez pas inviter cet ami."
    L.CONFIRM_DELETE_GROUP_TEXT = 'Supprimer le groupe "%s" ?\n\nLes amis qu\'il contient deviendront non groupés.'
    L.MSG_INVITE_ACCEPT_BROKEN  = "|cffff9955SocialPlus :|r cette invitation d'ami n'a pas pu être acceptée (l'invitation elle-même semble corrompue, pas SocialPlus). Essayez l'application Battle.net, ou demandez à l'expéditeur de l'annuler et de la renvoyer."

    ----------------------------------------------------------------
    -- Friend online/offline notifications
    ----------------------------------------------------------------
    L.NOTIFY_ONLINE_MSG         = "%s est maintenant |cFF00FF00en ligne|r"
    L.NOTIFY_OFFLINE_MSG        = "%s est maintenant |cFFFF0000hors ligne|r"
    L.TOOLTIP_ALSO_ONLINE       = "Également en ligne : %s"
    L.REGION_NA                 = "NA"
    L.REGION_EU                 = "EU"
    L.WOW_VERSION_RETAIL        = "Retail"
    L.WOW_VERSION_CLASSIC_ERA   = "Classic"
    L.WOW_VERSION_TBC           = "TBC"
    L.WOW_VERSION_WOTLK         = "WotLK"
    L.WOW_VERSION_CATA          = "Cata"
    L.WOW_VERSION_MOP           = "MoP"

elseif locale == "esES" or locale == "esMX" then
    ----------------------------------------------------------------
    -- Interaction Menu (right-click friend)
    ----------------------------------------------------------------
    L.MENU_INTERACT           = "Interactuar"
    L.MENU_WHISPER            = "Susurrar"
    L.MENU_INVITE             = "Invitar"
    L.MENU_SUGGEST            = "Sugerir invitación"
    L.MENU_COPY_NAME          = "Copiar nombre del personaje"
    L.MENU_VIEW_FRIENDS       = "Ver lista de amigos"

    L.MENU_GROUPS             = "Gestión de grupos"
    L.MENU_CREATE_GROUP       = "Crear un grupo"
    L.MENU_ADD_TO_GROUP       = "Añadir al grupo"
    L.MENU_MOVE_TO_GROUP      = "Mover a otro grupo"
    L.MENU_REMOVE_FROM_GROUP  = "Quitar del grupo"
    L.MENU_REMOVE_FROM_NAMED  = "Quitar de %s"

    L.MENU_OTHER_OPTIONS      = "Opciones adicionales"
    L.MENU_SET_NOTE           = "Añadir nota"
    L.MENU_REMOVE_BNET        = "Eliminar amigo de Battle.net"
    L.MENU_ADD_FAVORITE       = "Añadir a favoritos"
    L.MENU_REMOVE_FAVORITE    = "Quitar de favoritos"

    ----------------------------------------------------------------
    -- Search & grouping
    ----------------------------------------------------------------
    L.SEARCH_PLACEHOLDER      = "Nombres/Grupos/Clases"
    L.GROUP_UNGROUPED         = "General"
    L.GROUP_FAVORITES         = "Favoritos"
    L.GROUP_INGAME            = "Amigos en el juego"

    ----------------------------------------------------------------
    -- Group menu (header right-click)
    ----------------------------------------------------------------
    L.GROUP_INVITE_ALL        = "Invitar a todo el grupo"
    L.GROUP_RENAME            = "Renombrar grupo"
    L.GROUP_REMOVE            = "Eliminar grupo"
    L.GROUP_SETTINGS          = "Configuración de SocialPlus"
    L.GROUP_NO_GROUPS         = "No hay grupos disponibles"
    L.GROUP_NO_GROUPS_REMOVE  = "No hay grupos para eliminar"
    L.GROUP_MUTE_NOTIFICATIONS = "Silenciar notificaciones"

    ----------------------------------------------------------------
    -- Settings toggles (group submenu)
    ----------------------------------------------------------------
    L.SETTING_HIDE_OFFLINE       = "Ocultar amigos desconectados"
    L.SETTING_SHOW_LEVEL         = "Mostrar los niveles de los amigos"
    L.SETTING_COLOR_NAMES        = "Colorear nombres según la clase"
    L.SETTING_PRIORITIZE_PREFIX  = "Mostrar primero los amigos de "
    L.SETTING_PRIORITIZE_SUFFIX  = ""
    L.SETTING_SCROLL_SPEED       = "Velocidad de desplazamiento"
    L.SETTING_SCROLL_SPEED_DESC  = "Ajusta la velocidad de desplazamiento de la lista de amigos."
    L.SETTING_SECTION_NOTIFICATIONS = "Notificaciones"
    L.SETTING_NOTIFY_ENABLE      = "Notificar cuando un amigo se conecta"
    L.SETTING_NOTIFY_OFFLINE     = "Notificar cuando un amigo se desconecta"
    L.SETTING_NOTIFY_SAME_VERSION_PREFIX = "Notificar solo a los amigos de "
    L.SETTING_NOTIFY_SAME_VERSION_SUFFIX = ""
    L.SETTING_NOTIFY_SOUND       = "Reproducir sonido con las notificaciones"

    ----------------------------------------------------------------
    -- Popup titles
    ----------------------------------------------------------------
    L.POPUP_RENAME_TITLE        = "Nombre del grupo"
    L.POPUP_CREATE_TITLE        = "Nombre del nuevo grupo"
    L.POPUP_NOTE_TITLE          = "Añade una nota para este amigo"
    L.POPUP_COPY_TITLE          = "Nombre del personaje (Ctrl+C para copiar):"

    ----------------------------------------------------------------
    -- Extra messages
    ----------------------------------------------------------------
    L.INVITE_REASON_NOT_WOW     = "Este amigo no está actualmente en World of Warcraft."
    L.INVITE_REASON_WRONG_PROJECT = "Este amigo no tiene tu misma versión de WoW."
    L.INVITE_REASON_NO_REALM      = "Este amigo está en otra región."
    L.INVITE_REASON_OPPOSITE_FACTION = "Este amigo pertenece a la facción contraria."
    L.INVITE_REASON_ALREADY_GROUPED = "Este amigo ya está en tu grupo."

    L.CONFIRM_REMOVE_BNET_TEXT  = '¿Seguro que quieres eliminar a "%s"?\n\nEscribe "SÍ" para confirmar.'
    L.CONFIRM_REMOVE_BNET_WORD  = "SÍ"
    L.MSG_REMOVE_FRIEND_SUCCESS = 'Has eliminado a %s correctamente.'
    L.INVITE_GENERIC_FAIL       = "No puedes invitar a este amigo."
    L.CONFIRM_DELETE_GROUP_TEXT = '¿Eliminar el grupo "%s"?\n\nLos amigos en él quedarán sin grupo.'
    L.MSG_INVITE_ACCEPT_BROKEN  = "|cffff9955SocialPlus:|r no se pudo aceptar esta solicitud de amistad (la solicitud en sí parece dañada, no SocialPlus). Prueba la aplicación Battle.net, o pide al remitente que la cancele y la envíe de nuevo."

    ----------------------------------------------------------------
    -- Friend online/offline notifications
    ----------------------------------------------------------------
    L.NOTIFY_ONLINE_MSG         = "%s está ahora |cFF00FF00en línea|r"
    L.NOTIFY_OFFLINE_MSG        = "%s está ahora |cFFFF0000desconectado|r"
    L.TOOLTIP_ALSO_ONLINE       = "También en línea: %s"
    L.REGION_NA                 = "NA"
    L.REGION_EU                 = "EU"
    L.WOW_VERSION_RETAIL        = "Retail"
    L.WOW_VERSION_CLASSIC_ERA   = "Classic"
    L.WOW_VERSION_TBC           = "TBC"
    L.WOW_VERSION_WOTLK         = "WotLK"
    L.WOW_VERSION_CATA          = "Cata"
    L.WOW_VERSION_MOP           = "MoP"
end
