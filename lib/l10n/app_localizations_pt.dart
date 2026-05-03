// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Portuguese (`pt`).
class AppLocalizationsPt extends AppLocalizations {
  AppLocalizationsPt([String locale = 'pt']) : super(locale);

  @override
  String get navChannels => 'Canais';

  @override
  String get navContacts => 'Contactos';

  @override
  String get navMap => 'Mapa';

  @override
  String get navApps => 'Apps';

  @override
  String get navSettings => 'Definições';

  @override
  String get commonSave => 'Guardar';

  @override
  String get commonSaving => 'A guardar...';

  @override
  String get commonCancel => 'Cancelar';

  @override
  String get commonClear => 'Limpar';

  @override
  String get commonDelete => 'Apagar';

  @override
  String get commonClose => 'Fechar';

  @override
  String get commonBack => 'Voltar';

  @override
  String get commonRemove => 'Remover';

  @override
  String get commonAdd => 'Adicionar';

  @override
  String get commonEdit => 'Editar';

  @override
  String get commonShare => 'Partilhar';

  @override
  String get commonCopy => 'Copiar';

  @override
  String get commonRename => 'Renomear';

  @override
  String get commonReset => 'Repor';

  @override
  String get commonJustNow => 'agora mesmo';

  @override
  String commonMinutesAgo(int minutes) {
    return 'há $minutes min';
  }

  @override
  String commonHoursAgo(int hours) {
    return 'há $hours h';
  }

  @override
  String get gpsSharingTitle => 'Partilha de GPS';

  @override
  String get gpsSharingSubtitle =>
      'Tu decides se a tua localização vai junto nos anúncios da rádio. Por defeito está desligada.';

  @override
  String get gpsSharingStatusOff => 'DESLIGADA';

  @override
  String get gpsSharingStatusManual => 'MANUAL';

  @override
  String get gpsSharingStatusAuto => 'AUTOMÁTICA';

  @override
  String get gpsSharingModeOff => 'Desligada';

  @override
  String get gpsSharingModeManual => 'Manual';

  @override
  String get gpsSharingModeAuto => 'Automática';

  @override
  String get gpsSharingPrecisionTitle => 'Precisão enviada';

  @override
  String get gpsSharingPrecisionExact => 'Exacta';

  @override
  String get gpsSharingPrecisionRough => 'Aproximada';

  @override
  String get gpsSharingPrecisionVague => 'Vaga';

  @override
  String get gpsSharingIntervalLabel => 'Intervalo entre actualizações';

  @override
  String get gpsSharingShareNow => 'Partilhar agora';

  @override
  String get gpsSharingClearNow => 'Limpar do rádio';

  @override
  String get gpsSharingClearedOnRadio => 'Localização removida do rádio.';

  @override
  String get gpsSharingPrivacyDisclaimer =>
      'A tua posição será incluída nos anúncios LoRa que o teu rádio transmitir, podendo ser vista por outros nós. Liga apenas se aceitas partilhá-la.';

  @override
  String gpsSharingLastShared(Object ago, Object lat, Object lon) {
    return 'Partilhado $ago — $lat, $lon';
  }

  @override
  String gpsSharingOutcomeOk(Object lat, Object lon) {
    return '✅ Localização enviada: $lat, $lon';
  }

  @override
  String get gpsSharingOutcomeCleared => 'Localização limpa do rádio.';

  @override
  String get gpsSharingOutcomeDisabled =>
      'A partilha está desligada nas Definições.';

  @override
  String get gpsSharingOutcomeNoPerm => 'Permissão de localização negada.';

  @override
  String get gpsSharingOutcomeServiceOff =>
      'Serviço de localização desligado no telemóvel.';

  @override
  String get gpsSharingOutcomeNoFix => 'Sem fix de GPS disponível.';

  @override
  String get gpsSharingOutcomeDisconnected =>
      'Rádio desligado — liga primeiro.';

  @override
  String get gpsSharingOutcomeFailed => 'Falha ao enviar localização.';

  @override
  String get gpsSharingOutcomeSkipped => 'Posição não mudou — envio poupado.';

  @override
  String get gpsSharingMinMoveLabel => 'Movimento mínimo';

  @override
  String get gpsSharingMinMoveAlways => 'Sempre enviar';

  @override
  String get gpsSharingMinMoveHint =>
      'Em modo automático, só envia novo fix se te moveste pelo menos esta distância desde o último envio. Poupa air-time da rede LoRa.';

  @override
  String get gpsSharingAdvPolicyTitle => 'Difundir localização nos adverts';

  @override
  String get gpsSharingAdvPolicyNever =>
      'Desligado — os teus adverts não incluem coordenadas.';

  @override
  String get gpsSharingAdvPolicyAlways =>
      'Ligado — cada advert inclui a última localização conhecida do rádio.';

  @override
  String gpsSharingAdvPolicyUnknown(Object value) {
    return 'Política do rádio: byte $value — valor desconhecido.';
  }

  @override
  String get mapVisibilityShowTitle => 'Mostrar no mapa';

  @override
  String get mapVisibilityShowSubtitle =>
      'Esconde este contacto do teu mapa, mesmo que os adverts incluam coordenadas.';

  @override
  String get cannedMessagesTitle => 'Mensagens rápidas';

  @override
  String get cannedMessagesSubtitle =>
      'Biblioteca de respostas pré-gravadas para enviar com um toque (ou pelo botão SOS do widget).';

  @override
  String get cannedMessagesAdd => 'Adicionar mensagem';

  @override
  String get cannedMessagesAddTitle => 'Nova mensagem rápida';

  @override
  String get cannedMessagesEditTitle => 'Editar mensagem rápida';

  @override
  String get cannedMessagesEmpty =>
      'Sem mensagens guardadas. Toca em + para adicionar.';

  @override
  String get cannedMessagesReset => 'Repor por defeito';

  @override
  String get cannedMessagesResetTitle => 'Repor mensagens?';

  @override
  String get cannedMessagesResetConfirm =>
      'Vais perder todas as alterações e voltar à lista original.';

  @override
  String get cannedMessagesDeleteTitle => 'Apagar mensagem?';

  @override
  String cannedMessagesDeleteConfirm(Object label) {
    return 'Vais apagar “$label”.';
  }

  @override
  String get cannedMessagesLabelHint => 'Rótulo (opcional)';

  @override
  String get cannedMessagesTextHint => 'Texto da mensagem';

  @override
  String get cannedMessagesEmergencyToggle => 'Mensagem de emergência';

  @override
  String get cannedMessagesEmergencyDesc =>
      'É a mensagem usada pelo botão SOS do widget. Só uma pode estar marcada.';

  @override
  String get cannedMessagesPickerTooltip => 'Mensagens rápidas';

  @override
  String get cannedMessagesPickerTitle => 'Inserir mensagem rápida';

  @override
  String get cannedMessagesPickerSubtitle =>
      'Toca para colocar no campo de texto.';

  @override
  String get commonConfirm => 'Confirmar';

  @override
  String get commonError => 'Erro';

  @override
  String get commonErrors => 'Erros';

  @override
  String get commonYes => 'Sim';

  @override
  String get commonNo => 'Não';

  @override
  String get commonOk => 'Ok';

  @override
  String get commonLoading => 'A carregar...';

  @override
  String get commonSearch => 'Pesquisar';

  @override
  String get commonAll => 'Todos';

  @override
  String get commonUnread => 'Não lidos';

  @override
  String get commonDetails => 'Detalhes';

  @override
  String get commonReply => 'Responder';

  @override
  String get commonCopyText => 'Copiar texto';

  @override
  String get commonNoMessages => 'Sem mensagens';

