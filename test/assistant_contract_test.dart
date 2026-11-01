import 'package:flutter_test/flutter_test.dart';
import 'package:sareemart_customer/features/assistant/assistant_contract.dart';

void main() {
  test('maps Dify login and account routes to Flutter routes', () {
    expect(assistantAppPath('/?login=1'), '/login');
    expect(assistantAppPath('/profile/orders'), '/orders');
    expect(assistantAppPath('/profile/address'), '/addresses');
    expect(assistantAppPath('/profile/wallet-transaction'), '/wallet');
  });

  test('normalizes a Dify PRODUCT_CARD for the add-to-cart widget', () {
    final action = assistantProductAction({
      'type': 'PRODUCT_CARD',
      'label': 'عسل',
      'url': '/product/honey',
      'product': {
        'id': 7,
        'name': 'عسل يمني',
        'slug': 'honey',
        'price': 1200,
        'image': 'https://example.test/honey.jpg',
      },
    });

    expect(action['type'], 'PRODUCT_CARD');
    expect(action['url'], '/product/honey');
    expect((action['product'] as Map)['id'], 7);
    expect((action['product'] as Map)['image'], contains('honey.jpg'));
  });

  test('normalizes direct product results from the current assistant', () {
    final action = assistantProductAction({
      'id': 9,
      'name': 'قهوة',
      'path': '/product/coffee',
      'image_url': 'https://example.test/coffee.jpg',
      'price_text': '900 ر.ي',
    });

    final product = action['product'] as Map;
    expect(action['url'], '/product/coffee');
    expect(product['image'], contains('coffee.jpg'));
    expect(product['price'], '900 ر.ي');
  });
}
