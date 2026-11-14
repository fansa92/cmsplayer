import 'package:flutter_test/flutter_test.dart';

import 'package:cms_player/core/deep_link.dart';

/// 外部唤起：协议、命令行参数、裸地址三种写法。
void main() {
  tearDown(DeepLink.resetForTest);

  test('cmsplayer 协议里的 url 参数', () {
    expect(
      DeepLink.parseImportUrl(<String>[
        'cmsplayer://import?url=https%3A%2F%2Fexample.com%2Fsource.json',
      ]),
      'https://example.com/source.json',
    );
  });

  test('命令行 --import=', () {
    expect(
      DeepLink.parseImportUrl(<String>['--import=https://example.com/list.json']),
      'https://example.com/list.json',
    );
  });

  test('直接传一个源列表地址', () {
    expect(
      DeepLink.parseImportUrl(<String>['https://example.com/source.json']),
      'https://example.com/source.json',
    );
  });

  test('无关参数一律忽略', () {
    expect(
      DeepLink.parseImportUrl(<String>[
        '--verbose',
        'cmsplayer://play?id=1',
        'https://example.com/watch?v=1',
      ]),
      isNull,
    );
    expect(DeepLink.parseImportUrl(const <String>[]), isNull);
  });

  test('handleArgs 把结果留给界面消费', () {
    expect(DeepLink.pendingImport.value, isNull);
    DeepLink.handleArgs(<String>['cmsplayer://import?url=https://a.com/s.json']);
    expect(DeepLink.pendingImport.value, 'https://a.com/s.json');

    DeepLink.pendingImport.value = null;
    DeepLink.handleArgs(<String>['--verbose']);
    expect(DeepLink.pendingImport.value, isNull);
  });
}