  @override
  String get commonSendFirstMessage => 'Envie a primeira mensagem!';

  @override
  String get commonSendMessage => 'Enviar mensagem';

  @override
  String get commonNoData => 'Sem dados';

  @override
  String get commonMessageCopied => 'Mensagem copiada';

  @override
  String get commonSent => 'Enviada';

  @override
  String get commonSentByMe => 'Eu';

  @override
  String get commonPropagating => 'A propagar...';

  @override
  String get commonConnecting => 'A ligar...';

  @override
  String get commonSearching => 'A procurar...';

  @override
  String get commonAuthenticated => 'Autenticado';

  @override
  String get commonDirect => 'Direto';

  @override
  String get commonFlood => 'Flood';

  @override
  String get commonBattery => 'Bateria';

  @override
  String get commonStatus => 'Estado';

  @override
  String get commonPath => 'Caminho';

  @override
  String get commonTime => 'Hora';

  @override
  String get commonName => 'Nome';

  @override
  String get commonChannel => 'Canal';

  @override
  String get commonContact => 'Contacto';

  @override
  String get commonRoom => 'Sala';

  @override
  String get commonRooms => 'Salas';

  @override
  String get commonSensor => 'Sensor';

  @override
  String get commonSensors => 'Sensores';

  @override
  String get commonRepeater => 'Repetidor';

  @override
  String get commonRepeaters => 'Repetidores';

  @override
  String get commonType => 'Tipo';

  @override
  String get commonHops => 'Saltos';

  @override
  String get commonFavorites => 'Favoritos';

  @override
  String get commonTelemetry => 'Telemetria';

  @override
  String get commonSettings => 'Definições';

  @override
  String get commonRadioDisconnected => 'Rádio não ligado';

  @override
  String get commonConfiguring => 'A configurar...';

  @override
  String get commonSaveToRadio => 'Guardar no rádio';

  @override
  String get commonReportUrlCopied => 'URL do relatório copiado';

  @override
  String get commonErrorColon => 'Erro:';

  @override
  String get commonNoSpace =>
      'Sem espaço disponível. Remova um canal primeiro.';

  @override
  String get commonUpdated => 'Actualizado:';

  @override
  String get commonAdd2Radio => 'Adicionar ao Rádio';

  @override
  String get commonReconfigRadio => 'Re-configurar no Rádio';

  @override
  String get commonHashtag => 'Hashtag';

  @override
  String get commonSecretKey => 'Secret Key';

  @override
  String get commonReport => 'Relatório:';

  @override
  String get commonClearHistory => 'Limpar histórico';

  @override
  String get commonSingularHop => 'salto';

  @override
  String get commonPluralHops => 'saltos';

  @override
  String get homeDisconnectTitle => 'Desligar rádio?';

  @override
  String get homeDisconnectContent => 'A ligação ao rádio será terminada';

  @override
  String get homeDisconnect => 'Desligar';

  @override
  String get homeExitTitle => 'Sair da LusoAPP?';

  @override
  String get homeExitContent =>
      'A ligação ao rádio será terminada e a aplicação encerrada.';

  @override
  String get homeExit => 'Sair';

  @override
  String get settingsIdentity => 'Identidade';

  @override
  String get settingsPublicKey => 'Chave Pública';

  @override
  String get settingsCopyPublicKey => 'Copiar chave pública';

  @override
  String get settingsShareContact => 'Partilhar o meu contacto';

  @override
  String get settingsShareContactDesc => 'Mostra QR Code para partilhar';

  @override
  String get settingsConnection => 'Ligação';

  @override
  String get settingsConnected => 'Ligado';

  @override
  String get settingsConnectionError => 'Erro de ligação';

  @override
  String get settingsDisconnected => 'Desligado';

  @override
  String get settingsAutoReconnect => 'Reconexão automática';

  @override
  String get settingsAutoReconnectDesc =>
      'Reconecta automaticamente quando a ligação é perdida';

  @override
  String get settingsRadioConfig => 'Configuração do Rádio';

  @override
  String get settingsRadioConfigDesc => 'LoRa, telemetria e dispositivo';

  @override
  String get settingsReboot => 'Reboot';

  @override
  String get settingsShutdown => 'Shutdown';

  @override
  String get settingsRebootTitle => 'Reiniciar rádio';

  @override
  String get settingsRebootContent =>
      'Isto vai reiniciar o firmware do rádio. Tens a certeza?';

  @override
  String get settingsRebootSent =>
      'Comando de reboot enviado. A aguardar reconexão...';

  @override
  String get settingsRebootFail => 'Falha ao enviar comando de reboot';

  @override
  String get settingsAppearance => 'Aparência';

  @override
  String get settingsTheme => 'Tema';

  @override
  String get settingsThemeSystem => 'Sistema';

  @override
  String get settingsThemeLight => 'Claro';

  @override
  String get settingsThemeDark => 'Escuro';

  @override
  String get settingsAccent => 'Cor de destaque';

  @override
  String get settingsAccentDefault => 'Predefinido (laranja da marca)';

  @override
  String get settingsAccentCustom => 'Personalizada';

  @override
  String get settingsAccentReset => 'Repor predefinida';

  @override
  String get settingsMentionColors => 'Cores de menção';

  @override
  String get settingsSelfMention => 'Menção própria (@[Você])';

  @override
  String get settingsOtherMention => 'Menção de outros (@[Nome])';

  @override
  String get settingsChooseColor => 'Escolher cor';

  @override
  String get settingsNotifications => 'Notificações';

  @override
  String get settingsEnableNotifications => 'Activar notificações';

  @override
  String get settingsEnableNotificationsDesc =>
      'Mostrar alertas para novas mensagens';

  @override
  String get settingsNotificationPermissionDenied =>
      'Permissão de notificação não concedida';

  @override
  String get settingsAllow => 'Permitir';

  @override
  String get settingsPrivateMessages => 'Mensagens privadas';

  @override
  String get settingsChannelMessages => 'Mensagens de canal';

  @override
  String get settingsBackgroundOnly => 'Apenas em segundo plano';

  @override
  String get settingsPrivateKeyCopy => 'Cópia da Chave Privada';

  @override
  String get settingsPrivateKeyDesc =>
      'A chave privada identifica-te na rede. Guarda uma cópia segura antes de mudar de dispositivo.';

  @override
  String get settingsSaveFromRadio => 'Guardar do rádio';

  @override
  String get settingsPasteKey => 'Colar chave';

  @override
  String get settingsShareCopy => 'Partilhar cópia';

  @override
  String get settingsRestoreToRadio => 'Restaurar no rádio';

  @override
  String get settingsDeleteLocalCopy => 'Apagar cópia local';

  @override
  String get settingsRestorePrivateKeyTitle => 'Restaurar Chave Privada';

  @override
  String get settingsRestorePrivateKeyContent =>
      'O rádio vai reiniciar automaticamente após a restauração. Prosseguir?';

  @override
  String get settingsDeleteBackupTitle => 'Apagar cópia de segurança';

  @override
  String get settingsKeySavedSuccess =>
      'Cópia da chave privada guardada com sucesso';

  @override
  String get settingsKeyImportedSuccess => 'Chave importada com sucesso';

  @override
  String get settingsAbout => 'Sobre';

  @override
  String get settingsAppName => 'LusoAPP';

  @override
  String get settingsAppSubtitle => 'MeshCore Portugal';

  @override
  String get settingsCredit =>
      'Código fonte inicial criado por Paulo Pereira aka GZ7d0';

  @override
  String get settingsVersion => 'Versão';

  @override
  String get settingsProtocol => 'Protocolo';

