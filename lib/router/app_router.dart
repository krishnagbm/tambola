import 'package:go_router/go_router.dart';
import '../features/admin_lobby/screens/admin_lobby_screen.dart';
import '../features/game_setup/screens/create_game_screen.dart';
import '../features/gameplay/screens/admin_game_control_screen.dart';
import '../features/gameplay/screens/player_ticket_screen.dart';
import '../features/home/screens/home_screen.dart';
import '../features/live_display/screens/live_game_display_screen.dart';
import '../features/registration/screens/join_game_screen.dart';
import '../features/registration/screens/registration_status_screen.dart';
import '../features/rewards/screens/rewards_screen.dart';
import '../features/rewards/screens/verify_reward_screen.dart';
import '../features/wallet/screens/wallet_screen.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const HomeScreen(),
    ),
    GoRoute(
      path: '/create-game',
      builder: (context, state) => const CreateGameScreen(),
    ),
    GoRoute(
      path: '/join',
      builder: (context, state) {
        final code = state.uri.queryParameters['code'];
        return JoinGameScreen(initialCode: code);
      },
    ),
    GoRoute(
      path: '/join/:code',
      builder: (context, state) {
        final code = state.pathParameters['code'];
        return JoinGameScreen(initialCode: code);
      },
    ),
    GoRoute(
      path: '/game-status/:gameId',
      builder: (context, state) {
        final gameId = state.pathParameters['gameId']!;
        return RegistrationStatusScreen(gameId: gameId);
      },
    ),
    GoRoute(
      path: '/admin-lobby/:gameId',
      builder: (context, state) {
        final gameId = state.pathParameters['gameId']!;
        return AdminLobbyScreen(gameId: gameId);
      },
    ),
    GoRoute(
      path: '/admin-control/:gameId',
      builder: (context, state) {
        final gameId = state.pathParameters['gameId']!;
        return AdminGameControlScreen(gameId: gameId);
      },
    ),
    GoRoute(
      path: '/play/:gameId',
      builder: (context, state) {
        final gameId = state.pathParameters['gameId']!;
        return PlayerTicketScreen(gameId: gameId);
      },
    ),
    GoRoute(
      path: '/wallet',
      builder: (context, state) => const WalletScreen(),
    ),
    GoRoute(
      path: '/rewards',
      builder: (context, state) => const RewardsScreen(),
    ),
    GoRoute(
      path: '/verify-reward',
      builder: (context, state) => const VerifyRewardScreen(),
    ),
    GoRoute(
      path: '/live-display/:gameId',
      builder: (context, state) {
        final gameId = state.pathParameters['gameId']!;
        return LiveGameDisplayScreen(gameId: gameId);
      },
    ),
  ],
);
