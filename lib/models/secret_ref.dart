/// As chaves do cofre, num lugar só.
///
/// São `String` e não enum porque duas delas dependem de dado de execução: o
/// id do addon e o do console. O formato é o da seção 6.2 do spec de
/// arquitetura.
///
/// **Este arquivo é o mais difícil de mudar da fatia.** A chave vai parar no
/// chaveiro do sistema operacional do usuário, fora do alcance do app. Mudar
/// o formato depois deixa credencial órfã na máquina de quem atualizar, sem
/// como achar de volta. Por isso o saneamento mora aqui e não em quem gera id.
class SecretRef {
  /// O token de um console servido por um addon.
  ///
  /// Carrega o **addon**, e não só o console, porque o id do console vem do
  /// nome dele: dois addons que sirvam "Nintendo 64" produzem `nintendo_64`
  /// os dois, e têm logins diferentes.
  static String addonToken(String addonId, String consoleId) =>
      '${addonPrefix(addonId)}${_sane(consoleId)}';

  /// Tudo que pertence a um addon. Usado para apagar as credenciais dele
  /// quando o usuário o remove.
  ///
  /// Termina em `/` de propósito: sem isso, o prefixo de `ultranx` casaria
  /// com as chaves de `ultranx_2`.
  static String addonPrefix(String addonId) => 'addon:${_sane(addonId)}/';

  static const iaAccessKey = 'ia/accessKey';
  static const iaSecretKey = 'ia/secretKey';
  static const iaCookies = 'ia/cookies';

  /// Por provedor, porque Real-Debrid não vai ser o único.
  static String debrid(String provider) => 'debrid/${_sane(provider)}';

  /// Troca o que estrutura a chave por `_`, para que nenhum id consiga forjar
  /// a chave de outro. Só `:` e `/` são estruturais, então trocar os dois basta.
  ///
  /// A troca **não** é injetiva: `a:b`, `a/b` e `a_b` saem todos como `a_b`.
  /// Não se perde nada com isso, porque `_nameToId`
  /// (`catalog_service.dart:61`) já colapsa todo não alfanumérico em `_`, e
  /// então os ids reais nunca distinguem esses três. Trocar mais, tipo
  /// `[^a-z0-9]`, aí sim perderia: `meu-rts` e `meu_rts` são dois addons e
  /// virariam a mesma chave.
  ///
  /// Parte vazia sai sem guarda, de propósito. `_nameToId` devolve `''` para
  /// um nome só de pontuação, e aí `addonToken('x', '')` é igual a
  /// `addonPrefix('x')`. É inofensivo: o prefixo só serve para apagar em lote
  /// e nunca é chave de nada, e dois consoles de id vazio já são **um**
  /// console, porque `_parseConsoles` (`catalog_service.dart:91`) grava os
  /// dois na mesma entrada do mapa. Levantar aqui derrubaria a migração da
  /// Task 5, que itera chaves já gravadas, para defender contra uma colisão
  /// que o catálogo colapsou antes.
  static String _sane(String part) => part.replaceAll(RegExp(r'[:/]'), '_');
}