  @override
  String get settingsProtocolName => 'Companion Radio Protocol v3';

  @override
  String get settingsLicense => 'Licença';

  @override
  String get settingsLicenseMIT => 'MIT';

  @override
  String get contactsAll => 'Todos';

  @override
  String get contactsFavorites => 'Favoritos';

  @override
  String get contactsCompanions => 'Companheiros';

  @override
  String get contactsRepeaters => 'Repetidores';

  @override
  String get contactsSensors => 'Sensores';

  @override
  String get contactsSearchHint => 'Pesquisar contactos...';

  @override
  String get contactsSendAdvert => 'Enviar Anúncio';

  @override
  String get contactsAdvertZeroHop => 'Anúncio · Zero Hop';

  @override
  String get contactsAdvertFlood => 'Anúncio · Flood';

  @override
  String get contactsSort => 'Ordenar';

  @override
  String get contactsSortNameAZ => 'Nome (A-Z)';

  @override
  String get contactsSortLastHeard => 'Ouvido recentemente';

  @override
  String get contactsSortLastMessage => 'Última mensagem';

  @override
  String get contactsMoreOptions => 'Mais opções';

  @override
  String get contactsDiscover => 'Descobrir contactos';

  @override
  String get contactsMultiSelect => 'Selecionar múltiplos';

  @override
  String get contactsEmptyCompanions => 'Sem companheiros na rede';

  @override
  String get contactsEmptyRepeaters => 'Sem repetidores na rede';

  @override
  String get contactsEmptyRooms => 'Sem salas na rede';

  @override
  String get contactsEmptySensors => 'Sem sensores na rede';

  @override
  String get contactsEmpty => 'Sem contactos';

  @override
  String get contactsEmptyFavorites => 'Sem favoritos';

  @override
  String get contactsEmptyHint =>
      'Os contactos aparecem quando o rádio os descobre';

  @override
  String get contactsSelected => 'selecionado(s)';

  @override
  String get contactsRemoveSelected => 'Remover selecionados';

  @override
  String get contactsCancelSelection => 'Cancelar seleção';

  @override
  String get contactsAddContact => 'Adicionar contacto';

  @override
  String get contactsAddInstruction =>
      'Envie um anúncio para que outros nós o descubram automaticamente, ou adicione manualmente através da chave pública';

  @override
  String get contactsSendAdvertAuto => 'Enviar Anúncio (descoberta automática)';

  @override
  String get contactsReadQR => 'Ler QR Code';

  @override
  String get contactsOrManual => 'ou adicionar manualmente';

  @override
  String get contactsPublicKeyLabel => 'Chave pública (hex, 64 chars)';

  @override
  String get contactsDisplayName => 'Nome de exibição';

  @override
  String get contactsTypeChat => 'Chat';

  @override
  String get contactsTypeRepeater => 'Repetidor';

  @override
  String get contactsTypeRoom => 'Sala';

  @override
  String get contactsAdding => 'A adicionar...';

  @override
  String get contactsSeen => 'Visto:';

  @override
  String get contactsRenameTitle => 'Renomear contacto';

  @override
  String get contactsAnnouncedName => 'Nome anunciado:';

  @override
  String get contactsCustomName => 'Nome personalizado';

  @override
  String get contactsSaveToRadioTitle => 'Guardar contacto no rádio';

  @override
  String get contactsTypeCompanion => 'Tipo: Companheiro';

  @override
  String contactsSavedToRadio(String name) {
    return '$name guardado no rádio';
  }

  @override
  String get contactsSaveToRadioError => 'Erro ao guardar contacto no rádio';

  @override
  String get contactsSaveTimeout => 'Timeout: rádio não respondeu';

  @override
  String get contactsRemoveTitle => 'Remover contacto(s)?';

  @override
  String get contactsRemovedPrefix => 'Removidos';

  @override
  String get contactsRemoveErrorSuffix => 'erro(s)';

  @override
  String get contactsRemoveError => 'Erro ao remover contactos';

  @override
  String get contactsRemoveFromListSuffix => 'da lista de contactos?';

  @override
  String get contactsRemoveRadioError => 'Erro ao remover no rádio (código';

  @override
  String get contactsRemoveTimeout => 'Timeout: rádio não respondeu à remoção';

  @override
  String get contactsRemoveFavorites => 'Remover dos favoritos';

  @override
  String get contactsAddFavorites => 'Adicionar aos favoritos';

  @override
  String get contactsShareQR => 'Partilhar via QR';

  @override
  String get contactsPrivateMessage => 'Mensagem privada';

  @override
  String get contactsJoinRoom => 'Entrar na sala';

  @override
  String get contactsRemoteAdmin => 'Admin remoto';

  @override
  String get contactsManagePath => 'Gerir caminho';

  @override
  String get contactsCurrentPath => 'Caminho actual:';

  @override
  String get contactsRemoveContact => 'Remover contacto';

  @override
  String get contactsAdminLabel => 'Admin:';

  @override
  String get contactsIdLabel => 'ID:';

  @override
  String get contactsHopsLabel => 'Saltos:';

  @override
  String get contactsAuth => 'Autenticação';

  @override
  String get contactsPassword => 'Palavra-passe (opcional)';

  @override
  String get contactsPasswordHint => 'Deixar em branco se sem palavra-passe';

  @override
  String get contactsJoin => 'Entrar';

  @override
  String get contactsStatusSent => 'Pedido de estado enviado...';

  @override
  String get contactsStatusSending => 'A enviar:';

  @override
  String get contactsRemoteActions => 'Acções Remotas';

  @override
  String get contactsFloodAdvert => 'Anúncio Flood';

  @override
  String get contactsFloodAdvertDesc => 'Força o nó a enviar um anúncio flood';

  @override
  String get contactsZeroHopAdvert => 'Anúncio Zero-Hop';

  @override
  String get contactsZeroHopAdvertDesc => 'Anúncio só para vizinhos directos';

  @override
  String get contactsSyncClock => 'Sincronizar Relógio';

  @override
  String get contactsSyncClockDesc => 'Envia o timestamp actual para o nó';

  @override
  String get contactsStartOTA => 'Iniciar OTA';

  @override
  String get contactsStartOTADesc =>
      'Inicia actualização OTA — NRF DFU / ESP32';

  @override
  String get contactsConfirmOTATitle => 'Confirmar OTA';

  @override
  String get contactsConfirmOTAContent =>
      'O rádio vai entrar em modo de actualização OTA e ficará temporariamente inacessível';

  @override
  String get contactsConfirmOTAQuestion => 'Tens a certeza?';

  @override
  String get contactsStats => 'Estatísticas';

  @override
  String get contactsUptime => 'Uptime';

  @override
  String get contactsSnrLast => 'SNR (último)';

  @override
  String get contactsRssiLast => 'RSSI (último)';

  @override
  String get contactsNoise => 'Ruído';

  @override
  String get contactsRxTx => 'RX / TX';

  @override
  String get contactsFloodRxTx => 'Flood RX/TX';

  @override
  String get contactsDirectRxTx => 'Directo RX/TX';

  @override
  String get contactsAirtimeTx => 'Tempo no ar (TX)';

  @override
  String get contactsAirtimeRx => 'Tempo no ar (RX)';

  @override
  String get contactsDuplicates => 'Duplicados';

  @override
  String get contactsNotSavedHint =>
      'Este contacto foi ouvido mas não está guardado no rádio';

  @override
  String get channelsCreatePrivate => 'Criar Canal Privado';

  @override
  String get channelsCreatePrivateDesc => 'Seguro com uma chave secreta';

  @override
  String get channelsJoinPrivate => 'Entrar num Canal Privado';

