/// O eixo **a posteriori** da confiança numa fonte: o que a verificação por
/// CRC disse depois de ler o cabeçalho do arquivo remoto.
///
/// Não confunda com `MatchConfidence`, que é o eixo **a priori** e sai do tier
/// de nome (fatia 2). São dois eixos e eles não se misturam: ver a "Segunda
/// decisão travada" no plano da fatia 3. Se você se pegou querendo acrescentar
/// um `crcOk` ao `MatchConfidence`, é este enum que você queria.
///
/// Dart puro, sem import nenhum, de propósito.
enum SourceVerification {
  /// Ninguém perguntou. É o estado de toda fonte fora da tela de detalhe: a
  /// grade não verifica e o lote não verifica (seção 6 do spec de UI), e um
  /// console sem pacote não tem com o que verificar.
  notVerified,

  /// As duas requisições estão no ar.
  verifying,

  /// Um dump deste jogo está lá dentro. Certeza, não palpite.
  crcOk,

  /// Leu o CRC e ele não é deste jogo. A fonte sai do destaque e desce para a
  /// lista, marcada (seção 8).
  crcDiscarded,

  /// Não deu para saber: servidor sem `Range`, arquivo que não é ZIP, ZIP sem
  /// ROM dentro. **Não** é sinônimo de fonte ruim, e por isso não descarta.
  impossible,
}
