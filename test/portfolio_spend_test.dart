import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/portfolio/portfolio_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<PortfolioController> controllerWith(int coins) async {
    final controller = PortfolioController();
    await pumpEventQueue(); // let the initial load finish
    controller.addCurrency(coins);
    return controller;
  }

  test('spendCurrency takes the coins when there are enough', () async {
    final controller = await controllerWith(15);
    expect(controller.spendCurrency(5), isTrue);
    expect(controller.state.currency, 10);
  });

  test('spendCurrency refuses and changes nothing when there are not enough', () async {
    final controller = await controllerWith(3);
    expect(controller.spendCurrency(5), isFalse);
    expect(controller.state.currency, 3);
  });
}