  @override
  String get channelsJoinPrivateDesc =>
      'Introduza manualmente uma chave secreta';

  @override
  String get channelsJoinPublic => 'Entrar no Canal Público';

  @override
  String get channelsJoinPublicDesc =>
      'Qualquer pessoa pode entrar neste canal';

  @override
  String get channelsJoinHashtag => 'Entrar num Canal Hashtag';

  @override
  String get channelsJoinHashtagDesc =>
      'Qualquer pessoa pode entrar em canais hashtag';

  @override
  String get channelsReadQR => 'Ler QR Code';

  @override
  String get channelsReadQRDesc => 'Digitalizar o QR Code de um canal';

  @override
  String get channelsSlotPosition => 'Posição do canal';

  @override
  String get channelsSlot => 'Canal';

  @override
  String get channelsSlotInUse => '(em uso)';

  @override
  String get channelsChannelName => 'Nome do canal';

  @override
  String get channelsHashtagName => 'Nome do hashtag (sem #)';

  @override
  String get channelsHashtagHint => 'ex: meshcore  →  canal #meshcore';

  @override
  String get channelsNameHintGeneral => 'ex: Geral';

  @override
  String get channelsNameHintPrivate => 'ex: A Minha Rede';

  @override
  String get channelsSecretKey => 'Chave secreta (32 caracteres hex)';

  @override
  String get channelsSecretKeyHint => 'ex: 8b3387e9c5cdea6ac9e5edbaa115cd72';

  @override
  String get channelsPublicKey => 'Chave pública conhecida';

  @override
  String get channelsDerivedKey => 'Chave derivada do hashtag';

  @override
  String get channelsRandomKey => 'Chave gerada aleatoriamente';

  @override
  String get channelsPublicKeyInfo =>
      'Esta chave é pública e igual em todos os dispositivos MeshCore';

  @override
  String get channelsHashtagKeyInfo =>
      'Qualquer pessoa que entre no mesmo hashtag terá esta chave automaticamente';

  @override
  String get channelsRandomKeyInfo =>
      'Guarde esta chave ou partilhe o QR Code para convidar outros';

  @override
  String get channelsRegenerateKey => 'Regenerar chave';

  @override
  String get channelsEmpty => 'Sem canais';

  @override
  String get channelsEmptyHint =>
      'Os canais configurados no rádio aparecem aqui';

  @override
  String get channelsRefresh => 'Actualizar Canais';

  @override
  String get channelsAllRead => 'Tudo lido';

  @override
  String get channelsAllReadHint => 'Sem mensagens não lidas nos canais';

  @override
  String get channelsSeeAll => 'Ver todos os canais';

  @override
  String get channelsMsgSuffix => 'msg';

  @override
  String get channelsOptionsFabTooltip => 'Opções do canal';

  @override
  String get channelsClearHistoryConfirm =>
      'Apagar todas as mensagens deste canal? Esta ação não pode ser revertida';

  @override
  String get channelsEditSheet => 'Editar canal';

  @override
  String get channelsQRTitle => 'QR Code do canal';

  @override
  String get channelsShowQR => 'Mostrar QR Code do canal';

  @override
  String get channelsQRDesc => 'Partilhe este QR Code para dar acesso ao canal';

  @override
  String get channelsShareText => 'Partilhar texto';

  @override
  String get channelsShareQR => 'Partilhar QR';

  @override
  String get channelsRemovePublicTitle => 'Remover Canal Público?';

  @override
  String get channelsRemovePublicWarning =>
      'Está prestes a remover o Canal Público. Este é o canal principal partilhado pela comunidade MeshCore. Tem a certeza?';

  @override
  String get channelsRemoveAnyway => 'Remover mesmo assim';

  @override
  String get channelsRemoveTitle => 'Remover canal';

  @override
  String get channelsRemoveConfirm => 'Tem a certeza que quer remover';

  @override
  String get channelsRemoveWarning => 'Esta acção não pode ser desfeita.';

  @override
  String get channelsMuteTitle => 'Canal silenciado';

  @override
  String get channelsUnmuteTitle => 'Notificações activas';

  @override
  String get channelsMuteSubtitleOn =>
      'Sem alertas — badge de não lidas ainda visível';

  @override
  String get channelsMuteSubtitleOff =>
      'Recebe notificações e badge de não lidas';

  @override
  String get channelsMuteLabel => 'silenciado';

  @override
  String get chatMuteChannel => 'Silenciar canal';

  @override
  String get chatUnmuteChannel => 'Reativar notificações';

  @override
  String get chatNoMessages => 'Sem mensagens neste canal';

  @override
  String get chatSendFirstMessage => 'Envie a primeira mensagem!';

  @override
  String get chatInputHint => 'Mensagem para o canal...';

  @override
  String get chatRepeater => 'Repetidor';

  @override
  String get chatRepeaters => 'Repetidores';

  @override
  String get chatMsgCount => 'mensagens';

  @override
  String get chatHeard => 'Ouvida';

  @override
  String get chatOnce => 'vez';

  @override
  String get chatTimes => 'vezes por repetidores';

  @override
  String get chatViaRepeaters => 'Recebida via repetidores';

  @override
  String get chatAuthenticatedMessage => 'Autenticado';

  @override
  String get chatMsgDetails => 'Detalhes da mensagem';

  @override
  String get chatRetry => 'Reenviar';

  @override
  String get chatFailed => 'Falhou';

  @override
  String get chatPathLabel => 'Caminho';

  @override
  String get chatHeardCount => 'Ouvido';

  @override
  String get chatTimesCount => 'vezes';

  @override
  String get chatPathExplanation =>
      'Cada caminho representa uma vez que o teu rádio ouviu a mensagem de volta';

  @override
  String get chatPathInstruction => 'Toca num caminho para ver a rota completa';

  @override
  String get chatNoPathData =>
      'Os dados de caminho não estão disponíveis. Reconecta o rádio para registar novos caminhos';

  @override
  String get chatViewOnMap => 'Ver no mapa';

  @override
  String get chatYourRadio => 'O teu rádio';

  @override
  String get chatYouSent => 'Enviaste a mensagem';

  @override
  String get chatReceived => 'Recebeu a mensagem';

  @override
  String get chatHopLabel => 'Salto';

  @override
  String get chatRepeated => 'Repetiu';

  @override
  String get chatHashtagChannel =>
      'Canal Hashtag — qualquer pessoa com o nome pode entrar';

  @override
  String get chatKeyLabel => 'Chave:';

  @override
  String get chatCreateJoinChannel => 'Criar e entrar no canal';

  @override
  String get chatNoChannelSlots => 'Sem espaço disponível para novos canais';

  @override
  String get chatDeleteMessage => 'Apagar mensagem';

  @override
  String get chatMenuOptions => 'Opções do canal';

  @override
  String get chatNewMessages => 'Novas mensagens';

  @override
  String get chatPingButton => '!ping';

  @override
  String get chatViewResultOnline => 'ver resultado online';

  @override
  String get connectTitle => 'MeshCore Portugal';

  @override
  String get connectReconnect => 'Ligar novamente';

  @override
  String get connectContinueOffline => 'Continuar offline';

  @override
  String get connectSearchDevices => 'Procurar Dispositivos';

  @override
  String get connectSearching => 'A procurar...';

  @override
  String get connectBrowserNote =>
      'O browser irá mostrar um seletor de dispositivos Bluetooth';

  @override
  String get connectScanningMessage => 'A procurar rádios MeshCore...';

  @override
  String get connectTapHint =>
      'Toque em \"Procurar\" para encontrar dispositivos';

  @override
  String get connectSectionBluetooth => 'BLUETOOTH';

