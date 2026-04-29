// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get navChannels => 'Channels';

  @override
  String get navContacts => 'Contacts';

  @override
  String get navMap => 'Map';

  @override
  String get navApps => 'Apps';

  @override
  String get navSettings => 'Settings';

  @override
  String get commonSave => 'Save';

  @override
  String get commonSaving => 'Saving...';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonClear => 'Clear';

  @override
  String get commonDelete => 'Delete';

  @override
  String get commonClose => 'Close';

  @override
  String get commonBack => 'Back';

  @override
  String get commonRemove => 'Remove';

  @override
  String get commonAdd => 'Add';

  @override
  String get commonEdit => 'Edit';

  @override
  String get commonShare => 'Share';

  @override
  String get commonCopy => 'Copy';

  @override
  String get commonRename => 'Rename';

  @override
  String get commonReset => 'Reset';

  @override
  String get commonJustNow => 'just now';

  @override
  String commonMinutesAgo(int minutes) {
    return '$minutes min ago';
  }

  @override
  String commonHoursAgo(int hours) {
    return '$hours h ago';
  }

  @override
  String get gpsSharingTitle => 'GPS sharing';

  @override
  String get gpsSharingSubtitle =>
      'You decide whether your location is broadcast in the radio\'s adverts. Off by default.';

  @override
  String get gpsSharingStatusOff => 'OFF';

  @override
  String get gpsSharingStatusManual => 'MANUAL';

  @override
  String get gpsSharingStatusAuto => 'AUTO';

  @override
  String get gpsSharingModeOff => 'Off';

  @override
  String get gpsSharingModeManual => 'Manual';

  @override
  String get gpsSharingModeAuto => 'Auto';

  @override
  String get gpsSharingPrecisionTitle => 'Sent precision';

  @override
  String get gpsSharingPrecisionExact => 'Exact';

  @override
  String get gpsSharingPrecisionRough => 'Rough';

  @override
  String get gpsSharingPrecisionVague => 'Vague';

  @override
  String get gpsSharingIntervalLabel => 'Update interval';

  @override
  String get gpsSharingShareNow => 'Share now';

  @override
  String get gpsSharingClearNow => 'Clear from radio';

  @override
  String get gpsSharingClearedOnRadio => 'Location cleared from the radio.';

  @override
  String get gpsSharingPrivacyDisclaimer =>
      'Your position will be included in LoRa adverts your radio transmits and may be visible to other nodes. Only enable this if you accept sharing it.';

  @override
  String gpsSharingLastShared(Object ago, Object lat, Object lon) {
    return 'Shared $ago — $lat, $lon';
  }

  @override
  String gpsSharingOutcomeOk(Object lat, Object lon) {
    return '✅ Location sent: $lat, $lon';
  }

  @override
  String get gpsSharingOutcomeCleared => 'Location cleared from radio.';

  @override
  String get gpsSharingOutcomeDisabled => 'GPS sharing is off in Settings.';

  @override
  String get gpsSharingOutcomeNoPerm => 'Location permission denied.';

  @override
  String get gpsSharingOutcomeServiceOff => 'Phone location service disabled.';

  @override
  String get gpsSharingOutcomeNoFix => 'No GPS fix available.';

  @override
  String get gpsSharingOutcomeDisconnected =>
      'Radio disconnected — connect first.';

  @override
  String get gpsSharingOutcomeFailed => 'Failed to send location.';

  @override
  String get gpsSharingOutcomeSkipped =>
      'Position unchanged — transmit skipped.';

  @override
  String get gpsSharingMinMoveLabel => 'Minimum movement';

  @override
  String get gpsSharingMinMoveAlways => 'Always send';

  @override
  String get gpsSharingMinMoveHint =>
      'In Auto mode, only push a new fix if you have moved at least this far since the last send. Saves LoRa air-time.';

  @override
  String get gpsSharingAdvPolicyTitle => 'Broadcast location in adverts';

  @override
  String get gpsSharingAdvPolicyNever =>
      'Off — your adverts will not include coordinates.';

  @override
  String get gpsSharingAdvPolicyAlways =>
      'On — every advert will include the radio\'s last known location.';

  @override
  String gpsSharingAdvPolicyUnknown(Object value) {
    return 'Radio policy byte $value — unknown value.';
  }

  @override
  String get mapVisibilityShowTitle => 'Show on map';

  @override
  String get mapVisibilityShowSubtitle =>
      'Hide this contact from your map, even if its adverts include coordinates.';

  @override
  String get cannedMessagesTitle => 'Canned messages';

  @override
  String get cannedMessagesSubtitle =>
      'Library of pre-written replies to send with one tap (or from the widget\'s SOS button).';

  @override
  String get cannedMessagesAdd => 'Add message';

  @override
  String get cannedMessagesAddTitle => 'New canned message';

  @override
  String get cannedMessagesEditTitle => 'Edit canned message';

  @override
  String get cannedMessagesEmpty => 'No saved messages. Tap + to add one.';

  @override
  String get cannedMessagesReset => 'Reset to defaults';

  @override
  String get cannedMessagesResetTitle => 'Reset messages?';

  @override
  String get cannedMessagesResetConfirm =>
      'You\'ll lose all changes and restore the original list.';

  @override
  String get cannedMessagesDeleteTitle => 'Delete message?';

  @override
  String cannedMessagesDeleteConfirm(Object label) {
    return 'You will delete “$label”.';
  }

  @override
  String get cannedMessagesLabelHint => 'Label (optional)';

  @override
  String get cannedMessagesTextHint => 'Message text';

  @override
  String get cannedMessagesEmergencyToggle => 'Emergency message';

  @override
  String get cannedMessagesEmergencyDesc =>
      'Used by the widget\'s SOS button. Only one can be flagged.';

  @override
  String get cannedMessagesPickerTooltip => 'Canned messages';

  @override
  String get cannedMessagesPickerTitle => 'Insert canned message';

  @override
  String get cannedMessagesPickerSubtitle => 'Tap to put it into the composer.';

  @override
  String get commonConfirm => 'Confirm';

  @override
  String get commonError => 'Error';

  @override
  String get commonErrors => 'Errors';

  @override
  String get commonYes => 'Yes';

  @override
  String get commonNo => 'No';

  @override
  String get commonOk => 'Ok';

  @override
  String get commonLoading => 'Loading...';

  @override
  String get commonSearch => 'Search';

  @override
  String get commonAll => 'All';

  @override
  String get commonUnread => 'Unread';

  @override
  String get commonDetails => 'Details';

  @override
  String get commonReply => 'Reply';

  @override
  String get commonCopyText => 'Copy text';

  @override
  String get commonNoMessages => 'No messages';

  @override
  String get commonSendFirstMessage => 'Send the first message!';

  @override
  String get commonSendMessage => 'Send message';

  @override
  String get commonNoData => 'No data';

  @override
  String get commonMessageCopied => 'Message copied';

  @override
  String get commonSent => 'Sent';

  @override
  String get commonSentByMe => 'Me';

  @override
  String get commonPropagating => 'Propagating...';

  @override
  String get commonConnecting => 'Connecting...';

  @override
  String get commonSearching => 'Searching...';

  @override
  String get commonAuthenticated => 'Authenticated';

  @override
  String get commonDirect => 'Direct';

  @override
  String get commonFlood => 'Flood';

  @override
  String get commonBattery => 'Battery';

  @override
  String get commonStatus => 'Status';

  @override
  String get commonPath => 'Path';

  @override
  String get commonTime => 'Time';

  @override
  String get commonName => 'Name';

  @override
  String get commonChannel => 'Channel';

  @override
  String get commonContact => 'Contact';

  @override
  String get commonRoom => 'Room';

  @override
  String get commonRooms => 'Rooms';

  @override
  String get commonSensor => 'Sensor';

  @override
  String get commonSensors => 'Sensors';

  @override
  String get commonRepeater => 'Repeater';

  @override
  String get commonRepeaters => 'Repeaters';

  @override
  String get commonType => 'Type';

  @override
  String get commonHops => 'Hops';

  @override
  String get commonFavorites => 'Favorites';

  @override
  String get commonTelemetry => 'Telemetry';

  @override
  String get commonSettings => 'Settings';

  @override
  String get commonRadioDisconnected => 'Radio not connected';

  @override
  String get commonConfiguring => 'Configuring...';

  @override
  String get commonSaveToRadio => 'Save to radio';

  @override
  String get commonReportUrlCopied => 'Report URL copied';

  @override
  String get commonErrorColon => 'Error:';

  @override
  String get commonNoSpace => 'No slots available. Remove a channel first.';

  @override
  String get commonUpdated => 'Updated:';

  @override
  String get commonAdd2Radio => 'Add to Radio';

  @override
  String get commonReconfigRadio => 'Re-configure on Radio';

  @override
  String get commonHashtag => 'Hashtag';

  @override
  String get commonSecretKey => 'Secret Key';

  @override
  String get commonReport => 'Report:';

  @override
  String get commonClearHistory => 'Clear history';

  @override
  String get commonSingularHop => 'hop';

  @override
  String get commonPluralHops => 'hops';

  @override
  String get homeDisconnectTitle => 'Disconnect radio?';

  @override
  String get homeDisconnectContent => 'The radio connection will be terminated';

  @override
  String get homeDisconnect => 'Disconnect';

  @override
  String get homeExitTitle => 'Exit LusoAPP?';

  @override
  String get homeExitContent =>
      'The radio connection will be terminated and the app will close.';

  @override
  String get homeExit => 'Exit';

  @override
  String get settingsIdentity => 'Identity';

  @override
  String get settingsPublicKey => 'Public Key';

  @override
  String get settingsCopyPublicKey => 'Copy public key';

  @override
  String get settingsShareContact => 'Share my contact';

  @override
  String get settingsShareContactDesc => 'Shows QR Code to share';

  @override
  String get settingsConnection => 'Connection';

  @override
  String get settingsConnected => 'Connected';

  @override
  String get settingsConnectionError => 'Connection error';

  @override
  String get settingsDisconnected => 'Disconnected';

  @override
  String get settingsAutoReconnect => 'Auto-reconnect';

  @override
  String get settingsAutoReconnectDesc =>
      'Automatically reconnect when the connection is lost';

  @override
  String get settingsRadioConfig => 'Radio Configuration';

  @override
  String get settingsRadioConfigDesc => 'LoRa, telemetry and device';

  @override
  String get settingsReboot => 'Reboot';

  @override
  String get settingsShutdown => 'Shutdown';

  @override
  String get settingsRebootTitle => 'Restart radio';

  @override
  String get settingsRebootContent =>
      'This will restart the radio firmware. Are you sure?';

  @override
  String get settingsRebootSent =>
      'Reboot command sent. Waiting for reconnection...';

  @override
  String get settingsRebootFail => 'Failed to send reboot command';

  @override
  String get settingsAppearance => 'Appearance';

  @override
  String get settingsTheme => 'Theme';

  @override
  String get settingsThemeSystem => 'System';

  @override
  String get settingsThemeLight => 'Light';

  @override
  String get settingsThemeDark => 'Dark';

  @override
  String get settingsAccent => 'Accent color';

  @override
  String get settingsAccentDefault => 'Default (brand orange)';

  @override
  String get settingsAccentCustom => 'Custom';

  @override
  String get settingsAccentReset => 'Reset to default';

  @override
  String get settingsMentionColors => 'Mention colors';

  @override
  String get settingsSelfMention => 'Self mention (@[You])';

  @override
  String get settingsOtherMention => 'Other mention (@[Name])';

  @override
  String get settingsChooseColor => 'Choose color';

  @override
  String get settingsNotifications => 'Notifications';

  @override
  String get settingsEnableNotifications => 'Enable notifications';

  @override
  String get settingsEnableNotificationsDesc => 'Show alerts for new messages';

  @override
  String get settingsNotificationPermissionDenied =>
      'Notification permission not granted';

  @override
  String get settingsAllow => 'Allow';

  @override
  String get settingsPrivateMessages => 'Private messages';

  @override
  String get settingsChannelMessages => 'Channel messages';

  @override
  String get settingsBackgroundOnly => 'Background only';

  @override
  String get settingsPrivateKeyCopy => 'Private Key Backup';

  @override
  String get settingsPrivateKeyDesc =>
      'Your private key identifies you on the network. Save a secure copy before switching devices.';

  @override
  String get settingsSaveFromRadio => 'Save from radio';

  @override
  String get settingsPasteKey => 'Paste key';

  @override
  String get settingsShareCopy => 'Share copy';

  @override
  String get settingsRestoreToRadio => 'Restore to radio';

  @override
  String get settingsDeleteLocalCopy => 'Delete local copy';

  @override
  String get settingsRestorePrivateKeyTitle => 'Restore Private Key';

  @override
  String get settingsRestorePrivateKeyContent =>
      'The radio will restart automatically after restoration. Proceed?';

  @override
  String get settingsDeleteBackupTitle => 'Delete backup';

  @override
  String get settingsKeySavedSuccess => 'Private key copy saved successfully';

  @override
  String get settingsKeyImportedSuccess => 'Key imported successfully';

  @override
  String get settingsAbout => 'About';

  @override
  String get settingsAppName => 'LusoAPP';

  @override
  String get settingsAppSubtitle => 'MeshCore Portugal';

  @override
  String get settingsCredit =>
      'Initial source code created by Paulo Pereira aka GZ7d0';

  @override
  String get settingsVersion => 'Version';

  @override
  String get settingsProtocol => 'Protocol';

  @override
  String get settingsProtocolName => 'Companion Radio Protocol v3';

  @override
  String get settingsLicense => 'License';

  @override
  String get settingsLicenseMIT => 'MIT';

  @override
  String get contactsAll => 'All';

  @override
  String get contactsFavorites => 'Favorites';

  @override
  String get contactsCompanions => 'Companions';

  @override
  String get contactsRepeaters => 'Repeaters';

  @override
  String get contactsSensors => 'Sensors';

  @override
  String get contactsSearchHint => 'Search contacts...';

  @override
  String get contactsSendAdvert => 'Send Advert';

  @override
  String get contactsAdvertZeroHop => 'Advert · Zero Hop';

  @override
  String get contactsAdvertFlood => 'Advert · Flood';

  @override
  String get contactsSort => 'Sort';

  @override
  String get contactsSortNameAZ => 'Name (A-Z)';

  @override
  String get contactsSortLastHeard => 'Last heard';

  @override
  String get contactsSortLastMessage => 'Last message';

  @override
  String get contactsMoreOptions => 'More options';

  @override
  String get contactsDiscover => 'Discover contacts';

  @override
  String get contactsMultiSelect => 'Select multiple';

  @override
  String get contactsEmptyCompanions => 'No companions on the network';

  @override
  String get contactsEmptyRepeaters => 'No repeaters on the network';

  @override
  String get contactsEmptyRooms => 'No rooms on the network';

  @override
  String get contactsEmptySensors => 'No sensors on the network';

  @override
  String get contactsEmpty => 'No contacts';

  @override
  String get contactsEmptyFavorites => 'No favorites';

  @override
  String get contactsEmptyHint =>
      'Contacts appear when the radio discovers them';

  @override
  String get contactsSelected => 'selected';

  @override
  String get contactsRemoveSelected => 'Remove selected';

  @override
  String get contactsCancelSelection => 'Cancel selection';

  @override
  String get contactsAddContact => 'Add contact';

  @override
  String get contactsAddInstruction =>
      'Send an advert so other nodes discover you automatically, or add manually using the public key';

  @override
  String get contactsSendAdvertAuto => 'Send Advert (auto discovery)';

  @override
  String get contactsReadQR => 'Read QR Code';

  @override
  String get contactsOrManual => 'or add manually';

  @override
  String get contactsPublicKeyLabel => 'Public key (hex, 64 chars)';

  @override
  String get contactsDisplayName => 'Display name';

  @override
  String get contactsTypeChat => 'Chat';

  @override
  String get contactsTypeRepeater => 'Repeater';

  @override
  String get contactsTypeRoom => 'Room';

  @override
  String get contactsAdding => 'Adding...';

  @override
  String get contactsSeen => 'Seen:';

  @override
  String get contactsRenameTitle => 'Rename contact';

  @override
  String get contactsAnnouncedName => 'Announced name:';

  @override
  String get contactsCustomName => 'Custom name';

  @override
  String get contactsSaveToRadioTitle => 'Save contact to radio';

  @override
  String get contactsTypeCompanion => 'Type: Companion';

  @override
  String contactsSavedToRadio(String name) {
    return '$name saved to radio';
  }

  @override
  String get contactsSaveToRadioError => 'Error saving contact to radio';

  @override
  String get contactsSaveTimeout => 'Timeout: radio did not respond';

  @override
  String get contactsRemoveTitle => 'Remove contact(s)?';

  @override
  String get contactsRemovedPrefix => 'Removed';

  @override
  String get contactsRemoveErrorSuffix => 'error(s)';

  @override
  String get contactsRemoveError => 'Error removing contacts';

  @override
  String get contactsRemoveFromListSuffix => 'from the contact list?';

  @override
  String get contactsRemoveRadioError => 'Error removing on radio (code';

  @override
  String get contactsRemoveTimeout =>
      'Timeout: radio did not respond to removal';

  @override
  String get contactsRemoveFavorites => 'Remove from favorites';

  @override
  String get contactsAddFavorites => 'Add to favorites';

  @override
  String get contactsShareQR => 'Share via QR';

  @override
  String get contactsPrivateMessage => 'Private message';

  @override
  String get contactsJoinRoom => 'Join room';

  @override
  String get contactsRemoteAdmin => 'Remote admin';

  @override
  String get contactsManagePath => 'Manage path';

  @override
  String get contactsCurrentPath => 'Current path:';

  @override
  String get contactsRemoveContact => 'Remove contact';

  @override
  String get contactsAdminLabel => 'Admin:';

  @override
  String get contactsIdLabel => 'ID:';

  @override
  String get contactsHopsLabel => 'Hops:';

  @override
  String get contactsAuth => 'Authentication';

  @override
  String get contactsPassword => 'Password (optional)';

  @override
  String get contactsPasswordHint => 'Leave blank if no password';

  @override
  String get contactsJoin => 'Join';

  @override
  String get contactsStatusSent => 'Status request sent...';

  @override
  String get contactsStatusSending => 'Sending:';

  @override
  String get contactsRemoteActions => 'Remote Actions';

  @override
  String get contactsFloodAdvert => 'Flood Advert';

  @override
  String get contactsFloodAdvertDesc =>
      'Forces the node to send a flood advert';

  @override
  String get contactsZeroHopAdvert => 'Zero-Hop Advert';

  @override
  String get contactsZeroHopAdvertDesc => 'Advert to direct neighbours only';

  @override
  String get contactsSyncClock => 'Sync Clock';

  @override
  String get contactsSyncClockDesc => 'Sends the current timestamp to the node';

  @override
  String get contactsStartOTA => 'Start OTA';

  @override
  String get contactsStartOTADesc => 'Starts OTA update — NRF DFU / ESP32';

  @override
  String get contactsConfirmOTATitle => 'Confirm OTA';

  @override
  String get contactsConfirmOTAContent =>
      'The radio will enter OTA update mode and will be temporarily unreachable';

  @override
  String get contactsConfirmOTAQuestion => 'Are you sure?';

  @override
  String get contactsStats => 'Statistics';

  @override
  String get contactsUptime => 'Uptime';

  @override
  String get contactsSnrLast => 'SNR (last)';

  @override
  String get contactsRssiLast => 'RSSI (last)';

  @override
  String get contactsNoise => 'Noise';

  @override
  String get contactsRxTx => 'RX / TX';

  @override
  String get contactsFloodRxTx => 'Flood RX/TX';

  @override
  String get contactsDirectRxTx => 'Direct RX/TX';

  @override
  String get contactsAirtimeTx => 'Airtime (TX)';

  @override
  String get contactsAirtimeRx => 'Airtime (RX)';

  @override
  String get contactsDuplicates => 'Duplicates';

  @override
  String get contactsNotSavedHint =>
      'This contact was heard but is not saved on the radio';

  @override
  String get channelsCreatePrivate => 'Create Private Channel';

  @override
  String get channelsCreatePrivateDesc => 'Secured with a secret key';

  @override
  String get channelsJoinPrivate => 'Join Private Channel';

  @override
  String get channelsJoinPrivateDesc => 'Manually enter a secret key';

  @override
  String get channelsJoinPublic => 'Join Public Channel';

  @override
  String get channelsJoinPublicDesc => 'Anyone can join this channel';

  @override
  String get channelsJoinHashtag => 'Join Hashtag Channel';

  @override
  String get channelsJoinHashtagDesc => 'Anyone can join hashtag channels';

  @override
  String get channelsReadQR => 'Read QR Code';

  @override
  String get channelsReadQRDesc => 'Scan a channel QR Code';

  @override
  String get channelsSlotPosition => 'Channel slot';

  @override
  String get channelsSlot => 'Slot';

  @override
  String get channelsSlotInUse => '(in use)';

  @override
  String get channelsChannelName => 'Channel name';

  @override
  String get channelsHashtagName => 'Hashtag name (without #)';

  @override
  String get channelsHashtagHint => 'e.g.: meshcore  →  channel #meshcore';

  @override
  String get channelsNameHintGeneral => 'e.g.: General';

  @override
  String get channelsNameHintPrivate => 'e.g.: My Network';

  @override
  String get channelsSecretKey => 'Secret key (32 hex characters)';

  @override
  String get channelsSecretKeyHint => 'e.g.: 8b3387e9c5cdea6ac9e5edbaa115cd72';

  @override
  String get channelsPublicKey => 'Known public key';

  @override
  String get channelsDerivedKey => 'Hashtag-derived key';

  @override
  String get channelsRandomKey => 'Randomly generated key';

  @override
  String get channelsPublicKeyInfo =>
      'This key is public and identical on all MeshCore devices';

  @override
  String get channelsHashtagKeyInfo =>
      'Anyone who enters the same hashtag will automatically have this key';

  @override
  String get channelsRandomKeyInfo =>
      'Save this key or share the QR Code to invite others';

  @override
  String get channelsRegenerateKey => 'Regenerate key';

  @override
  String get channelsEmpty => 'No channels';

  @override
  String get channelsEmptyHint =>
      'Channels configured on the radio appear here';

  @override
  String get channelsRefresh => 'Refresh Channels';

  @override
  String get channelsAllRead => 'All read';

  @override
  String get channelsAllReadHint => 'No unread messages in channels';

  @override
  String get channelsSeeAll => 'See all channels';

  @override
  String get channelsMsgSuffix => 'msg';

  @override
  String get channelsOptionsFabTooltip => 'Channel options';

  @override
  String get channelsClearHistoryConfirm =>
      'Delete all messages in this channel? This action cannot be undone';

  @override
  String get channelsEditSheet => 'Edit channel';

  @override
  String get channelsQRTitle => 'Channel QR Code';

  @override
  String get channelsShowQR => 'Show channel QR Code';

  @override
  String get channelsQRDesc =>
      'Share this QR Code to grant access to the channel';

  @override
  String get channelsShareText => 'Share text';

  @override
  String get channelsShareQR => 'Share QR';

  @override
  String get channelsRemovePublicTitle => 'Remove Public Channel?';

  @override
  String get channelsRemovePublicWarning =>
      'You are about to remove the Public Channel. This is the main channel shared by the MeshCore community. Are you sure?';

  @override
  String get channelsRemoveAnyway => 'Remove anyway';

  @override
  String get channelsRemoveTitle => 'Remove channel';

  @override
  String get channelsRemoveConfirm => 'Are you sure you want to remove';

  @override
  String get channelsRemoveWarning => 'This action cannot be undone.';

  @override
  String get channelsMuteTitle => 'Channel muted';

  @override
  String get channelsUnmuteTitle => 'Notifications active';

  @override
  String get channelsMuteSubtitleOn => 'No alerts — unread badge still shown';

  @override
  String get channelsMuteSubtitleOff =>
      'Receives notifications and unread badge';

  @override
  String get channelsMuteLabel => 'muted';

  @override
  String get chatMuteChannel => 'Mute channel';

  @override
  String get chatUnmuteChannel => 'Unmute channel';

  @override
  String get chatNoMessages => 'No messages in this channel';

  @override
  String get chatSendFirstMessage => 'Send the first message!';

  @override
  String get chatInputHint => 'Message to channel...';

  @override
  String get chatRepeater => 'Repeater';

  @override
  String get chatRepeaters => 'Repeaters';

  @override
  String get chatMsgCount => 'messages';

  @override
  String get chatHeard => 'Heard';

  @override
  String get chatOnce => 'time';

  @override
  String get chatTimes => 'times by repeaters';

  @override
  String get chatViaRepeaters => 'Received via repeaters';

  @override
  String get chatAuthenticatedMessage => 'Authenticated';

  @override
  String get chatMsgDetails => 'Message details';

  @override
  String get chatRetry => 'Retry';

  @override
  String get chatFailed => 'Failed';

  @override
  String get chatPathLabel => 'Path';

  @override
  String get chatHeardCount => 'Heard';

  @override
  String get chatTimesCount => 'times';

  @override
  String get chatPathExplanation =>
      'Each path represents one time your radio heard the message back';

  @override
  String get chatPathInstruction => 'Tap a path to see the full route';

  @override
  String get chatNoPathData =>
      'Path data is not available. Reconnect the radio to log new paths';

  @override
  String get chatViewOnMap => 'View on map';

  @override
  String get chatYourRadio => 'Your radio';

  @override
  String get chatYouSent => 'You sent the message';

  @override
  String get chatReceived => 'Received the message';

  @override
  String get chatHopLabel => 'Hop';

  @override
  String get chatRepeated => 'Repeated';

  @override
  String get chatHashtagChannel =>
      'Hashtag channel — anyone with the name can join';

  @override
  String get chatKeyLabel => 'Key:';

  @override
  String get chatCreateJoinChannel => 'Create and join channel';

  @override
  String get chatNoChannelSlots => 'No slots available for new channels';

  @override
  String get chatDeleteMessage => 'Delete message';

  @override
  String get chatMenuOptions => 'Channel options';

  @override
  String get chatNewMessages => 'New messages';

  @override
  String get chatPingButton => '!ping';

  @override
  String get chatViewResultOnline => 'view result online';

  @override
  String get connectTitle => 'MeshCore Portugal';

  @override
  String get connectReconnect => 'Reconnect';

  @override
  String get connectContinueOffline => 'Continue offline';

  @override
  String get connectSearchDevices => 'Search Devices';

  @override
  String get connectSearching => 'Searching...';

  @override
  String get connectBrowserNote =>
      'The browser will show a Bluetooth device selector';

  @override
  String get connectScanningMessage => 'Searching for MeshCore radios...';

  @override
  String get connectTapHint => 'Tap \"Search\" to find devices';

  @override
  String get connectDeviceBLE => '(Bluetooth LE)';

  @override
  String get connectDeviceUSB => '(USB Serial — Companion)';

  @override
  String get connectDeviceKISS => '(KISS TNC)';

  @override
  String get connectStepConnecting => 'Connecting...';

  @override
  String get connectStepWaiting => 'Waiting for radio...';

  @override
  String get connectStepDeviceInfo => 'Device information';

  @override
  String get connectStepContacts => 'Contacts';

  @override
  String get connectStepChannels => 'Channels';

  @override
  String get connectStepDone => 'Done';

  @override
  String get connectBluetoothOffTitle => 'Bluetooth off';

  @override
  String get connectBluetoothOffMessage =>
      'Bluetooth is off. Would you like to enable it to connect to the MeshCore radio?';

  @override
  String get connectBluetoothEnable => 'Enable';

  @override
  String get connectBluetoothDeniedTitle => 'Bluetooth activation denied';

  @override
  String get connectBluetoothDeniedMessage =>
      'Please enable Bluetooth in system Settings';

  @override
  String get connectBluetoothOff =>
      'Bluetooth off. Enable Bluetooth to search for devices';

  @override
  String get connectBluetoothPermission =>
      'Bluetooth permissions required to search for devices';

  @override
  String get connectOpenSettings => 'Settings';

  @override
  String get connectFailTitle => 'Failed to connect to device';

  @override
  String get connectLastFailTitle => 'Failed to connect to last device';

  @override
  String get discoverTitle => 'Discover';

  @override
  String get discoverSubtitle => 'Recent Adverts';

  @override
  String get discoverSearchHint => 'Search discovered contacts...';

  @override
  String get discoverEmpty => 'No contacts found';

  @override
  String get discoverEmptyHint => 'Try a different search';

  @override
  String get discoverNone => 'No contacts discovered';

  @override
  String get discoverNoneHint =>
      'Contacts appear while transmitting on the network';

  @override
  String get discoverCleanTooltip => 'Clean local-only contacts';

  @override
  String get discoverCleanSheetTitle => 'Clean local-only contacts';

  @override
  String get discoverCleanSheetSubtitle =>
      'Pick which discovered contacts to remove. Contacts stored on the radio are always kept.';

  @override
  String get discoverCleanOption48h => 'Not heard in 48 hours';

  @override
  String get discoverCleanOption7d => 'Not heard in 7 days';

  @override
  String get discoverCleanOption30d => 'Not heard in 30 days';

  @override
  String get discoverCleanOptionNever => 'Never heard (no advert)';

  @override
  String get discoverCleanOptionAll => 'All local-only contacts';

  @override
  String get discoverCleanTitle => 'Clean discovered contacts?';

  @override
  String discoverCleanBody(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n contacts',
      one: '1 contact',
    );
    return 'This will remove $_temp0 that are not stored on the radio. Contacts saved on the radio are kept.';
  }

  @override
  String get discoverCleanNothing =>
      'All discovered contacts are saved on the radio. Nothing to clean.';

  @override
  String discoverCleanDone(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: 'Removed $n contacts',
      one: 'Removed 1 contact',
    );
    return '$_temp0';
  }

  @override
  String get discoverSaveToRadio => 'Save to radio';

  @override
  String get discoverSendMessage => 'Send message';

  @override
  String get discoverJoinRoom => 'Join room';

  @override
  String get discoverAddAndSave => 'Add and save';

  @override
  String get discoverAnnouncedName => 'Announced Name';

  @override
  String get discoverHeard => 'Heard';

  @override
  String get discoverNever => 'Never';

  @override
  String get discoverNoName => 'No name';

  @override
  String get discoverTypeCompanion => 'Companion';

  @override
  String get discoverTypeUnknown => 'Unknown';

  @override
  String get discoverPathNear => 'Nearby';

  @override
  String get discoverJustNow => 'Just now';

  @override
  String discoverMinutesAgo(int min) {
    return '${min}m ago';
  }

  @override
  String discoverHoursAgo(int hours) {
    return '${hours}h ago';
  }

  @override
  String discoverDaysAgo(int days) {
    return '${days}d ago';
  }

  @override
  String get appsPlano333Title => 'Plan 3-3-3';

  @override
  String get appsPlano333Subtitle => 'Weekly MeshCore event';

  @override
  String get appsTelemetryTitle => 'Telemetry';

  @override
  String get appsTelemetrySubtitle => 'Battery, RF and counters';

  @override
  String get appsRxLogTitle => 'RX Log';

  @override
  String get appsRxLogSubtitle => 'Capture and export PCAP';

  @override
  String get appsQrTitle => 'QR Reader';

  @override
  String get appsQrSubtitle => 'Scan QR code';

  @override
  String get mapNoGps =>
      'No GPS data. Tap \"Locate\" or wait for contacts with coordinates';

  @override
  String get mapShareMap => 'Share map';

  @override
  String get mapViewAll => 'View all';

  @override
  String get mapCenterMyPosition => 'Center on my position';

  @override
  String get mapGetGps => 'Get GPS location';

  @override
  String get mapLocationDisabled => 'Location service disabled';

  @override
  String get mapLocationDenied => 'Location permission denied';

  @override
  String get mapLocationDeniedPermanently =>
      'Location permission permanently denied';

  @override
  String get mapLocationError => 'Error getting GPS location';

  @override
  String get mapCaptureError => 'Could not capture the map';

  @override
  String get mapImageError => 'Failed to generate map image';

  @override
  String get mapShareError => 'Error sharing map';

  @override
  String get mapNodesAtLocation => 'nodes at this location';

  @override
  String get mapMinimizeList => 'Minimize list';

  @override
  String get mapShowMore => 'Show +';

  @override
  String get mapHops => 'hop(s)';

  @override
  String get mapFinal => 'Final:';

  @override
  String get mapAttribution => 'MeshCore Portugal';

  @override
  String get mapAttributionOSM => '© OpenStreetMap contributors';

  @override
  String get mapPathPrefix => 'Path ·';

  @override
  String get privateNoMessages => 'No messages';

  @override
  String get privateSendFirstMessage => 'Send the first message!';

  @override
  String privateMessageTo(String name) {
    return 'Message to $name...';
  }

  @override
  String privateTracingRoute(String name) {
    return 'Tracing route to $name';
  }

  @override
  String get privateRouteFailed =>
      'Could not discover route — please try again';

  @override
  String get privateRouteNoResponse => 'No route response — please try again';

  @override
  String get privateRouteFound => 'Route found —';

  @override
  String get privateDirectRoute => 'Direct route (no repeaters)';

  @override
  String get privateReceivedOnRadio => 'Received on radio';

  @override
  String get privateConfirmed => 'Confirmed';

  @override
  String get privatePending => 'Pending';

  @override
  String get privateSentVia => 'Sent via';

  @override
  String get privateTraceRoute => 'Trace route';

  @override
  String get privateManagePath => 'Manage path';

  @override
  String get privateContactLabel => 'Contact';

  @override
  String get qrTitle => 'Read QR Code';

  @override
  String get qrUnavailable => 'QR Code scanner not available on this platform';

  @override
  String get qrUnavailableHint => 'Use an Android or iOS device';

  @override
  String get qrHint => 'Point at a MeshCore QR Code';

  @override
  String get radioSettingsTitle => 'Radio Configuration';

  @override
  String get radioSettingsDevice => 'Device';

  @override
  String get radioSettingsModel => 'Model';

  @override
  String get radioSettingsFirmware => 'Firmware';

  @override
  String get radioSettingsStorage => 'Storage';

  @override
  String get radioSettingsChannels => 'Channels';

  @override
  String get radioSettingsContacts => 'Contacts';

  @override
  String get radioSettingsDiscovered => 'Discovered';

  @override
  String get radioSettingsAppVersion => 'App Version';

  @override
  String get radioSettingsLoRa => 'LoRa Parameters';

  @override
  String get radioSettingsFrequency => 'Frequency (MHz)';

  @override
  String get radioSettingsFreqLabel => 'Frequency';

  @override
  String get radioSettingsFrequencyHint => 'e.g.: 868.1250';

  @override
  String get radioSettingsBandwidth => 'Bandwidth';

  @override
  String get radioSettingsSpreadingFactor => 'Spreading Factor';

  @override
  String get radioSettingsCodingRate => 'Coding Rate';

  @override
  String get radioSettingsTxPower => 'TX Power';

  @override
  String get radioSettingsMax => 'Max:';

  @override
  String get radioSettingsDbm => 'dBm';

  @override
  String get radioSettingsFrequencyRequired => 'Enter the frequency';

  @override
  String get radioSettingsFrequencyInvalid =>
      'Invalid frequency (150–2500 MHz)';

  @override
  String get radioSettingsBandwidthRequired => 'Select the bandwidth';

  @override
  String get radioSettingsSFRequired => 'Select the spreading factor';

  @override
  String get radioSettingsCRRequired => 'Select the coding rate';

  @override
  String get radioSettingsPowerRequired => 'Enter the power';

  @override
  String get radioSettingsPowerInvalid => 'Invalid power (1–30 dBm)';

  @override
  String get radioSettingsActiveConfig => 'Active Configuration';

  @override
  String get radioSettingsSaved => 'Configuration saved';

  @override
  String get radioSettingsPrivKeyCopied => 'Private key copied';

  @override
  String get radioSettingsResetValues => 'Reset to current values';

  @override
  String get radioSettingsAutoAddTitle => 'Contact Settings';

  @override
  String get radioSettingsAutoAddDesc =>
      'When a node sends an advert and the radio is in manual mode, automatically add as:';

  @override
  String get radioSettingsAutoAddAll => 'Auto Add All';

  @override
  String get radioSettingsAutoAddAllDesc =>
      'When enabled, all received adverts will be added to contacts.';

  @override
  String get radioSettingsAutoAddSelected => 'Auto Add Selected';

  @override
  String get radioSettingsAutoAddSelectedDesc =>
      'When enabled, only contact types selected below will be auto added to contacts.';

  @override
  String get radioSettingsAutoAddCompanion => 'Companion (Chat)';

  @override
  String get radioSettingsAutoAddRepeater => 'Repeater';

  @override
  String get radioSettingsAutoAddRoom => 'Room';

  @override
  String get radioSettingsAutoAddSensor => 'Sensor';

  @override
  String get radioSettingsOverwriteOldest => 'Overwrite Oldest';

  @override
  String get radioSettingsOverwriteOldestDesc =>
      'When enabled, oldest non-favourite contacts are overwritten with new contacts when contacts list is full.';

  @override
  String get radioSettingsAutoAddMaxHops => 'Auto Add Max Hops';

  @override
  String get radioSettingsAutoAddMaxHopsDesc =>
      'Contacts will only be auto added if their advert path has the same or less hops as the configured limit. Leave this field blank for no limit.';

  @override
  String get radioSettingsAutoAddMaxHopsHint => 'Max Hops (0-63)';

  @override
  String get radioSettingsPullToRefresh => 'Pull To Refresh';

  @override
  String get radioSettingsPullToRefreshDesc =>
      'When enabled, you can swipe down to refresh the contacts list.';

  @override
  String get radioSettingsShowPublicKeys => 'Show Public Keys';

  @override
  String get radioSettingsShowPublicKeysDesc =>
      'When enabled, public keys will be shown in contacts list.';

  @override
  String get radioSettingsBandPresetsTitle => 'Band Presets';

  @override
  String get roomJoinTitle => 'Join room';

  @override
  String get roomJoinInstruction =>
      'This room may require a password. Leave blank if public.';

  @override
  String get roomPasswordLabel => 'Password (optional)';

  @override
  String get roomPasswordHint => 'Leave blank if no password';

  @override
  String get roomJoinFailed => 'Failed — check the password';

  @override
  String get roomJoining => 'Connecting...';

  @override
  String get roomJoinError =>
      'Could not join the room. Check the password and try again.';

  @override
  String get roomReplyStrip => 'Room';

  @override
  String roomMessageHint(String name) {
    return 'Message to $name room...';
  }

  @override
  String get roomMessageFallback => 'Write a message...';

  @override
  String get roomTelemetryData => 'Telemetry data';

  @override
  String get rxLogTitle => 'RX Log';

  @override
  String get rxLogExportPcap => 'Export PCAPNG';

  @override
  String get rxLogClearLog => 'Clear log';

  @override
  String get rxLogPacketCount => 'packets captured';

  @override
  String get rxLogClearTitle => 'Clear RX Log';

  @override
  String get rxLogClearConfirm => 'Remove all captured packets?';

  @override
  String get rxLogEmpty => 'RX Log empty - nothing to export';

  @override
  String get rxLogExportFail => 'Failed to export PCAPNG';

  @override
  String get rxLogPacketAdvert => 'Advert';

  @override
  String get rxLogPacketGroupText => 'Group Text';

  @override
  String get rxLogPacketPrivateText => 'Private Text';

  @override
  String get rxLogPacketPath => 'Path';

  @override
  String get rxLogPacketControl => 'Control';

  @override
  String get rxLogPacketTypePrefix => 'Type';

  @override
  String get rxLogEmptyTitle => 'No RX packets';

  @override
  String get rxLogEmptyHint =>
      'When the radio receives mesh traffic, packets appear here.';

  @override
  String get telemetryBattery => 'Battery';

  @override
  String get telemetryNetStats => 'Network Statistics';

  @override
  String get telemetryRadioState => 'Radio — State';

  @override
  String get telemetryRadioWaiting => 'Waiting for radio statistics...';

  @override
  String get telemetryRadioRF => 'Radio — RF';

  @override
  String get telemetryRFWaiting => 'Waiting for RF statistics...';

  @override
  String get telemetryPacketCounters => 'Radio — Packet Counters';

  @override
  String get telemetryCountersWaiting => 'Waiting for packet counters...';

  @override
  String get telemetrySensors => 'Sensors (Telemetry)';

  @override
  String get telemetryNoData => 'No telemetry received.';

  @override
  String get telemetrySamplesSuffix => 'samples';

  @override
  String get telemetryNow => 'Now';

  @override
  String get telemetryHistoryHint =>
      'History appears after the first battery reading.';

  @override
  String get telemetryRX => 'RX';

  @override
  String get telemetryTX => 'TX';

  @override
  String get telemetryHeard => 'Heard';

  @override
  String get telemetryCardPrefix => 'Telemetry —';

  @override
  String get telemetryUptime => 'Uptime';

  @override
  String get telemetryTxQueue => 'TX Queue';

  @override
  String get telemetryErrorsPrefix => 'Errors:';

  @override
  String get telemetryRSSI => 'RSSI';

  @override
  String get telemetryNoise => 'Noise';

  @override
  String get telemetrySNR => 'SNR';

  @override
  String get telemetryAirtimeTX => 'Airtime TX';

  @override
  String get telemetryAirtimeRX => 'Airtime RX';

  @override
  String get telemetryErrors => 'Errors';

  @override
  String get telemetryRXTotal => 'RX Total';

  @override
  String get telemetryTXTotal => 'TX Total';

  @override
  String get telemetryErrorsRX => 'RX Errors';

  @override
  String get telemetryFloodTX => 'Flood TX';

  @override
  String get telemetryFloodRX => 'Flood RX';

  @override
  String get telemetryDirectTX => 'Direct TX';

  @override
  String get telemetryDirectRX => 'Direct RX';

  @override
  String get eventTitle => 'Event Program';

  @override
  String get eventDateLabel => 'April 2026';

  @override
  String get eventSummitTitle => 'Tech Summit 2026';

  @override
  String get eventSummitSubtitle => 'MeshCore Portugal';

  @override
  String get eventMorning => 'Morning';

  @override
  String get eventAfternoon => 'Afternoon';

  @override
  String get eventWorkshops => 'Workshops (parallel room)';

  @override
  String get eventAddChannel => 'Add';

  @override
  String get eventChannelSheetTitle => 'MeshCore Channel  #plano333';

  @override
  String get eventChannelSheetDesc =>
      'Add the channel to the connected radio or consult the data manually.';

  @override
  String eventChannelAdded(int slot) {
    return 'Channel #plano333 added in slot $slot';
  }

  @override
  String get eventChannelNotFound =>
      'Channel #techsummit2026 not found on radio.';

  @override
  String get eventChannelNoSlots =>
      'No channel slots available to add #techsummit2026.';

  @override
  String get plan333CardTitle => 'MESH 3-3-3';

  @override
  String get plan333EventActive => '● EVENT ACTIVE';

  @override
  String get plan333PhaseCQ => 'CQ 21:00–22:00';

  @override
  String get plan333CqSent => 'CQ sent:';

  @override
  String get plan333LastSent => '(last:';

  @override
  String get plan333EventSchedule =>
      'Saturdays 21:00–22:00  •  CQ MeshCore Presence';

  @override
  String get plan333ReportPrefix => 'Report at';

  @override
  String get plan333ConfigTitle => 'Event Configuration';

  @override
  String get plan333StationName => 'Station name *';

  @override
  String get plan333StationNameHint => 'e.g.: Mike 05';

  @override
  String get plan333City => 'City *';

  @override
  String get plan333CityHint => 'e.g.: Lisbon';

  @override
  String get plan333Locality => 'Locality';

  @override
  String get plan333LocalityHint => 'e.g.: Olaias';

  @override
  String get plan333AutoSend => 'Automatic CQ sending';

  @override
  String get plan333AutoSendDesc => 'CQ: up to 3 messages (21:00–22:00)';

  @override
  String get plan333CqMessageLabel => 'CQ Message:';

  @override
  String get plan333FormatTitle => 'Message Formats';

  @override
  String get plan333FormatPresence => 'Presence (CQ)';

  @override
  String get plan333FormatPresencePhase => 'MeshCore 21:00–22:00';

  @override
  String get plan333FormatCqTemplate =>
      'CQ Plan 333, [Name], [City], [Locality]';

  @override
  String get plan333ConfigureChannel =>
      'Configure MeshCore Channel  (#plano333)';

  @override
  String get plan333Alerts => 'Mesh 3-3-3 Alerts';

  @override
  String get plan333AlertToggle => 'Saturday event reminder';

  @override
  String get plan333AlertDesc =>
      'Alerts 10 and 5 min before Mesh 3-3-3 (Saturdays 21:00)';

  @override
  String get plan333AlertsActive => 'Alerts active at 20:50 and 20:55.';

  @override
  String get plan333StationsHeard => 'Heard Stations';

  @override
  String get plan333ShareLog => 'Share log';

  @override
  String get plan333ClearLog => 'Clear log';

  @override
  String get plan333NoStationsYet =>
      'No stations heard yet. CQs received on the channel appear here automatically.';

  @override
  String get plan333ClearQslTitle => 'Clear log?';

  @override
  String get plan333ClearQslContent => 'All logged stations will be deleted.';

  @override
  String get plan333AddQslTitle => 'Add station';

  @override
  String get plan333StationLabel => 'Station *';

  @override
  String get plan333StationHint => 'e.g.: Daytona';

  @override
  String get plan333HopsLabel => 'Hops:';

  @override
  String get plan333DirectOption => 'Direct';

  @override
  String get plan333LocationLabel => 'Location';

  @override
  String get plan333LocationHint => 'e.g.: Tomar';

  @override
  String get plan333NotesLabel => 'Notes (optional)';

  @override
  String get plan333AbortAutoSend => 'Abort auto-send';

  @override
  String get plan333AbortedMessage =>
      'Automation aborted — no more sends this session.';

  @override
  String plan333SendCqButton(int count) {
    return 'SEND CQ  ($count/3)';
  }

  @override
  String get plan333AllSent => '✓  3 CQs sent';

  @override
  String get plan333ConfigureFirst => 'Configure your data first';

  @override
  String get plan333RadioOff => 'Radio off — cannot send';

  @override
  String get plan333ChannelSheetTitle => 'MeshCore Channel  #plano333';

  @override
  String get plan333ChannelSheetDesc =>
      'Add the channel to the connected radio or consult the data manually.';

  @override
  String plan333ChannelAdded(int slot) {
    return 'Channel #plano333 added in slot $slot';
  }

  @override
  String get signalNone => 'No signal (no packets in last 5 min)';

  @override
  String get signalWeak => 'Very weak signal';

  @override
  String get signalFair => 'Weak signal';

  @override
  String get signalGood => 'Good signal';

  @override
  String get signalExcellent => 'Excellent signal';

  @override
  String get urlOpenTitle => 'Open external link?';

  @override
  String get urlOpenConfirm => 'Open';

  @override
  String get topologyScreenTitle => 'Network Topology';

  @override
  String get topologyTabGraph => 'Graph';

  @override
  String get topologyTabTimeline => 'Timeline';

  @override
  String get topologyEmptyTitle => 'No topology data';

  @override
  String get topologyEmptyHint =>
      'Connect to a radio to\nvisualize the network';

  @override
  String get topologySelf => 'Me';

  @override
  String get topologyResetView => 'Reset view';

  @override
  String get topologySnrGood => 'SNR ≥ 5 dB';

  @override
  String get topologySnrMid => 'SNR 0–5 dB';

  @override
  String get topologySnrBad => 'SNR < 0 dB';

  @override
  String get topologyLabelId => 'ID';

  @override
  String get topologyLabelPath => 'Path';

  @override
  String get topologyLabelSeen => 'Seen';

  @override
  String topologySecondsAgo(int s) {
    return '${s}s ago';
  }

  @override
  String topologyMinutesAgo(int min) {
    return '${min}min ago';
  }

  @override
  String topologyHoursAgo(int h) {
    return '${h}h ago';
  }

  @override
  String topologyDaysAgo(int d) {
    return '${d}d ago';
  }

  @override
  String topologyWeeksAgo(int w) {
    return '${w}w ago';
  }

  @override
  String get topologyFilterRecent => 'Show only contacts on radio';

  @override
  String get topologyFilterAll => 'Show all (including local-only)';

  @override
  String get topologyToggleLabels => 'Toggle labels';

  @override
  String topologyNodesShown(int shown, int total) {
    return '$shown/$total nodes';
  }

  @override
  String get topologyHopDirect => 'Direct';

  @override
  String get topologyHop1 => '1 hop';

  @override
  String get topologyHop2 => '2 hops';

  @override
  String get topologyHopFlood => 'Flood / 3+';

  @override
  String get topologyTabPaths => 'Paths';

  @override
  String get topologyPathsEmptyTitle => 'No path data';

  @override
  String get topologyPathsEmptyHint =>
      'Run a trace from a contact\nto see its routing path';

  @override
  String topologyPathsCount(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n paths',
      one: '1 path',
    );
    return '$_temp0';
  }

  @override
  String get repeaterTitle => 'Manage Repeater';

  @override
  String get repeaterConfig => 'Remote Configuration';

  @override
  String get repeaterApply => 'Apply';

  @override
  String get repeaterNodeName => 'Node name';

  @override
  String get repeaterTxPower => 'TX Power';

  @override
  String get repeaterForwarding => 'Packet forwarding';

  @override
  String get repeaterForwardingDesc => 'Enable or disable packet forwarding';

  @override
  String get repeaterAdvertInterval => 'Local advert interval';

  @override
  String get repeaterAdvertZeroHop => 'Auto Advert (Zero Hop)';

  @override
  String get repeaterAdvertFlood => 'Auto Advert (Flood)';

  @override
  String get repeaterIntervalMinutes => 'Interval (minutes)';

  @override
  String get repeaterIntervalHours => 'Interval (hours)';

  @override
  String get repeaterMinimalTrafficHint =>
      'To use minimal mesh traffic, please use the refresh icons to request the info you need.';

  @override
  String get repeaterValueNotLoaded => '—';

  @override
  String get repeaterFloodMax => 'Max flood hops';

  @override
  String get repeaterClearStats => 'Clear Statistics';

  @override
  String get repeaterClearStatsDesc => 'Resets packet and error counters';

  @override
  String get repeaterNoStats =>
      'Authenticate and press \"Refresh\" to fetch repeater statistics.';

  @override
  String get repeaterFetchStats => 'Refresh';

  @override
  String get repeaterAuthenticated => 'Authenticated';

  @override
  String get repeaterTabStatus => 'Status';

  @override
  String get repeaterTabCommandLine => 'Command Line';

  @override
  String get repeaterTabSettings => 'Settings';

  @override
  String get repeaterCmdHint => 'Send a command...';

  @override
  String get repeaterCmdEmpty =>
      'No commands sent yet. Use the input below to send raw CLI commands.';

  @override
  String get repeaterCmdClear => 'Clear history';

  @override
  String get repeaterMenuHelp => 'Command Help';

  @override
  String get repeaterMenuClearHistory => 'Delete Command History';

  @override
  String get repeaterHelpTitle => 'Help';

  @override
  String get repeaterHelpSubtitle => 'Repeater Commands';

  @override
  String get repeaterHelpFirmwareNote =>
      'Some commands require the latest firmware.';

  @override
  String get repeaterHelpSearchHint => 'Search';

  @override
  String get dataExportTitle => 'Data Export';

  @override
  String get dataExportContactsTitle => 'Contacts';

  @override
  String dataExportContactsDesc(int count) {
    return '$count contacts stored';
  }

  @override
  String get dataExportMessagesTitle => 'Messages';

  @override
  String get dataExportMessagesDesc => 'All conversations — private & channels';

  @override
  String get dataExportKmlTitle => 'Map Data';

  @override
  String dataExportKmlDesc(int count) {
    return '$count contacts with GPS';
  }

  @override
  String get dataExportNote =>
      'Files are exported directly to the share sheet.\nNo data leaves the device unless you choose to share it.';

  @override
  String get dataExportNoContacts => 'No contacts to export';

  @override
  String get dataExportNoMessages => 'No messages to export';

  @override
  String get dataExportNoGps => 'No contacts with GPS coordinates';

  @override
  String get dataExportFailed => 'Export failed';

  @override
  String get appsDataExportTitle => 'Data Export';

  @override
  String get appsDataExportSubtitle => 'Export contacts, messages & map data';
}
