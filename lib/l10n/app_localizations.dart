import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_es.dart';
import 'app_localizations_pt.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('es'),
    Locale('pt'),
  ];

  /// No description provided for @navChannels.
  ///
  /// In pt, this message translates to:
  /// **'Canais'**
  String get navChannels;

  /// No description provided for @navContacts.
  ///
  /// In pt, this message translates to:
  /// **'Contactos'**
  String get navContacts;

  /// No description provided for @navMap.
  ///
  /// In pt, this message translates to:
  /// **'Mapa'**
  String get navMap;

  /// No description provided for @navApps.
  ///
  /// In pt, this message translates to:
  /// **'Apps'**
  String get navApps;

  /// No description provided for @navSettings.
  ///
  /// In pt, this message translates to:
  /// **'Definições'**
  String get navSettings;

  /// No description provided for @commonSave.
  ///
  /// In pt, this message translates to:
  /// **'Guardar'**
  String get commonSave;

  /// No description provided for @commonSaving.
  ///
  /// In pt, this message translates to:
  /// **'A guardar...'**
  String get commonSaving;

  /// No description provided for @commonCancel.
  ///
  /// In pt, this message translates to:
  /// **'Cancelar'**
  String get commonCancel;

  /// No description provided for @commonClear.
  ///
  /// In pt, this message translates to:
  /// **'Limpar'**
  String get commonClear;

  /// No description provided for @commonDelete.
  ///
  /// In pt, this message translates to:
  /// **'Apagar'**
  String get commonDelete;

  /// No description provided for @commonClose.
  ///
  /// In pt, this message translates to:
  /// **'Fechar'**
  String get commonClose;

  /// No description provided for @commonBack.
  ///
  /// In pt, this message translates to:
  /// **'Voltar'**
  String get commonBack;

  /// No description provided for @commonRemove.
  ///
  /// In pt, this message translates to:
  /// **'Remover'**
  String get commonRemove;

  /// No description provided for @commonAdd.
  ///
  /// In pt, this message translates to:
  /// **'Adicionar'**
  String get commonAdd;

  /// No description provided for @commonEdit.
  ///
  /// In pt, this message translates to:
  /// **'Editar'**
  String get commonEdit;

  /// No description provided for @commonShare.
  ///
  /// In pt, this message translates to:
  /// **'Partilhar'**
  String get commonShare;

  /// No description provided for @commonCopy.
  ///
  /// In pt, this message translates to:
  /// **'Copiar'**
  String get commonCopy;

  /// No description provided for @commonRename.
  ///
  /// In pt, this message translates to:
  /// **'Renomear'**
  String get commonRename;

  /// No description provided for @commonConfirm.
  ///
  /// In pt, this message translates to:
  /// **'Confirmar'**
  String get commonConfirm;

  /// No description provided for @commonError.
  ///
  /// In pt, this message translates to:
  /// **'Erro'**
  String get commonError;

  /// No description provided for @commonErrors.
  ///
  /// In pt, this message translates to:
  /// **'Erros'**
  String get commonErrors;

  /// No description provided for @commonYes.
  ///
  /// In pt, this message translates to:
  /// **'Sim'**
  String get commonYes;

  /// No description provided for @commonNo.
  ///
  /// In pt, this message translates to:
  /// **'Não'**
  String get commonNo;

  /// No description provided for @commonOk.
  ///
  /// In pt, this message translates to:
  /// **'Ok'**
  String get commonOk;

  /// No description provided for @commonLoading.
  ///
  /// In pt, this message translates to:
  /// **'A carregar...'**
  String get commonLoading;

  /// No description provided for @commonSearch.
  ///
  /// In pt, this message translates to:
  /// **'Pesquisar'**
  String get commonSearch;

  /// No description provided for @commonAll.
  ///
  /// In pt, this message translates to:
  /// **'Todos'**
  String get commonAll;

  /// No description provided for @commonUnread.
  ///
  /// In pt, this message translates to:
  /// **'Não lidos'**
  String get commonUnread;

  /// No description provided for @commonDetails.
  ///
  /// In pt, this message translates to:
  /// **'Detalhes'**
  String get commonDetails;

  /// No description provided for @commonReply.
  ///
  /// In pt, this message translates to:
  /// **'Responder'**
  String get commonReply;

  /// No description provided for @commonCopyText.
  ///
  /// In pt, this message translates to:
  /// **'Copiar texto'**
  String get commonCopyText;

  /// No description provided for @commonNoMessages.
  ///
  /// In pt, this message translates to:
  /// **'Sem mensagens'**
  String get commonNoMessages;

  /// No description provided for @commonSendFirstMessage.
  ///
  /// In pt, this message translates to:
  /// **'Envie a primeira mensagem!'**
  String get commonSendFirstMessage;

  /// No description provided for @commonSendMessage.
  ///
  /// In pt, this message translates to:
  /// **'Enviar mensagem'**
  String get commonSendMessage;

  /// No description provided for @commonNoData.
  ///
  /// In pt, this message translates to:
  /// **'Sem dados'**
  String get commonNoData;

  /// No description provided for @commonMessageCopied.
  ///
  /// In pt, this message translates to:
  /// **'Mensagem copiada'**
  String get commonMessageCopied;

  /// No description provided for @commonSent.
  ///
  /// In pt, this message translates to:
  /// **'Enviada'**
  String get commonSent;

  /// No description provided for @commonSentByMe.
  ///
  /// In pt, this message translates to:
  /// **'Eu'**
  String get commonSentByMe;

  /// No description provided for @commonPropagating.
  ///
  /// In pt, this message translates to:
  /// **'A propagar...'**
  String get commonPropagating;

  /// No description provided for @commonConnecting.
  ///
  /// In pt, this message translates to:
  /// **'A ligar...'**
  String get commonConnecting;

  /// No description provided for @commonSearching.
  ///
  /// In pt, this message translates to:
  /// **'A procurar...'**
  String get commonSearching;

  /// No description provided for @commonAuthenticated.
  ///
  /// In pt, this message translates to:
  /// **'Autenticado'**
  String get commonAuthenticated;

  /// No description provided for @commonDirect.
  ///
  /// In pt, this message translates to:
  /// **'Direto'**
  String get commonDirect;

  /// No description provided for @commonFlood.
  ///
  /// In pt, this message translates to:
  /// **'Flood'**
  String get commonFlood;

  /// No description provided for @commonBattery.
  ///
  /// In pt, this message translates to:
  /// **'Bateria'**
  String get commonBattery;

  /// No description provided for @commonStatus.
  ///
  /// In pt, this message translates to:
  /// **'Estado'**
  String get commonStatus;

  /// No description provided for @commonPath.
  ///
  /// In pt, this message translates to:
  /// **'Caminho'**
  String get commonPath;

  /// No description provided for @commonTime.
  ///
  /// In pt, this message translates to:
  /// **'Hora'**
  String get commonTime;

  /// No description provided for @commonName.
  ///
  /// In pt, this message translates to:
  /// **'Nome'**
  String get commonName;

  /// No description provided for @commonChannel.
  ///
  /// In pt, this message translates to:
  /// **'Canal'**
  String get commonChannel;

  /// No description provided for @commonContact.
  ///
  /// In pt, this message translates to:
  /// **'Contacto'**
  String get commonContact;

  /// No description provided for @commonRoom.
  ///
  /// In pt, this message translates to:
  /// **'Sala'**
  String get commonRoom;

  /// No description provided for @commonRooms.
  ///
  /// In pt, this message translates to:
  /// **'Salas'**
  String get commonRooms;

  /// No description provided for @commonSensor.
  ///
  /// In pt, this message translates to:
  /// **'Sensor'**
  String get commonSensor;

  /// No description provided for @commonSensors.
  ///
  /// In pt, this message translates to:
  /// **'Sensores'**
  String get commonSensors;

  /// No description provided for @commonRepeater.
  ///
  /// In pt, this message translates to:
  /// **'Repetidor'**
  String get commonRepeater;

  /// No description provided for @commonRepeaters.
  ///
  /// In pt, this message translates to:
  /// **'Repetidores'**
  String get commonRepeaters;

  /// No description provided for @commonType.
  ///
  /// In pt, this message translates to:
  /// **'Tipo'**
  String get commonType;

  /// No description provided for @commonHops.
  ///
  /// In pt, this message translates to:
  /// **'Saltos'**
  String get commonHops;

  /// No description provided for @commonFavorites.
  ///
  /// In pt, this message translates to:
  /// **'Favoritos'**
  String get commonFavorites;

  /// No description provided for @commonTelemetry.
  ///
  /// In pt, this message translates to:
  /// **'Telemetria'**
  String get commonTelemetry;

  /// No description provided for @commonSettings.
  ///
  /// In pt, this message translates to:
  /// **'Definições'**
  String get commonSettings;

  /// No description provided for @commonRadioDisconnected.
  ///
  /// In pt, this message translates to:
  /// **'Rádio não ligado'**
  String get commonRadioDisconnected;

  /// No description provided for @commonConfiguring.
  ///
  /// In pt, this message translates to:
  /// **'A configurar...'**
  String get commonConfiguring;

  /// No description provided for @commonSaveToRadio.
  ///
  /// In pt, this message translates to:
  /// **'Guardar no rádio'**
  String get commonSaveToRadio;

  /// No description provided for @commonReportUrlCopied.
  ///
  /// In pt, this message translates to:
  /// **'URL do relatório copiado'**
  String get commonReportUrlCopied;

  /// No description provided for @commonErrorColon.
  ///
  /// In pt, this message translates to:
  /// **'Erro:'**
  String get commonErrorColon;

  /// No description provided for @commonNoSpace.
  ///
  /// In pt, this message translates to:
  /// **'Sem espaço disponível. Remova um canal primeiro.'**
  String get commonNoSpace;

  /// No description provided for @commonUpdated.
  ///
  /// In pt, this message translates to:
  /// **'Actualizado:'**
  String get commonUpdated;

  /// No description provided for @commonAdd2Radio.
  ///
  /// In pt, this message translates to:
  /// **'Adicionar ao Rádio'**
  String get commonAdd2Radio;

  /// No description provided for @commonReconfigRadio.
  ///
  /// In pt, this message translates to:
  /// **'Re-configurar no Rádio'**
  String get commonReconfigRadio;

  /// No description provided for @commonHashtag.
  ///
  /// In pt, this message translates to:
  /// **'Hashtag'**
  String get commonHashtag;

  /// No description provided for @commonSecretKey.
  ///
  /// In pt, this message translates to:
  /// **'Secret Key'**
  String get commonSecretKey;

  /// No description provided for @commonReport.
  ///
  /// In pt, this message translates to:
  /// **'Relatório:'**
  String get commonReport;

  /// No description provided for @commonClearHistory.
  ///
  /// In pt, this message translates to:
  /// **'Limpar histórico'**
  String get commonClearHistory;

  /// No description provided for @commonSingularHop.
  ///
  /// In pt, this message translates to:
  /// **'salto'**
  String get commonSingularHop;

  /// No description provided for @commonPluralHops.
  ///
  /// In pt, this message translates to:
  /// **'saltos'**
  String get commonPluralHops;

  /// No description provided for @homeDisconnectTitle.
  ///
  /// In pt, this message translates to:
  /// **'Desligar rádio?'**
  String get homeDisconnectTitle;

  /// No description provided for @homeDisconnectContent.
  ///
  /// In pt, this message translates to:
  /// **'A ligação ao rádio será terminada'**
  String get homeDisconnectContent;

  /// No description provided for @homeDisconnect.
  ///
  /// In pt, this message translates to:
  /// **'Desligar'**
  String get homeDisconnect;

  /// No description provided for @homeExitTitle.
  ///
  /// In pt, this message translates to:
  /// **'Sair da LusoAPP?'**
  String get homeExitTitle;

  /// No description provided for @homeExitContent.
  ///
  /// In pt, this message translates to:
  /// **'A ligação ao rádio será terminada e a aplicação encerrada.'**
  String get homeExitContent;

  /// No description provided for @homeExit.
  ///
  /// In pt, this message translates to:
  /// **'Sair'**
  String get homeExit;

  /// No description provided for @settingsIdentity.
  ///
  /// In pt, this message translates to:
  /// **'Identidade'**
  String get settingsIdentity;

  /// No description provided for @settingsPublicKey.
  ///
  /// In pt, this message translates to:
  /// **'Chave Pública'**
  String get settingsPublicKey;

  /// No description provided for @settingsCopyPublicKey.
  ///
  /// In pt, this message translates to:
  /// **'Copiar chave pública'**
  String get settingsCopyPublicKey;

  /// No description provided for @settingsShareContact.
  ///
  /// In pt, this message translates to:
  /// **'Partilhar o meu contacto'**
  String get settingsShareContact;

  /// No description provided for @settingsShareContactDesc.
  ///
  /// In pt, this message translates to:
  /// **'Mostra QR Code para partilhar'**
  String get settingsShareContactDesc;

  /// No description provided for @settingsConnection.
  ///
  /// In pt, this message translates to:
  /// **'Ligação'**
  String get settingsConnection;

  /// No description provided for @settingsConnected.
  ///
  /// In pt, this message translates to:
  /// **'Ligado'**
  String get settingsConnected;

  /// No description provided for @settingsConnectionError.
  ///
  /// In pt, this message translates to:
  /// **'Erro de ligação'**
  String get settingsConnectionError;

  /// No description provided for @settingsDisconnected.
  ///
  /// In pt, this message translates to:
  /// **'Desligado'**
  String get settingsDisconnected;

  /// No description provided for @settingsAutoReconnect.
  ///
  /// In pt, this message translates to:
  /// **'Reconexão automática'**
  String get settingsAutoReconnect;

  /// No description provided for @settingsAutoReconnectDesc.
  ///
  /// In pt, this message translates to:
  /// **'Reconecta automaticamente quando a ligação é perdida'**
  String get settingsAutoReconnectDesc;

  /// No description provided for @settingsRadioConfig.
  ///
  /// In pt, this message translates to:
  /// **'Configuração do Rádio'**
  String get settingsRadioConfig;

  /// No description provided for @settingsRadioConfigDesc.
  ///
  /// In pt, this message translates to:
  /// **'LoRa, telemetria e dispositivo'**
  String get settingsRadioConfigDesc;

  /// No description provided for @settingsReboot.
  ///
  /// In pt, this message translates to:
  /// **'Reboot'**
  String get settingsReboot;

  /// No description provided for @settingsShutdown.
  ///
  /// In pt, this message translates to:
  /// **'Shutdown'**
  String get settingsShutdown;

  /// No description provided for @settingsRebootTitle.
  ///
  /// In pt, this message translates to:
  /// **'Reiniciar rádio'**
  String get settingsRebootTitle;

  /// No description provided for @settingsRebootContent.
  ///
  /// In pt, this message translates to:
  /// **'Isto vai reiniciar o firmware do rádio. Tens a certeza?'**
  String get settingsRebootContent;

  /// No description provided for @settingsRebootSent.
  ///
  /// In pt, this message translates to:
  /// **'Comando de reboot enviado. A aguardar reconexão...'**
  String get settingsRebootSent;

  /// No description provided for @settingsRebootFail.
  ///
  /// In pt, this message translates to:
  /// **'Falha ao enviar comando de reboot'**
  String get settingsRebootFail;

  /// No description provided for @settingsAppearance.
  ///
  /// In pt, this message translates to:
  /// **'Aparência'**
  String get settingsAppearance;

  /// No description provided for @settingsSelfMention.
  ///
  /// In pt, this message translates to:
  /// **'Menção própria (@[Você])'**
  String get settingsSelfMention;

  /// No description provided for @settingsOtherMention.
  ///
  /// In pt, this message translates to:
  /// **'Menção de outros (@[Nome])'**
  String get settingsOtherMention;

  /// No description provided for @settingsChooseColor.
  ///
  /// In pt, this message translates to:
  /// **'Escolher cor'**
  String get settingsChooseColor;

  /// No description provided for @settingsNotifications.
  ///
  /// In pt, this message translates to:
  /// **'Notificações'**
  String get settingsNotifications;

  /// No description provided for @settingsEnableNotifications.
  ///
  /// In pt, this message translates to:
  /// **'Activar notificações'**
  String get settingsEnableNotifications;

  /// No description provided for @settingsEnableNotificationsDesc.
  ///
  /// In pt, this message translates to:
  /// **'Mostrar alertas para novas mensagens'**
  String get settingsEnableNotificationsDesc;

  /// No description provided for @settingsNotificationPermissionDenied.
  ///
  /// In pt, this message translates to:
  /// **'Permissão de notificação não concedida'**
  String get settingsNotificationPermissionDenied;

  /// No description provided for @settingsAllow.
  ///
  /// In pt, this message translates to:
  /// **'Permitir'**
  String get settingsAllow;

  /// No description provided for @settingsPrivateMessages.
  ///
  /// In pt, this message translates to:
  /// **'Mensagens privadas'**
  String get settingsPrivateMessages;

  /// No description provided for @settingsChannelMessages.
  ///
  /// In pt, this message translates to:
  /// **'Mensagens de canal'**
  String get settingsChannelMessages;

  /// No description provided for @settingsBackgroundOnly.
  ///
  /// In pt, this message translates to:
  /// **'Apenas em segundo plano'**
  String get settingsBackgroundOnly;

  /// No description provided for @settingsPrivateKeyCopy.
  ///
  /// In pt, this message translates to:
  /// **'Cópia da Chave Privada'**
  String get settingsPrivateKeyCopy;

  /// No description provided for @settingsPrivateKeyDesc.
  ///
  /// In pt, this message translates to:
  /// **'A chave privada identifica-te na rede. Guarda uma cópia segura antes de mudar de dispositivo.'**
  String get settingsPrivateKeyDesc;

  /// No description provided for @settingsSaveFromRadio.
  ///
  /// In pt, this message translates to:
  /// **'Guardar do rádio'**
  String get settingsSaveFromRadio;

  /// No description provided for @settingsPasteKey.
  ///
  /// In pt, this message translates to:
  /// **'Colar chave'**
  String get settingsPasteKey;

  /// No description provided for @settingsShareCopy.
  ///
  /// In pt, this message translates to:
  /// **'Partilhar cópia'**
  String get settingsShareCopy;

  /// No description provided for @settingsRestoreToRadio.
  ///
  /// In pt, this message translates to:
  /// **'Restaurar no rádio'**
  String get settingsRestoreToRadio;

  /// No description provided for @settingsDeleteLocalCopy.
  ///
  /// In pt, this message translates to:
  /// **'Apagar cópia local'**
  String get settingsDeleteLocalCopy;

  /// No description provided for @settingsRestorePrivateKeyTitle.
  ///
  /// In pt, this message translates to:
  /// **'Restaurar Chave Privada'**
  String get settingsRestorePrivateKeyTitle;

  /// No description provided for @settingsRestorePrivateKeyContent.
  ///
  /// In pt, this message translates to:
  /// **'O rádio vai reiniciar automaticamente após a restauração. Prosseguir?'**
  String get settingsRestorePrivateKeyContent;

  /// No description provided for @settingsDeleteBackupTitle.
  ///
  /// In pt, this message translates to:
  /// **'Apagar cópia de segurança'**
  String get settingsDeleteBackupTitle;

  /// No description provided for @settingsKeySavedSuccess.
  ///
  /// In pt, this message translates to:
  /// **'Cópia da chave privada guardada com sucesso'**
  String get settingsKeySavedSuccess;

  /// No description provided for @settingsKeyImportedSuccess.
  ///
  /// In pt, this message translates to:
  /// **'Chave importada com sucesso'**
  String get settingsKeyImportedSuccess;

  /// No description provided for @settingsAbout.
  ///
  /// In pt, this message translates to:
  /// **'Sobre'**
  String get settingsAbout;

  /// No description provided for @settingsAppName.
  ///
  /// In pt, this message translates to:
  /// **'LusoAPP'**
  String get settingsAppName;

  /// No description provided for @settingsAppSubtitle.
  ///
  /// In pt, this message translates to:
  /// **'MeshCore Portugal'**
  String get settingsAppSubtitle;

  /// No description provided for @settingsCredit.
  ///
  /// In pt, this message translates to:
  /// **'Código fonte inicial criado por Paulo Pereira aka GZ7d0'**
  String get settingsCredit;

  /// No description provided for @settingsVersion.
  ///
  /// In pt, this message translates to:
  /// **'Versão'**
  String get settingsVersion;

  /// No description provided for @settingsProtocol.
  ///
  /// In pt, this message translates to:
  /// **'Protocolo'**
  String get settingsProtocol;

  /// No description provided for @settingsProtocolName.
  ///
  /// In pt, this message translates to:
  /// **'Companion Radio Protocol v3'**
  String get settingsProtocolName;

  /// No description provided for @settingsLicense.
  ///
  /// In pt, this message translates to:
  /// **'Licença'**
  String get settingsLicense;

  /// No description provided for @settingsLicenseMIT.
  ///
  /// In pt, this message translates to:
  /// **'MIT'**
  String get settingsLicenseMIT;

  /// No description provided for @contactsAll.
  ///
  /// In pt, this message translates to:
  /// **'Todos'**
  String get contactsAll;

  /// No description provided for @contactsFavorites.
  ///
  /// In pt, this message translates to:
  /// **'Favoritos'**
  String get contactsFavorites;

  /// No description provided for @contactsCompanions.
  ///
  /// In pt, this message translates to:
  /// **'Companheiros'**
  String get contactsCompanions;

  /// No description provided for @contactsRepeaters.
  ///
  /// In pt, this message translates to:
  /// **'Repetidores'**
  String get contactsRepeaters;

  /// No description provided for @contactsSensors.
  ///
  /// In pt, this message translates to:
  /// **'Sensores'**
  String get contactsSensors;

  /// No description provided for @contactsSearchHint.
  ///
  /// In pt, this message translates to:
  /// **'Pesquisar contactos...'**
  String get contactsSearchHint;

  /// No description provided for @contactsSendAdvert.
  ///
  /// In pt, this message translates to:
  /// **'Enviar Anúncio'**
  String get contactsSendAdvert;

  /// No description provided for @contactsAdvertZeroHop.
  ///
  /// In pt, this message translates to:
  /// **'Anúncio · Zero Hop'**
  String get contactsAdvertZeroHop;

  /// No description provided for @contactsAdvertFlood.
  ///
  /// In pt, this message translates to:
  /// **'Anúncio · Flood'**
  String get contactsAdvertFlood;

  /// No description provided for @contactsSort.
  ///
  /// In pt, this message translates to:
  /// **'Ordenar'**
  String get contactsSort;

  /// No description provided for @contactsSortNameAZ.
  ///
  /// In pt, this message translates to:
  /// **'Nome (A-Z)'**
  String get contactsSortNameAZ;

  /// No description provided for @contactsSortLastHeard.
  ///
  /// In pt, this message translates to:
  /// **'Ouvido recentemente'**
  String get contactsSortLastHeard;

  /// No description provided for @contactsSortLastMessage.
  ///
  /// In pt, this message translates to:
  /// **'Última mensagem'**
  String get contactsSortLastMessage;

  /// No description provided for @contactsMoreOptions.
  ///
  /// In pt, this message translates to:
  /// **'Mais opções'**
  String get contactsMoreOptions;

  /// No description provided for @contactsDiscover.
  ///
  /// In pt, this message translates to:
  /// **'Descobrir contactos'**
  String get contactsDiscover;

  /// No description provided for @contactsMultiSelect.
  ///
  /// In pt, this message translates to:
  /// **'Selecionar múltiplos'**
  String get contactsMultiSelect;

  /// No description provided for @contactsEmptyCompanions.
  ///
  /// In pt, this message translates to:
  /// **'Sem companheiros na rede'**
  String get contactsEmptyCompanions;

  /// No description provided for @contactsEmptyRepeaters.
  ///
  /// In pt, this message translates to:
  /// **'Sem repetidores na rede'**
  String get contactsEmptyRepeaters;

  /// No description provided for @contactsEmptyRooms.
  ///
  /// In pt, this message translates to:
  /// **'Sem salas na rede'**
  String get contactsEmptyRooms;

  /// No description provided for @contactsEmptySensors.
  ///
  /// In pt, this message translates to:
  /// **'Sem sensores na rede'**
  String get contactsEmptySensors;

  /// No description provided for @contactsEmpty.
  ///
  /// In pt, this message translates to:
  /// **'Sem contactos'**
  String get contactsEmpty;

  /// No description provided for @contactsEmptyFavorites.
  ///
  /// In pt, this message translates to:
  /// **'Sem favoritos'**
  String get contactsEmptyFavorites;

  /// No description provided for @contactsEmptyHint.
  ///
  /// In pt, this message translates to:
  /// **'Os contactos aparecem quando o rádio os descobre'**
  String get contactsEmptyHint;

  /// No description provided for @contactsSelected.
  ///
  /// In pt, this message translates to:
  /// **'selecionado(s)'**
  String get contactsSelected;

  /// No description provided for @contactsRemoveSelected.
  ///
  /// In pt, this message translates to:
  /// **'Remover selecionados'**
  String get contactsRemoveSelected;

  /// No description provided for @contactsCancelSelection.
  ///
  /// In pt, this message translates to:
  /// **'Cancelar seleção'**
  String get contactsCancelSelection;

  /// No description provided for @contactsAddContact.
  ///
  /// In pt, this message translates to:
  /// **'Adicionar contacto'**
  String get contactsAddContact;

  /// No description provided for @contactsAddInstruction.
  ///
  /// In pt, this message translates to:
  /// **'Envie um anúncio para que outros nós o descubram automaticamente, ou adicione manualmente através da chave pública'**
  String get contactsAddInstruction;

  /// No description provided for @contactsSendAdvertAuto.
  ///
  /// In pt, this message translates to:
  /// **'Enviar Anúncio (descoberta automática)'**
  String get contactsSendAdvertAuto;

  /// No description provided for @contactsReadQR.
  ///
  /// In pt, this message translates to:
  /// **'Ler QR Code'**
  String get contactsReadQR;

  /// No description provided for @contactsOrManual.
  ///
  /// In pt, this message translates to:
  /// **'ou adicionar manualmente'**
  String get contactsOrManual;

  /// No description provided for @contactsPublicKeyLabel.
  ///
  /// In pt, this message translates to:
  /// **'Chave pública (hex, 64 chars)'**
  String get contactsPublicKeyLabel;

  /// No description provided for @contactsDisplayName.
  ///
  /// In pt, this message translates to:
  /// **'Nome de exibição'**
  String get contactsDisplayName;

  /// No description provided for @contactsTypeChat.
  ///
  /// In pt, this message translates to:
  /// **'Chat'**
  String get contactsTypeChat;

  /// No description provided for @contactsTypeRepeater.
  ///
  /// In pt, this message translates to:
  /// **'Repetidor'**
  String get contactsTypeRepeater;

  /// No description provided for @contactsTypeRoom.
  ///
  /// In pt, this message translates to:
  /// **'Sala'**
  String get contactsTypeRoom;

  /// No description provided for @contactsAdding.
  ///
  /// In pt, this message translates to:
  /// **'A adicionar...'**
  String get contactsAdding;

  /// No description provided for @contactsSeen.
  ///
  /// In pt, this message translates to:
  /// **'Visto:'**
  String get contactsSeen;

  /// No description provided for @contactsRenameTitle.
  ///
  /// In pt, this message translates to:
  /// **'Renomear contacto'**
  String get contactsRenameTitle;

  /// No description provided for @contactsAnnouncedName.
  ///
  /// In pt, this message translates to:
  /// **'Nome anunciado:'**
  String get contactsAnnouncedName;

  /// No description provided for @contactsCustomName.
  ///
  /// In pt, this message translates to:
  /// **'Nome personalizado'**
  String get contactsCustomName;

  /// No description provided for @contactsSaveToRadioTitle.
  ///
  /// In pt, this message translates to:
  /// **'Guardar contacto no rádio'**
  String get contactsSaveToRadioTitle;

  /// No description provided for @contactsTypeCompanion.
  ///
  /// In pt, this message translates to:
  /// **'Tipo: Companheiro'**
  String get contactsTypeCompanion;

  /// No description provided for @contactsSavedToRadio.
  ///
  /// In pt, this message translates to:
  /// **'{name} guardado no rádio'**
  String contactsSavedToRadio(String name);

  /// No description provided for @contactsSaveToRadioError.
  ///
  /// In pt, this message translates to:
  /// **'Erro ao guardar contacto no rádio'**
  String get contactsSaveToRadioError;

  /// No description provided for @contactsSaveTimeout.
  ///
  /// In pt, this message translates to:
  /// **'Timeout: rádio não respondeu'**
  String get contactsSaveTimeout;

  /// No description provided for @contactsRemoveTitle.
  ///
  /// In pt, this message translates to:
  /// **'Remover contacto(s)?'**
  String get contactsRemoveTitle;

  /// No description provided for @contactsRemovedPrefix.
  ///
  /// In pt, this message translates to:
  /// **'Removidos'**
  String get contactsRemovedPrefix;

  /// No description provided for @contactsRemoveErrorSuffix.
  ///
  /// In pt, this message translates to:
  /// **'erro(s)'**
  String get contactsRemoveErrorSuffix;

  /// No description provided for @contactsRemoveError.
  ///
  /// In pt, this message translates to:
  /// **'Erro ao remover contactos'**
  String get contactsRemoveError;

  /// No description provided for @contactsRemoveFromListSuffix.
  ///
  /// In pt, this message translates to:
  /// **'da lista de contactos?'**
  String get contactsRemoveFromListSuffix;

  /// No description provided for @contactsRemoveRadioError.
  ///
  /// In pt, this message translates to:
  /// **'Erro ao remover no rádio (código'**
  String get contactsRemoveRadioError;

  /// No description provided for @contactsRemoveTimeout.
  ///
  /// In pt, this message translates to:
  /// **'Timeout: rádio não respondeu à remoção'**
  String get contactsRemoveTimeout;

  /// No description provided for @contactsRemoveFavorites.
  ///
  /// In pt, this message translates to:
  /// **'Remover dos favoritos'**
  String get contactsRemoveFavorites;

  /// No description provided for @contactsAddFavorites.
  ///
  /// In pt, this message translates to:
  /// **'Adicionar aos favoritos'**
  String get contactsAddFavorites;

  /// No description provided for @contactsShareQR.
  ///
  /// In pt, this message translates to:
  /// **'Partilhar via QR'**
  String get contactsShareQR;

  /// No description provided for @contactsPrivateMessage.
  ///
  /// In pt, this message translates to:
  /// **'Mensagem privada'**
  String get contactsPrivateMessage;

  /// No description provided for @contactsJoinRoom.
  ///
  /// In pt, this message translates to:
  /// **'Entrar na sala'**
  String get contactsJoinRoom;

  /// No description provided for @contactsRemoteAdmin.
  ///
  /// In pt, this message translates to:
  /// **'Admin remoto'**
  String get contactsRemoteAdmin;

  /// No description provided for @contactsManagePath.
  ///
  /// In pt, this message translates to:
  /// **'Gerir caminho'**
  String get contactsManagePath;

  /// No description provided for @contactsCurrentPath.
  ///
  /// In pt, this message translates to:
  /// **'Caminho actual:'**
  String get contactsCurrentPath;

  /// No description provided for @contactsRemoveContact.
  ///
  /// In pt, this message translates to:
  /// **'Remover contacto'**
  String get contactsRemoveContact;

  /// No description provided for @contactsAdminLabel.
  ///
  /// In pt, this message translates to:
  /// **'Admin:'**
  String get contactsAdminLabel;

  /// No description provided for @contactsIdLabel.
  ///
  /// In pt, this message translates to:
  /// **'ID:'**
  String get contactsIdLabel;

  /// No description provided for @contactsHopsLabel.
  ///
  /// In pt, this message translates to:
  /// **'Saltos:'**
  String get contactsHopsLabel;

  /// No description provided for @contactsAuth.
  ///
  /// In pt, this message translates to:
  /// **'Autenticação'**
  String get contactsAuth;

  /// No description provided for @contactsPassword.
  ///
  /// In pt, this message translates to:
  /// **'Palavra-passe (opcional)'**
  String get contactsPassword;

  /// No description provided for @contactsPasswordHint.
  ///
  /// In pt, this message translates to:
  /// **'Deixar em branco se sem palavra-passe'**
  String get contactsPasswordHint;

  /// No description provided for @contactsJoin.
  ///
  /// In pt, this message translates to:
  /// **'Entrar'**
  String get contactsJoin;

  /// No description provided for @contactsStatusSent.
  ///
  /// In pt, this message translates to:
  /// **'Pedido de estado enviado...'**
  String get contactsStatusSent;

  /// No description provided for @contactsStatusSending.
  ///
  /// In pt, this message translates to:
  /// **'A enviar:'**
  String get contactsStatusSending;

  /// No description provided for @contactsRemoteActions.
  ///
  /// In pt, this message translates to:
  /// **'Acções Remotas'**
  String get contactsRemoteActions;

  /// No description provided for @contactsFloodAdvert.
  ///
  /// In pt, this message translates to:
  /// **'Anúncio Flood'**
  String get contactsFloodAdvert;

  /// No description provided for @contactsFloodAdvertDesc.
  ///
  /// In pt, this message translates to:
  /// **'Força o nó a enviar um anúncio flood'**
  String get contactsFloodAdvertDesc;

  /// No description provided for @contactsZeroHopAdvert.
  ///
  /// In pt, this message translates to:
  /// **'Anúncio Zero-Hop'**
  String get contactsZeroHopAdvert;

  /// No description provided for @contactsZeroHopAdvertDesc.
  ///
  /// In pt, this message translates to:
  /// **'Anúncio só para vizinhos directos'**
  String get contactsZeroHopAdvertDesc;

  /// No description provided for @contactsSyncClock.
  ///
  /// In pt, this message translates to:
  /// **'Sincronizar Relógio'**
  String get contactsSyncClock;

  /// No description provided for @contactsSyncClockDesc.
  ///
  /// In pt, this message translates to:
  /// **'Envia o timestamp actual para o nó'**
  String get contactsSyncClockDesc;

  /// No description provided for @contactsStartOTA.
  ///
  /// In pt, this message translates to:
  /// **'Iniciar OTA'**
  String get contactsStartOTA;

  /// No description provided for @contactsStartOTADesc.
  ///
  /// In pt, this message translates to:
  /// **'Inicia actualização OTA — NRF DFU / ESP32'**
  String get contactsStartOTADesc;

  /// No description provided for @contactsConfirmOTATitle.
  ///
  /// In pt, this message translates to:
  /// **'Confirmar OTA'**
  String get contactsConfirmOTATitle;

  /// No description provided for @contactsConfirmOTAContent.
  ///
  /// In pt, this message translates to:
  /// **'O rádio vai entrar em modo de actualização OTA e ficará temporariamente inacessível'**
  String get contactsConfirmOTAContent;

  /// No description provided for @contactsConfirmOTAQuestion.
  ///
  /// In pt, this message translates to:
  /// **'Tens a certeza?'**
  String get contactsConfirmOTAQuestion;

  /// No description provided for @contactsStats.
  ///
  /// In pt, this message translates to:
  /// **'Estatísticas'**
  String get contactsStats;

  /// No description provided for @contactsUptime.
  ///
  /// In pt, this message translates to:
  /// **'Uptime'**
  String get contactsUptime;

  /// No description provided for @contactsSnrLast.
  ///
  /// In pt, this message translates to:
  /// **'SNR (último)'**
  String get contactsSnrLast;

  /// No description provided for @contactsRssiLast.
  ///
  /// In pt, this message translates to:
  /// **'RSSI (último)'**
  String get contactsRssiLast;

  /// No description provided for @contactsNoise.
  ///
  /// In pt, this message translates to:
  /// **'Ruído'**
  String get contactsNoise;

  /// No description provided for @contactsRxTx.
  ///
  /// In pt, this message translates to:
  /// **'RX / TX'**
  String get contactsRxTx;

  /// No description provided for @contactsFloodRxTx.
  ///
  /// In pt, this message translates to:
  /// **'Flood RX/TX'**
  String get contactsFloodRxTx;

  /// No description provided for @contactsDirectRxTx.
  ///
  /// In pt, this message translates to:
  /// **'Directo RX/TX'**
  String get contactsDirectRxTx;

  /// No description provided for @contactsAirtimeTx.
  ///
  /// In pt, this message translates to:
  /// **'Tempo no ar (TX)'**
  String get contactsAirtimeTx;

  /// No description provided for @contactsAirtimeRx.
  ///
  /// In pt, this message translates to:
  /// **'Tempo no ar (RX)'**
  String get contactsAirtimeRx;

  /// No description provided for @contactsDuplicates.
  ///
  /// In pt, this message translates to:
  /// **'Duplicados'**
  String get contactsDuplicates;

  /// No description provided for @contactsNotSavedHint.
  ///
  /// In pt, this message translates to:
  /// **'Este contacto foi ouvido mas não está guardado no rádio'**
  String get contactsNotSavedHint;

  /// No description provided for @channelsCreatePrivate.
  ///
  /// In pt, this message translates to:
  /// **'Criar Canal Privado'**
  String get channelsCreatePrivate;

  /// No description provided for @channelsCreatePrivateDesc.
  ///
  /// In pt, this message translates to:
  /// **'Seguro com uma chave secreta'**
  String get channelsCreatePrivateDesc;

  /// No description provided for @channelsJoinPrivate.
  ///
  /// In pt, this message translates to:
  /// **'Entrar num Canal Privado'**
  String get channelsJoinPrivate;

  /// No description provided for @channelsJoinPrivateDesc.
  ///
  /// In pt, this message translates to:
  /// **'Introduza manualmente uma chave secreta'**
  String get channelsJoinPrivateDesc;

  /// No description provided for @channelsJoinPublic.
  ///
  /// In pt, this message translates to:
  /// **'Entrar no Canal Público'**
  String get channelsJoinPublic;

  /// No description provided for @channelsJoinPublicDesc.
  ///
  /// In pt, this message translates to:
  /// **'Qualquer pessoa pode entrar neste canal'**
  String get channelsJoinPublicDesc;

  /// No description provided for @channelsJoinHashtag.
  ///
  /// In pt, this message translates to:
  /// **'Entrar num Canal Hashtag'**
  String get channelsJoinHashtag;

  /// No description provided for @channelsJoinHashtagDesc.
  ///
  /// In pt, this message translates to:
  /// **'Qualquer pessoa pode entrar em canais hashtag'**
  String get channelsJoinHashtagDesc;

  /// No description provided for @channelsReadQR.
  ///
  /// In pt, this message translates to:
  /// **'Ler QR Code'**
  String get channelsReadQR;

  /// No description provided for @channelsReadQRDesc.
  ///
  /// In pt, this message translates to:
  /// **'Digitalizar o QR Code de um canal'**
  String get channelsReadQRDesc;

  /// No description provided for @channelsSlotPosition.
  ///
  /// In pt, this message translates to:
  /// **'Posição do canal'**
  String get channelsSlotPosition;

  /// No description provided for @channelsSlot.
  ///
  /// In pt, this message translates to:
  /// **'Canal'**
  String get channelsSlot;

  /// No description provided for @channelsSlotInUse.
  ///
  /// In pt, this message translates to:
  /// **'(em uso)'**
  String get channelsSlotInUse;

  /// No description provided for @channelsChannelName.
  ///
  /// In pt, this message translates to:
  /// **'Nome do canal'**
  String get channelsChannelName;

  /// No description provided for @channelsHashtagName.
  ///
  /// In pt, this message translates to:
  /// **'Nome do hashtag (sem #)'**
  String get channelsHashtagName;

  /// No description provided for @channelsHashtagHint.
  ///
  /// In pt, this message translates to:
  /// **'ex: meshcore  →  canal #meshcore'**
  String get channelsHashtagHint;

  /// No description provided for @channelsNameHintGeneral.
  ///
  /// In pt, this message translates to:
  /// **'ex: Geral'**
  String get channelsNameHintGeneral;

  /// No description provided for @channelsNameHintPrivate.
  ///
  /// In pt, this message translates to:
  /// **'ex: A Minha Rede'**
  String get channelsNameHintPrivate;

  /// No description provided for @channelsSecretKey.
  ///
  /// In pt, this message translates to:
  /// **'Chave secreta (32 caracteres hex)'**
  String get channelsSecretKey;

  /// No description provided for @channelsSecretKeyHint.
  ///
  /// In pt, this message translates to:
  /// **'ex: 8b3387e9c5cdea6ac9e5edbaa115cd72'**
  String get channelsSecretKeyHint;

  /// No description provided for @channelsPublicKey.
  ///
  /// In pt, this message translates to:
  /// **'Chave pública conhecida'**
  String get channelsPublicKey;

  /// No description provided for @channelsDerivedKey.
  ///
  /// In pt, this message translates to:
  /// **'Chave derivada do hashtag'**
  String get channelsDerivedKey;

  /// No description provided for @channelsRandomKey.
  ///
  /// In pt, this message translates to:
  /// **'Chave gerada aleatoriamente'**
  String get channelsRandomKey;

  /// No description provided for @channelsPublicKeyInfo.
  ///
  /// In pt, this message translates to:
  /// **'Esta chave é pública e igual em todos os dispositivos MeshCore'**
  String get channelsPublicKeyInfo;

  /// No description provided for @channelsHashtagKeyInfo.
  ///
  /// In pt, this message translates to:
  /// **'Qualquer pessoa que entre no mesmo hashtag terá esta chave automaticamente'**
  String get channelsHashtagKeyInfo;

  /// No description provided for @channelsRandomKeyInfo.
  ///
  /// In pt, this message translates to:
  /// **'Guarde esta chave ou partilhe o QR Code para convidar outros'**
  String get channelsRandomKeyInfo;

  /// No description provided for @channelsRegenerateKey.
  ///
  /// In pt, this message translates to:
  /// **'Regenerar chave'**
  String get channelsRegenerateKey;

  /// No description provided for @channelsEmpty.
  ///
  /// In pt, this message translates to:
  /// **'Sem canais'**
  String get channelsEmpty;

  /// No description provided for @channelsEmptyHint.
  ///
  /// In pt, this message translates to:
  /// **'Os canais configurados no rádio aparecem aqui'**
  String get channelsEmptyHint;

  /// No description provided for @channelsRefresh.
  ///
  /// In pt, this message translates to:
  /// **'Actualizar Canais'**
  String get channelsRefresh;

  /// No description provided for @channelsAllRead.
  ///
  /// In pt, this message translates to:
  /// **'Tudo lido'**
  String get channelsAllRead;

  /// No description provided for @channelsAllReadHint.
  ///
  /// In pt, this message translates to:
  /// **'Sem mensagens não lidas nos canais'**
  String get channelsAllReadHint;

  /// No description provided for @channelsSeeAll.
  ///
  /// In pt, this message translates to:
  /// **'Ver todos os canais'**
  String get channelsSeeAll;

  /// No description provided for @channelsMsgSuffix.
  ///
  /// In pt, this message translates to:
  /// **'msg'**
  String get channelsMsgSuffix;

  /// No description provided for @channelsOptionsFabTooltip.
  ///
  /// In pt, this message translates to:
  /// **'Opções do canal'**
  String get channelsOptionsFabTooltip;

  /// No description provided for @channelsClearHistoryConfirm.
  ///
  /// In pt, this message translates to:
  /// **'Apagar todas as mensagens deste canal? Esta ação não pode ser revertida'**
  String get channelsClearHistoryConfirm;

  /// No description provided for @channelsEditSheet.
  ///
  /// In pt, this message translates to:
  /// **'Editar canal'**
  String get channelsEditSheet;

  /// No description provided for @channelsQRTitle.
  ///
  /// In pt, this message translates to:
  /// **'QR Code do canal'**
  String get channelsQRTitle;

  /// No description provided for @channelsShowQR.
  ///
  /// In pt, this message translates to:
  /// **'Mostrar QR Code do canal'**
  String get channelsShowQR;

  /// No description provided for @channelsQRDesc.
  ///
  /// In pt, this message translates to:
  /// **'Partilhe este QR Code para dar acesso ao canal'**
  String get channelsQRDesc;

  /// No description provided for @channelsShareText.
  ///
  /// In pt, this message translates to:
  /// **'Partilhar texto'**
  String get channelsShareText;

  /// No description provided for @channelsShareQR.
  ///
  /// In pt, this message translates to:
  /// **'Partilhar QR'**
  String get channelsShareQR;

  /// No description provided for @channelsRemovePublicTitle.
  ///
  /// In pt, this message translates to:
  /// **'Remover Canal Público?'**
  String get channelsRemovePublicTitle;

  /// No description provided for @channelsRemovePublicWarning.
  ///
  /// In pt, this message translates to:
  /// **'Está prestes a remover o Canal Público. Este é o canal principal partilhado pela comunidade MeshCore. Tem a certeza?'**
  String get channelsRemovePublicWarning;

  /// No description provided for @channelsRemoveAnyway.
  ///
  /// In pt, this message translates to:
  /// **'Remover mesmo assim'**
  String get channelsRemoveAnyway;

  /// No description provided for @channelsRemoveTitle.
  ///
  /// In pt, this message translates to:
  /// **'Remover canal'**
  String get channelsRemoveTitle;

  /// No description provided for @channelsRemoveConfirm.
  ///
  /// In pt, this message translates to:
  /// **'Tem a certeza que quer remover'**
  String get channelsRemoveConfirm;

  /// No description provided for @channelsRemoveWarning.
  ///
  /// In pt, this message translates to:
  /// **'Esta acção não pode ser desfeita.'**
  String get channelsRemoveWarning;

  /// No description provided for @channelsMuteTitle.
  ///
  /// In pt, this message translates to:
  /// **'Canal silenciado'**
  String get channelsMuteTitle;

  /// No description provided for @channelsUnmuteTitle.
  ///
  /// In pt, this message translates to:
  /// **'Notificações activas'**
  String get channelsUnmuteTitle;

  /// No description provided for @channelsMuteSubtitleOn.
  ///
  /// In pt, this message translates to:
  /// **'Sem alertas — badge de não lidas ainda visível'**
  String get channelsMuteSubtitleOn;

  /// No description provided for @channelsMuteSubtitleOff.
  ///
  /// In pt, this message translates to:
  /// **'Recebe notificações e badge de não lidas'**
  String get channelsMuteSubtitleOff;

  /// No description provided for @channelsMuteLabel.
  ///
  /// In pt, this message translates to:
  /// **'silenciado'**
  String get channelsMuteLabel;

  /// No description provided for @chatMuteChannel.
  ///
  /// In pt, this message translates to:
  /// **'Silenciar canal'**
  String get chatMuteChannel;

  /// No description provided for @chatUnmuteChannel.
  ///
  /// In pt, this message translates to:
  /// **'Reativar notificações'**
  String get chatUnmuteChannel;

  /// No description provided for @chatNoMessages.
  ///
  /// In pt, this message translates to:
  /// **'Sem mensagens neste canal'**
  String get chatNoMessages;

  /// No description provided for @chatSendFirstMessage.
  ///
  /// In pt, this message translates to:
  /// **'Envie a primeira mensagem!'**
  String get chatSendFirstMessage;

  /// No description provided for @chatInputHint.
  ///
  /// In pt, this message translates to:
  /// **'Mensagem para o canal...'**
  String get chatInputHint;

  /// No description provided for @chatRepeater.
  ///
  /// In pt, this message translates to:
  /// **'Repetidor'**
  String get chatRepeater;

  /// No description provided for @chatRepeaters.
  ///
  /// In pt, this message translates to:
  /// **'Repetidores'**
  String get chatRepeaters;

  /// No description provided for @chatMsgCount.
  ///
  /// In pt, this message translates to:
  /// **'mensagens'**
  String get chatMsgCount;

  /// No description provided for @chatHeard.
  ///
  /// In pt, this message translates to:
  /// **'Ouvida'**
  String get chatHeard;

  /// No description provided for @chatOnce.
  ///
  /// In pt, this message translates to:
  /// **'vez'**
  String get chatOnce;

  /// No description provided for @chatTimes.
  ///
  /// In pt, this message translates to:
  /// **'vezes por repetidores'**
  String get chatTimes;

  /// No description provided for @chatViaRepeaters.
  ///
  /// In pt, this message translates to:
  /// **'Recebida via repetidores'**
  String get chatViaRepeaters;

  /// No description provided for @chatAuthenticatedMessage.
  ///
  /// In pt, this message translates to:
  /// **'Autenticado'**
  String get chatAuthenticatedMessage;

  /// No description provided for @chatMsgDetails.
  ///
  /// In pt, this message translates to:
  /// **'Detalhes da mensagem'**
  String get chatMsgDetails;

  /// No description provided for @chatRetry.
  ///
  /// In pt, this message translates to:
  /// **'Reenviar'**
  String get chatRetry;

  /// No description provided for @chatFailed.
  ///
  /// In pt, this message translates to:
  /// **'Falhou'**
  String get chatFailed;

  /// No description provided for @chatPathLabel.
  ///
  /// In pt, this message translates to:
  /// **'Caminho'**
  String get chatPathLabel;

  /// No description provided for @chatHeardCount.
  ///
  /// In pt, this message translates to:
  /// **'Ouvido'**
  String get chatHeardCount;

  /// No description provided for @chatTimesCount.
  ///
  /// In pt, this message translates to:
  /// **'vezes'**
  String get chatTimesCount;

  /// No description provided for @chatPathExplanation.
  ///
  /// In pt, this message translates to:
  /// **'Cada caminho representa uma vez que o teu rádio ouviu a mensagem de volta'**
  String get chatPathExplanation;

  /// No description provided for @chatPathInstruction.
  ///
  /// In pt, this message translates to:
  /// **'Toca num caminho para ver a rota completa'**
  String get chatPathInstruction;

  /// No description provided for @chatNoPathData.
  ///
  /// In pt, this message translates to:
  /// **'Os dados de caminho não estão disponíveis. Reconecta o rádio para registar novos caminhos'**
  String get chatNoPathData;

  /// No description provided for @chatViewOnMap.
  ///
  /// In pt, this message translates to:
  /// **'Ver no mapa'**
  String get chatViewOnMap;

  /// No description provided for @chatYourRadio.
  ///
  /// In pt, this message translates to:
  /// **'O teu rádio'**
  String get chatYourRadio;

  /// No description provided for @chatYouSent.
  ///
  /// In pt, this message translates to:
  /// **'Enviaste a mensagem'**
  String get chatYouSent;

  /// No description provided for @chatReceived.
  ///
  /// In pt, this message translates to:
  /// **'Recebeu a mensagem'**
  String get chatReceived;

  /// No description provided for @chatHopLabel.
  ///
  /// In pt, this message translates to:
  /// **'Salto'**
  String get chatHopLabel;

  /// No description provided for @chatRepeated.
  ///
  /// In pt, this message translates to:
  /// **'Repetiu'**
  String get chatRepeated;

  /// No description provided for @chatHashtagChannel.
  ///
  /// In pt, this message translates to:
  /// **'Canal Hashtag — qualquer pessoa com o nome pode entrar'**
  String get chatHashtagChannel;

  /// No description provided for @chatKeyLabel.
  ///
  /// In pt, this message translates to:
  /// **'Chave:'**
  String get chatKeyLabel;

  /// No description provided for @chatCreateJoinChannel.
  ///
  /// In pt, this message translates to:
  /// **'Criar e entrar no canal'**
  String get chatCreateJoinChannel;

  /// No description provided for @chatNoChannelSlots.
  ///
  /// In pt, this message translates to:
  /// **'Sem espaço disponível para novos canais'**
  String get chatNoChannelSlots;

  /// No description provided for @chatDeleteMessage.
  ///
  /// In pt, this message translates to:
  /// **'Apagar mensagem'**
  String get chatDeleteMessage;

  /// No description provided for @chatMenuOptions.
  ///
  /// In pt, this message translates to:
  /// **'Opções do canal'**
  String get chatMenuOptions;

  /// No description provided for @chatNewMessages.
  ///
  /// In pt, this message translates to:
  /// **'Novas mensagens'**
  String get chatNewMessages;

  /// No description provided for @chatPingButton.
  ///
  /// In pt, this message translates to:
  /// **'!ping'**
  String get chatPingButton;

  /// No description provided for @chatViewResultOnline.
  ///
  /// In pt, this message translates to:
  /// **'ver resultado online'**
  String get chatViewResultOnline;

  /// No description provided for @connectTitle.
  ///
  /// In pt, this message translates to:
  /// **'MeshCore Portugal'**
  String get connectTitle;

  /// No description provided for @connectReconnect.
  ///
  /// In pt, this message translates to:
  /// **'Ligar novamente'**
  String get connectReconnect;

  /// No description provided for @connectContinueOffline.
  ///
  /// In pt, this message translates to:
  /// **'Continuar offline'**
  String get connectContinueOffline;

  /// No description provided for @connectSearchDevices.
  ///
  /// In pt, this message translates to:
  /// **'Procurar Dispositivos'**
  String get connectSearchDevices;

  /// No description provided for @connectSearching.
  ///
  /// In pt, this message translates to:
  /// **'A procurar...'**
  String get connectSearching;

  /// No description provided for @connectBrowserNote.
  ///
  /// In pt, this message translates to:
  /// **'O browser irá mostrar um seletor de dispositivos Bluetooth'**
  String get connectBrowserNote;

  /// No description provided for @connectScanningMessage.
  ///
  /// In pt, this message translates to:
  /// **'A procurar rádios MeshCore...'**
  String get connectScanningMessage;

  /// No description provided for @connectTapHint.
  ///
  /// In pt, this message translates to:
  /// **'Toque em \"Procurar\" para encontrar dispositivos'**
  String get connectTapHint;

  /// No description provided for @connectDeviceBLE.
  ///
  /// In pt, this message translates to:
  /// **'(Bluetooth LE)'**
  String get connectDeviceBLE;

  /// No description provided for @connectDeviceUSB.
  ///
  /// In pt, this message translates to:
  /// **'(Série USB — Companion)'**
  String get connectDeviceUSB;

  /// No description provided for @connectDeviceKISS.
  ///
  /// In pt, this message translates to:
  /// **'(KISS TNC)'**
  String get connectDeviceKISS;

  /// No description provided for @connectStepConnecting.
  ///
  /// In pt, this message translates to:
  /// **'A ligar...'**
  String get connectStepConnecting;

  /// No description provided for @connectStepWaiting.
  ///
  /// In pt, this message translates to:
  /// **'A aguardar rádio...'**
  String get connectStepWaiting;

  /// No description provided for @connectStepDeviceInfo.
  ///
  /// In pt, this message translates to:
  /// **'Informação do dispositivo'**
  String get connectStepDeviceInfo;

  /// No description provided for @connectStepContacts.
  ///
  /// In pt, this message translates to:
  /// **'Contactos'**
  String get connectStepContacts;

  /// No description provided for @connectStepChannels.
  ///
  /// In pt, this message translates to:
  /// **'Canais'**
  String get connectStepChannels;

  /// No description provided for @connectStepDone.
  ///
  /// In pt, this message translates to:
  /// **'Concluído'**
  String get connectStepDone;

  /// No description provided for @connectBluetoothOffTitle.
  ///
  /// In pt, this message translates to:
  /// **'Bluetooth desligado'**
  String get connectBluetoothOffTitle;

  /// No description provided for @connectBluetoothOffMessage.
  ///
  /// In pt, this message translates to:
  /// **'O Bluetooth está desligado. Deseja activá-lo para ligar ao rádio MeshCore?'**
  String get connectBluetoothOffMessage;

  /// No description provided for @connectBluetoothEnable.
  ///
  /// In pt, this message translates to:
  /// **'Activar'**
  String get connectBluetoothEnable;

  /// No description provided for @connectBluetoothDeniedTitle.
  ///
  /// In pt, this message translates to:
  /// **'Activação do Bluetooth recusada'**
  String get connectBluetoothDeniedTitle;

  /// No description provided for @connectBluetoothDeniedMessage.
  ///
  /// In pt, this message translates to:
  /// **'Por favor active o Bluetooth nas Definições do sistema'**
  String get connectBluetoothDeniedMessage;

  /// No description provided for @connectBluetoothOff.
  ///
  /// In pt, this message translates to:
  /// **'Bluetooth desligado. Ligue o Bluetooth para procurar dispositivos'**
  String get connectBluetoothOff;

  /// No description provided for @connectBluetoothPermission.
  ///
  /// In pt, this message translates to:
  /// **'Permissões Bluetooth necessárias para procurar dispositivos'**
  String get connectBluetoothPermission;

  /// No description provided for @connectOpenSettings.
  ///
  /// In pt, this message translates to:
  /// **'Definições'**
  String get connectOpenSettings;

  /// No description provided for @connectFailTitle.
  ///
  /// In pt, this message translates to:
  /// **'Falha ao ligar ao dispositivo'**
  String get connectFailTitle;

  /// No description provided for @connectLastFailTitle.
  ///
  /// In pt, this message translates to:
  /// **'Falha ao ligar ao último dispositivo'**
  String get connectLastFailTitle;

  /// No description provided for @discoverTitle.
  ///
  /// In pt, this message translates to:
  /// **'Descobrir'**
  String get discoverTitle;

  /// No description provided for @discoverSubtitle.
  ///
  /// In pt, this message translates to:
  /// **'Anúncios Recentes'**
  String get discoverSubtitle;

  /// No description provided for @discoverSearchHint.
  ///
  /// In pt, this message translates to:
  /// **'Procurar contactos descobertos...'**
  String get discoverSearchHint;

  /// No description provided for @discoverEmpty.
  ///
  /// In pt, this message translates to:
  /// **'Nenhum contacto encontrado'**
  String get discoverEmpty;

  /// No description provided for @discoverEmptyHint.
  ///
  /// In pt, this message translates to:
  /// **'Tente uma busca diferente'**
  String get discoverEmptyHint;

  /// No description provided for @discoverNone.
  ///
  /// In pt, this message translates to:
  /// **'Nenhum contacto descoberto'**
  String get discoverNone;

  /// No description provided for @discoverNoneHint.
  ///
  /// In pt, this message translates to:
  /// **'Contactos aparecem enquanto transmitem na rede'**
  String get discoverNoneHint;

  /// No description provided for @discoverSaveToRadio.
  ///
  /// In pt, this message translates to:
  /// **'Guardar no rádio'**
  String get discoverSaveToRadio;

  /// No description provided for @discoverSendMessage.
  ///
  /// In pt, this message translates to:
  /// **'Enviar mensagem'**
  String get discoverSendMessage;

  /// No description provided for @discoverJoinRoom.
  ///
  /// In pt, this message translates to:
  /// **'Entrar na sala'**
  String get discoverJoinRoom;

  /// No description provided for @discoverAddAndSave.
  ///
  /// In pt, this message translates to:
  /// **'Adicionar e guardar'**
  String get discoverAddAndSave;

  /// No description provided for @discoverAnnouncedName.
  ///
  /// In pt, this message translates to:
  /// **'Nome Anunciado'**
  String get discoverAnnouncedName;

  /// No description provided for @discoverHeard.
  ///
  /// In pt, this message translates to:
  /// **'Ouvido'**
  String get discoverHeard;

  /// No description provided for @discoverNever.
  ///
  /// In pt, this message translates to:
  /// **'Nunca'**
  String get discoverNever;

  /// No description provided for @discoverNoName.
  ///
  /// In pt, this message translates to:
  /// **'Sem nome'**
  String get discoverNoName;

  /// No description provided for @discoverTypeCompanion.
  ///
  /// In pt, this message translates to:
  /// **'Companheiro'**
  String get discoverTypeCompanion;

  /// No description provided for @discoverTypeUnknown.
  ///
  /// In pt, this message translates to:
  /// **'Desconhecido'**
  String get discoverTypeUnknown;

  /// No description provided for @discoverPathNear.
  ///
  /// In pt, this message translates to:
  /// **'Próximo'**
  String get discoverPathNear;

  /// No description provided for @discoverJustNow.
  ///
  /// In pt, this message translates to:
  /// **'Agora'**
  String get discoverJustNow;

  /// No description provided for @discoverMinutesAgo.
  ///
  /// In pt, this message translates to:
  /// **'{min}m atrás'**
  String discoverMinutesAgo(int min);

  /// No description provided for @discoverHoursAgo.
  ///
  /// In pt, this message translates to:
  /// **'{hours}h atrás'**
  String discoverHoursAgo(int hours);

  /// No description provided for @discoverDaysAgo.
  ///
  /// In pt, this message translates to:
  /// **'{days}d atrás'**
  String discoverDaysAgo(int days);

  /// No description provided for @appsPlano333Title.
  ///
  /// In pt, this message translates to:
  /// **'Plano 3-3-3'**
  String get appsPlano333Title;

  /// No description provided for @appsPlano333Subtitle.
  ///
  /// In pt, this message translates to:
  /// **'Evento semanal MeshCore'**
  String get appsPlano333Subtitle;

  /// No description provided for @appsTelemetryTitle.
  ///
  /// In pt, this message translates to:
  /// **'Telemetria'**
  String get appsTelemetryTitle;

  /// No description provided for @appsTelemetrySubtitle.
  ///
  /// In pt, this message translates to:
  /// **'Bateria, RF e contadores'**
  String get appsTelemetrySubtitle;

  /// No description provided for @appsRxLogTitle.
  ///
  /// In pt, this message translates to:
  /// **'RX Log'**
  String get appsRxLogTitle;

  /// No description provided for @appsRxLogSubtitle.
  ///
  /// In pt, this message translates to:
  /// **'Captura e exporta PCAP'**
  String get appsRxLogSubtitle;

  /// No description provided for @appsQrTitle.
  ///
  /// In pt, this message translates to:
  /// **'Leitor QR'**
  String get appsQrTitle;

  /// No description provided for @appsQrSubtitle.
  ///
  /// In pt, this message translates to:
  /// **'Digitalizar código QR'**
  String get appsQrSubtitle;

  /// No description provided for @mapNoGps.
  ///
  /// In pt, this message translates to:
  /// **'Sem dados GPS. Toca em \"Localizar\" ou aguarda contactos com coordenadas'**
  String get mapNoGps;

  /// No description provided for @mapShareMap.
  ///
  /// In pt, this message translates to:
  /// **'Partilhar mapa'**
  String get mapShareMap;

  /// No description provided for @mapViewAll.
  ///
  /// In pt, this message translates to:
  /// **'Ver todos'**
  String get mapViewAll;

  /// No description provided for @mapCenterMyPosition.
  ///
  /// In pt, this message translates to:
  /// **'Centrar na minha posição'**
  String get mapCenterMyPosition;

  /// No description provided for @mapGetGps.
  ///
  /// In pt, this message translates to:
  /// **'Obter localização GPS'**
  String get mapGetGps;

  /// No description provided for @mapLocationDisabled.
  ///
  /// In pt, this message translates to:
  /// **'Serviço de localização desactivado'**
  String get mapLocationDisabled;

  /// No description provided for @mapLocationDenied.
  ///
  /// In pt, this message translates to:
  /// **'Permissão de localização negada'**
  String get mapLocationDenied;

  /// No description provided for @mapLocationDeniedPermanently.
  ///
  /// In pt, this message translates to:
  /// **'Permissão de localização negada permanentemente'**
  String get mapLocationDeniedPermanently;

  /// No description provided for @mapLocationError.
  ///
  /// In pt, this message translates to:
  /// **'Erro ao obter localização GPS'**
  String get mapLocationError;

  /// No description provided for @mapCaptureError.
  ///
  /// In pt, this message translates to:
  /// **'Não foi possível capturar o mapa'**
  String get mapCaptureError;

  /// No description provided for @mapImageError.
  ///
  /// In pt, this message translates to:
  /// **'Falha ao gerar imagem do mapa'**
  String get mapImageError;

  /// No description provided for @mapShareError.
  ///
  /// In pt, this message translates to:
  /// **'Erro ao partilhar o mapa'**
  String get mapShareError;

  /// No description provided for @mapNodesAtLocation.
  ///
  /// In pt, this message translates to:
  /// **'nós nesta localização'**
  String get mapNodesAtLocation;

  /// No description provided for @mapMinimizeList.
  ///
  /// In pt, this message translates to:
  /// **'Minimizar lista'**
  String get mapMinimizeList;

  /// No description provided for @mapShowMore.
  ///
  /// In pt, this message translates to:
  /// **'Mostrar +'**
  String get mapShowMore;

  /// No description provided for @mapHops.
  ///
  /// In pt, this message translates to:
  /// **'hop(s)'**
  String get mapHops;

  /// No description provided for @mapFinal.
  ///
  /// In pt, this message translates to:
  /// **'Final:'**
  String get mapFinal;

  /// No description provided for @mapAttribution.
  ///
  /// In pt, this message translates to:
  /// **'MeshCore Portugal'**
  String get mapAttribution;

  /// No description provided for @mapAttributionOSM.
  ///
  /// In pt, this message translates to:
  /// **'© OpenStreetMap contributors'**
  String get mapAttributionOSM;

  /// No description provided for @mapPathPrefix.
  ///
  /// In pt, this message translates to:
  /// **'Path ·'**
  String get mapPathPrefix;

  /// No description provided for @privateNoMessages.
  ///
  /// In pt, this message translates to:
  /// **'Sem mensagens'**
  String get privateNoMessages;

  /// No description provided for @privateSendFirstMessage.
  ///
  /// In pt, this message translates to:
  /// **'Envie a primeira mensagem!'**
  String get privateSendFirstMessage;

  /// No description provided for @privateMessageTo.
  ///
  /// In pt, this message translates to:
  /// **'Mensagem para {name}...'**
  String privateMessageTo(String name);

  /// No description provided for @privateTracingRoute.
  ///
  /// In pt, this message translates to:
  /// **'A traçar rota para {name}'**
  String privateTracingRoute(String name);

  /// No description provided for @privateRouteFailed.
  ///
  /// In pt, this message translates to:
  /// **'Não foi possível descobrir a rota — tente novamente'**
  String get privateRouteFailed;

  /// No description provided for @privateRouteNoResponse.
  ///
  /// In pt, this message translates to:
  /// **'Sem resposta à rota — tente novamente'**
  String get privateRouteNoResponse;

  /// No description provided for @privateRouteFound.
  ///
  /// In pt, this message translates to:
  /// **'Rota encontrada —'**
  String get privateRouteFound;

  /// No description provided for @privateDirectRoute.
  ///
  /// In pt, this message translates to:
  /// **'Rota directa (sem repetidores)'**
  String get privateDirectRoute;

  /// No description provided for @privateReceivedOnRadio.
  ///
  /// In pt, this message translates to:
  /// **'Recebido no rádio'**
  String get privateReceivedOnRadio;

  /// No description provided for @privateConfirmed.
  ///
  /// In pt, this message translates to:
  /// **'Confirmado'**
  String get privateConfirmed;

  /// No description provided for @privatePending.
  ///
  /// In pt, this message translates to:
  /// **'Pendente'**
  String get privatePending;

  /// No description provided for @privateSentVia.
  ///
  /// In pt, this message translates to:
  /// **'Enviado via'**
  String get privateSentVia;

  /// No description provided for @privateTraceRoute.
  ///
  /// In pt, this message translates to:
  /// **'Traçar rota'**
  String get privateTraceRoute;

  /// No description provided for @privateManagePath.
  ///
  /// In pt, this message translates to:
  /// **'Gerir caminho'**
  String get privateManagePath;

  /// No description provided for @privateContactLabel.
  ///
  /// In pt, this message translates to:
  /// **'Contacto'**
  String get privateContactLabel;

  /// No description provided for @qrTitle.
  ///
  /// In pt, this message translates to:
  /// **'Ler QR Code'**
  String get qrTitle;

  /// No description provided for @qrUnavailable.
  ///
  /// In pt, this message translates to:
  /// **'Scanner de QR Code não disponível nesta plataforma'**
  String get qrUnavailable;

  /// No description provided for @qrUnavailableHint.
  ///
  /// In pt, this message translates to:
  /// **'Use um dispositivo Android ou iOS'**
  String get qrUnavailableHint;

  /// No description provided for @qrHint.
  ///
  /// In pt, this message translates to:
  /// **'Aponte para um QR Code MeshCore'**
  String get qrHint;

  /// No description provided for @radioSettingsTitle.
  ///
  /// In pt, this message translates to:
  /// **'Configuração do Rádio'**
  String get radioSettingsTitle;

  /// No description provided for @radioSettingsDevice.
  ///
  /// In pt, this message translates to:
  /// **'Dispositivo'**
  String get radioSettingsDevice;

  /// No description provided for @radioSettingsModel.
  ///
  /// In pt, this message translates to:
  /// **'Modelo'**
  String get radioSettingsModel;

  /// No description provided for @radioSettingsFirmware.
  ///
  /// In pt, this message translates to:
  /// **'Firmware'**
  String get radioSettingsFirmware;

  /// No description provided for @radioSettingsStorage.
  ///
  /// In pt, this message translates to:
  /// **'Armazenamento'**
  String get radioSettingsStorage;

  /// No description provided for @radioSettingsChannels.
  ///
  /// In pt, this message translates to:
  /// **'Canais'**
  String get radioSettingsChannels;

  /// No description provided for @radioSettingsContacts.
  ///
  /// In pt, this message translates to:
  /// **'Contactos'**
  String get radioSettingsContacts;

  /// No description provided for @radioSettingsDiscovered.
  ///
  /// In pt, this message translates to:
  /// **'Descobertos'**
  String get radioSettingsDiscovered;

  /// No description provided for @radioSettingsAppVersion.
  ///
  /// In pt, this message translates to:
  /// **'Versão da App'**
  String get radioSettingsAppVersion;

  /// No description provided for @radioSettingsLoRa.
  ///
  /// In pt, this message translates to:
  /// **'Parâmetros LoRa'**
  String get radioSettingsLoRa;

  /// No description provided for @radioSettingsFrequency.
  ///
  /// In pt, this message translates to:
  /// **'Frequência (MHz)'**
  String get radioSettingsFrequency;

  /// No description provided for @radioSettingsFreqLabel.
  ///
  /// In pt, this message translates to:
  /// **'Frequência'**
  String get radioSettingsFreqLabel;

  /// No description provided for @radioSettingsFrequencyHint.
  ///
  /// In pt, this message translates to:
  /// **'Ex: 868.1250'**
  String get radioSettingsFrequencyHint;

  /// No description provided for @radioSettingsBandwidth.
  ///
  /// In pt, this message translates to:
  /// **'Largura de banda'**
  String get radioSettingsBandwidth;

  /// No description provided for @radioSettingsSpreadingFactor.
  ///
  /// In pt, this message translates to:
  /// **'Spreading Factor'**
  String get radioSettingsSpreadingFactor;

  /// No description provided for @radioSettingsCodingRate.
  ///
  /// In pt, this message translates to:
  /// **'Coding Rate'**
  String get radioSettingsCodingRate;

  /// No description provided for @radioSettingsTxPower.
  ///
  /// In pt, this message translates to:
  /// **'Potência TX'**
  String get radioSettingsTxPower;

  /// No description provided for @radioSettingsMax.
  ///
  /// In pt, this message translates to:
  /// **'Máx:'**
  String get radioSettingsMax;

  /// No description provided for @radioSettingsDbm.
  ///
  /// In pt, this message translates to:
  /// **'dBm'**
  String get radioSettingsDbm;

  /// No description provided for @radioSettingsFrequencyRequired.
  ///
  /// In pt, this message translates to:
  /// **'Insere a frequência'**
  String get radioSettingsFrequencyRequired;

  /// No description provided for @radioSettingsFrequencyInvalid.
  ///
  /// In pt, this message translates to:
  /// **'Frequência inválida (150–2500 MHz)'**
  String get radioSettingsFrequencyInvalid;

  /// No description provided for @radioSettingsBandwidthRequired.
  ///
  /// In pt, this message translates to:
  /// **'Selecciona a largura de banda'**
  String get radioSettingsBandwidthRequired;

  /// No description provided for @radioSettingsSFRequired.
  ///
  /// In pt, this message translates to:
  /// **'Selecciona o spreading factor'**
  String get radioSettingsSFRequired;

  /// No description provided for @radioSettingsCRRequired.
  ///
  /// In pt, this message translates to:
  /// **'Selecciona o coding rate'**
  String get radioSettingsCRRequired;

  /// No description provided for @radioSettingsPowerRequired.
  ///
  /// In pt, this message translates to:
  /// **'Insere a potência'**
  String get radioSettingsPowerRequired;

  /// No description provided for @radioSettingsPowerInvalid.
  ///
  /// In pt, this message translates to:
  /// **'Potência inválida (1–30 dBm)'**
  String get radioSettingsPowerInvalid;

  /// No description provided for @radioSettingsActiveConfig.
  ///
  /// In pt, this message translates to:
  /// **'Configuração Activa'**
  String get radioSettingsActiveConfig;

  /// No description provided for @radioSettingsSaved.
  ///
  /// In pt, this message translates to:
  /// **'Configuração guardada'**
  String get radioSettingsSaved;

  /// No description provided for @radioSettingsPrivKeyCopied.
  ///
  /// In pt, this message translates to:
  /// **'Chave privada copiada'**
  String get radioSettingsPrivKeyCopied;

  /// No description provided for @radioSettingsResetValues.
  ///
  /// In pt, this message translates to:
  /// **'Repor valores actuais'**
  String get radioSettingsResetValues;

  /// No description provided for @radioSettingsAutoAddTitle.
  ///
  /// In pt, this message translates to:
  /// **'Definições de Contactos'**
  String get radioSettingsAutoAddTitle;

  /// No description provided for @radioSettingsAutoAddDesc.
  ///
  /// In pt, this message translates to:
  /// **'Quando um nó envia um advert e o rádio está em modo manual, adicionar automaticamente como:'**
  String get radioSettingsAutoAddDesc;

  /// No description provided for @radioSettingsAutoAddAll.
  ///
  /// In pt, this message translates to:
  /// **'Auto Adicionar Todos'**
  String get radioSettingsAutoAddAll;

  /// No description provided for @radioSettingsAutoAddAllDesc.
  ///
  /// In pt, this message translates to:
  /// **'Quando ativo, todos os adverts recebidos serão adicionados aos contactos.'**
  String get radioSettingsAutoAddAllDesc;

  /// No description provided for @radioSettingsAutoAddSelected.
  ///
  /// In pt, this message translates to:
  /// **'Auto Adicionar Selecionados'**
  String get radioSettingsAutoAddSelected;

  /// No description provided for @radioSettingsAutoAddSelectedDesc.
  ///
  /// In pt, this message translates to:
  /// **'Quando ativo, apenas os tipos de contactos selecionados abaixo serão auto adicionados.'**
  String get radioSettingsAutoAddSelectedDesc;

  /// No description provided for @radioSettingsAutoAddCompanion.
  ///
  /// In pt, this message translates to:
  /// **'Companheiro (Chat)'**
  String get radioSettingsAutoAddCompanion;

  /// No description provided for @radioSettingsAutoAddRepeater.
  ///
  /// In pt, this message translates to:
  /// **'Repetidor'**
  String get radioSettingsAutoAddRepeater;

  /// No description provided for @radioSettingsAutoAddRoom.
  ///
  /// In pt, this message translates to:
  /// **'Sala (Room)'**
  String get radioSettingsAutoAddRoom;

  /// No description provided for @radioSettingsAutoAddSensor.
  ///
  /// In pt, this message translates to:
  /// **'Sensor'**
  String get radioSettingsAutoAddSensor;

  /// No description provided for @radioSettingsOverwriteOldest.
  ///
  /// In pt, this message translates to:
  /// **'Sobrescrever Mais Antigo'**
  String get radioSettingsOverwriteOldest;

  /// No description provided for @radioSettingsOverwriteOldestDesc.
  ///
  /// In pt, this message translates to:
  /// **'Quando ativo, os contactos mais antigos sem favorito são substituídos por novos quando a lista está cheia.'**
  String get radioSettingsOverwriteOldestDesc;

  /// No description provided for @radioSettingsAutoAddMaxHops.
  ///
  /// In pt, this message translates to:
  /// **'Saltos Máximos de Auto Adição'**
  String get radioSettingsAutoAddMaxHops;

  /// No description provided for @radioSettingsAutoAddMaxHopsDesc.
  ///
  /// In pt, this message translates to:
  /// **'Os contactos só serão auto adicionados se o caminho do advert tiver o mesmo ou menos saltos que o limite. Deixe em branco para sem limite.'**
  String get radioSettingsAutoAddMaxHopsDesc;

  /// No description provided for @radioSettingsAutoAddMaxHopsHint.
  ///
  /// In pt, this message translates to:
  /// **'Saltos (0-63)'**
  String get radioSettingsAutoAddMaxHopsHint;

  /// No description provided for @radioSettingsPullToRefresh.
  ///
  /// In pt, this message translates to:
  /// **'Puxar para Atualizar'**
  String get radioSettingsPullToRefresh;

  /// No description provided for @radioSettingsPullToRefreshDesc.
  ///
  /// In pt, this message translates to:
  /// **'Quando ativo, pode deslizar para baixo para atualizar a lista de contactos.'**
  String get radioSettingsPullToRefreshDesc;

  /// No description provided for @radioSettingsShowPublicKeys.
  ///
  /// In pt, this message translates to:
  /// **'Mostrar Chaves Públicas'**
  String get radioSettingsShowPublicKeys;

  /// No description provided for @radioSettingsShowPublicKeysDesc.
  ///
  /// In pt, this message translates to:
  /// **'Quando ativo, as chaves públicas serão mostradas na lista de contactos.'**
  String get radioSettingsShowPublicKeysDesc;

  /// No description provided for @radioSettingsBandPresetsTitle.
  ///
  /// In pt, this message translates to:
  /// **'Predefinições de Banda'**
  String get radioSettingsBandPresetsTitle;

  /// No description provided for @roomJoinTitle.
  ///
  /// In pt, this message translates to:
  /// **'Entrar na sala'**
  String get roomJoinTitle;

  /// No description provided for @roomJoinInstruction.
  ///
  /// In pt, this message translates to:
  /// **'Esta sala pode requerer uma palavra-passe. Deixe em branco se for pública.'**
  String get roomJoinInstruction;

  /// No description provided for @roomPasswordLabel.
  ///
  /// In pt, this message translates to:
  /// **'Palavra-passe (opcional)'**
  String get roomPasswordLabel;

  /// No description provided for @roomPasswordHint.
  ///
  /// In pt, this message translates to:
  /// **'Deixar em branco se sem palavra-passe'**
  String get roomPasswordHint;

  /// No description provided for @roomJoinFailed.
  ///
  /// In pt, this message translates to:
  /// **'Falhou — verifique a palavra-passe'**
  String get roomJoinFailed;

  /// No description provided for @roomJoining.
  ///
  /// In pt, this message translates to:
  /// **'A ligar...'**
  String get roomJoining;

  /// No description provided for @roomJoinError.
  ///
  /// In pt, this message translates to:
  /// **'Não foi possível entrar na sala. Verifique a palavra-passe e tente novamente.'**
  String get roomJoinError;

  /// No description provided for @roomReplyStrip.
  ///
  /// In pt, this message translates to:
  /// **'Sala'**
  String get roomReplyStrip;

  /// No description provided for @roomMessageHint.
  ///
  /// In pt, this message translates to:
  /// **'Mensagem para {name} sala...'**
  String roomMessageHint(String name);

  /// No description provided for @roomMessageFallback.
  ///
  /// In pt, this message translates to:
  /// **'Escreva uma mensagem...'**
  String get roomMessageFallback;

  /// No description provided for @roomTelemetryData.
  ///
  /// In pt, this message translates to:
  /// **'Dados de telemetria'**
  String get roomTelemetryData;

  /// No description provided for @rxLogTitle.
  ///
  /// In pt, this message translates to:
  /// **'RX Log'**
  String get rxLogTitle;

  /// No description provided for @rxLogExportPcap.
  ///
  /// In pt, this message translates to:
  /// **'Exportar PCAPNG'**
  String get rxLogExportPcap;

  /// No description provided for @rxLogClearLog.
  ///
  /// In pt, this message translates to:
  /// **'Limpar log'**
  String get rxLogClearLog;

  /// No description provided for @rxLogPacketCount.
  ///
  /// In pt, this message translates to:
  /// **'pacotes capturados'**
  String get rxLogPacketCount;

  /// No description provided for @rxLogClearTitle.
  ///
  /// In pt, this message translates to:
  /// **'Limpar RX Log'**
  String get rxLogClearTitle;

  /// No description provided for @rxLogClearConfirm.
  ///
  /// In pt, this message translates to:
  /// **'Remover todos os pacotes capturados?'**
  String get rxLogClearConfirm;

  /// No description provided for @rxLogEmpty.
  ///
  /// In pt, this message translates to:
  /// **'RX Log vazio - nada para exportar'**
  String get rxLogEmpty;

  /// No description provided for @rxLogExportFail.
  ///
  /// In pt, this message translates to:
  /// **'Falha ao exportar PCAPNG'**
  String get rxLogExportFail;

  /// No description provided for @rxLogPacketAdvert.
  ///
  /// In pt, this message translates to:
  /// **'Advert'**
  String get rxLogPacketAdvert;

  /// No description provided for @rxLogPacketGroupText.
  ///
  /// In pt, this message translates to:
  /// **'Group Text'**
  String get rxLogPacketGroupText;

  /// No description provided for @rxLogPacketPrivateText.
  ///
  /// In pt, this message translates to:
  /// **'Private Text'**
  String get rxLogPacketPrivateText;

  /// No description provided for @rxLogPacketPath.
  ///
  /// In pt, this message translates to:
  /// **'Path'**
  String get rxLogPacketPath;

  /// No description provided for @rxLogPacketControl.
  ///
  /// In pt, this message translates to:
  /// **'Control'**
  String get rxLogPacketControl;

  /// No description provided for @rxLogPacketTypePrefix.
  ///
  /// In pt, this message translates to:
  /// **'Tipo'**
  String get rxLogPacketTypePrefix;

  /// No description provided for @rxLogEmptyTitle.
  ///
  /// In pt, this message translates to:
  /// **'Sem pacotes RX'**
  String get rxLogEmptyTitle;

  /// No description provided for @rxLogEmptyHint.
  ///
  /// In pt, this message translates to:
  /// **'Quando a rádio receber tráfego mesh, os pacotes aparecem aqui.'**
  String get rxLogEmptyHint;

  /// No description provided for @telemetryBattery.
  ///
  /// In pt, this message translates to:
  /// **'Bateria'**
  String get telemetryBattery;

  /// No description provided for @telemetryNetStats.
  ///
  /// In pt, this message translates to:
  /// **'Estatísticas da Rede'**
  String get telemetryNetStats;

  /// No description provided for @telemetryRadioState.
  ///
  /// In pt, this message translates to:
  /// **'Rádio — Estado'**
  String get telemetryRadioState;

  /// No description provided for @telemetryRadioWaiting.
  ///
  /// In pt, this message translates to:
  /// **'A aguardar estatísticas do rádio...'**
  String get telemetryRadioWaiting;

  /// No description provided for @telemetryRadioRF.
  ///
  /// In pt, this message translates to:
  /// **'Rádio — RF'**
  String get telemetryRadioRF;

  /// No description provided for @telemetryRFWaiting.
  ///
  /// In pt, this message translates to:
  /// **'A aguardar estatísticas de RF...'**
  String get telemetryRFWaiting;

  /// No description provided for @telemetryPacketCounters.
  ///
  /// In pt, this message translates to:
  /// **'Rádio — Contadores de Pacotes'**
  String get telemetryPacketCounters;

  /// No description provided for @telemetryCountersWaiting.
  ///
  /// In pt, this message translates to:
  /// **'A aguardar contadores de pacotes...'**
  String get telemetryCountersWaiting;

  /// No description provided for @telemetrySensors.
  ///
  /// In pt, this message translates to:
  /// **'Sensores (Telemetria)'**
  String get telemetrySensors;

  /// No description provided for @telemetryNoData.
  ///
  /// In pt, this message translates to:
  /// **'Nenhuma telemetria recebida.'**
  String get telemetryNoData;

  /// No description provided for @telemetrySamplesSuffix.
  ///
  /// In pt, this message translates to:
  /// **'amostras'**
  String get telemetrySamplesSuffix;

  /// No description provided for @telemetryNow.
  ///
  /// In pt, this message translates to:
  /// **'Agora'**
  String get telemetryNow;

  /// No description provided for @telemetryHistoryHint.
  ///
  /// In pt, this message translates to:
  /// **'O histórico aparece após a primeira leitura de bateria.'**
  String get telemetryHistoryHint;

  /// No description provided for @telemetryRX.
  ///
  /// In pt, this message translates to:
  /// **'RX'**
  String get telemetryRX;

  /// No description provided for @telemetryTX.
  ///
  /// In pt, this message translates to:
  /// **'TX'**
  String get telemetryTX;

  /// No description provided for @telemetryHeard.
  ///
  /// In pt, this message translates to:
  /// **'Ouvidos'**
  String get telemetryHeard;

  /// No description provided for @telemetryCardPrefix.
  ///
  /// In pt, this message translates to:
  /// **'Telemetria —'**
  String get telemetryCardPrefix;

  /// No description provided for @telemetryUptime.
  ///
  /// In pt, this message translates to:
  /// **'Uptime'**
  String get telemetryUptime;

  /// No description provided for @telemetryTxQueue.
  ///
  /// In pt, this message translates to:
  /// **'Fila TX'**
  String get telemetryTxQueue;

  /// No description provided for @telemetryErrorsPrefix.
  ///
  /// In pt, this message translates to:
  /// **'Erros:'**
  String get telemetryErrorsPrefix;

  /// No description provided for @telemetryRSSI.
  ///
  /// In pt, this message translates to:
  /// **'RSSI'**
  String get telemetryRSSI;

  /// No description provided for @telemetryNoise.
  ///
  /// In pt, this message translates to:
  /// **'Ruído'**
  String get telemetryNoise;

  /// No description provided for @telemetrySNR.
  ///
  /// In pt, this message translates to:
  /// **'SNR'**
  String get telemetrySNR;

  /// No description provided for @telemetryAirtimeTX.
  ///
  /// In pt, this message translates to:
  /// **'Airtime TX'**
  String get telemetryAirtimeTX;

  /// No description provided for @telemetryAirtimeRX.
  ///
  /// In pt, this message translates to:
  /// **'Airtime RX'**
  String get telemetryAirtimeRX;

  /// No description provided for @telemetryErrors.
  ///
  /// In pt, this message translates to:
  /// **'Erros'**
  String get telemetryErrors;

  /// No description provided for @telemetryRXTotal.
  ///
  /// In pt, this message translates to:
  /// **'RX Total'**
  String get telemetryRXTotal;

  /// No description provided for @telemetryTXTotal.
  ///
  /// In pt, this message translates to:
  /// **'TX Total'**
  String get telemetryTXTotal;

  /// No description provided for @telemetryErrorsRX.
  ///
  /// In pt, this message translates to:
  /// **'Erros RX'**
  String get telemetryErrorsRX;

  /// No description provided for @telemetryFloodTX.
  ///
  /// In pt, this message translates to:
  /// **'Flood TX'**
  String get telemetryFloodTX;

  /// No description provided for @telemetryFloodRX.
  ///
  /// In pt, this message translates to:
  /// **'Flood RX'**
  String get telemetryFloodRX;

  /// No description provided for @telemetryDirectTX.
  ///
  /// In pt, this message translates to:
  /// **'Direto TX'**
  String get telemetryDirectTX;

  /// No description provided for @telemetryDirectRX.
  ///
  /// In pt, this message translates to:
  /// **'Direto RX'**
  String get telemetryDirectRX;

  /// No description provided for @eventTitle.
  ///
  /// In pt, this message translates to:
  /// **'Programa do Evento'**
  String get eventTitle;

  /// No description provided for @eventDateLabel.
  ///
  /// In pt, this message translates to:
  /// **'Abril 2026'**
  String get eventDateLabel;

  /// No description provided for @eventSummitTitle.
  ///
  /// In pt, this message translates to:
  /// **'Tech Summit 2026'**
  String get eventSummitTitle;

  /// No description provided for @eventSummitSubtitle.
  ///
  /// In pt, this message translates to:
  /// **'MeshCore Portugal'**
  String get eventSummitSubtitle;

  /// No description provided for @eventMorning.
  ///
  /// In pt, this message translates to:
  /// **'Manhã'**
  String get eventMorning;

  /// No description provided for @eventAfternoon.
  ///
  /// In pt, this message translates to:
  /// **'Tarde'**
  String get eventAfternoon;

  /// No description provided for @eventWorkshops.
  ///
  /// In pt, this message translates to:
  /// **'Workshops (sala paralela)'**
  String get eventWorkshops;

  /// No description provided for @eventAddChannel.
  ///
  /// In pt, this message translates to:
  /// **'Adicionar'**
  String get eventAddChannel;

  /// No description provided for @eventChannelSheetTitle.
  ///
  /// In pt, this message translates to:
  /// **'Canal MeshCore  #plano333'**
  String get eventChannelSheetTitle;

  /// No description provided for @eventChannelSheetDesc.
  ///
  /// In pt, this message translates to:
  /// **'Adiciona o canal ao rádio ligado ou consulte os dados manualmente.'**
  String get eventChannelSheetDesc;

  /// No description provided for @eventChannelAdded.
  ///
  /// In pt, this message translates to:
  /// **'Canal #plano333 adicionado no slot {slot}'**
  String eventChannelAdded(int slot);

  /// No description provided for @eventChannelNotFound.
  ///
  /// In pt, this message translates to:
  /// **'Canal #techsummit2026 não encontrado no rádio.'**
  String get eventChannelNotFound;

  /// No description provided for @eventChannelNoSlots.
  ///
  /// In pt, this message translates to:
  /// **'Sem slots de canal disponíveis para adicionar #techsummit2026.'**
  String get eventChannelNoSlots;

  /// No description provided for @plan333CardTitle.
  ///
  /// In pt, this message translates to:
  /// **'MESH 3-3-3'**
  String get plan333CardTitle;

  /// No description provided for @plan333EventActive.
  ///
  /// In pt, this message translates to:
  /// **'● EVENTO ACTIVO'**
  String get plan333EventActive;

  /// No description provided for @plan333PhaseCQ.
  ///
  /// In pt, this message translates to:
  /// **'CQ 21:00–22:00'**
  String get plan333PhaseCQ;

  /// No description provided for @plan333CqSent.
  ///
  /// In pt, this message translates to:
  /// **'CQ enviados:'**
  String get plan333CqSent;

  /// No description provided for @plan333LastSent.
  ///
  /// In pt, this message translates to:
  /// **'(último:'**
  String get plan333LastSent;

  /// No description provided for @plan333EventSchedule.
  ///
  /// In pt, this message translates to:
  /// **'Sábados 21:00–22:00  •  CQ Presenças MeshCore'**
  String get plan333EventSchedule;

  /// No description provided for @plan333ReportPrefix.
  ///
  /// In pt, this message translates to:
  /// **'Relatório em'**
  String get plan333ReportPrefix;

  /// No description provided for @plan333ConfigTitle.
  ///
  /// In pt, this message translates to:
  /// **'Configuração do Evento'**
  String get plan333ConfigTitle;

  /// No description provided for @plan333StationName.
  ///
  /// In pt, this message translates to:
  /// **'Nome de estação *'**
  String get plan333StationName;

  /// No description provided for @plan333StationNameHint.
  ///
  /// In pt, this message translates to:
  /// **'Ex: Mike 05'**
  String get plan333StationNameHint;

  /// No description provided for @plan333City.
  ///
  /// In pt, this message translates to:
  /// **'Cidade *'**
  String get plan333City;

  /// No description provided for @plan333CityHint.
  ///
  /// In pt, this message translates to:
  /// **'Ex: Lisboa'**
  String get plan333CityHint;

  /// No description provided for @plan333Locality.
  ///
  /// In pt, this message translates to:
  /// **'Localidade'**
  String get plan333Locality;

  /// No description provided for @plan333LocalityHint.
  ///
  /// In pt, this message translates to:
  /// **'Ex: Olaias'**
  String get plan333LocalityHint;

  /// No description provided for @plan333AutoSend.
  ///
  /// In pt, this message translates to:
  /// **'Envio automático de CQ'**
  String get plan333AutoSend;

  /// No description provided for @plan333AutoSendDesc.
  ///
  /// In pt, this message translates to:
  /// **'CQ: até 3 mensagens (21:00–22:00)'**
  String get plan333AutoSendDesc;

  /// No description provided for @plan333CqMessageLabel.
  ///
  /// In pt, this message translates to:
  /// **'Mensagem CQ:'**
  String get plan333CqMessageLabel;

  /// No description provided for @plan333FormatTitle.
  ///
  /// In pt, this message translates to:
  /// **'Formatos de Mensagem'**
  String get plan333FormatTitle;

  /// No description provided for @plan333FormatPresence.
  ///
  /// In pt, this message translates to:
  /// **'Presença (CQ)'**
  String get plan333FormatPresence;

  /// No description provided for @plan333FormatPresencePhase.
  ///
  /// In pt, this message translates to:
  /// **'MeshCore 21:00–22:00'**
  String get plan333FormatPresencePhase;

  /// No description provided for @plan333FormatCqTemplate.
  ///
  /// In pt, this message translates to:
  /// **'CQ Plano 333, [Nome], [Cidade], [Localidade]'**
  String get plan333FormatCqTemplate;

  /// No description provided for @plan333ConfigureChannel.
  ///
  /// In pt, this message translates to:
  /// **'Configurar Canal MeshCore  (#plano333)'**
  String get plan333ConfigureChannel;

  /// No description provided for @plan333Alerts.
  ///
  /// In pt, this message translates to:
  /// **'Alertas Mesh 3-3-3'**
  String get plan333Alerts;

  /// No description provided for @plan333AlertToggle.
  ///
  /// In pt, this message translates to:
  /// **'Lembrete do evento de sábado'**
  String get plan333AlertToggle;

  /// No description provided for @plan333AlertDesc.
  ///
  /// In pt, this message translates to:
  /// **'Alertas 10 e 5 min antes do Mesh 3-3-3 (Sábados 21:00)'**
  String get plan333AlertDesc;

  /// No description provided for @plan333AlertsActive.
  ///
  /// In pt, this message translates to:
  /// **'Alertas ativos às 20:50 e 20:55.'**
  String get plan333AlertsActive;

  /// No description provided for @plan333StationsHeard.
  ///
  /// In pt, this message translates to:
  /// **'Estações Ouvidas'**
  String get plan333StationsHeard;

  /// No description provided for @plan333ShareLog.
  ///
  /// In pt, this message translates to:
  /// **'Partilhar log'**
  String get plan333ShareLog;

  /// No description provided for @plan333ClearLog.
  ///
  /// In pt, this message translates to:
  /// **'Limpar log'**
  String get plan333ClearLog;

  /// No description provided for @plan333NoStationsYet.
  ///
  /// In pt, this message translates to:
  /// **'Nenhuma estação ouvida ainda. Os CQs recebidos no canal aparecem aqui automaticamente.'**
  String get plan333NoStationsYet;

  /// No description provided for @plan333ClearQslTitle.
  ///
  /// In pt, this message translates to:
  /// **'Limpar log?'**
  String get plan333ClearQslTitle;

  /// No description provided for @plan333ClearQslContent.
  ///
  /// In pt, this message translates to:
  /// **'Todas as estações registadas serão apagadas.'**
  String get plan333ClearQslContent;

  /// No description provided for @plan333AddQslTitle.
  ///
  /// In pt, this message translates to:
  /// **'Adicionar estação'**
  String get plan333AddQslTitle;

  /// No description provided for @plan333StationLabel.
  ///
  /// In pt, this message translates to:
  /// **'Estação *'**
  String get plan333StationLabel;

  /// No description provided for @plan333StationHint.
  ///
  /// In pt, this message translates to:
  /// **'ex: Daytona'**
  String get plan333StationHint;

  /// No description provided for @plan333HopsLabel.
  ///
  /// In pt, this message translates to:
  /// **'Hops:'**
  String get plan333HopsLabel;

  /// No description provided for @plan333DirectOption.
  ///
  /// In pt, this message translates to:
  /// **'Direto'**
  String get plan333DirectOption;

  /// No description provided for @plan333LocationLabel.
  ///
  /// In pt, this message translates to:
  /// **'Localização'**
  String get plan333LocationLabel;

  /// No description provided for @plan333LocationHint.
  ///
  /// In pt, this message translates to:
  /// **'ex: Tomar'**
  String get plan333LocationHint;

  /// No description provided for @plan333NotesLabel.
  ///
  /// In pt, this message translates to:
  /// **'Notas (opcional)'**
  String get plan333NotesLabel;

  /// No description provided for @plan333AbortAutoSend.
  ///
  /// In pt, this message translates to:
  /// **'Abortar auto-envio'**
  String get plan333AbortAutoSend;

  /// No description provided for @plan333AbortedMessage.
  ///
  /// In pt, this message translates to:
  /// **'Automação abortada — sem mais envios nesta sessão.'**
  String get plan333AbortedMessage;

  /// No description provided for @plan333SendCqButton.
  ///
  /// In pt, this message translates to:
  /// **'ENVIAR CQ  ({count}/3)'**
  String plan333SendCqButton(int count);

  /// No description provided for @plan333AllSent.
  ///
  /// In pt, this message translates to:
  /// **'✓  3 CQs enviados'**
  String get plan333AllSent;

  /// No description provided for @plan333ConfigureFirst.
  ///
  /// In pt, this message translates to:
  /// **'Configure os dados primeiro'**
  String get plan333ConfigureFirst;

  /// No description provided for @plan333RadioOff.
  ///
  /// In pt, this message translates to:
  /// **'Rádio desligado — não é possível enviar'**
  String get plan333RadioOff;

  /// No description provided for @plan333ChannelSheetTitle.
  ///
  /// In pt, this message translates to:
  /// **'Canal MeshCore  #plano333'**
  String get plan333ChannelSheetTitle;

  /// No description provided for @plan333ChannelSheetDesc.
  ///
  /// In pt, this message translates to:
  /// **'Adiciona o canal ao rádio ligado ou consulte os dados manualmente.'**
  String get plan333ChannelSheetDesc;

  /// No description provided for @plan333ChannelAdded.
  ///
  /// In pt, this message translates to:
  /// **'Canal #plano333 adicionado no slot {slot}'**
  String plan333ChannelAdded(int slot);

  /// No description provided for @signalNone.
  ///
  /// In pt, this message translates to:
  /// **'Sem sinal (nenhum pacote recebido nos últimos 5 min)'**
  String get signalNone;

  /// No description provided for @signalWeak.
  ///
  /// In pt, this message translates to:
  /// **'Sinal muito fraco'**
  String get signalWeak;

  /// No description provided for @signalFair.
  ///
  /// In pt, this message translates to:
  /// **'Sinal fraco'**
  String get signalFair;

  /// No description provided for @signalGood.
  ///
  /// In pt, this message translates to:
  /// **'Bom sinal'**
  String get signalGood;

  /// No description provided for @signalExcellent.
  ///
  /// In pt, this message translates to:
  /// **'Sinal excelente'**
  String get signalExcellent;

  /// No description provided for @urlOpenTitle.
  ///
  /// In pt, this message translates to:
  /// **'Abrir link externo?'**
  String get urlOpenTitle;

  /// No description provided for @urlOpenConfirm.
  ///
  /// In pt, this message translates to:
  /// **'Abrir'**
  String get urlOpenConfirm;

  /// No description provided for @topologyScreenTitle.
  ///
  /// In pt, this message translates to:
  /// **'Topologia da Rede'**
  String get topologyScreenTitle;

  /// No description provided for @topologyTabGraph.
  ///
  /// In pt, this message translates to:
  /// **'Grafo'**
  String get topologyTabGraph;

  /// No description provided for @topologyTabTimeline.
  ///
  /// In pt, this message translates to:
  /// **'Cronologia'**
  String get topologyTabTimeline;

  /// No description provided for @topologyEmptyTitle.
  ///
  /// In pt, this message translates to:
  /// **'Sem dados de topologia'**
  String get topologyEmptyTitle;

  /// No description provided for @topologyEmptyHint.
  ///
  /// In pt, this message translates to:
  /// **'Liga-te a um rádio para\nvisualizar a rede'**
  String get topologyEmptyHint;

  /// No description provided for @topologySelf.
  ///
  /// In pt, this message translates to:
  /// **'Eu'**
  String get topologySelf;

  /// No description provided for @topologyResetView.
  ///
  /// In pt, this message translates to:
  /// **'Repor vista'**
  String get topologyResetView;

  /// No description provided for @topologySnrGood.
  ///
  /// In pt, this message translates to:
  /// **'SNR ≥ 5 dB'**
  String get topologySnrGood;

  /// No description provided for @topologySnrMid.
  ///
  /// In pt, this message translates to:
  /// **'SNR 0–5 dB'**
  String get topologySnrMid;

  /// No description provided for @topologySnrBad.
  ///
  /// In pt, this message translates to:
  /// **'SNR < 0 dB'**
  String get topologySnrBad;

  /// No description provided for @topologyLabelId.
  ///
  /// In pt, this message translates to:
  /// **'ID'**
  String get topologyLabelId;

  /// No description provided for @topologyLabelPath.
  ///
  /// In pt, this message translates to:
  /// **'Caminho'**
  String get topologyLabelPath;

  /// No description provided for @topologyLabelSeen.
  ///
  /// In pt, this message translates to:
  /// **'Visto'**
  String get topologyLabelSeen;

  /// No description provided for @topologySecondsAgo.
  ///
  /// In pt, this message translates to:
  /// **'há {s}s'**
  String topologySecondsAgo(int s);

  /// No description provided for @topologyMinutesAgo.
  ///
  /// In pt, this message translates to:
  /// **'há {min}min'**
  String topologyMinutesAgo(int min);

  /// No description provided for @topologyHoursAgo.
  ///
  /// In pt, this message translates to:
  /// **'há {h}h'**
  String topologyHoursAgo(int h);

  /// No description provided for @topologyDaysAgo.
  ///
  /// In pt, this message translates to:
  /// **'há {d}d'**
  String topologyDaysAgo(int d);

  /// No description provided for @topologyWeeksAgo.
  ///
  /// In pt, this message translates to:
  /// **'há {w} sem.'**
  String topologyWeeksAgo(int w);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'es', 'pt'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
    case 'pt':
      return AppLocalizationsPt();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