  @override
  String get connectSectionSerial => 'USB / SÉRIE';

  @override
  String get connectDeviceBLE => '(Bluetooth LE)';

  @override
  String get connectDeviceUSB => '(Série USB — Companion)';

  @override
  String get connectDeviceKISS => '(KISS TNC)';

  @override
  String get connectDeviceWebUSB => 'Web USB — Companion';

  @override
  String get connectDeviceWebKISS => 'Web USB — KISS TNC';

  @override
  String get connectWebUsbButton => 'Ligar via USB (Web Serial)';

  @override
  String get connectWebUsbScanning => 'A selecionar porta USB...';

  @override
  String get connectWebUsbHint =>
      'Suportado no Chrome e Edge. O browser mostrará um seletor de portas USB.';

  @override
  String get connectWebUsbExpiredMessage =>
      'Porta USB não disponível (página recarregada). Selecione novamente o dispositivo.';

  @override
  String get connectWebUsbAction => 'Ligar via USB';

  @override
  String get connectStepConnecting => 'A ligar...';

  @override
  String get connectStepWaiting => 'A aguardar rádio...';

  @override
  String get connectStepDeviceInfo => 'Informação do dispositivo';

  @override
  String get connectStepContacts => 'Contactos';

  @override
  String get connectStepChannels => 'Canais';

  @override
  String get connectStepDone => 'Concluído';

  @override
  String get connectBluetoothOffTitle => 'Bluetooth desligado';

  @override
  String get connectBluetoothOffMessage =>
      'O Bluetooth está desligado. Deseja activá-lo para ligar ao rádio MeshCore?';

  @override
  String get connectBluetoothEnable => 'Activar';

  @override
  String get connectBluetoothDeniedTitle => 'Activação do Bluetooth recusada';

  @override
  String get connectBluetoothDeniedMessage =>
      'Por favor active o Bluetooth nas Definições do sistema';

  @override
  String get connectBluetoothOff =>
      'Bluetooth desligado. Ligue o Bluetooth para procurar dispositivos';

  @override
  String get connectBluetoothPermission =>
      'Permissões Bluetooth necessárias para procurar dispositivos';

  @override
  String get connectOpenSettings => 'Definições';

  @override
  String get connectFailTitle => 'Falha ao ligar ao dispositivo';

  @override
  String get connectLastFailTitle => 'Falha ao ligar ao último dispositivo';

  @override
  String get discoverTitle => 'Descobrir';

  @override
  String get discoverSubtitle => 'Anúncios Recentes';

  @override
  String get discoverSearchHint => 'Procurar contactos descobertos...';

  @override
  String get discoverEmpty => 'Nenhum contacto encontrado';

  @override
  String get discoverEmptyHint => 'Tente uma busca diferente';

  @override
  String get discoverNone => 'Nenhum contacto descoberto';

  @override
  String get discoverNoneHint =>
      'Contactos aparecem enquanto transmitem na rede';

  @override
  String get discoverCleanTooltip => 'Limpar contactos só locais';

  @override
  String get discoverCleanSheetTitle => 'Limpar contactos só locais';

  @override
  String get discoverCleanSheetSubtitle =>
      'Escolhe quais contactos descobertos remover. Os contactos guardados no rádio são sempre mantidos.';

  @override
  String get discoverCleanOption48h => 'Não ouvidos há 48 horas';

  @override
  String get discoverCleanOption7d => 'Não ouvidos há 7 dias';

  @override
  String get discoverCleanOption30d => 'Não ouvidos há 30 dias';

  @override
  String get discoverCleanOptionNever => 'Nunca ouvidos (sem advert)';

  @override
  String get discoverCleanOptionAll => 'Todos os contactos só locais';

  @override
  String get discoverCleanTitle => 'Limpar contactos descobertos?';

