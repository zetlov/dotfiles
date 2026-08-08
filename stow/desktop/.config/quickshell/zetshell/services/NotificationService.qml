import QtQuick
import Quickshell.Services.Notifications

Item {
    id: root

    property var notifications: []
    property var toasts: []
    property bool centerOpen: false
    property int maxHistory: 50
    property int maxToasts: 4
    property int toastTimeoutMs: 7000
    property int criticalToastTimeoutMs: 12000

    readonly property int unreadCount: notifications.reduce((count, entry) => count + (entry.unread ? 1 : 0), 0)
    readonly property bool hasUnread: unreadCount > 0
    readonly property string badgeText: unreadCount > 99 ? "99+" : `${unreadCount}`
    readonly property var latestEntry: notifications.length > 0 ? notifications[0] : null

    function makeEntry(notification) {
        return {
            id: notification.id,
            notification: notification,
            unread: !root.centerOpen,
            timestamp: Date.now()
        };
    }

    function toastLifetime(entry) {
        if (entry.notification.urgency === NotificationUrgency.Critical)
            return root.criticalToastTimeoutMs;

        return root.toastTimeoutMs;
    }

    function trimEntries(entries, maxEntries) {
        return entries.slice(0, Math.max(0, maxEntries));
    }

    function withUnread(entry, unread) {
        return {
            id: entry.id,
            notification: entry.notification,
            unread: unread,
            timestamp: entry.timestamp
        };
    }

    function upsertEntry(entries, entry) {
        const next = entries.filter(existing => existing.id !== entry.id);
        next.unshift(entry);
        return next;
    }

    function removeEntry(entries, notificationId) {
        return entries.filter(entry => entry.id !== notificationId);
    }

    function trackNotification(notification) {
        notification.tracked = true;

        const entry = makeEntry(notification);
        root.notifications = trimEntries(upsertEntry(root.notifications, entry), root.maxHistory);
        root.toasts = trimEntries(upsertEntry(root.toasts, entry), root.maxToasts);
        toastExpiry.restart();

        notification.closed.connect(function() {
            root.notifications = removeEntry(root.notifications, notification.id);
            root.toasts = removeEntry(root.toasts, notification.id);
            toastExpiry.restart();
        });
    }

    function markRead(notificationId) {
        root.notifications = root.notifications.map(entry => entry.id === notificationId ? withUnread(entry, false) : entry);
    }

    function markAllRead() {
        root.notifications = root.notifications.map(entry => withUnread(entry, false));
    }

    function dismiss(notificationId) {
        const entry = root.notifications.find(candidate => candidate.id === notificationId);
        if (!entry)
            return;

        markRead(notificationId);
        root.toasts = removeEntry(root.toasts, notificationId);
        entry.notification.dismiss();
    }

    function expire(notificationId) {
        const entry = root.notifications.find(candidate => candidate.id === notificationId);
        if (!entry)
            return;

        markRead(notificationId);
        root.toasts = removeEntry(root.toasts, notificationId);
        entry.notification.expire();
    }

    function dismissToast(notificationId) {
        markRead(notificationId);
        root.toasts = removeEntry(root.toasts, notificationId);
        toastExpiry.restart();
    }

    function invokeAction(notificationId, actionIdentifier) {
        const entry = root.notifications.find(candidate => candidate.id === notificationId);
        if (!entry)
            return;

        const action = entry.notification.actions.find(candidate => candidate.identifier === actionIdentifier);
        if (!action)
            return;

        markRead(notificationId);
        root.toasts = removeEntry(root.toasts, notificationId);
        action.invoke();
    }

    function sendInlineReply(notificationId, replyText) {
        const entry = root.notifications.find(candidate => candidate.id === notificationId);
        if (!entry || !replyText || replyText.trim() === "")
            return;

        markRead(notificationId);
        root.toasts = removeEntry(root.toasts, notificationId);
        entry.notification.sendInlineReply(replyText.trim());
    }

    function formatTimestamp(timestamp) {
        const value = new Date(timestamp);
        const now = new Date();
        const sameDay = value.getFullYear() === now.getFullYear()
            && value.getMonth() === now.getMonth()
            && value.getDate() === now.getDate();

        return sameDay
            ? Qt.formatTime(value, "HH:mm:ss")
            : Qt.formatDateTime(value, "MM-dd HH:mm");
    }

    function setCenterOpen(open) {
        root.centerOpen = open;
        if (open)
            markAllRead();
    }

    function toggleCenter() {
        setCenterOpen(!root.centerOpen);
    }

    Timer {
        id: toastExpiry

        interval: 1000
        repeat: true
        running: root.toasts.length > 0

        onTriggered: {
            const now = Date.now();
            const expired = root.toasts
                .filter(entry => now - entry.timestamp >= root.toastLifetime(entry))
                .map(entry => entry.id);

            if (expired.length === 0)
                return;

            expired.forEach(id => root.dismissToast(id));
        }
    }

    NotificationServer {
        id: server

        keepOnReload: true
        persistenceSupported: true
        bodySupported: true
        bodyMarkupSupported: false
        bodyHyperlinksSupported: false
        bodyImagesSupported: true
        actionsSupported: true
        actionIconsSupported: false
        imageSupported: true
        inlineReplySupported: true

        onNotification: notification => {
            root.trackNotification(notification);
        }
    }
}
