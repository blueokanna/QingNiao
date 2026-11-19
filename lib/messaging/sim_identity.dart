import '../l10n/app_strings.dart';
import 'models.dart';

/// Slots describe active subscriptions only; an old subscription ID is never
/// a slot number, even when just one card remains on the device.
String simCardLabel(SimCard card) {
  final kind = card.isEmbedded ? 'eSIM' : 'SIM';
  final slot = card.slot > 0 ? '$kind ${card.slot}' : kind;
  final name = card.name.trim().isNotEmpty
      ? card.name.trim()
      : card.carrier.trim();
  return name.isEmpty ? slot : '$slot · $name';
}

class MessageSimSource {
  const MessageSimSource._(this.subscriptionId, this.card);

  factory MessageSimSource.resolve(
    int subscriptionId,
    Iterable<SimCard> cards,
  ) {
    SimCard? match;
    if (subscriptionId >= 0) {
      for (final card in cards) {
        if (card.id == subscriptionId) {
          match = card;
          break;
        }
      }
    }
    return MessageSimSource._(subscriptionId, match);
  }

  final int subscriptionId;
  final SimCard? card;

  String get label => card != null
      ? simCardLabel(card!)
      : subscriptionId < 0
      ? tr('Unknown SIM')
      : tr('Unavailable SIM · ID {p0}', [subscriptionId]);

  String get description => [
    label,
    if (card != null &&
        card!.carrier.trim().isNotEmpty &&
        card!.carrier.trim() != card!.name.trim())
      card!.carrier.trim(),
    if (subscriptionId >= 0) '${tr('Subscription ID')}: $subscriptionId',
  ].join('\n');
}