  @override
  String discoverCleanBody(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n contactos',
      one: '1 contacto',
    );
    return 'Vai remover $_temp0 que não estão guardados no rádio. Os contactos guardados no rádio são mantidos.';
  }

  @override
  String get discoverCleanNothing =>
      'Todos os contactos descobertos estão guardados no rádio. Nada para limpar.';

  @override
  String discoverCleanDone(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: 'Removidos $n contactos',
      one: 'Removido 1 contacto',
    );
    return '$_temp0';
  }

  @override
  String get discoverSaveToRadio => 'Guardar no rádio';

  @override
  String get discoverSendMessage => 'Enviar mensagem';

  @override
  String get discoverJoinRoom => 'Entrar na sala';

  @override
  String get discoverAddAndSave => 'Adicionar e guardar';

  @override
  String get discoverAnnouncedName => 'Nome Anunciado';

  @override
  String get discoverHeard => 'Ouvido';

  @override
  String get discoverNever => 'Nunca';

  @override
  String get discoverNoName => 'Sem nome';

  @override
  String get discoverTypeCompanion => 'Companheiro';

  @override
  String get discoverTypeUnknown => 'Desconhecido';

  @override
  String get discoverPathNear => 'Próximo';

  @override
  String get discoverJustNow => 'Agora';

  @override
  String discoverMinutesAgo(int min) {
    return '${min}m atrás';
  }

  @override
  String discoverHoursAgo(int hours) {
    return '${hours}h atrás';
  }

  @override
  String discoverDaysAgo(int days) {
    return '${days}d atrás';
  }

  @override
  String get appsPlano333Title => 'Plano 3-3-3';

  @override
  String get appsPlano333Subtitle => 'Evento semanal MeshCore';

  @override
  String get appsTelemetryTitle => 'Telemetria';

  @override
  String get appsTelemetrySubtitle => 'Bateria, RF e contadores';

  @override
  String get appsRxLogTitle => 'RX Log';

  @override
  String get appsRxLogSubtitle => 'Captura e exporta PCAP';

  @override
  String get appsQrTitle => 'Leitor QR';

  @override
  String get appsQrSubtitle => 'Digitalizar código QR';

  @override
  String get mapNoGps =>
      'Sem dados GPS. Toca em \"Localizar\" ou aguarda contactos com coordenadas';

  @override
  String get mapShareMap => 'Partilhar mapa';

  @override
  String get mapViewAll => 'Ver todos';

  @override
  String get mapCenterMyPosition => 'Centrar na minha posição';

  @override
  String get mapGetGps => 'Obter localização GPS';

  @override
  String get mapLocationDisabled => 'Serviço de localização desactivado';

  @override
  String get mapLocationDenied => 'Permissão de localização negada';

  @override
  String get mapLocationDeniedPermanently =>
      'Permissão de localização negada permanentemente';

  @override
  String get mapLocationError => 'Erro ao obter localização GPS';

  @override
  String get mapCaptureError => 'Não foi possível capturar o mapa';

  @override
  String get mapImageError => 'Falha ao gerar imagem do mapa';

  @override
  String get mapShareError => 'Erro ao partilhar o mapa';

  @override
  String get mapNodesAtLocation => 'nós nesta localização';

  @override
  String get mapMinimizeList => 'Minimizar lista';

  @override
  String get mapShowMore => 'Mostrar +';

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
  String get privateNoMessages => 'Sem mensagens';

  @override
  String get privateSendFirstMessage => 'Envie a primeira mensagem!';

  @override
  String privateMessageTo(String name) {
    return 'Mensagem para $name...';
  }

  @override
  String privateTracingRoute(String name) {
    return 'A traçar rota para $name';
  }

  @override
  String get privateRouteFailed =>
      'Não foi possível descobrir a rota — tente novamente';

  @override
  String get privateRouteNoResponse => 'Sem resposta à rota — tente novamente';

  @override
  String get privateRouteFound => 'Rota encontrada —';

  @override
  String get privateDirectRoute => 'Rota directa (sem repetidores)';

  @override
  String get privateReceivedOnRadio => 'Recebido no rádio';

  @override
  String get privateConfirmed => 'Confirmado';

  @override
  String get privatePending => 'Pendente';

  @override
  String get privateSentVia => 'Enviado via';

  @override
  String get privateTraceRoute => 'Traçar rota';

  @override
  String get privateManagePath => 'Gerir caminho';

  @override
  String get privateContactLabel => 'Contacto';

  @override
  String get qrTitle => 'Ler QR Code';

  @override
  String get qrUnavailable =>
      'Scanner de QR Code não disponível nesta plataforma';

  @override
  String get qrUnavailableHint => 'Use um dispositivo Android ou iOS';

  @override
  String get qrHint => 'Aponte para um QR Code MeshCore';

  @override
  String get radioSettingsTitle => 'Configuração do Rádio';

  @override
  String get radioSettingsDevice => 'Dispositivo';

  @override
  String get radioSettingsModel => 'Modelo';

  @override
  String get radioSettingsFirmware => 'Firmware';

  @override
  String get radioSettingsStorage => 'Armazenamento';

  @override
  String get radioSettingsChannels => 'Canais';

  @override
  String get radioSettingsContacts => 'Contactos';

  @override
  String get radioSettingsDiscovered => 'Descobertos';

  @override
  String get radioSettingsAppVersion => 'Versão da App';

  @override
  String get radioSettingsLoRa => 'Parâmetros LoRa';

  @override
  String get radioSettingsFrequency => 'Frequência (MHz)';

  @override
  String get radioSettingsFreqLabel => 'Frequência';

  @override
  String get radioSettingsFrequencyHint => 'Ex: 868.1250';

  @override
  String get radioSettingsBandwidth => 'Largura de banda';

  @override
  String get radioSettingsSpreadingFactor => 'Spreading Factor';

  @override
  String get radioSettingsCodingRate => 'Coding Rate';

  @override
  String get radioSettingsTxPower => 'Potência TX';

  @override
  String get radioSettingsMax => 'Máx:';

  @override
  String get radioSettingsDbm => 'dBm';

  @override
  String get radioSettingsFrequencyRequired => 'Insere a frequência';

  @override
  String get radioSettingsFrequencyInvalid =>
      'Frequência inválida (150–2500 MHz)';

  @override
  String get radioSettingsBandwidthRequired => 'Selecciona a largura de banda';

  @override
  String get radioSettingsSFRequired => 'Selecciona o spreading factor';

  @override
  String get radioSettingsCRRequired => 'Selecciona o coding rate';

  @override
  String get radioSettingsPowerRequired => 'Insere a potência';

  @override
  String get radioSettingsPowerInvalid => 'Potência inválida (1–30 dBm)';

  @override
  String get radioSettingsActiveConfig => 'Configuração Activa';

  @override
  String get radioSettingsSaved => 'Configuração guardada';

  @override
  String get radioSettingsPrivKeyCopied => 'Chave privada copiada';

  @override
  String get radioSettingsResetValues => 'Repor valores actuais';

  @override
  String get radioSettingsExperimentalTitle => 'Experimental';

  @override
  String get radioSettingsExperimentalWarning =>
      'Usar com cuidado — estas opções afectam a compatibilidade no ar com outros nós.';

  @override
  String get radioSettingsPathHashMode => 'Tamanho do hash de caminho';

  @override
  String get radioSettingsPathHashModeDesc =>
      'Número de bytes usados por salto no caminho de encaminhamento. Valores maiores reduzem a probabilidade de colisão entre nós distantes. Requer firmware v10+. Predefinição: 1 byte.';

  @override
  String get radioSettingsPathHashMode1 => '1 byte';

  @override
  String get radioSettingsPathHashMode2 => '2 bytes';

  @override
  String get radioSettingsPathHashMode3 => '3 bytes';

  @override
  String get radioSettingsPathHashModeCaptionDefault =>
      '1 byte por salto — predefinição, compatível com todos os firmwares.';

  @override
  String get radioSettingsPathHashModeCaptionExperimental =>
      'Experimental — só nós com firmware v10+ encaminham este pacote correctamente.';

  @override
  String get radioSettingsPathHashModeUnsupported =>
      'Não suportado por este firmware.';

  @override
  String get radioSettingsPathHashModeSaved => 'Tamanho do hash actualizado';

  @override
  String get radioSettingsPathHashModeFailed =>
      'Falha ao actualizar o tamanho do hash';

  @override
  String get radioSettingsAutoAddTitle => 'Definições de Contactos';

  @override
  String get radioSettingsAutoAddDesc =>
      'Quando um nó envia um advert e o rádio está em modo manual, adicionar automaticamente como:';

  @override
  String get radioSettingsAutoAddAll => 'Auto Adicionar Todos';

  @override
  String get radioSettingsAutoAddAllDesc =>
      'Quando ativo, todos os adverts recebidos serão adicionados aos contactos.';

  @override
  String get radioSettingsAutoAddSelected => 'Auto Adicionar Selecionados';

  @override
  String get radioSettingsAutoAddSelectedDesc =>
      'Quando ativo, apenas os tipos de contactos selecionados abaixo serão auto adicionados.';

  @override
  String get radioSettingsAutoAddCompanion => 'Companheiro (Chat)';

  @override
  String get radioSettingsAutoAddRepeater => 'Repetidor';

  @override
  String get radioSettingsAutoAddRoom => 'Sala (Room)';

  @override
  String get radioSettingsAutoAddSensor => 'Sensor';

  @override
  String get radioSettingsOverwriteOldest => 'Sobrescrever Mais Antigo';

  @override
  String get radioSettingsOverwriteOldestDesc =>
      'Quando ativo, os contactos mais antigos sem favorito são substituídos por novos quando a lista está cheia.';

  @override
  String get radioSettingsAutoAddMaxHops => 'Saltos Máximos de Auto Adição';

  @override
  String get radioSettingsAutoAddMaxHopsDesc =>
      'Os contactos só serão auto adicionados se o caminho do advert tiver o mesmo ou menos saltos que o limite. Deixe em branco para sem limite.';

  @override
  String get radioSettingsAutoAddMaxHopsHint => 'Saltos (0-63)';

  @override
  String get radioSettingsPullToRefresh => 'Puxar para Atualizar';

  @override
  String get radioSettingsPullToRefreshDesc =>
      'Quando ativo, pode deslizar para baixo para atualizar a lista de contactos.';

  @override
  String get radioSettingsShowPublicKeys => 'Mostrar Chaves Públicas';

  @override
  String get radioSettingsShowPublicKeysDesc =>
      'Quando ativo, as chaves públicas serão mostradas na lista de contactos.';

  @override
  String get radioSettingsBandPresetsTitle => 'Predefinições de Banda';

  @override
  String get roomJoinTitle => 'Entrar na sala';

  @override
  String get roomJoinInstruction =>
      'Esta sala pode requerer uma palavra-passe. Deixe em branco se for pública.';

  @override
  String get roomPasswordLabel => 'Palavra-passe (opcional)';

  @override
  String get roomPasswordHint => 'Deixar em branco se sem palavra-passe';

  @override
  String get roomJoinFailed => 'Falhou — verifique a palavra-passe';

  @override
  String get roomJoining => 'A ligar...';

  @override
  String get roomJoinError =>
      'Não foi possível entrar na sala. Verifique a palavra-passe e tente novamente.';

  @override
  String get roomReplyStrip => 'Sala';

  @override
  String roomMessageHint(String name) {
    return 'Mensagem para $name sala...';
  }

  @override
  String get roomMessageFallback => 'Escreva uma mensagem...';

  @override
  String get roomTelemetryData => 'Dados de telemetria';

  @override
  String get rxLogTitle => 'RX Log';

  @override
  String get rxLogExportPcap => 'Exportar PCAPNG';

  @override
  String get rxLogClearLog => 'Limpar log';

  @override
  String get rxLogPacketCount => 'pacotes capturados';

  @override
  String get rxLogClearTitle => 'Limpar RX Log';

  @override
  String get rxLogClearConfirm => 'Remover todos os pacotes capturados?';

  @override
  String get rxLogEmpty => 'RX Log vazio - nada para exportar';

  @override
  String get rxLogExportFail => 'Falha ao exportar PCAPNG';

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
  String get rxLogPacketTypePrefix => 'Tipo';

  @override
  String get rxLogEmptyTitle => 'Sem pacotes RX';

  @override
  String get rxLogEmptyHint =>
      'Quando a rádio receber tráfego mesh, os pacotes aparecem aqui.';

  @override
  String get telemetryBattery => 'Bateria';

  @override
  String get telemetryNetStats => 'Estatísticas da Rede';

  @override
  String get telemetryRadioState => 'Rádio — Estado';

  @override
  String get telemetryRadioWaiting => 'A aguardar estatísticas do rádio...';

  @override
  String get telemetryRadioRF => 'Rádio — RF';

  @override
  String get telemetryRFWaiting => 'A aguardar estatísticas de RF...';

  @override
  String get telemetryPacketCounters => 'Rádio — Contadores de Pacotes';

  @override
  String get telemetryCountersWaiting => 'A aguardar contadores de pacotes...';

  @override
  String get telemetrySensors => 'Sensores (Telemetria)';

  @override
  String get telemetryNoData => 'Nenhuma telemetria recebida.';

  @override
  String get telemetrySamplesSuffix => 'amostras';

  @override
  String get telemetryNow => 'Agora';

  @override
  String get telemetryHistoryHint =>
      'O histórico aparece após a primeira leitura de bateria.';

  @override
  String get telemetryRX => 'RX';

  @override
  String get telemetryTX => 'TX';

  @override
  String get telemetryHeard => 'Ouvidos';

  @override
  String get telemetryCardPrefix => 'Telemetria —';

  @override
  String get telemetryUptime => 'Uptime';

  @override
  String get telemetryTxQueue => 'Fila TX';

  @override
  String get telemetryErrorsPrefix => 'Erros:';

  @override
  String get telemetryRSSI => 'RSSI';

  @override
  String get telemetryNoise => 'Ruído';

  @override
  String get telemetrySNR => 'SNR';

  @override
  String get telemetryAirtimeTX => 'Airtime TX';

  @override
  String get telemetryAirtimeRX => 'Airtime RX';

  @override
  String get telemetryErrors => 'Erros';

  @override
  String get telemetryRXTotal => 'RX Total';

  @override
  String get telemetryTXTotal => 'TX Total';

  @override
  String get telemetryErrorsRX => 'Erros RX';

  @override
  String get telemetryFloodTX => 'Flood TX';

  @override
  String get telemetryFloodRX => 'Flood RX';

  @override
  String get telemetryDirectTX => 'Direto TX';

  @override
  String get telemetryDirectRX => 'Direto RX';

  @override
  String get eventTitle => 'Programa do Evento';

  @override
  String get eventDateLabel => 'Abril 2026';

  @override
  String get eventSummitTitle => 'Tech Summit 2026';

  @override
  String get eventSummitSubtitle => 'MeshCore Portugal';

  @override
  String get eventMorning => 'Manhã';

  @override
  String get eventAfternoon => 'Tarde';

  @override
  String get eventWorkshops => 'Workshops (sala paralela)';

  @override
  String get eventAddChannel => 'Adicionar';

  @override
  String get eventChannelSheetTitle => 'Canal MeshCore  #plano333';

  @override
  String get eventChannelSheetDesc =>
      'Adiciona o canal ao rádio ligado ou consulte os dados manualmente.';

  @override
  String eventChannelAdded(int slot) {
    return 'Canal #plano333 adicionado no slot $slot';
  }

  @override
  String get eventChannelNotFound =>
      'Canal #techsummit2026 não encontrado no rádio.';

  @override
  String get eventChannelNoSlots =>
      'Sem slots de canal disponíveis para adicionar #techsummit2026.';

  @override
  String get plan333CardTitle => 'MESH 3-3-3';

  @override
  String get plan333EventActive => '● EVENTO ACTIVO';

  @override
  String get plan333PhaseCQ => 'CQ 21:00–22:00';

  @override
  String get plan333CqSent => 'CQ enviados:';

  @override
  String get plan333LastSent => '(último:';

  @override
  String get plan333EventSchedule =>
      'Sábados 21:00–22:00  •  CQ Presenças MeshCore';

  @override
  String get plan333ReportPrefix => 'Relatório em';

  @override
  String get plan333ConfigTitle => 'Configuração do Evento';

  @override
  String get plan333StationName => 'Nome de estação *';

  @override
  String get plan333StationNameHint => 'Ex: Mike 05';

  @override
  String get plan333City => 'Cidade *';

  @override
  String get plan333CityHint => 'Ex: Lisboa';

  @override
  String get plan333Locality => 'Localidade';

  @override
  String get plan333LocalityHint => 'Ex: Olaias';

  @override
  String get plan333AutoSend => 'Envio automático de CQ';

  @override
  String get plan333AutoSendDesc => 'CQ: até 3 mensagens (21:00–22:00)';

  @override
  String get plan333CqMessageLabel => 'Mensagem CQ:';

  @override
  String get plan333FormatTitle => 'Formatos de Mensagem';

  @override
  String get plan333FormatPresence => 'Presença (CQ)';

  @override
  String get plan333FormatPresencePhase => 'MeshCore 21:00–22:00';

  @override
  String get plan333FormatCqTemplate =>
      'CQ Plano 333, [Nome], [Cidade], [Localidade]';

  @override
  String get plan333ConfigureChannel =>
      'Configurar Canal MeshCore  (#plano333)';

  @override
  String get plan333Alerts => 'Alertas Mesh 3-3-3';

  @override
  String get plan333AlertToggle => 'Lembrete do evento de sábado';

  @override
  String get plan333AlertDesc =>
      'Alertas 10 e 5 min antes do Mesh 3-3-3 (Sábados 21:00)';

  @override
  String get plan333AlertsActive => 'Alertas ativos às 20:50 e 20:55.';

  @override
  String get plan333StationsHeard => 'Estações Ouvidas';

  @override
  String get plan333ShareLog => 'Partilhar log';

  @override
  String get plan333ClearLog => 'Limpar log';

  @override
  String get plan333NoStationsYet =>
      'Nenhuma estação ouvida ainda. Os CQs recebidos no canal aparecem aqui automaticamente.';

  @override
  String get plan333ClearQslTitle => 'Limpar log?';

  @override
  String get plan333ClearQslContent =>
      'Todas as estações registadas serão apagadas.';

  @override
  String get plan333AddQslTitle => 'Adicionar estação';

  @override
  String get plan333StationLabel => 'Estação *';

  @override
  String get plan333StationHint => 'ex: Daytona';

  @override
  String get plan333HopsLabel => 'Hops:';

  @override
  String get plan333DirectOption => 'Direto';

  @override
  String get plan333LocationLabel => 'Localização';

  @override
  String get plan333LocationHint => 'ex: Tomar';

  @override
  String get plan333NotesLabel => 'Notas (opcional)';

  @override
  String get plan333AbortAutoSend => 'Abortar auto-envio';

  @override
  String get plan333AbortedMessage =>
      'Automação abortada — sem mais envios nesta sessão.';

  @override
  String plan333SendCqButton(int count) {
    return 'ENVIAR CQ  ($count/3)';
  }

  @override
  String get plan333AllSent => '✓  3 CQs enviados';

  @override
  String get plan333ConfigureFirst => 'Configure os dados primeiro';

  @override
  String get plan333RadioOff => 'Rádio desligado — não é possível enviar';

  @override
  String get plan333ChannelSheetTitle => 'Canal MeshCore  #plano333';

  @override
  String get plan333ChannelSheetDesc =>
      'Adiciona o canal ao rádio ligado ou consulte os dados manualmente.';

  @override
  String plan333ChannelAdded(int slot) {
    return 'Canal #plano333 adicionado no slot $slot';
  }

  @override
  String get signalNone =>
      'Sem sinal (nenhum pacote recebido nos últimos 5 min)';

  @override
  String get signalWeak => 'Sinal muito fraco';

  @override
  String get signalFair => 'Sinal fraco';

  @override
  String get signalGood => 'Bom sinal';

  @override
  String get signalExcellent => 'Sinal excelente';

  @override
  String get urlOpenTitle => 'Abrir link externo?';

  @override
  String get urlOpenConfirm => 'Abrir';

  @override
  String get topologyScreenTitle => 'Topologia da Rede';

  @override
  String get topologyTabGraph => 'Grafo';

  @override
  String get topologyTabTimeline => 'Cronologia';

  @override
  String get topologyEmptyTitle => 'Sem dados de topologia';

  @override
  String get topologyEmptyHint => 'Liga-te a um rádio para\nvisualizar a rede';

  @override
  String get topologySelf => 'Eu';

  @override
  String get topologyResetView => 'Repor vista';

  @override
  String get topologySnrGood => 'SNR ≥ 5 dB';

  @override
  String get topologySnrMid => 'SNR 0–5 dB';

  @override
  String get topologySnrBad => 'SNR < 0 dB';

  @override
  String get topologyLabelId => 'ID';

  @override
  String get topologyLabelPath => 'Caminho';

  @override
  String get topologyLabelSeen => 'Visto';

  @override
  String topologySecondsAgo(int s) {
    return 'há ${s}s';
  }

  @override
  String topologyMinutesAgo(int min) {
    return 'há ${min}min';
  }

  @override
  String topologyHoursAgo(int h) {
    return 'há ${h}h';
  }

  @override
  String topologyDaysAgo(int d) {
    return 'há ${d}d';
  }

  @override
  String topologyWeeksAgo(int w) {
    return 'há $w sem.';
  }

  @override
  String get topologyFilterRecent => 'Mostrar apenas contactos no rádio';

  @override
  String get topologyFilterAll => 'Mostrar todos (incl. locais)';

  @override
  String get topologyToggleLabels => 'Mostrar/ocultar etiquetas';

  @override
  String topologyNodesShown(int shown, int total) {
    return '$shown/$total nós';
  }

  @override
  String get topologyHopDirect => 'Direto';

  @override
  String get topologyHop1 => '1 salto';

  @override
  String get topologyHop2 => '2 saltos';

  @override
  String get topologyHopFlood => 'Flood / 3+';

  @override
  String get topologyTabPaths => 'Caminhos';

  @override
  String get topologyPathsEmptyTitle => 'Sem dados de rota';

  @override
  String get topologyPathsEmptyHint =>
      'Faz um trace a partir de um\ncontacto para ver o caminho';

  @override
  String topologyPathsCount(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n caminhos',
      one: '1 caminho',
    );
    return '$_temp0';
  }

  @override
  String get repeaterTitle => 'Gerir Repetidor';

  @override
  String get repeaterConfig => 'Configuração Remota';

  @override
  String get repeaterApply => 'Aplicar';

  @override
  String get repeaterNodeName => 'Nome do nó';

  @override
  String get repeaterTxPower => 'Potência TX';

  @override
  String get repeaterForwarding => 'Repetição de pacotes';

  @override
  String get repeaterForwardingDesc =>
      'Activa ou desactiva o reencaminhamento de pacotes';

  @override
  String get repeaterAdvertInterval => 'Intervalo anúncio local';

  @override
  String get repeaterAdvertZeroHop => 'Anúncio Auto (Zero Hop)';

  @override
  String get repeaterAdvertFlood => 'Anúncio Auto (Flood)';

  @override
  String get repeaterIntervalMinutes => 'Intervalo (minutos)';

  @override
  String get repeaterIntervalHours => 'Intervalo (horas)';

  @override
  String get repeaterMinimalTrafficHint =>
      'Para usar tráfego mínimo na rede, use os ícones de refrescar para pedir apenas a informação que precisa.';

  @override
  String get repeaterValueNotLoaded => '—';

  @override
  String get repeaterFloodMax => 'Flood máximo (saltos)';

  @override
  String get repeaterClearStats => 'Limpar Estatísticas';

  @override
  String get repeaterClearStatsDesc => 'Reinicia contadores de pacotes e erros';

  @override
  String get repeaterNoStats =>
      'Autentique-se e prima \"Actualizar\" para obter as estatísticas.';

  @override
  String get repeaterFetchStats => 'Actualizar';

  @override
  String get repeaterAuthenticated => 'Autenticado';

  @override
  String get repeaterTabStatus => 'Estado';

  @override
  String get repeaterTabCommandLine => 'Linha de comandos';

  @override
  String get repeaterTabSettings => 'Definições';

  @override
  String get repeaterCmdHint => 'Enviar um comando...';

  @override
  String get repeaterCmdEmpty =>
      'Sem comandos enviados. Use o campo abaixo para enviar comandos CLI directamente.';

  @override
  String get repeaterCmdClear => 'Limpar histórico';

  @override
  String get repeaterMenuHelp => 'Ajuda de Comandos';

  @override
  String get repeaterMenuClearHistory => 'Apagar Histórico de Comandos';

  @override
  String get repeaterHelpTitle => 'Ajuda';

  @override
  String get repeaterHelpSubtitle => 'Comandos do Repetidor';

  @override
  String get repeaterHelpFirmwareNote =>
      'Alguns comandos requerem firmware recente.';

  @override
  String get repeaterHelpSearchHint => 'Pesquisar';

  @override
  String get dataExportTitle => 'Exportar Dados';

  @override
  String get dataExportContactsTitle => 'Contactos';

  @override
  String dataExportContactsDesc(int count) {
    return '$count contactos guardados';
  }

  @override
  String get dataExportMessagesTitle => 'Mensagens';

  @override
  String get dataExportMessagesDesc => 'Todas as conversas — privadas e canais';

  @override
  String get dataExportKmlTitle => 'Dados de Mapa';

  @override
  String dataExportKmlDesc(int count) {
    return '$count contactos com GPS';
  }

  @override
  String get dataExportNote =>
      'Os ficheiros são exportados diretamente para o menu de partilha.\nNenhum dado sai do dispositivo sem a tua confirmação.';

  @override
  String get dataExportNoContacts => 'Sem contactos para exportar';

  @override
  String get dataExportNoMessages => 'Sem mensagens para exportar';

  @override
  String get dataExportNoGps => 'Sem contactos com coordenadas GPS';

  @override
  String get dataExportFailed => 'Falha na exportação';

  @override
  String get appsDataExportTitle => 'Exportar Dados';

  @override
  String get appsDataExportSubtitle =>
      'Exporta contactos, mensagens e dados de mapa';
}
