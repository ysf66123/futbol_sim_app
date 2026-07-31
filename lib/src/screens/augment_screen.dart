import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/session_controller.dart';
import '../services/room_game_service.dart';
import '../theme/app_theme.dart';
import '../utils/dialogs.dart';
import '../utils/game_exception.dart';
import '../widgets/ui.dart';

class AugmentScreen extends StatelessWidget {
  const AugmentScreen({super.key});

  Future<void> _selectAugment(BuildContext context, String augmentId) async {
    final session = context.read<SessionController>();
    final roomRef = session.roomRef;
    if (roomRef == null ||
        session.playerId == null ||
        session.opponentId == null) {
      return;
    }

    try {
      final currentTurn = session.pendingAugmentTurn;
      final picked = await roomRef.firestore.runTransaction<bool>((
        transaction,
      ) async {
        final playerRef = roomRef.collection('players').doc(session.playerId);
        final playerSnapshot = await transaction.get(playerRef);
        final playerData = playerSnapshot.data() ?? <String, dynamic>{};
        final completed = List<int>.from(
          (playerData['augment_turns_completed'] as List?) ?? const [],
        );
        if (completed.contains(currentTurn)) {
          return false;
        }
        transaction.update(playerRef, {
          'augments_chosen': FieldValue.arrayUnion([augmentId]),
          'augment_turns_completed': FieldValue.arrayUnion([currentTurn]),
        });
        transaction.update(roomRef.collection('game_state').doc('current'), {
          'augment_pool': FieldValue.arrayRemove(session.pendingAugments),
        });
        return true;
      });
      if (!picked) {
        session.clearPendingAugments();
        session.switchView(GameView.draft);
        return;
      }

      final messages = await RoomGameService.applyAugmentEffect(
        db: roomRef.firestore,
        roomRef: roomRef,
        gameConfig: session.gameConfig,
        currentTurn: currentTurn,
        playerId: session.playerId!,
        opponentId: session.opponentId!,
        augmentId: augmentId,
      );

      session.clearPendingAugments();
      session.switchView(GameView.draft);
      if (messages.isNotEmpty && context.mounted) {
        await showGameDialog(
          context,
          title: 'Eklenti Etkisi',
          message: messages.join('\n'),
        );
      }
    } on GameException catch (error) {
      if (!context.mounted) return;
      await showGameDialog(context, title: error.title, message: error.message);
    } catch (error) {
      if (!context.mounted) return;
      await showGameDialog(context, title: 'Eklenti Hatası', message: '$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    final options = session.pendingAugments;
    return GamePageScaffold(
      title: 'Eklenti Seçimi',
      subtitle: 'Tur ${session.pendingAugmentTurn}',
      actions: [
        GameIconButton(
          onPressed: () {
            session.clearPendingAugments();
            session.switchView(GameView.draft);
          },
          icon: const Icon(Icons.close_rounded),
        ),
      ],
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          if (options.isEmpty)
            const EmptyPanel(
              message:
                  'Sunulacak eklenti kalmadı. Draft ekranına dönebilirsin.',
            )
          else
            ...options.map((id) {
              final data =
                  session.augmentCatalog[id] ??
                  const <String, dynamic>{'name': 'Eklenti', 'description': ''};
              return Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const InfoBadge(
                            label: 'Eklenti',
                            color: AppColors.gold,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              data['name'] as String,
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(data['description'] as String),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: GameFilledButton(
                          onPressed: () => _selectAugment(context, id),
                          child: const Text('Bu Eklentiyi Seç'),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}
